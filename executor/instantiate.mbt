// ============================================================
// Module Instantiation (MVP)
// ============================================================

///|
/// Convert an arbitrary thrown value into a `RuntimeError` for public APIs.
///
/// The executor uses internal `ControlSignal`s for structured control flow; any
/// leaked signal should be surfaced as `unreachable` externally.
fn normalize_runtime_error(e : Error) -> @runtime.RuntimeError {
  match e {
    @runtime.StackUnderflow => @runtime.StackUnderflow
    @runtime.StackOverflow => @runtime.StackOverflow
    @runtime.TypeMismatch => @runtime.TypeMismatch
    @runtime.OutOfBoundsMemoryAccess => @runtime.OutOfBoundsMemoryAccess
    @runtime.OutOfBoundsTableAccess => @runtime.OutOfBoundsTableAccess
    @runtime.OutOfBoundsArrayAccess => @runtime.OutOfBoundsArrayAccess
    @runtime.UndefinedElement => @runtime.UndefinedElement
    @runtime.UninitializedElement => @runtime.UninitializedElement
    @runtime.IndirectCallTypeMismatch => @runtime.IndirectCallTypeMismatch
    @runtime.DivisionByZero => @runtime.DivisionByZero
    @runtime.IntegerOverflow => @runtime.IntegerOverflow
    @runtime.InvalidConversion => @runtime.InvalidConversion
    @runtime.Unreachable => @runtime.Unreachable
    @runtime.CallStackExhausted => @runtime.CallStackExhausted
    @runtime.UnknownImport(_, _) as err => err
    @runtime.LinkError => @runtime.LinkError
    @runtime.LinkErrorDetail(_) as err => err
    @runtime.NullReference => @runtime.NullReference
    @runtime.UnalignedAtomic => @runtime.UnalignedAtomic
    @runtime.InvalidConstantExpression(_) as err => err
    InvocationSignal::HostInvocation(err) => normalize_runtime_error(err)
    _ => @runtime.Unreachable
  }
}

///|
fn find_export_by_name(
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

///|
/// Create a simple module instance from a parsed module
pub fn instantiate_module(
  mod : @types.Module,
) -> (@runtime.Store, @runtime.ModuleInstance) {
  let store = @runtime.Store::new()
  // Set module types for GC support
  store.set_module_types(mod.types, rec_groups=mod.type_rec_groups)

  // Allocate functions with their types
  let func_addrs : Array[Int] = []
  for i, code in mod.codes {
    let type_idx = mod.funcs[i]
    let func_type = mod.get_func_type(type_idx)
    let addr = store.alloc_func(code, func_type~, type_idx~)
    func_addrs.push(addr)
  }

  // Allocate memories
  let mem_addrs : Array[Int] = []
  for i, mem_type in mod.memories {
    let min = mem_type.limits.min.to_int()
    let max = mem_type.limits.max.map(fn(m) { m.to_int() })
    let mem = if i == 0 &&
      !mem_type.is_memory64 &&
      mem_type.page_size_log2 == 16 {
      @runtime.Memory::new_guarded_memory0(min, max)
    } else {
      @runtime.Memory::new(
        min,
        max,
        is_memory64=mem_type.is_memory64,
        page_size_log2=mem_type.page_size_log2,
      )
    }
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
      eval_const_expr(
        init_expr,
        func_addrs~,
        globals=[],
        store=Some(store),
        types=mod.types,
      ) catch {
        e => abort(e.to_string())
      }
    } else {
      @types.Value::Null
    }
    let table = @runtime.Table::new(
      table_def.type_.elem_type,
      table_def.type_.limits.min.to_int(),
      table_def.type_.limits.max.map(fn(m) { m.to_int() }),
      init_value~,
      is_table64=table_def.type_.is_table64,
    )
    let addr = store.alloc_table(table)
    table_addrs.push(addr)
  }

  // Allocate globals with initialization
  let global_addrs : Array[Int] = []
  let global_instances : Array[@runtime.GlobalInstance] = []
  for global in mod.globals {
    // Evaluate init expression with access to already-initialized globals
    // Pass store and types for GC const expr support (array.new_default, struct.new, etc.)
    let init_value = eval_const_expr(
      global.init,
      func_addrs~,
      globals=global_instances,
      store=Some(store),
      types=mod.types,
    ) catch {
      e => abort(e.to_string())
    }
    let global_inst = @runtime.GlobalInstance::new(global.type_, init_value)
    let addr = store.alloc_global(global_inst)
    global_addrs.push(addr)
    global_instances.push(global_inst)
  }

  // Allocate tags
  let tag_addrs : Array[Int] = []
  for tag in mod.tags {
    let tag_type = mod.get_func_type(tag.type_idx)
    let addr = store.alloc_tag(tag_type, type_idx=tag.type_idx)
    tag_addrs.push(addr)
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
  // Compute canonical type indices for structural equivalence
  let canonical_type_indices = @types.compute_canonical_type_indices(
    mod.types,
    type_rec_groups=mod.type_rec_groups,
  )
  let instance : @runtime.ModuleInstance = {
    types: mod.types,
    type_rec_groups: mod.type_rec_groups,
    canonical_type_indices,
    store_idx: -1,
    func_addrs,
    func_type_indices: mod.funcs,
    table_addrs,
    mem_addrs,
    global_addrs,
    tag_addrs,
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
/// and GC instructions (array.new, array.new_default, array.new_fixed, struct.new, struct.new_default)
pub fn eval_const_expr(
  instrs : Array[@types.Instruction],
  func_addrs? : Array[Int] = [],
  globals? : Array[@runtime.GlobalInstance] = [],
  store? : @runtime.Store? = None,
  types? : Array[@types.SubType] = [],
) -> @types.Value raise @runtime.RuntimeError {
  // Use stack-based evaluation for extended constant expressions
  let stack : Array[@types.Value] = []
  for instr in instrs {
    match instr {
      I32Const(n) => stack.push(I32(n))
      I64Const(n) => stack.push(I64(n))
      F32Const(f) => stack.push(F32(f))
      F64Const(d) => stack.push(F64(d))
      V128Const(bytes) => stack.push(V128(bytes))
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
        } else {
          raise @runtime.InvalidConstantExpression(
            "global.get out of range: " + idx.to_string(),
          )
        }
      // GC: i31 reference creation
      RefI31 =>
        if stack.length() < 1 {
          raise @runtime.InvalidConstantExpression(
            "ref.i31 requires an i32 operand",
          )
        } else {
          let val = stack.pop().unwrap()
          match val {
            I32(n) => {
              // i31 stores only the lower 31 bits
              let i31_val = n & 0x7FFFFFFF
              stack.push(I31(i31_val))
            }
            _ =>
              raise @runtime.InvalidConstantExpression(
                "ref.i31 operand must be i32",
              )
          }
        }
      // GC: array.new_default - create array with default values
      ArrayNewDefault(type_idx) =>
        if stack.length() < 1 {
          raise @runtime.InvalidConstantExpression(
            "array.new_default requires a length operand",
          )
        } else if store is None {
          raise @runtime.InvalidConstantExpression(
            "array.new_default requires a store",
          )
        } else if type_idx < 0 || type_idx >= types.length() {
          raise @runtime.InvalidConstantExpression(
            "array.new_default type index out of range: " + type_idx.to_string(),
          )
        } else {
          let len_val = stack.pop().unwrap()
          if len_val is I32(len) {
            let array_type = match types[type_idx].composite {
              Array(at) => at
              _ =>
                raise @runtime.InvalidConstantExpression(
                  "array.new_default expects an array type at index " +
                  type_idx.to_string(),
                )
            }
            let default_val = default_value_for_storage_type(
              array_type.element.storage_type,
            )
            let elements : Array[@types.Value] = Array::make(len, default_val)
            let ref_idx = store.unwrap().alloc_array(type_idx, elements)
            stack.push(ArrayRef(ref_idx))
          } else {
            raise @runtime.InvalidConstantExpression(
              "array.new_default length must be i32",
            )
          }
        }
      // GC: array.new - create array with initial value
      ArrayNew(type_idx) =>
        if stack.length() < 2 {
          raise @runtime.InvalidConstantExpression(
            "array.new requires (init, len) operands",
          )
        } else if store is None {
          raise @runtime.InvalidConstantExpression("array.new requires a store")
        } else {
          let len_val = stack.pop().unwrap()
          let init_val = stack.pop().unwrap()
          if len_val is I32(len) {
            let elements : Array[@types.Value] = Array::make(len, init_val)
            let ref_idx = store.unwrap().alloc_array(type_idx, elements)
            stack.push(ArrayRef(ref_idx))
          } else {
            raise @runtime.InvalidConstantExpression(
              "array.new length must be i32",
            )
          }
        }
      // GC: array.new_fixed - create array from fixed number of stack values
      ArrayNewFixed(type_idx, len) =>
        if store is None {
          raise @runtime.InvalidConstantExpression(
            "array.new_fixed requires a store",
          )
        } else if type_idx < 0 || type_idx >= types.length() {
          raise @runtime.InvalidConstantExpression(
            "array.new_fixed type index out of range: " + type_idx.to_string(),
          )
        } else {
          // Ensure this is actually an array type.
          match types[type_idx].composite {
            Array(_) => ()
            _ =>
              raise @runtime.InvalidConstantExpression(
                "array.new_fixed expects an array type at index " +
                type_idx.to_string(),
              )
          }
          if len == 0 {
            let ref_idx = store.unwrap().alloc_array(type_idx, [])
            stack.push(ArrayRef(ref_idx))
          } else if stack.length() >= len {
            // Pop elements in reverse order (last element pushed first).
            let elements : Array[@types.Value] = Array::make(
              len,
              @types.Value::Null,
            )
            for i = len - 1; i >= 0; i = i - 1 {
              elements[i] = stack.pop().unwrap()
            }
            let ref_idx = store.unwrap().alloc_array(type_idx, elements)
            stack.push(ArrayRef(ref_idx))
          } else {
            raise @runtime.InvalidConstantExpression(
              "array.new_fixed requires " +
              len.to_string() +
              " element operands",
            )
          }
        }
      // GC: struct.new_default - create struct with default values
      StructNewDefault(type_idx) =>
        if store is None {
          raise @runtime.InvalidConstantExpression(
            "struct.new_default requires a store",
          )
        } else if type_idx < 0 || type_idx >= types.length() {
          raise @runtime.InvalidConstantExpression(
            "struct.new_default type index out of range: " +
            type_idx.to_string(),
          )
        } else {
          let struct_type = match types[type_idx].composite {
            Struct(st) => st
            _ =>
              raise @runtime.InvalidConstantExpression(
                "struct.new_default expects a struct type at index " +
                type_idx.to_string(),
              )
          }
          let fields : Array[@types.Value] = []
          for field in struct_type.fields {
            fields.push(default_value_for_storage_type(field.storage_type))
          }
          let ref_idx = store.unwrap().alloc_struct(type_idx, fields)
          stack.push(StructRef(ref_idx))
        }
      // GC: struct.new - create struct from stack values
      StructNew(type_idx) =>
        if store is None {
          raise @runtime.InvalidConstantExpression(
            "struct.new requires a store",
          )
        } else if type_idx < 0 || type_idx >= types.length() {
          raise @runtime.InvalidConstantExpression(
            "struct.new type index out of range: " + type_idx.to_string(),
          )
        } else {
          let struct_type = match types[type_idx].composite {
            Struct(st) => st
            _ =>
              raise @runtime.InvalidConstantExpression(
                "struct.new expects a struct type at index " +
                type_idx.to_string(),
              )
          }
          let num_fields = struct_type.fields.length()
          if stack.length() >= num_fields {
            // Pop fields in reverse order (last field pushed first)
            let fields : Array[@types.Value] = Array::make(
              num_fields,
              @types.Value::Null,
            )
            for i = num_fields - 1; i >= 0; i = i - 1 {
              fields[i] = stack.pop().unwrap()
            }
            let ref_idx = store.unwrap().alloc_struct(type_idx, fields)
            stack.push(StructRef(ref_idx))
          } else {
            raise @runtime.InvalidConstantExpression(
              "struct.new requires " +
              num_fields.to_string() +
              " field operands",
            )
          }
        }
      // GC: any.convert_extern - convert externref to anyref
      AnyConvertExtern =>
        if stack.length() < 1 {
          raise @runtime.InvalidConstantExpression(
            "any.convert_extern requires 1 operand",
          )
        } else if store is None {
          raise @runtime.InvalidConstantExpression(
            "any.convert_extern requires a store",
          )
        } else {
          let val = stack.pop().unwrap()
          match val {
            Null => stack.push(@types.Value::Null)
            ExternRef(_) => {
              // Unwrap: host externrefs stay as ExternRef, wrapped internals get unwrapped
              let unwrapped = store.unwrap().unwrap_extern(val)
              stack.push(unwrapped)
            }
            _ => stack.push(val)
          }
        }
      // GC: extern.convert_any - convert anyref to externref
      ExternConvertAny =>
        if stack.length() < 1 {
          raise @runtime.InvalidConstantExpression(
            "extern.convert_any requires 1 operand",
          )
        } else if store is None {
          raise @runtime.InvalidConstantExpression(
            "extern.convert_any requires a store",
          )
        } else {
          let val = stack.pop().unwrap()
          match val {
            Null => stack.push(@types.Value::Null)
            ExternRef(_) =>
              // Already an externref, pass through
              stack.push(val)
            I31(_) | StructRef(_) | ArrayRef(_) => {
              // Wrap internal GC values as externref
              let wrapped = store.unwrap().wrap_as_extern(val)
              stack.push(wrapped)
            }
            _ => stack.push(val)
          }
        }
      // i32 arithmetic operations
      I32Add =>
        if stack.length() < 2 {
          raise @runtime.InvalidConstantExpression(
            "i32.add requires 2 operands",
          )
        } else {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I32(av), I32(bv)) => stack.push(I32(av + bv))
            _ =>
              raise @runtime.InvalidConstantExpression(
                "i32.add operands must be i32",
              )
          }
        }
      I32Sub =>
        if stack.length() < 2 {
          raise @runtime.InvalidConstantExpression(
            "i32.sub requires 2 operands",
          )
        } else {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I32(av), I32(bv)) => stack.push(I32(av - bv))
            _ =>
              raise @runtime.InvalidConstantExpression(
                "i32.sub operands must be i32",
              )
          }
        }
      I32Mul =>
        if stack.length() < 2 {
          raise @runtime.InvalidConstantExpression(
            "i32.mul requires 2 operands",
          )
        } else {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I32(av), I32(bv)) => stack.push(I32(av * bv))
            _ =>
              raise @runtime.InvalidConstantExpression(
                "i32.mul operands must be i32",
              )
          }
        }
      // i64 arithmetic operations
      I64Add =>
        if stack.length() < 2 {
          raise @runtime.InvalidConstantExpression(
            "i64.add requires 2 operands",
          )
        } else {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I64(av), I64(bv)) => stack.push(I64(av + bv))
            _ =>
              raise @runtime.InvalidConstantExpression(
                "i64.add operands must be i64",
              )
          }
        }
      I64Sub =>
        if stack.length() < 2 {
          raise @runtime.InvalidConstantExpression(
            "i64.sub requires 2 operands",
          )
        } else {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I64(av), I64(bv)) => stack.push(I64(av - bv))
            _ =>
              raise @runtime.InvalidConstantExpression(
                "i64.sub operands must be i64",
              )
          }
        }
      I64Mul =>
        if stack.length() < 2 {
          raise @runtime.InvalidConstantExpression(
            "i64.mul requires 2 operands",
          )
        } else {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I64(av), I64(bv)) => stack.push(I64(av * bv))
            _ =>
              raise @runtime.InvalidConstantExpression(
                "i64.mul operands must be i64",
              )
          }
        }
      _ =>
        raise @runtime.InvalidConstantExpression(
          "unsupported const expr instruction: " + instr.to_string(),
        )
    }
  }
  if stack.length() != 1 {
    raise @runtime.InvalidConstantExpression(
      "expected 1 value on stack, got " + stack.length().to_string(),
    )
  }
  stack[0]
}

///|
/// Evaluate an extended constant expression for elem/data segment offsets
/// Supports i32/i64.add, i32/i64.sub, i32/i64.mul in addition to basic constants
/// Returns the offset value as Int (truncated for i64)
fn eval_extended_const_expr(
  instrs : Array[@types.Instruction],
  globals : Array[@runtime.GlobalInstance],
) -> Int {
  // Use a simple stack-based evaluator with Int64 to handle both i32 and i64
  let stack : Array[Int64] = []
  for instr in instrs {
    match instr {
      I32Const(n) => stack.push(n.to_int64())
      I64Const(n) => stack.push(n)
      GlobalGet(idx) =>
        if idx < globals.length() {
          match globals[idx].get() {
            I32(n) => stack.push(n.to_int64())
            I64(n) => stack.push(n)
            _ => ()
          }
        }
      I32Add | I64Add =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() + b.unwrap())
        }
      I32Sub | I64Sub =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() - b.unwrap())
        }
      I32Mul | I64Mul =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() * b.unwrap())
        }
      _ => ()
    }
  }
  if stack.length() > 0 {
    stack[stack.length() - 1].to_int()
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
    // GC: handle ref.i31 expressions for i31ref element segments
    [I32Const(n), RefI31] => {
      // i31 stores only the lower 31 bits
      let i31_val = n & 0x7FFFFFFF
      Some(@types.Value::I31(i31_val))
    }
    [GlobalGet(idx), RefI31] =>
      // ref.i31 with global value
      if idx < globals.length() {
        match globals[idx].get() {
          I32(n) => {
            let i31_val = n & 0x7FFFFFFF
            Some(@types.Value::I31(i31_val))
          }
          _ => None
        }
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

  // Per WebAssembly spec: element segments are initialized BEFORE data segments
  // This ensures that if data segment initialization traps, the element segment
  // modifications to shared tables are already visible.

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

  // Execute start function if present
  if mod.start is Some(start_func_idx) {
    let ctx = ExecContext::new(store, instance)
    (ctx.call_func(start_func_idx, []) catch {
      BranchWith(_, _) | Return => raise @runtime.Unreachable
      e => raise normalize_runtime_error(e)
    })
    |> ignore
  }
  (store, instance)
}

///|
/// Import diagnostic category for strict import validation.
pub(all) enum ImportDiagnosticKind {
  MissingImport
  ImportKindMismatch
  ImportTypeMismatch
}

///|
/// Structured diagnostic for one import check failure.
pub struct ImportDiagnostic {
  import_index : Int
  module_name : String
  name : String
  kind : ImportDiagnosticKind
  expected : String
  actual : String?
  message : String
}

///|
/// Structured diagnostics result for module imports.
pub struct ImportDiagnosticsResult {
  mut ok : Bool
  diagnostics : Array[ImportDiagnostic]
}

///|
pub fn ImportDiagnosticsResult::new() -> ImportDiagnosticsResult {
  { ok: true, diagnostics: [] }
}

///|
fn push_import_diagnostic(
  result : ImportDiagnosticsResult,
  import_index : Int,
  module_name : String,
  name : String,
  kind : ImportDiagnosticKind,
  expected : String,
  actual : String?,
  message : String,
) -> Unit {
  result.ok = false
  result.diagnostics.push({
    import_index,
    module_name,
    name,
    kind,
    expected,
    actual,
    message,
  })
}

///|
fn import_desc_kind(desc : @types.ImportDesc) -> String {
  match desc {
    Func(_) => "func"
    Memory(_) => "memory"
    Table(_) => "table"
    Global(_) => "global"
    Tag(_) => "tag"
  }
}

///|
fn extern_val_kind(v : @runtime.ExternVal) -> String {
  match v {
    @runtime.ExternVal::Func(_) => "func"
    @runtime.ExternVal::Memory(_) => "memory"
    @runtime.ExternVal::Table(_) => "table"
    @runtime.ExternVal::Global(_) => "global"
    @runtime.ExternVal::Tag(_) => "tag"
  }
}

///|
fn format_limits_pair(limits : (Int, Int?)) -> String {
  let max_text = match limits.1 {
    Some(max) => max.to_string()
    None => "none"
  }
  "(min=\{limits.0}, max=\{max_text})"
}

///|
/// Validate module imports against provided imports with structured diagnostics.
pub fn validate_imports_with_diagnostics(
  store : @runtime.Store,
  mod : @types.Module,
  imports : @runtime.Imports,
) -> ImportDiagnosticsResult {
  store.set_module_types(mod.types, rec_groups=mod.type_rec_groups)
  let result = ImportDiagnosticsResult::new()
  let canonical_type_indices = @types.compute_canonical_type_indices(
    mod.types,
    type_rec_groups=mod.type_rec_groups,
  )
  for import_index, imp in mod.imports {
    let expected_kind = import_desc_kind(imp.desc)
    let resolved = imports.resolve(imp.mod_name, imp.name)
    guard resolved is Some(extern_val) else {
      push_import_diagnostic(
        result,
        import_index,
        imp.mod_name,
        imp.name,
        MissingImport,
        expected_kind,
        None,
        "import \{imp.mod_name}.\{imp.name} is missing",
      )
      continue
    }

    if extern_val_kind(extern_val) != expected_kind {
      push_import_diagnostic(
        result,
        import_index,
        imp.mod_name,
        imp.name,
        ImportKindMismatch,
        expected_kind,
        Some(extern_val_kind(extern_val)),
        "import \{imp.mod_name}.\{imp.name} kind mismatch",
      )
      continue
    }

    match imp.desc {
      Func(type_idx) =>
        match extern_val {
          @runtime.ExternVal::Func(addr) => {
            let expected_type = mod.get_func_type(type_idx)
            let actual_type = match store.get_func_type_opt(addr) {
              Some(type_) => type_
              None => {
                push_import_diagnostic(
                  result,
                  import_index,
                  imp.mod_name,
                  imp.name,
                  ImportTypeMismatch,
                  expected_type.to_string(),
                  None,
                  "import \{imp.mod_name}.\{imp.name} refers to invalid function address \{addr}",
                )
                continue
              }
            }
            match store.get_func_owner(addr) {
              Some(owner) => {
                let actual_type_idx = store.get_func_type_idx(addr)
                let canonical_export = @types.compute_canonical_type_indices(
                  owner.types,
                  type_rec_groups=owner.type_rec_groups,
                )
                let ctx = @types.SubtypingContext::cross_module(
                  owner.types,
                  mod.types,
                  rec_groups1=owner.type_rec_groups,
                  rec_groups2=mod.type_rec_groups,
                  canonical1=canonical_export,
                  canonical2=canonical_type_indices,
                )
                if !ctx.is_subtype(actual_type_idx, type_idx) {
                  push_import_diagnostic(
                    result,
                    import_index,
                    imp.mod_name,
                    imp.name,
                    ImportTypeMismatch,
                    expected_type.to_string(),
                    Some(actual_type.to_string()),
                    "import \{imp.mod_name}.\{imp.name} function type mismatch (cross-module subtype check failed)",
                  )
                }
              }
              None => {
                let expected_rec_info = @types.get_rec_group_info(
                  mod.type_rec_groups,
                  type_idx,
                )
                if expected_rec_info != (0, 1) {
                  push_import_diagnostic(
                    result,
                    import_index,
                    imp.mod_name,
                    imp.name,
                    ImportTypeMismatch,
                    expected_type.to_string(),
                    Some(actual_type.to_string()),
                    "import \{imp.mod_name}.\{imp.name} expects singleton rec group type, got \{expected_rec_info}",
                  )
                  continue
                }
                if !@types.func_types_equal(expected_type, actual_type) {
                  push_import_diagnostic(
                    result,
                    import_index,
                    imp.mod_name,
                    imp.name,
                    ImportTypeMismatch,
                    expected_type.to_string(),
                    Some(actual_type.to_string()),
                    "import \{imp.mod_name}.\{imp.name} function type mismatch",
                  )
                }
              }
            }
          }
          _ => continue
        }
      Memory(expected_mem_type) =>
        match extern_val {
          @runtime.ExternVal::Memory(addr) => {
            let actual_mem = try store.get_mem(addr) catch {
              _ => {
                push_import_diagnostic(
                  result,
                  import_index,
                  imp.mod_name,
                  imp.name,
                  ImportTypeMismatch,
                  expected_mem_type.to_string(),
                  None,
                  "import \{imp.mod_name}.\{imp.name} refers to invalid memory address \{addr}",
                )
                continue
              }
            } noraise {
              mem => mem
            }
            let actual_limits = actual_mem.get_limits()
            if actual_mem.is_memory64() != expected_mem_type.is_memory64 {
              push_import_diagnostic(
                result,
                import_index,
                imp.mod_name,
                imp.name,
                ImportTypeMismatch,
                expected_mem_type.to_string(),
                Some(
                  "memory64=\{actual_mem.is_memory64()}, limits=\{format_limits_pair(actual_limits)}",
                ),
                "import \{imp.mod_name}.\{imp.name} memory64 mismatch",
              )
              continue
            }
            if actual_limits.0 < expected_mem_type.limits.min.to_int() {
              push_import_diagnostic(
                result,
                import_index,
                imp.mod_name,
                imp.name,
                ImportTypeMismatch,
                expected_mem_type.to_string(),
                Some(
                  "memory64=\{actual_mem.is_memory64()}, limits=\{format_limits_pair(actual_limits)}",
                ),
                "import \{imp.mod_name}.\{imp.name} memory minimum is smaller than required",
              )
              continue
            }
            if expected_mem_type.limits.max is Some(expected_max) {
              match actual_limits.1 {
                Some(actual_max) =>
                  if actual_max > expected_max.to_int() {
                    push_import_diagnostic(
                      result,
                      import_index,
                      imp.mod_name,
                      imp.name,
                      ImportTypeMismatch,
                      expected_mem_type.to_string(),
                      Some(
                        "memory64=\{actual_mem.is_memory64()}, limits=\{format_limits_pair(actual_limits)}",
                      ),
                      "import \{imp.mod_name}.\{imp.name} memory maximum exceeds requirement",
                    )
                  }
                None =>
                  push_import_diagnostic(
                    result,
                    import_index,
                    imp.mod_name,
                    imp.name,
                    ImportTypeMismatch,
                    expected_mem_type.to_string(),
                    Some(
                      "memory64=\{actual_mem.is_memory64()}, limits=\{format_limits_pair(actual_limits)}",
                    ),
                    "import \{imp.mod_name}.\{imp.name} memory maximum is required but missing",
                  )
              }
            }
          }
          _ => continue
        }
      Table(expected_table_type) =>
        match extern_val {
          @runtime.ExternVal::Table(addr) => {
            let actual_table = try store.get_table(addr) catch {
              _ => {
                push_import_diagnostic(
                  result,
                  import_index,
                  imp.mod_name,
                  imp.name,
                  ImportTypeMismatch,
                  expected_table_type.to_string(),
                  None,
                  "import \{imp.mod_name}.\{imp.name} refers to invalid table address \{addr}",
                )
                continue
              }
            } noraise {
              table => table
            }
            let actual_limits = actual_table.get_limits()
            if actual_table.get_elem_type() != expected_table_type.elem_type {
              push_import_diagnostic(
                result,
                import_index,
                imp.mod_name,
                imp.name,
                ImportTypeMismatch,
                expected_table_type.to_string(),
                Some(
                  "elem=\{actual_table.get_elem_type()}, table64=\{actual_table.is_table64()}, limits=\{format_limits_pair(actual_limits)}",
                ),
                "import \{imp.mod_name}.\{imp.name} table element type mismatch",
              )
              continue
            }
            if actual_table.is_table64() != expected_table_type.is_table64 {
              push_import_diagnostic(
                result,
                import_index,
                imp.mod_name,
                imp.name,
                ImportTypeMismatch,
                expected_table_type.to_string(),
                Some(
                  "elem=\{actual_table.get_elem_type()}, table64=\{actual_table.is_table64()}, limits=\{format_limits_pair(actual_limits)}",
                ),
                "import \{imp.mod_name}.\{imp.name} table64 mismatch",
              )
              continue
            }
            if actual_limits.0 < expected_table_type.limits.min.to_int() {
              push_import_diagnostic(
                result,
                import_index,
                imp.mod_name,
                imp.name,
                ImportTypeMismatch,
                expected_table_type.to_string(),
                Some(
                  "elem=\{actual_table.get_elem_type()}, table64=\{actual_table.is_table64()}, limits=\{format_limits_pair(actual_limits)}",
                ),
                "import \{imp.mod_name}.\{imp.name} table minimum is smaller than required",
              )
              continue
            }
            if expected_table_type.limits.max is Some(expected_max) {
              match actual_limits.1 {
                Some(actual_max) =>
                  if actual_max > expected_max.to_int() {
                    push_import_diagnostic(
                      result,
                      import_index,
                      imp.mod_name,
                      imp.name,
                      ImportTypeMismatch,
                      expected_table_type.to_string(),
                      Some(
                        "elem=\{actual_table.get_elem_type()}, table64=\{actual_table.is_table64()}, limits=\{format_limits_pair(actual_limits)}",
                      ),
                      "import \{imp.mod_name}.\{imp.name} table maximum exceeds requirement",
                    )
                  }
                None =>
                  push_import_diagnostic(
                    result,
                    import_index,
                    imp.mod_name,
                    imp.name,
                    ImportTypeMismatch,
                    expected_table_type.to_string(),
                    Some(
                      "elem=\{actual_table.get_elem_type()}, table64=\{actual_table.is_table64()}, limits=\{format_limits_pair(actual_limits)}",
                    ),
                    "import \{imp.mod_name}.\{imp.name} table maximum is required but missing",
                  )
              }
            }
          }
          _ => continue
        }
      Global(expected_global_type) =>
        match extern_val {
          @runtime.ExternVal::Global(addr) => {
            let actual_global = try store.get_global(addr) catch {
              _ => {
                push_import_diagnostic(
                  result,
                  import_index,
                  imp.mod_name,
                  imp.name,
                  ImportTypeMismatch,
                  expected_global_type.to_string(),
                  None,
                  "import \{imp.mod_name}.\{imp.name} refers to invalid global address \{addr}",
                )
                continue
              }
            } noraise {
              global => global
            }
            let actual_type = actual_global.get_type()
            if actual_type.mutable {
              if actual_type.value_type != expected_global_type.value_type ||
                actual_type.mutable != expected_global_type.mutable {
                push_import_diagnostic(
                  result,
                  import_index,
                  imp.mod_name,
                  imp.name,
                  ImportTypeMismatch,
                  expected_global_type.to_string(),
                  Some(actual_type.to_string()),
                  "import \{imp.mod_name}.\{imp.name} mutable global type mismatch",
                )
              }
            } else {
              if !is_value_type_subtype(
                  actual_type.value_type,
                  expected_global_type.value_type,
                ) {
                push_import_diagnostic(
                  result,
                  import_index,
                  imp.mod_name,
                  imp.name,
                  ImportTypeMismatch,
                  expected_global_type.to_string(),
                  Some(actual_type.to_string()),
                  "import \{imp.mod_name}.\{imp.name} immutable global type mismatch",
                )
                continue
              }
              if expected_global_type.mutable {
                push_import_diagnostic(
                  result,
                  import_index,
                  imp.mod_name,
                  imp.name,
                  ImportTypeMismatch,
                  expected_global_type.to_string(),
                  Some(actual_type.to_string()),
                  "import \{imp.mod_name}.\{imp.name} expected mutable global but actual is immutable",
                )
              }
            }
          }
          _ => continue
        }
      Tag(expected_type_idx) =>
        match extern_val {
          @runtime.ExternVal::Tag(addr) => {
            let actual_type = try store.get_tag_type(addr) catch {
              _ => {
                push_import_diagnostic(
                  result,
                  import_index,
                  imp.mod_name,
                  imp.name,
                  ImportTypeMismatch,
                  mod.get_func_type(expected_type_idx).to_string(),
                  None,
                  "import \{imp.mod_name}.\{imp.name} refers to invalid tag address \{addr}",
                )
                continue
              }
            } noraise {
              type_ => type_
            }
            let expected_type = mod.get_func_type(expected_type_idx)
            let owner = store.get_tag_owner(addr)
            let actual_type_idx = store.get_tag_type_idx(addr)
            match owner {
              Some(owner_instance) => {
                let expected_rec_info = @types.get_rec_group_info(
                  mod.type_rec_groups,
                  expected_type_idx,
                )
                let actual_rec_info = @types.get_rec_group_info(
                  owner_instance.type_rec_groups,
                  actual_type_idx,
                )
                if expected_rec_info.1 == 1 && actual_rec_info.1 == 1 {
                  if expected_type.params != actual_type.params {
                    push_import_diagnostic(
                      result,
                      import_index,
                      imp.mod_name,
                      imp.name,
                      ImportTypeMismatch,
                      expected_type.to_string(),
                      Some(actual_type.to_string()),
                      "import \{imp.mod_name}.\{imp.name} tag parameter mismatch",
                    )
                  }
                } else {
                  let canonical_export = @types.compute_canonical_type_indices(
                    owner_instance.types,
                    type_rec_groups=owner_instance.type_rec_groups,
                  )
                  let ctx = @types.SubtypingContext::cross_module(
                    owner_instance.types,
                    mod.types,
                    rec_groups1=owner_instance.type_rec_groups,
                    rec_groups2=mod.type_rec_groups,
                    canonical1=canonical_export,
                    canonical2=canonical_type_indices,
                  )
                  if !(ctx.is_subtype(actual_type_idx, expected_type_idx) &&
                    ctx.is_subtype(expected_type_idx, actual_type_idx)) {
                    push_import_diagnostic(
                      result,
                      import_index,
                      imp.mod_name,
                      imp.name,
                      ImportTypeMismatch,
                      expected_type.to_string(),
                      Some(actual_type.to_string()),
                      "import \{imp.mod_name}.\{imp.name} tag type mismatch",
                    )
                  }
                }
              }
              None =>
                if expected_type.params != actual_type.params {
                  push_import_diagnostic(
                    result,
                    import_index,
                    imp.mod_name,
                    imp.name,
                    ImportTypeMismatch,
                    expected_type.to_string(),
                    Some(actual_type.to_string()),
                    "import \{imp.mod_name}.\{imp.name} tag parameter mismatch",
                  )
                }
            }
          }
          _ => continue
        }
    }
  }
  result
}

///|
pub(all) enum InstantiateWithImportDiagnosticsResult {
  Ok(@runtime.ModuleInstance)
  ImportError(ImportDiagnosticsResult)
  RuntimeFailure(@runtime.RuntimeError)
}

///|
/// Instantiate module with strict import diagnostics.
pub fn instantiate_module_with_import_diagnostics(
  store : @runtime.Store,
  mod : @types.Module,
  imports : @runtime.Imports,
) -> InstantiateWithImportDiagnosticsResult {
  let diagnostics = validate_imports_with_diagnostics(store, mod, imports)
  if !diagnostics.ok {
    return ImportError(diagnostics)
  }
  let instance = instantiate_module_with_imports(store, mod, imports) catch {
    e => return RuntimeFailure(normalize_runtime_error(e))
  }
  Ok(instance)
}

///|
/// Create a module instance with imports using an existing store
/// Raises UnknownImport if any required import is not provided
pub fn instantiate_module_with_imports(
  store : @runtime.Store,
  mod : @types.Module,
  imports : @runtime.Imports,
) -> @runtime.ModuleInstance raise @runtime.RuntimeError {
  // Set module types for GC support
  store.set_module_types(mod.types, rec_groups=mod.type_rec_groups)

  // Compute canonical type indices early (needed for import type checking)
  let canonical_type_indices = @types.compute_canonical_type_indices(
    mod.types,
    type_rec_groups=mod.type_rec_groups,
  )

  // Process imports first
  let func_addrs : Array[Int] = []
  let func_type_indices : Array[Int] = []
  let mem_addrs : Array[Int] = []
  let table_addrs : Array[Int] = []
  let global_addrs : Array[Int] = []
  let tag_addrs : Array[Int] = []

  // Import functions and memories first (they come before module definitions in the index space)
  for imp in mod.imports {
    match imp.desc {
      Func(type_idx) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Func(addr)) => {
            // Check that imported function type matches expected type
            let owner = store.get_func_owner(addr)
            let expected_type = mod.get_func_type(type_idx)
            let actual_type = store.get_func_type(addr)
            match owner {
              Some(o) => {
                // Cross-module function: the exported type must be a subtype
                // of the imported type (T_export <: T_import).
                // For GC types, this means checking declared supertype chains
                // and structural compatibility across modules.
                let actual_type_idx = store.get_func_type_idx(addr)

                // Compute canonical indices for both modules
                let canonical_import = canonical_type_indices
                let canonical_export = @types.compute_canonical_type_indices(
                  o.types,
                  type_rec_groups=o.type_rec_groups,
                )

                // Use subtyping context for cross-module comparison
                let ctx = @types.SubtypingContext::cross_module(
                  o.types,
                  mod.types,
                  rec_groups1=o.type_rec_groups,
                  rec_groups2=mod.type_rec_groups,
                  canonical1=canonical_export,
                  canonical2=canonical_import,
                )
                // Check if T_export <: T_import
                if not(ctx.is_subtype(actual_type_idx, type_idx)) {
                  raise @runtime.LinkErrorDetail(
                    "import \{imp.mod_name}.\{imp.name}: exported type is not a subtype of imported type",
                  )
                }
              }
              None => {
                // Host function: direct type comparison (no rec groups)
                // Host functions are always considered singleton rec groups
                let expected_rec_info = @types.get_rec_group_info(
                  mod.type_rec_groups,
                  type_idx,
                )
                // Host functions must be imported by singleton rec group types
                if expected_rec_info != (0, 1) {
                  raise @runtime.LinkErrorDetail(
                    "import \{imp.mod_name}.\{imp.name}: expected singleton rec group type, got \{expected_rec_info}",
                  )
                }
                // Compare types structurally
                if not(@types.func_types_equal(expected_type, actual_type)) {
                  raise @runtime.LinkErrorDetail(
                    "import \{imp.mod_name}.\{imp.name}: type mismatch; expected=\{expected_type} actual=\{actual_type}",
                  )
                }
              }
            }
            func_addrs.push(addr)
            func_type_indices.push(type_idx)
          }
          _ => raise @runtime.UnknownImport(imp.mod_name, imp.name)
        }
      Memory(expected_mem_type) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Memory(addr)) => {
            // Check memory type compatibility
            let actual_mem = store.get_mem(addr)
            let actual_limits = actual_mem.get_limits()
            // Memory64 status must match
            if actual_mem.is_memory64() != expected_mem_type.is_memory64 {
              raise @runtime.LinkError
            }
            // Import memory limits must be compatible:
            // - actual min >= expected min
            // - if expected has max, actual must have max <= expected max
            if actual_limits.0 < expected_mem_type.limits.min.to_int() {
              raise @runtime.LinkError
            }
            if expected_mem_type.limits.max is Some(expected_max) {
              match actual_limits.1 {
                Some(actual_max) =>
                  if actual_max > expected_max.to_int() {
                    raise @runtime.LinkError
                  }
                None => raise @runtime.LinkError
              }
            } // actual has no max but expected does
            mem_addrs.push(addr)
          }
          _ => raise @runtime.UnknownImport(imp.mod_name, imp.name)
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
            // Table64 status must match
            if actual_table.is_table64() != expected_table_type.is_table64 {
              raise @runtime.LinkError
            }
            // Limits must be compatible:
            // - actual min >= expected min
            // - if expected has max, actual must have max <= expected max
            if actual_limits.0 < expected_table_type.limits.min.to_int() {
              raise @runtime.LinkError
            }
            if expected_table_type.limits.max is Some(expected_max) {
              match actual_limits.1 {
                Some(actual_max) =>
                  if actual_max > expected_max.to_int() {
                    raise @runtime.LinkError
                  }
                None => raise @runtime.LinkError
              }
            }
            table_addrs.push(addr)
          }
          _ => raise @runtime.UnknownImport(imp.mod_name, imp.name)
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
          _ => raise @runtime.UnknownImport(imp.mod_name, imp.name)
        }
      Tag(expected_type_idx) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Tag(addr)) => {
            // Check that imported tag type matches expected type
            let owner = store.get_tag_owner(addr)
            let actual_type_idx = store.get_tag_type_idx(addr)
            let expected_type = mod.get_func_type(expected_type_idx)
            let actual_type = try! store.get_tag_type(addr)
            match owner {
              Some(o) => {
                // Cross-module tag: check rec group membership
                let expected_rec_info = @types.get_rec_group_info(
                  mod.type_rec_groups,
                  expected_type_idx,
                )
                let actual_rec_info = @types.get_rec_group_info(
                  o.type_rec_groups,
                  actual_type_idx,
                )

                // If both are singleton rec groups, compare structurally
                if expected_rec_info.1 == 1 && actual_rec_info.1 == 1 {
                  // Both are singleton - structural comparison
                  if expected_type.params != actual_type.params {
                    raise @runtime.LinkError
                  }
                } else {
                  // At least one is in a multi-type rec group - use canonical comparison
                  let canonical_import = canonical_type_indices
                  let canonical_export = @types.compute_canonical_type_indices(
                    o.types,
                    type_rec_groups=o.type_rec_groups,
                  )

                  // Use subtyping context for cross-module comparison
                  let ctx = @types.SubtypingContext::cross_module(
                    o.types,
                    mod.types,
                    rec_groups1=o.type_rec_groups,
                    rec_groups2=mod.type_rec_groups,
                    canonical1=canonical_export,
                    canonical2=canonical_import,
                  )
                  // For tags in rec groups, types must match via canonical indices
                  // Check bidirectional subtyping for equality
                  if not(
                      ctx.is_subtype(actual_type_idx, expected_type_idx) &&
                      ctx.is_subtype(expected_type_idx, actual_type_idx),
                    ) {
                    raise @runtime.LinkError
                  }
                }
              }
              None =>
                // No owner - fallback to structural comparison
                if expected_type.params != actual_type.params {
                  raise @runtime.LinkError
                }
            }
            tag_addrs.push(addr)
          }
          _ => raise @runtime.UnknownImport(imp.mod_name, imp.name)
        }
    }
  }

  // Allocate module functions with their types
  for i, code in mod.codes {
    let type_idx = mod.funcs[i]
    let func_type = mod.get_func_type(type_idx)
    let addr = store.alloc_func(code, func_type~, type_idx~)
    func_addrs.push(addr)
    func_type_indices.push(type_idx)
  }

  // Allocate memories (after imported memories)
  for mem_type in mod.memories {
    let min_pages = mem_type.limits.min.to_int()
    let mem = @runtime.Memory::new(
      min_pages,
      mem_type.limits.max.map(fn(m) { m.to_int() }),
      is_memory64=mem_type.is_memory64,
      page_size_log2=mem_type.page_size_log2,
    )
    let addr = store.alloc_mem(mem)
    mem_addrs.push(addr)
  }

  // Set WASI memory address for interpreter mode WASI callbacks
  // This allows WASI functions to access the correct memory instead of hardcoded index 0
  if mem_addrs.length() > 0 {
    store.set_wasi_mem_addr(mem_addrs[0])
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
        eval_const_expr(
          init_expr,
          func_addrs~,
          globals=global_instances,
          store=Some(store),
          types=mod.types,
        )
      None => @types.Value::Null
    }
    let min_elems = table_def.type_.limits.min.to_int()
    let table = @runtime.Table::new(
      table_def.type_.elem_type,
      min_elems,
      table_def.type_.limits.max.map(fn(m) { m.to_int() }),
      init_value~,
      is_table64=table_def.type_.is_table64,
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
      store=Some(store),
      types=mod.types,
    )
    let global_inst = @runtime.GlobalInstance::new(global.type_, init_value)
    let addr = store.alloc_global(global_inst)
    global_addrs.push(addr)
    global_instances.push(global_inst)
  }

  // Allocate tags (after imported tags)
  for tag in mod.tags {
    let tag_type = mod.get_func_type(tag.type_idx)
    let addr = store.alloc_tag(tag_type, type_idx=tag.type_idx)
    tag_addrs.push(addr)
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

  // Per WebAssembly spec: element segments are initialized BEFORE data segments
  // This ensures that if data segment initialization traps, the element segment
  // modifications to shared tables are already visible.

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
  // canonical_type_indices was computed at the start of the function (for import type checking)
  let instance : @runtime.ModuleInstance = {
    types: mod.types,
    type_rec_groups: mod.type_rec_groups,
    canonical_type_indices,
    store_idx: -1,
    func_addrs,
    func_type_indices,
    table_addrs,
    mem_addrs,
    global_addrs,
    tag_addrs,
    exports: mod.exports,
    elem_segments: mod.elems,
    data_segments: mod.datas,
    dropped_elems,
    dropped_datas,
  }

  // Register instance with store for cross-module call resolution
  // This also sets the store_idx field
  store.register_instance(instance) |> ignore

  // Execute start function if present
  if mod.start is Some(start_func_idx) {
    let ctx = ExecContext::new(store, instance)
    (ctx.call_func(start_func_idx, []) catch {
      BranchWith(_, _) | Return => raise @runtime.Unreachable
      e => raise normalize_runtime_error(e)
    })
    |> ignore
  }
  instance
}

///|
/// Failure category for controlled export invocation.
pub(all) enum CallExportFailureKind {
  ExportNotFound
  NotFunctionExport
  Trap
  HostInvocation
  Cancelled
  UnsupportedOption
}

///|
/// Structured failure for controlled export invocation.
pub struct CallExportFailure {
  kind : CallExportFailureKind
  message : String
  runtime_error : @runtime.RuntimeError?
}

///|
/// Result type for controlled export invocation.
pub(all) enum CallExportResult {
  Ok(Array[@types.Value])
  Err(CallExportFailure)
}

///|
/// Options for controlled export invocation.
///
/// Current engine support:
/// - `cancel` is checked before invocation.
/// - `timeout_ms`, `fuel`, and `budget` are parsed and surfaced as structured
///   `UnsupportedOption` errors for integration-time capability probing.
pub struct CallExportOptions {
  timeout_ms : Int?
  fuel : Int?
  budget : Int?
  cancel : (() -> Bool)?
}

///|
pub fn CallExportOptions::new(
  timeout_ms? : Int? = None,
  fuel? : Int? = None,
  budget? : Int? = None,
  cancel? : (() -> Bool)? = None,
) -> CallExportOptions {
  { timeout_ms, fuel, budget, cancel }
}

///|
fn call_export_failure(
  kind : CallExportFailureKind,
  message : String,
  runtime_error? : @runtime.RuntimeError? = None,
) -> CallExportFailure {
  { kind, message, runtime_error }
}

///|
fn check_call_export_options(options : CallExportOptions) -> CallExportFailure? {
  if options.timeout_ms is Some(timeout_ms) {
    return Some(
      call_export_failure(
        UnsupportedOption,
        "timeout_ms is not supported yet (requested: \{timeout_ms})",
      ),
    )
  }
  if options.fuel is Some(fuel) {
    return Some(
      call_export_failure(
        UnsupportedOption,
        "fuel is not supported yet (requested: \{fuel})",
      ),
    )
  }
  if options.budget is Some(budget) {
    return Some(
      call_export_failure(
        UnsupportedOption,
        "budget is not supported yet (requested: \{budget})",
      ),
    )
  }
  if options.cancel is Some(cancel_fn) && cancel_fn() {
    return Some(
      call_export_failure(Cancelled, "invocation cancelled before execution"),
    )
  }
  None
}

///|
/// Controlled export invocation with structured result.
pub fn call_exported_func_with_options(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  name : String,
  args : Array[@types.Value],
  options? : CallExportOptions = CallExportOptions::new(),
) -> CallExportResult {
  if check_call_export_options(options) is Some(failure) {
    return Err(failure)
  }

  match find_export_by_name(instance.exports, name) {
    Some(exp) =>
      match exp.desc {
        Func(func_idx) => {
          let ctx = ExecContext::new(store, instance)
          let results = ctx.call_func(func_idx, args) catch {
            BranchWith(_, _) | Return =>
              return Err(
                call_export_failure(
                  Trap,
                  "internal control signal escaped during function invocation",
                  runtime_error=Some(@runtime.Unreachable),
                ),
              )
            InvocationSignal::HostInvocation(err) => {
              let runtime_err = normalize_runtime_error(err)
              return Err(
                call_export_failure(
                  HostInvocation,
                  runtime_err.to_string(),
                  runtime_error=Some(runtime_err),
                ),
              )
            }
            e => {
              let runtime_err = normalize_runtime_error(e)
              return Err(
                call_export_failure(
                  Trap,
                  runtime_err.to_string(),
                  runtime_error=Some(runtime_err),
                ),
              )
            }
          }
          Ok(results)
        }
        _ =>
          Err(
            call_export_failure(
              NotFunctionExport,
              "export '\{name}' is not a function",
            ),
          )
      }
    None =>
      Err(call_export_failure(ExportNotFound, "export '\{name}' not found"))
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
  match find_export_by_name(instance.exports, name) {
    Some(exp) =>
      match exp.desc {
        Func(func_idx) => {
          let ctx = ExecContext::new(store, instance)
          // Catch any leaked ControlSignal and convert to RuntimeError
          ctx.call_func(func_idx, args) catch {
            BranchWith(_, _) | Return => raise @runtime.Unreachable
            e => raise normalize_runtime_error(e)
          }
        } // Unknown error
        _ => raise @runtime.UndefinedElement
      }
    None => raise @runtime.UndefinedElement
  }
}

///|
/// Call a function by module function index
pub fn call_func_by_index(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int,
  args : Array[@types.Value],
) -> Array[@types.Value] raise @runtime.RuntimeError {
  let ctx = ExecContext::new(store, instance)
  // Catch any leaked ControlSignal and convert to RuntimeError
  ctx.call_func(func_idx, args) catch {
    BranchWith(_, _) | Return => raise @runtime.Unreachable
    e => raise normalize_runtime_error(e)
  }
}

///|
/// Get the value of an exported global variable
pub fn get_exported_global(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  name : String,
) -> @types.Value raise @runtime.RuntimeError {
  match find_export_by_name(instance.exports, name) {
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
      e => raise normalize_runtime_error(e)
    })
    |> ignore
  }
  linker.register(name, instance)
  instance
}
