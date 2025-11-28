// Wasmoon Executor - Main instruction dispatch and module execution

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

    // Drop
    Drop => {
      let _ = self.stack.pop()

    }

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
    | I32GtS
    | I32LeS
    | I32GeS
    | I32Eqz
    | I32And
    | I32Or
    | I32Xor
    | I32Shl
    | I32ShrS
    | I32ShrU => self.exec_i32_numeric(instr)

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
    | I64GtS
    | I64LeS
    | I64GeS
    | I64Eqz
    | I64And
    | I64Or
    | I64Xor
    | I64Shl
    | I64ShrS
    | I64ShrU => self.exec_i64_numeric(instr)

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
    | F32Min
    | F32Max
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
    | F64Min
    | F64Max
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
    | Nop
    | Return => self.exec_control(instr)

    // Function call operations
    Call(func_idx) => self.exec_call(func_idx)
    CallIndirect(type_idx, table_idx) =>
      self.exec_call_indirect(type_idx, table_idx)

    // Fallback for unimplemented instructions
    _ => raise @runtime.RuntimeError::Unreachable
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
  let func = self.store.get_func(store_addr)

  // Get the function type to determine return arity
  let type_idx = self.instance.func_type_indices[func_idx]
  let func_type = self.instance.types[type_idx]
  let return_arity = func_type.results.length()

  // Create locals array: params + local variables
  let locals : Array[@types.Value] = []

  // Add parameters
  for arg in args {
    locals.push(arg)
  }

  // Add local variables (initialized to 0/null)
  for local_type in func.locals {
    locals.push(
      match local_type {
        I32 => I32(0)
        I64 => I64(0L)
        F32 => F32(0.0)
        F64 => F64(0.0)
        FuncRef => Null
        ExternRef => Null
        _ => Null
      },
    )
  }

  // Create and push frame
  let frame = @runtime.Frame::new(func_idx, locals, return_arity)
  self.push_frame(frame)

  // Execute function body
  self.exec_expr(func.body)

  // Pop frame
  self.pop_frame()

  // Collect return values from stack (in reverse order, then reverse back)
  let results : Array[@types.Value] = []
  for i = 0; i < return_arity; i = i + 1 {
    results.push(self.stack.pop())
  }
  results.rev_inplace()
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

  // Allocate functions
  let func_addrs : Array[Int] = []
  for code in mod.codes {
    let addr = store.alloc_func(code)
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
  let table_addrs : Array[Int] = []
  for table_type in mod.tables {
    let table = @runtime.Table::new(
      table_type.elem_type,
      table_type.limits.min,
      table_type.limits.max,
    )
    let addr = store.alloc_table(table)
    table_addrs.push(addr)
  }

  // Allocate globals with initialization
  let global_addrs : Array[Int] = []
  for global in mod.globals {
    // Evaluate init expression (for now, assume simple constant expressions)
    let init_value = eval_const_expr(global.init)
    let global_inst = @runtime.GlobalInstance::new(global.type_, init_value)
    let addr = store.alloc_global(global_inst)
    global_addrs.push(addr)
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
fn eval_const_expr(instrs : Array[@types.Instruction]) -> @types.Value {
  // WebAssembly constant expressions can only contain:
  // - i32.const, i64.const, f32.const, f64.const
  // - ref.null, ref.func
  // - global.get (for imported globals only)
  match instrs {
    [I32Const(n)] => I32(n)
    [I64Const(n)] => I64(n)
    [F32Const(f)] => F32(f)
    [F64Const(d)] => F64(d)
    _ => Null // fallback for unsupported expressions
  }
}

///|
/// Create a module instance with element and data segment initialization
pub fn instantiate_module_with_init(
  mod : @types.Module,
) -> (@runtime.Store, @runtime.ModuleInstance) raise @runtime.RuntimeError {
  let (store, instance) = instantiate_module(mod)

  // Initialize data segments (copy data to memory)
  for data in mod.datas {
    if instance.mem_addrs.length() > data.memory_idx {
      let mem = store.get_mem(instance.mem_addrs[data.memory_idx])

      // Evaluate offset expression
      let offset = match data.offset {
        [I32Const(n)] => n
        _ => 0
      }

      // Copy data to memory
      mem.init_data(offset, data.init)
    }
  }

  // Initialize element segments (populate tables with function references)
  for elem in mod.elems {
    if instance.table_addrs.length() > elem.table_idx {
      let table = store.get_table(instance.table_addrs[elem.table_idx])

      // Evaluate offset expression
      let offset = match elem.offset {
        [I32Const(n)] => n
        _ => 0
      }

      // Set table entries
      for i, func_idx in elem.init {
        table.set(offset + i, @types.Value::FuncRef(func_idx)) catch {
          _ => ()
        }
      }
    }
  }

  // Execute start function if present
  match mod.start {
    Some(start_func_idx) => {
      let ctx = ExecContext::new(store, instance)
      let _ = ctx.call_func(start_func_idx, []) catch {
        BranchWith(_, _) | Return => raise @runtime.Unreachable
        @runtime.StackUnderflow => raise @runtime.StackUnderflow
        @runtime.StackOverflow => raise @runtime.StackOverflow
        @runtime.TypeMismatch => raise @runtime.TypeMismatch
        @runtime.OutOfBoundsMemoryAccess =>
          raise @runtime.OutOfBoundsMemoryAccess
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
      }

    }
    None => ()
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
            func_addrs.push(addr)
            func_type_indices.push(type_idx)
          }
          _ => raise @runtime.UnknownImport
        }
      Memory(_) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Memory(addr)) => mem_addrs.push(addr)
          _ => raise @runtime.UnknownImport
        }
      Table(_) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Table(addr)) => table_addrs.push(addr)
          _ => raise @runtime.UnknownImport
        }
      Global(_) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Global(addr)) => global_addrs.push(addr)
          _ => raise @runtime.UnknownImport
        }
    }
  }

  // Allocate module functions
  for i, code in mod.codes {
    let addr = store.alloc_func(code)
    func_addrs.push(addr)
    func_type_indices.push(mod.funcs[i])
  }

  // Allocate memories (after imported memories)
  for mem_type in mod.memories {
    let mem = @runtime.Memory::new(mem_type.limits.min, mem_type.limits.max)
    let addr = store.alloc_mem(mem)
    mem_addrs.push(addr)
  }

  // Allocate tables (after imported tables)
  for table_type in mod.tables {
    let table = @runtime.Table::new(
      table_type.elem_type,
      table_type.limits.min,
      table_type.limits.max,
    )
    let addr = store.alloc_table(table)
    table_addrs.push(addr)
  }

  // Allocate globals (after imported globals)
  for global in mod.globals {
    let init_value = eval_const_expr(global.init)
    let global_inst = @runtime.GlobalInstance::new(global.type_, init_value)
    let addr = store.alloc_global(global_inst)
    global_addrs.push(addr)
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
  {
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
  let _ = store.register_instance(instance)

  // Initialize data segments (copy data to memory)
  for data in mod.datas {
    if instance.mem_addrs.length() > data.memory_idx {
      let mem = store.get_mem(instance.mem_addrs[data.memory_idx])
      let offset = match data.offset {
        [I32Const(n)] => n
        _ => 0
      }
      mem.init_data(offset, data.init)
    }
  }

  // Initialize element segments (populate tables with function references)
  for elem in mod.elems {
    if instance.table_addrs.length() > elem.table_idx {
      let table = store.get_table(instance.table_addrs[elem.table_idx])
      let offset = match elem.offset {
        [I32Const(n)] => n
        _ => 0
      }
      for i, func_idx in elem.init {
        table.set(offset + i, @types.Value::FuncRef(func_idx)) catch {
          _ => ()
        }
      }
    }
  }

  // Execute start function if present
  match mod.start {
    Some(start_func_idx) => {
      let ctx = ExecContext::new(store, instance)
      let _ = ctx.call_func(start_func_idx, []) catch {
        BranchWith(_, _) | Return => raise @runtime.Unreachable
        @runtime.StackUnderflow => raise @runtime.StackUnderflow
        @runtime.StackOverflow => raise @runtime.StackOverflow
        @runtime.TypeMismatch => raise @runtime.TypeMismatch
        @runtime.OutOfBoundsMemoryAccess =>
          raise @runtime.OutOfBoundsMemoryAccess
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
      }

    }
    None => ()
  }
  linker.register(name, instance)
  instance
}
