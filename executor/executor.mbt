// Wasmoon Executor - Main instruction dispatch and module execution

///|
/// Check if subtype is a subtype of supertype for value types.
/// This implements WebAssembly reference type subtyping:
/// - RefFunc <: FuncRef (ref func <: ref null func)
/// - RefExtern <: ExternRef (ref extern <: ref null extern)
/// - RefFuncTyped(i) <: RefNullFuncTyped(i) (ref $t <: ref null $t)
/// - RefFuncTyped(i) <: RefFunc <: FuncRef (concrete <: abstract <: nullable abstract)
/// - RefNullFuncTyped(i) <: FuncRef (ref null $t <: ref null func)
/// - All types are subtypes of themselves
fn is_value_type_subtype(
  subtype : @types.ValueType,
  supertype : @types.ValueType,
) -> Bool {
  if subtype == supertype {
    return true
  }
  match (subtype, supertype) {
    // RefFunc (ref func) is subtype of FuncRef (ref null func)
    (RefFunc, FuncRef) => true
    // RefExtern (ref extern) is subtype of ExternRef (ref null extern)
    (RefExtern, ExternRef) => true
    // RefFuncTyped(i) is subtype of RefNullFuncTyped(i) for same i
    (RefFuncTyped(i), RefNullFuncTyped(j)) => i == j
    // RefFuncTyped is subtype of RefFunc (concrete <: abstract)
    (RefFuncTyped(_), RefFunc) => true
    // RefFuncTyped is subtype of FuncRef (concrete <: nullable abstract)
    (RefFuncTyped(_), FuncRef) => true
    // RefNullFuncTyped is subtype of FuncRef (nullable concrete <: nullable abstract)
    (RefNullFuncTyped(_), FuncRef) => true
    // Everything else: not a subtype
    _ => false
  }
}

///|
/// Execute a single instruction
fn ExecContext::exec_instr(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise {
  match instr {
    // Constants
    I32Const(n) => self.stack.push(I32(n))
    I64Const(n) => self.stack.push(I64(n))
    F32Const(f) => self.stack.push(F32(f))
    F64Const(d) => self.stack.push(F64(d))

    // Local variables
    LocalGet(idx) => {
      let frame = self.get_frame()
      let value = frame.get_local(idx)
      self.stack.push(value)
    }
    LocalSet(idx) => {
      let value = self.stack.pop()
      let frame = self.get_frame()
      frame.set_local(idx, value)
    }
    LocalTee(idx) => {
      let value = self.stack.peek()
      let frame = self.get_frame()
      frame.set_local(idx, value)
    }

    // Global variables
    GlobalGet(idx) => {
      let global_addr = self.instance.global_addrs[idx]
      let global = self.store.get_global(global_addr)
      self.stack.push(global.get())
    }
    GlobalSet(idx) => {
      let value = self.stack.pop()
      let global_addr = self.instance.global_addrs[idx]
      let global = self.store.get_global(global_addr)
      global.set(value)
    }

    // Table operations
    TableGet(table_idx) => {
      let elem_idx = self.stack.pop_i32()
      let table_addr = self.instance.table_addrs[table_idx]
      let table = self.store.get_table(table_addr)
      let value = table.get(elem_idx)
      self.stack.push(value)
    }
    TableSet(table_idx) => {
      let value = self.stack.pop()
      let elem_idx = self.stack.pop_i32()
      let table_addr = self.instance.table_addrs[table_idx]
      let table = self.store.get_table(table_addr)
      table.set(elem_idx, value)
    }
    TableSize(table_idx) => {
      let table_addr = self.instance.table_addrs[table_idx]
      let table = self.store.get_table(table_addr)
      self.stack.push(I32(table.size()))
    }
    TableGrow(table_idx) => {
      let delta = self.stack.pop_i32()
      let init_val = self.stack.pop()
      let table_addr = self.instance.table_addrs[table_idx]
      let table = self.store.get_table(table_addr)
      let old_size = table.grow(delta, init_val)
      self.stack.push(I32(old_size))
    }
    TableFill(table_idx) => {
      let n = self.stack.pop_i32()
      let value = self.stack.pop()
      let dest = self.stack.pop_i32()
      let table_addr = self.instance.table_addrs[table_idx]
      let table = self.store.get_table(table_addr)
      table.fill(dest, value, n)
    }
    TableCopy(dest_table_idx, src_table_idx) => {
      let n = self.stack.pop_i32()
      let src = self.stack.pop_i32()
      let dest = self.stack.pop_i32()
      let dest_table_addr = self.instance.table_addrs[dest_table_idx]
      let src_table_addr = self.instance.table_addrs[src_table_idx]
      let dest_table = self.store.get_table(dest_table_addr)
      let src_table = self.store.get_table(src_table_addr)
      dest_table.copy_from(dest, src_table, src, n)
    }
    TableInit(table_idx, elem_idx) => {
      // table.init copies elements from elem segment to table
      // Pop operands: n (count), s (src offset in elem), d (dest offset in table)
      let n = self.stack.pop_i32()
      let s = self.stack.pop_i32()
      let d = self.stack.pop_i32()

      // Get elem segment
      let elem_segment = self.instance.elem_segments[elem_idx]

      // Check if segment has been dropped or is declarative
      // Declarative elem segments behave as if they have been dropped
      let is_dropped = self.instance.dropped_elems[elem_idx]
      let is_declarative = elem_segment.mode is @types.ElemMode::Declarative
      if (is_dropped || is_declarative) && n != 0 {
        // Dropped/declarative segments behave as if they have zero length
        raise @runtime.RuntimeError::OutOfBoundsTableAccess
      }
      if is_dropped || is_declarative {
        return
      }

      // Check bounds
      let elem_len = elem_segment.init.length()
      let table_addr = self.instance.table_addrs[table_idx]
      let table = self.store.get_table(table_addr)
      let table_size = table.size()
      if s < 0 || n < 0 || s + n > elem_len || d < 0 || d + n > table_size {
        raise @runtime.RuntimeError::OutOfBoundsTableAccess
      }

      // Copy elements from elem segment to table
      for i in 0..<n {
        let init_expr = elem_segment.init[s + i]
        // Evaluate the init expression to get the value
        let value = match init_expr {
          [RefFunc(func_idx)] => {
            // Convert module function index to store address
            let store_addr = self.instance.func_addrs[func_idx]
            @types.Value::FuncRef(store_addr)
          }
          [RefNull(ref_type)] =>
            match ref_type {
              FuncRef | ExternRef => @types.Value::Null
              _ => @types.Value::Null
            }
          [I32Const(idx)] => {
            // Legacy format: function index as i32
            let store_addr = self.instance.func_addrs[idx]
            @types.Value::FuncRef(store_addr)
          }
          _ => @types.Value::Null
        }
        table.set(d + i, value)
      }
    }

    // Drop
    Drop => self.stack.pop() |> ignore

    // Reference type instructions
    RefNull(ref_type) =>
      match ref_type {
        FuncRef => self.stack.push(Null)
        ExternRef => self.stack.push(Null)
        _ => raise @runtime.RuntimeError::TypeMismatch
      }
    RefIsNull => {
      let value = self.stack.pop()
      match value {
        Null => self.stack.push(I32(1))
        _ => self.stack.push(I32(0))
      }
    }
    RefFunc(func_idx) => {
      // Get the store address for the function
      let func_addr = self.instance.func_addrs[func_idx]
      self.stack.push(FuncRef(func_addr))
    }
    RefAsNonNull => {
      // ref.as_non_null: traps if reference is null
      let value = self.stack.pop()
      match value {
        Null => raise @runtime.RuntimeError::Unreachable
        _ => self.stack.push(value)
      }
    }
    BrOnNull(_) | BrOnNonNull(_) =>
      // br_on_null and br_on_non_null are control instructions
      self.exec_control(instr)

    // i32 numeric operations
    I32Add
    | I32Sub
    | I32Mul
    | I32DivS
    | I32DivU
    | I32RemS
    | I32RemU
    | I32Eq
    | I32Ne
    | I32LtS
    | I32LtU
    | I32GtS
    | I32GtU
    | I32LeS
    | I32LeU
    | I32GeS
    | I32GeU
    | I32Eqz
    | I32And
    | I32Or
    | I32Xor
    | I32Shl
    | I32ShrS
    | I32ShrU
    | I32Rotl
    | I32Rotr
    | I32Clz
    | I32Ctz
    | I32Popcnt
    | I32Extend8S
    | I32Extend16S => self.exec_i32_numeric(instr)

    // i64 numeric operations
    I64Add
    | I64Sub
    | I64Mul
    | I64DivS
    | I64DivU
    | I64RemS
    | I64RemU
    | I64Eq
    | I64Ne
    | I64LtS
    | I64LtU
    | I64GtS
    | I64GtU
    | I64LeS
    | I64LeU
    | I64GeS
    | I64GeU
    | I64Eqz
    | I64And
    | I64Or
    | I64Xor
    | I64Shl
    | I64ShrS
    | I64ShrU
    | I64Rotl
    | I64Rotr
    | I64Clz
    | I64Ctz
    | I64Popcnt
    | I64Extend8S
    | I64Extend16S
    | I64Extend32S => self.exec_i64_numeric(instr)

    // f32 numeric operations
    F32Add
    | F32Sub
    | F32Mul
    | F32Div
    | F32Abs
    | F32Neg
    | F32Sqrt
    | F32Ceil
    | F32Floor
    | F32Trunc
    | F32Nearest
    | F32Min
    | F32Max
    | F32Copysign
    | F32Eq
    | F32Ne
    | F32Lt
    | F32Gt
    | F32Le
    | F32Ge => self.exec_f32_numeric(instr)

    // f64 numeric operations
    F64Add
    | F64Sub
    | F64Mul
    | F64Div
    | F64Abs
    | F64Neg
    | F64Sqrt
    | F64Ceil
    | F64Floor
    | F64Trunc
    | F64Nearest
    | F64Min
    | F64Max
    | F64Copysign
    | F64Eq
    | F64Ne
    | F64Lt
    | F64Gt
    | F64Le
    | F64Ge => self.exec_f64_numeric(instr)

    // Conversion operations
    I32WrapI64
    | I64ExtendI32S
    | I64ExtendI32U
    | I32TruncF32S
    | I32TruncF32U
    | I32TruncF64S
    | I32TruncF64U
    | I64TruncF32S
    | I64TruncF32U
    | I64TruncF64S
    | I64TruncF64U
    | F32ConvertI32S
    | F32ConvertI32U
    | F32ConvertI64S
    | F32ConvertI64U
    | F64ConvertI32S
    | F64ConvertI32U
    | F64ConvertI64S
    | F64ConvertI64U
    | F32DemoteF64
    | F64PromoteF32
    | I32ReinterpretF32
    | I64ReinterpretF64
    | F32ReinterpretI32
    | F64ReinterpretI64 => self.exec_conversion(instr)

    // Saturating truncation operations
    I32TruncSatF32S
    | I32TruncSatF32U
    | I32TruncSatF64S
    | I32TruncSatF64U
    | I64TruncSatF32S
    | I64TruncSatF32U
    | I64TruncSatF64S
    | I64TruncSatF64U => self.exec_trunc_sat(instr)

    // Memory load operations
    I32Load(_, _)
    | I64Load(_, _)
    | F32Load(_, _)
    | F64Load(_, _)
    | I32Load8S(_, _)
    | I32Load8U(_, _)
    | I32Load16S(_, _)
    | I32Load16U(_, _)
    | I64Load8S(_, _)
    | I64Load8U(_, _)
    | I64Load16S(_, _)
    | I64Load16U(_, _)
    | I64Load32S(_, _)
    | I64Load32U(_, _) => self.exec_memory_load(instr)

    // Memory store operations
    I32Store(_, _)
    | I64Store(_, _)
    | F32Store(_, _)
    | F64Store(_, _)
    | I32Store8(_, _)
    | I32Store16(_, _)
    | I64Store8(_, _)
    | I64Store16(_, _)
    | I64Store32(_, _) => self.exec_memory_store(instr)

    // Memory size/grow and bulk operations
    MemorySize
    | MemoryGrow
    | MemoryInit(_)
    | DataDrop(_)
    | MemoryCopy
    | MemoryFill
    | ElemDrop(_) => self.exec_memory_misc(instr)

    // Control flow operations
    Block(_, _)
    | Loop(_, _)
    | If(_, _, _)
    | Br(_)
    | BrIf(_)
    | BrTable(_, _)
    | Unreachable
    | Select
    | SelectTyped(_)
    | Nop
    | Return => self.exec_control(instr)

    // Function call operations
    Call(func_idx) => self.exec_call(func_idx)
    CallIndirect(type_idx, table_idx) =>
      self.exec_call_indirect(type_idx, table_idx)
    CallRef(type_idx) => self.exec_call_ref(type_idx)
  }
}

// ============================================================
// Function Execution
// ============================================================

///|
/// Call a function by index
pub fn ExecContext::call_func(
  self : ExecContext,
  func_idx : Int,
  args : Array[@types.Value],
) -> Array[@types.Value] raise {
  // Get the store address from instance
  let store_addr = self.instance.func_addrs[func_idx]
  let func_inst = self.store.get_func_inst(store_addr)

  // Get the function type to determine return arity
  let type_idx = self.instance.func_type_indices[func_idx]
  let func_type = self.instance.types[type_idx]
  let return_arity = func_type.results.length()

  // Use the same context-switching logic as exec_call
  self.call_func_inst_with_context(store_addr, func_inst, args, return_arity)

  // Collect return values from stack (in reverse order, then reverse back)
  let results : Array[@types.Value] = []
  for _ in 0..<return_arity {
    results.push(self.stack.pop())
  }
  results.rev_in_place()
  results
}

// ============================================================
// Module Instantiation (MVP)
// ============================================================

///|
/// Create a simple module instance from a parsed module
pub fn instantiate_module(
  mod : @types.Module,
) -> (@runtime.Store, @runtime.ModuleInstance) {
  let store = @runtime.Store::new()

  // Allocate functions with their types
  let func_addrs : Array[Int] = []
  for i, code in mod.codes {
    let type_idx = mod.funcs[i]
    let func_type = mod.types[type_idx]
    let addr = store.alloc_func(code, func_type~)
    func_addrs.push(addr)
  }

  // Allocate memories
  let mem_addrs : Array[Int] = []
  for mem_type in mod.memories {
    let mem = @runtime.Memory::new(mem_type.limits.min, mem_type.limits.max)
    let addr = store.alloc_mem(mem)
    mem_addrs.push(addr)
  }

  // Allocate tables
  // Note: table init expressions can reference imported globals, so we need to
  // create imported global instances first if we have any table init expressions.
  // For simplicity, we'll evaluate table init expressions with an empty globals array
  // since the validator already ensures only imported globals can be referenced.
  let table_addrs : Array[Int] = []
  for table_def in mod.tables {
    // Evaluate table init expression if present
    let init_value : @types.Value = if table_def.init is Some(init_expr) {
      eval_const_expr(init_expr, func_addrs~, globals=[])
    } else {
      @types.Value::Null
    }
    let table = @runtime.Table::new(
      table_def.type_.elem_type,
      table_def.type_.limits.min,
      table_def.type_.limits.max,
      init_value~,
    )
    let addr = store.alloc_table(table)
    table_addrs.push(addr)
  }

  // Allocate globals with initialization
  let global_addrs : Array[Int] = []
  let global_instances : Array[@runtime.GlobalInstance] = []
  for global in mod.globals {
    // Evaluate init expression with access to already-initialized globals
    let init_value = eval_const_expr(
      global.init,
      func_addrs~,
      globals=global_instances,
    )
    let global_inst = @runtime.GlobalInstance::new(global.type_, init_value)
    let addr = store.alloc_global(global_inst)
    global_addrs.push(addr)
    global_instances.push(global_inst)
  }

  // func_addrs: indices into store.funcs
  // func_type_indices: type index for each function (from mod.funcs)
  // Initialize dropped arrays with false values
  let dropped_elems : Array[Bool] = []
  for _ in 0..<mod.elems.length() {
    dropped_elems.push(false)
  }
  let dropped_datas : Array[Bool] = []
  for _ in 0..<mod.datas.length() {
    dropped_datas.push(false)
  }
  let instance : @runtime.ModuleInstance = {
    types: mod.types,
    func_addrs,
    func_type_indices: mod.funcs,
    table_addrs,
    mem_addrs,
    global_addrs,
    exports: mod.exports,
    elem_segments: mod.elems,
    data_segments: mod.datas,
    dropped_elems,
    dropped_datas,
  }
  (store, instance)
}

///|
/// Evaluate a constant initialization expression
/// Supports extended constant expressions with arithmetic operations
fn eval_const_expr(
  instrs : Array[@types.Instruction],
  func_addrs? : Array[Int] = [],
  globals? : Array[@runtime.GlobalInstance] = [],
) -> @types.Value {
  // Use stack-based evaluation for extended constant expressions
  let stack : Array[@types.Value] = []
  for instr in instrs {
    match instr {
      I32Const(n) => stack.push(I32(n))
      I64Const(n) => stack.push(I64(n))
      F32Const(f) => stack.push(F32(f))
      F64Const(d) => stack.push(F64(d))
      RefNull(_) => stack.push(Null)
      RefFunc(idx) => {
        let store_addr = if idx < func_addrs.length() {
          func_addrs[idx]
        } else {
          idx
        }
        stack.push(FuncRef(store_addr))
      }
      GlobalGet(idx) =>
        if idx < globals.length() {
          stack.push(globals[idx].get())
        }
      // i32 arithmetic operations
      I32Add =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          if (a, b) is (I32(av), I32(bv)) {
            stack.push(I32(av + bv))
          }
        }
      I32Sub =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          if (a, b) is (I32(av), I32(bv)) {
            stack.push(I32(av - bv))
          }
        }
      I32Mul =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          if (a, b) is (I32(av), I32(bv)) {
            stack.push(I32(av * bv))
          }
        }
      // i64 arithmetic operations
      I64Add =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          if (a, b) is (I64(av), I64(bv)) {
            stack.push(I64(av + bv))
          }
        }
      I64Sub =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          if (a, b) is (I64(av), I64(bv)) {
            stack.push(I64(av - bv))
          }
        }
      I64Mul =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I64(av), I64(bv)) => stack.push(I64(av * bv))
            _ => ()
          }
        }
      _ => ()
    }
  }
  if stack.length() > 0 {
    stack[stack.length() - 1]
  } else {
    Null
  }
}

///|
/// Evaluate an extended constant expression for elem/data segment offsets
/// Supports i32.add, i32.sub, i32.mul in addition to basic constants
/// Returns the i32 offset value
fn eval_extended_const_expr(
  instrs : Array[@types.Instruction],
  globals : Array[@runtime.GlobalInstance],
) -> Int {
  // Use a simple stack-based evaluator
  let stack : Array[Int] = []
  for instr in instrs {
    match instr {
      I32Const(n) => stack.push(n)
      GlobalGet(idx) =>
        if idx < globals.length() && globals[idx].get() is I32(n) {
          stack.push(n)
        }
      I32Add =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() + b.unwrap())
        }
      I32Sub =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() - b.unwrap())
        }
      I32Mul =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() * b.unwrap())
        }
      _ => ()
    }
  }
  if stack.length() > 0 {
    stack[stack.length() - 1]
  } else {
    0
  }
}

///|
/// Helper to get global instances from a store given global addresses
fn get_global_instances(
  store : @runtime.Store,
  global_addrs : Array[Int],
) -> Array[@runtime.GlobalInstance] {
  let globals : Array[@runtime.GlobalInstance] = []
  for addr in global_addrs {
    globals.push(store.get_global(addr)) catch {
      _ => ()
    }
  }
  globals
}

///|
/// Evaluate an elem segment init expression to get a Value
/// Returns None for unsupported expressions that should be skipped
fn eval_elem_init_expr(
  init_expr : Array[@types.Instruction],
  func_addrs : Array[Int],
  globals : Array[@runtime.GlobalInstance],
) -> @types.Value? {
  match init_expr {
    [RefFunc(idx)] => {
      // Convert module function index to store address
      let store_addr = if idx < func_addrs.length() {
        func_addrs[idx]
      } else {
        idx // fallback, should not happen for valid modules
      }
      Some(@types.Value::FuncRef(store_addr))
    }
    [I32Const(idx)] => {
      // Legacy format: function index as i32
      let store_addr = if idx < func_addrs.length() {
        func_addrs[idx]
      } else {
        idx // fallback
      }
      Some(@types.Value::FuncRef(store_addr))
    }
    [RefNull(_)] => Some(@types.Value::Null)
    [GlobalGet(idx)] =>
      // Get funcref from global
      if idx < globals.length() {
        Some(globals[idx].get())
      } else {
        None
      }
    _ => None
  }
}

///|
/// Create a module instance with element and data segment initialization
pub fn instantiate_module_with_init(
  mod : @types.Module,
) -> (@runtime.Store, @runtime.ModuleInstance) raise @runtime.RuntimeError {
  let (store, instance) = instantiate_module(mod)

  // Initialize data segments (copy data to memory)
  // Get global instances for evaluating offset expressions
  let globals_for_data = get_global_instances(store, instance.global_addrs)
  for data in mod.datas {
    if instance.mem_addrs.length() > data.memory_idx {
      let mem = store.get_mem(instance.mem_addrs[data.memory_idx])

      // Evaluate offset expression using extended const expr evaluator
      let offset = eval_extended_const_expr(data.offset, globals_for_data)

      // Copy data to memory
      mem.init_data(offset, data.init)
    }
  }

  // Initialize element segments (populate tables with function references)
  for elem_idx, elem in mod.elems {
    // Only process active element segments
    if elem.mode is @types.ElemMode::Active(table_idx, offset_expr) {
      if instance.table_addrs.length() > table_idx {
        let table = store.get_table(instance.table_addrs[table_idx])

        // Evaluate offset expression using extended const expr evaluator
        let globals = get_global_instances(store, instance.global_addrs)
        let offset = eval_extended_const_expr(offset_expr, globals)

        // Check bounds before initializing
        // offset + num_elements must not exceed table size
        if offset < 0 || offset + elem.init.length() > table.size() {
          raise @runtime.OutOfBoundsTableAccess
        }

        // Set table entries - evaluate init expression to get value
        for i, init_expr in elem.init {
          match eval_elem_init_expr(init_expr, instance.func_addrs, globals) {
            Some(value) => table.set(offset + i, value)
            None => continue
          }
        }
      }
      // Active elem segments are implicitly dropped after initialization
      instance.dropped_elems[elem_idx] = true
    }
  }

  // Execute start function if present
  if mod.start is Some(start_func_idx) {
    let ctx = ExecContext::new(store, instance)
    (ctx.call_func(start_func_idx, []) catch {
      BranchWith(_, _) | Return => raise @runtime.Unreachable
      @runtime.StackUnderflow => raise @runtime.StackUnderflow
      @runtime.StackOverflow => raise @runtime.StackOverflow
      @runtime.TypeMismatch => raise @runtime.TypeMismatch
      @runtime.OutOfBoundsMemoryAccess => raise @runtime.OutOfBoundsMemoryAccess
      @runtime.OutOfBoundsTableAccess => raise @runtime.OutOfBoundsTableAccess
      @runtime.UndefinedElement => raise @runtime.UndefinedElement
      @runtime.UninitializedElement => raise @runtime.UninitializedElement
      @runtime.IndirectCallTypeMismatch =>
        raise @runtime.IndirectCallTypeMismatch
      @runtime.DivisionByZero => raise @runtime.DivisionByZero
      @runtime.IntegerOverflow => raise @runtime.IntegerOverflow
      @runtime.InvalidConversion => raise @runtime.InvalidConversion
      @runtime.Unreachable => raise @runtime.Unreachable
      @runtime.CallStackExhausted => raise @runtime.CallStackExhausted
      @runtime.UnknownImport => raise @runtime.UnknownImport
      _ => raise @runtime.Unreachable
    })
    |> ignore
  }
  (store, instance)
}

///|
/// Create a module instance with imports using an existing store
/// Raises UnknownImport if any required import is not provided
pub fn instantiate_module_with_imports(
  store : @runtime.Store,
  mod : @types.Module,
  imports : @runtime.Imports,
) -> @runtime.ModuleInstance raise @runtime.RuntimeError {
  // Process imports first
  let func_addrs : Array[Int] = []
  let func_type_indices : Array[Int] = []
  let mem_addrs : Array[Int] = []
  let table_addrs : Array[Int] = []
  let global_addrs : Array[Int] = []

  // Import functions and memories first (they come before module definitions in the index space)
  for imp in mod.imports {
    match imp.desc {
      Func(type_idx) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Func(addr)) => {
            // Check that imported function type matches expected type
            let expected_type = mod.types[type_idx]
            let actual_type = store.get_func_type(addr)
            if expected_type != actual_type {
              raise @runtime.LinkError
            }
            func_addrs.push(addr)
            func_type_indices.push(type_idx)
          }
          _ => raise @runtime.UnknownImport
        }
      Memory(expected_mem_type) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Memory(addr)) => {
            // Check memory type compatibility
            let actual_mem = store.get_mem(addr)
            let actual_limits = actual_mem.get_limits()
            // Import memory limits must be compatible:
            // - actual min >= expected min
            // - if expected has max, actual must have max <= expected max
            if actual_limits.0 < expected_mem_type.limits.min {
              raise @runtime.LinkError
            }
            if expected_mem_type.limits.max is Some(expected_max) {
              match actual_limits.1 {
                Some(actual_max) =>
                  if actual_max > expected_max {
                    raise @runtime.LinkError
                  }
                None => raise @runtime.LinkError
              }
            } // actual has no max but expected does
            mem_addrs.push(addr)
          }
          _ => raise @runtime.UnknownImport
        }
      Table(expected_table_type) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Table(addr)) => {
            // Check table type compatibility
            let actual_table = store.get_table(addr)
            let actual_elem_type = actual_table.get_elem_type()
            let actual_limits = actual_table.get_limits()
            // Element types must match
            if actual_elem_type != expected_table_type.elem_type {
              raise @runtime.LinkError
            }
            // Limits must be compatible:
            // - actual min >= expected min
            // - if expected has max, actual must have max <= expected max
            if actual_limits.0 < expected_table_type.limits.min {
              raise @runtime.LinkError
            }
            if expected_table_type.limits.max is Some(expected_max) {
              match actual_limits.1 {
                Some(actual_max) =>
                  if actual_max > expected_max {
                    raise @runtime.LinkError
                  }
                None => raise @runtime.LinkError
              }
            }
            table_addrs.push(addr)
          }
          _ => raise @runtime.UnknownImport
        }
      Global(expected_global_type) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Global(addr)) => {
            // Check global type compatibility
            let actual_global = store.get_global(addr)
            let actual_type = actual_global.get_type()
            // For mutable globals: types must match exactly (invariant)
            // For immutable globals: expected type must be supertype of actual type
            if actual_type.mutable {
              // Mutable globals: exact match required
              if actual_type.value_type != expected_global_type.value_type {
                raise @runtime.LinkError
              }
              if actual_type.mutable != expected_global_type.mutable {
                raise @runtime.LinkError
              }
            } else {
              // Immutable globals: expected must be supertype of actual
              // (i.e., actual is subtype of expected)
              if !is_value_type_subtype(
                  actual_type.value_type,
                  expected_global_type.value_type,
                ) {
                raise @runtime.LinkError
              }
              // Import must also be immutable for immutable export
              if expected_global_type.mutable {
                raise @runtime.LinkError
              }
            }
            global_addrs.push(addr)
          }
          _ => raise @runtime.UnknownImport
        }
    }
  }

  // Allocate module functions with their types
  for i, code in mod.codes {
    let type_idx = mod.funcs[i]
    let func_type = mod.types[type_idx]
    let addr = store.alloc_func(code, func_type~)
    func_addrs.push(addr)
    func_type_indices.push(type_idx)
  }

  // Allocate memories (after imported memories)
  for mem_type in mod.memories {
    let mem = @runtime.Memory::new(mem_type.limits.min, mem_type.limits.max)
    let addr = store.alloc_mem(mem)
    mem_addrs.push(addr)
  }

  // First, collect instances for already-allocated globals (imports)
  // This is needed for table init expressions that reference imported globals
  let global_instances : Array[@runtime.GlobalInstance] = []
  for addr in global_addrs {
    global_instances.push(
      store.get_global(addr) catch {
        _ =>
          @runtime.GlobalInstance::new(
            { value_type: I32, mutable: false },
            I32(0),
          )
      },
    )
  }

  // Allocate tables (after imported tables and globals)
  // Table init expressions can reference imported globals
  for table_def in mod.tables {
    // Evaluate table init expression if present
    let init_value : @types.Value = match table_def.init {
      Some(init_expr) =>
        eval_const_expr(init_expr, func_addrs~, globals=global_instances)
      None => @types.Value::Null
    }
    let table = @runtime.Table::new(
      table_def.type_.elem_type,
      table_def.type_.limits.min,
      table_def.type_.limits.max,
      init_value~,
    )
    let addr = store.alloc_table(table)
    table_addrs.push(addr)
  }

  // Allocate globals (after imported globals)
  for global in mod.globals {
    let init_value = eval_const_expr(
      global.init,
      func_addrs~,
      globals=global_instances,
    )
    let global_inst = @runtime.GlobalInstance::new(global.type_, init_value)
    let addr = store.alloc_global(global_inst)
    global_addrs.push(addr)
    global_instances.push(global_inst)
  }
  // Initialize dropped arrays with false values
  let dropped_elems : Array[Bool] = []
  for _ in 0..<mod.elems.length() {
    dropped_elems.push(false)
  }
  let dropped_datas : Array[Bool] = []
  for _ in 0..<mod.datas.length() {
    dropped_datas.push(false)
  }

  // Initialize active data segments (copy data to memory)
  let globals_for_data_init = get_global_instances(store, global_addrs)
  for data in mod.datas {
    // Active data segments have a non-empty offset expression
    if data.offset.length() > 0 && mem_addrs.length() > data.memory_idx {
      let mem = store.get_mem(mem_addrs[data.memory_idx])
      // Evaluate offset expression using extended const expr evaluator
      let offset = eval_extended_const_expr(data.offset, globals_for_data_init)
      // Copy data to memory
      mem.init_data(offset, data.init)
    }
  }

  // Initialize active element segments (populate tables with function references)
  for elem_idx, elem in mod.elems {
    // Only process active element segments
    if elem.mode is @types.ElemMode::Active(table_idx, offset_expr) {
      if table_addrs.length() > table_idx {
        let table = store.get_table(table_addrs[table_idx])
        // Evaluate offset expression using extended const expr evaluator
        let globals = get_global_instances(store, global_addrs)
        let offset = eval_extended_const_expr(offset_expr, globals)

        // Check bounds before initializing
        // offset + num_elements must not exceed table size
        if offset < 0 || offset + elem.init.length() > table.size() {
          raise @runtime.OutOfBoundsTableAccess
        }

        // Set table entries - evaluate init expression to get value
        for i, init_expr in elem.init {
          match eval_elem_init_expr(init_expr, func_addrs, globals) {
            Some(value) => table.set(offset + i, value)
            None => continue
          }
        }
      }
      // Active elem segments are implicitly dropped after initialization
      dropped_elems[elem_idx] = true
    }
  }
  let instance : @runtime.ModuleInstance = {
    types: mod.types,
    func_addrs,
    func_type_indices,
    table_addrs,
    mem_addrs,
    global_addrs,
    exports: mod.exports,
    elem_segments: mod.elems,
    data_segments: mod.datas,
    dropped_elems,
    dropped_datas,
  }

  // Register instance with store for cross-module call resolution
  store.register_instance(instance) |> ignore

  // Execute start function if present
  if mod.start is Some(start_func_idx) {
    let ctx = ExecContext::new(store, instance)
    (ctx.call_func(start_func_idx, []) catch {
      BranchWith(_, _) | Return => raise @runtime.Unreachable
      @runtime.StackUnderflow => raise @runtime.StackUnderflow
      @runtime.StackOverflow => raise @runtime.StackOverflow
      @runtime.TypeMismatch => raise @runtime.TypeMismatch
      @runtime.OutOfBoundsMemoryAccess => raise @runtime.OutOfBoundsMemoryAccess
      @runtime.OutOfBoundsTableAccess => raise @runtime.OutOfBoundsTableAccess
      @runtime.UndefinedElement => raise @runtime.UndefinedElement
      @runtime.UninitializedElement => raise @runtime.UninitializedElement
      @runtime.IndirectCallTypeMismatch =>
        raise @runtime.IndirectCallTypeMismatch
      @runtime.DivisionByZero => raise @runtime.DivisionByZero
      @runtime.IntegerOverflow => raise @runtime.IntegerOverflow
      @runtime.InvalidConversion => raise @runtime.InvalidConversion
      @runtime.Unreachable => raise @runtime.Unreachable
      @runtime.CallStackExhausted => raise @runtime.CallStackExhausted
      @runtime.UnknownImport => raise @runtime.UnknownImport
      @runtime.LinkError => raise @runtime.LinkError
      _ => raise @runtime.Unreachable
    })
    |> ignore
  }
  instance
}

///|
/// Find and call an exported function
pub fn call_exported_func(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  name : String,
  args : Array[@types.Value],
) -> Array[@types.Value] raise @runtime.RuntimeError {
  // Find the export
  fn find_export(
    exports : Array[@types.Export],
    target : String,
  ) -> @types.Export? {
    loop 0 {
      idx =>
        if idx >= exports.length() {
          None
        } else {
          let exp = exports[idx]
          if exp.name == target {
            Some(exp)
          } else {
            continue idx + 1
          }
        }
    }
  }

  match find_export(instance.exports, name) {
    Some(exp) =>
      match exp.desc {
        Func(func_idx) => {
          let ctx = ExecContext::new(store, instance)
          // Catch any leaked ControlSignal and convert to RuntimeError
          ctx.call_func(func_idx, args) catch {
            BranchWith(_, _) | Return => raise @runtime.Unreachable
            @runtime.StackUnderflow => raise @runtime.StackUnderflow
            @runtime.StackOverflow => raise @runtime.StackOverflow
            @runtime.TypeMismatch => raise @runtime.TypeMismatch
            @runtime.OutOfBoundsMemoryAccess =>
              raise @runtime.OutOfBoundsMemoryAccess
            @runtime.OutOfBoundsTableAccess =>
              raise @runtime.OutOfBoundsTableAccess
            @runtime.UndefinedElement => raise @runtime.UndefinedElement
            @runtime.UninitializedElement => raise @runtime.UninitializedElement
            @runtime.IndirectCallTypeMismatch =>
              raise @runtime.IndirectCallTypeMismatch
            @runtime.DivisionByZero => raise @runtime.DivisionByZero
            @runtime.IntegerOverflow => raise @runtime.IntegerOverflow
            @runtime.InvalidConversion => raise @runtime.InvalidConversion
            @runtime.Unreachable => raise @runtime.Unreachable
            @runtime.CallStackExhausted => raise @runtime.CallStackExhausted
            @runtime.UnknownImport => raise @runtime.UnknownImport
            _ => raise @runtime.Unreachable
          }
        } // Unknown error
        _ => raise @runtime.UndefinedElement
      }
    None => raise @runtime.UndefinedElement
  }
}

///|
/// Get the value of an exported global variable
pub fn get_exported_global(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  name : String,
) -> @types.Value raise @runtime.RuntimeError {
  // Find the export
  fn find_export(
    exports : Array[@types.Export],
    target : String,
  ) -> @types.Export? {
    loop 0 {
      idx =>
        if idx >= exports.length() {
          None
        } else {
          let exp = exports[idx]
          if exp.name == target {
            Some(exp)
          } else {
            continue idx + 1
          }
        }
    }
  }

  match find_export(instance.exports, name) {
    Some(exp) =>
      match exp.desc {
        Global(global_idx) => {
          let global_addr = instance.global_addrs[global_idx]
          let global = store.get_global(global_addr)
          global.get()
        }
        _ => raise @runtime.UndefinedElement
      }
    None => raise @runtime.UndefinedElement
  }
}

///|
/// Instantiate a module using a Linker
/// The linker provides imports from previously registered modules
/// The instantiated module is automatically registered with the given name
pub fn instantiate_with_linker(
  linker : @runtime.Linker,
  name : String,
  mod : @types.Module,
) -> @runtime.ModuleInstance raise @runtime.RuntimeError {
  let imports = linker.build_imports()
  let store = linker.get_store()
  let instance = instantiate_module_with_imports(store, mod, imports)

  // Register the instance with the store for cross-module call resolution
  store.register_instance(instance) |> ignore

  // Initialize data segments (copy data to memory)
  let globals_for_linker_data = get_global_instances(
    store,
    instance.global_addrs,
  )
  for data in mod.datas {
    if instance.mem_addrs.length() > data.memory_idx {
      let mem = store.get_mem(instance.mem_addrs[data.memory_idx])
      let offset = eval_extended_const_expr(
        data.offset,
        globals_for_linker_data,
      )
      mem.init_data(offset, data.init)
    }
  }

  // Initialize element segments (populate tables with function references)
  for elem_idx, elem in mod.elems {
    // Only process active element segments
    if elem.mode is @types.ElemMode::Active(table_idx, offset_expr) {
      if instance.table_addrs.length() > table_idx {
        let table = store.get_table(instance.table_addrs[table_idx])
        // Evaluate offset expression using extended const expr evaluator
        let globals = get_global_instances(store, instance.global_addrs)
        let offset = eval_extended_const_expr(offset_expr, globals)

        // Check bounds before initializing
        // offset + num_elements must not exceed table size
        if offset < 0 || offset + elem.init.length() > table.size() {
          raise @runtime.OutOfBoundsTableAccess
        }

        // Set table entries - evaluate init expression to get value
        for i, init_expr in elem.init {
          match eval_elem_init_expr(init_expr, instance.func_addrs, globals) {
            Some(value) => table.set(offset + i, value)
            None => continue
          }
        }
      }
      // Active elem segments are implicitly dropped after initialization
      instance.dropped_elems[elem_idx] = true
    }
  }

  // Execute start function if present
  if mod.start is Some(start_func_idx) {
    let ctx = ExecContext::new(store, instance)
    (ctx.call_func(start_func_idx, []) catch {
      BranchWith(_, _) | Return => raise @runtime.Unreachable
      @runtime.StackUnderflow => raise @runtime.StackUnderflow
      @runtime.StackOverflow => raise @runtime.StackOverflow
      @runtime.TypeMismatch => raise @runtime.TypeMismatch
      @runtime.OutOfBoundsMemoryAccess => raise @runtime.OutOfBoundsMemoryAccess
      @runtime.OutOfBoundsTableAccess => raise @runtime.OutOfBoundsTableAccess
      @runtime.UndefinedElement => raise @runtime.UndefinedElement
      @runtime.UninitializedElement => raise @runtime.UninitializedElement
      @runtime.IndirectCallTypeMismatch =>
        raise @runtime.IndirectCallTypeMismatch
      @runtime.DivisionByZero => raise @runtime.DivisionByZero
      @runtime.IntegerOverflow => raise @runtime.IntegerOverflow
      @runtime.InvalidConversion => raise @runtime.InvalidConversion
      @runtime.Unreachable => raise @runtime.Unreachable
      @runtime.CallStackExhausted => raise @runtime.CallStackExhausted
      @runtime.UnknownImport => raise @runtime.UnknownImport
      _ => raise @runtime.Unreachable
    })
    |> ignore
  }
  linker.register(name, instance)
  instance
}
