// ============================================================
// Module Instantiation (MVP)
// ============================================================

///|
/// Convert an arbitrary thrown value into a `RuntimeError` for public APIs.
///
/// The executor uses internal `ControlSignal`s for structured control flow; any
/// leaked signal should be surfaced as `unreachable` externally.
fn normalize_runtime_error(e : Error) -> @runtime.RuntimeError {
  match @runtime.RuntimeError::from_error(e) {
    Some(runtime_error) => runtime_error
    None =>
      match e {
        InvocationSignal::HostInvocation(err) => normalize_runtime_error(err)
        ThrowException(_, _) => UncaughtException
        ExecutionSuspended => UnhandledSuspension
        @runtime.GuestContinuationSignal::GuestContinuationYield(_, body) => {
          (body.cancel)()
          UnhandledSuspension
        }
        _ => Unreachable
      }
  }
}

///|
fn find_export_by_name(
  exports : ArrayView[@types.Export],
  target : String,
) -> @types.Export? {
  for exp in exports {
    if exp.name == target {
      return Some(exp)
    }
  }
  None
}

///|
/// Create a simple module instance from a parsed module
pub fn instantiate_module(
  mod : @types.Module,
) -> (@runtime.Store, @runtime.ModuleInstance) raise @runtime.RuntimeError {
  instantiate_validated_module(validate_execution_module(mod))
}

///|
/// Instantiate protected validation evidence without validating the module again.
pub fn instantiate_validated_module(
  validated : @validator.ValidatedModule,
) -> (@runtime.Store, @runtime.ModuleInstance) raise @runtime.RuntimeError {
  instantiate_fresh_module(validated, Bare)
}

///|
fn instantiate_fresh_module(
  validated : @validator.ValidatedModule,
  setup : CoreInstanceSetup,
) -> (@runtime.Store, @runtime.ModuleInstance) raise @runtime.RuntimeError {
  let mod = validated.snapshot()
  let store = @runtime.Store::Store()
  errdefer store.close()
  let admission = store.reserve_instance(module_=mod)
  defer admission.cancel()
  validate_continuation_gc_storage(mod)
  store.set_module_types(mod.types, rec_groups=mod.type_rec_groups)
  let instance = allocate_core_instance(
    store,
    validated,
    mod,
    admission,
    CoreAddresses(),
    setup,
  )
  if setup is Initialize && mod.start is Some(start) {
    let ctx = ExecContext::ExecContext(store, instance)
    (ctx.call_func(start, []) catch {
      BranchWith(_, _) | Return => raise Unreachable
      error => raise normalize_runtime_error(error)
    })
    |> ignore
  }
  (store, instance)
}

///|
/// Evaluate a constant initialization expression
/// Supports extended constant expressions with arithmetic operations
/// and GC instructions (array.new, array.new_default, array.new_fixed, struct.new, struct.new_default)
pub fn eval_const_expr(
  instrs : ArrayView[@types.Instruction],
  func_addrs~ : Array[Int32] = [],
  globals~ : Array[@runtime.GlobalInstance] = [],
  store~ : @runtime.Store? = None,
  types~ : Array[@types.SubType] = [],
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
          raise InvalidConstantExpression(
            "global.get out of range: " + idx.to_string(),
          )
        }
      // GC: i31 reference creation
      RefI31 =>
        if stack.length() < 1 {
          raise InvalidConstantExpression("ref.i31 requires an i32 operand")
        } else {
          let val = stack.pop().unwrap()
          match val {
            I32(n) => {
              // i31 stores only the lower 31 bits
              let i31_val = n & 0x7FFFFFFF
              stack.push(I31(i31_val))
            }
            _ => raise InvalidConstantExpression("ref.i31 operand must be i32")
          }
        }
      // GC: array.new_default - create array with default values
      ArrayNewDefault(type_idx) =>
        if stack.length() < 1 {
          raise InvalidConstantExpression(
            "array.new_default requires a length operand",
          )
        } else if store is None {
          raise InvalidConstantExpression("array.new_default requires a store")
        } else if type_idx < 0 || type_idx >= types.length() {
          raise InvalidConstantExpression(
            "array.new_default type index out of range: " + type_idx.to_string(),
          )
        } else {
          let len_val = stack.pop().unwrap()
          if len_val is I32(len) {
            let array_type = match types[type_idx].composite {
              Array(at) => at
              _ =>
                raise InvalidConstantExpression(
                  "array.new_default expects an array type at index " +
                  type_idx.to_string(),
                )
            }
            let default_val = default_value_for_storage_type(
              array_type.element.storage_type,
            )
            check_gc_array_length(len)
            let ref_idx = store
              .unwrap()
              .alloc_array_repeated(type_idx, len, default_val)
            stack.push(ArrayRef(ref_idx))
          } else {
            raise InvalidConstantExpression(
              "array.new_default length must be i32",
            )
          }
        }
      // GC: array.new - create array with initial value
      ArrayNew(type_idx) =>
        if stack.length() < 2 {
          raise InvalidConstantExpression(
            "array.new requires (init, len) operands",
          )
        } else if store is None {
          raise InvalidConstantExpression("array.new requires a store")
        } else {
          let len_val = stack.pop().unwrap()
          let init_val = stack.pop().unwrap()
          if len_val is I32(len) {
            check_gc_array_length(len)
            let ref_idx = store
              .unwrap()
              .alloc_array_repeated(type_idx, len, init_val)
            stack.push(ArrayRef(ref_idx))
          } else {
            raise InvalidConstantExpression("array.new length must be i32")
          }
        }
      // GC: array.new_fixed - create array from fixed number of stack values
      ArrayNewFixed(type_idx, len) =>
        if store is None {
          raise InvalidConstantExpression("array.new_fixed requires a store")
        } else if type_idx < 0 || type_idx >= types.length() {
          raise InvalidConstantExpression(
            "array.new_fixed type index out of range: " + type_idx.to_string(),
          )
        } else {
          // Ensure this is actually an array type.
          match types[type_idx].composite {
            Array(_) => ()
            _ =>
              raise InvalidConstantExpression(
                "array.new_fixed expects an array type at index " +
                type_idx.to_string(),
              )
          }
          if len == 0 {
            let ref_idx = store.unwrap().alloc_array(type_idx, [])
            stack.push(ArrayRef(ref_idx))
          } else if stack.length() >= len {
            // Pop elements in reverse order (last element pushed first).
            check_gc_array_length(len)
            let staging = store.unwrap().reserve_gc_array_work(len)
            defer (if staging is Some((bytes, objects)) {
              bytes.release()
              objects.release()
            })
            let elements : Array[@types.Value] = Array::make(len, Null)
            for i = len - 1; i >= 0; i = i - 1 {
              elements[i] = stack.pop().unwrap()
            }
            if staging is Some((bytes, objects)) {
              bytes.release()
              objects.release()
            }
            let ref_idx = store.unwrap().alloc_array(type_idx, elements)
            stack.push(ArrayRef(ref_idx))
          } else {
            raise InvalidConstantExpression(
              "array.new_fixed requires " +
              len.to_string() +
              " element operands",
            )
          }
        }
      // GC: struct.new_default - create struct with default values
      StructNewDefault(type_idx) =>
        if store is None {
          raise InvalidConstantExpression("struct.new_default requires a store")
        } else if type_idx < 0 || type_idx >= types.length() {
          raise InvalidConstantExpression(
            "struct.new_default type index out of range: " +
            type_idx.to_string(),
          )
        } else {
          let struct_type = match types[type_idx].composite {
            Struct(st) => st
            _ =>
              raise InvalidConstantExpression(
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
          raise InvalidConstantExpression("struct.new requires a store")
        } else if type_idx < 0 || type_idx >= types.length() {
          raise InvalidConstantExpression(
            "struct.new type index out of range: " + type_idx.to_string(),
          )
        } else {
          let struct_type = match types[type_idx].composite {
            Struct(st) => st
            _ =>
              raise InvalidConstantExpression(
                "struct.new expects a struct type at index " +
                type_idx.to_string(),
              )
          }
          let num_fields = struct_type.fields.length()
          if stack.length() >= num_fields {
            // Pop fields in reverse order (last field pushed first)
            let fields : Array[@types.Value] = Array::make(num_fields, Null)
            for i = num_fields - 1; i >= 0; i = i - 1 {
              fields[i] = stack.pop().unwrap()
            }
            let ref_idx = store.unwrap().alloc_struct(type_idx, fields)
            stack.push(StructRef(ref_idx))
          } else {
            raise InvalidConstantExpression(
              "struct.new requires " +
              num_fields.to_string() +
              " field operands",
            )
          }
        }
      // GC: any.convert_extern - convert externref to anyref
      AnyConvertExtern =>
        if stack.length() < 1 {
          raise InvalidConstantExpression(
            "any.convert_extern requires 1 operand",
          )
        } else if store is None {
          raise InvalidConstantExpression("any.convert_extern requires a store")
        } else {
          let val = stack.pop().unwrap()
          match val {
            Null => stack.push(Null)
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
          raise InvalidConstantExpression(
            "extern.convert_any requires 1 operand",
          )
        } else if store is None {
          raise InvalidConstantExpression("extern.convert_any requires a store")
        } else {
          let val = stack.pop().unwrap()
          match val {
            Null => stack.push(Null)
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
          raise InvalidConstantExpression("i32.add requires 2 operands")
        } else {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I32(av), I32(bv)) => stack.push(I32(av + bv))
            _ => raise InvalidConstantExpression("i32.add operands must be i32")
          }
        }
      I32Sub =>
        if stack.length() < 2 {
          raise InvalidConstantExpression("i32.sub requires 2 operands")
        } else {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I32(av), I32(bv)) => stack.push(I32(av - bv))
            _ => raise InvalidConstantExpression("i32.sub operands must be i32")
          }
        }
      I32Mul =>
        if stack.length() < 2 {
          raise InvalidConstantExpression("i32.mul requires 2 operands")
        } else {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I32(av), I32(bv)) => stack.push(I32(av * bv))
            _ => raise InvalidConstantExpression("i32.mul operands must be i32")
          }
        }
      // i64 arithmetic operations
      I64Add =>
        if stack.length() < 2 {
          raise InvalidConstantExpression("i64.add requires 2 operands")
        } else {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I64(av), I64(bv)) => stack.push(I64(av + bv))
            _ => raise InvalidConstantExpression("i64.add operands must be i64")
          }
        }
      I64Sub =>
        if stack.length() < 2 {
          raise InvalidConstantExpression("i64.sub requires 2 operands")
        } else {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I64(av), I64(bv)) => stack.push(I64(av - bv))
            _ => raise InvalidConstantExpression("i64.sub operands must be i64")
          }
        }
      I64Mul =>
        if stack.length() < 2 {
          raise InvalidConstantExpression("i64.mul requires 2 operands")
        } else {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I64(av), I64(bv)) => stack.push(I64(av * bv))
            _ => raise InvalidConstantExpression("i64.mul operands must be i64")
          }
        }
      _ =>
        raise InvalidConstantExpression(
          "unsupported const expr instruction: " + instr.to_string(),
        )
    }
  }
  if stack.length() != 1 {
    raise InvalidConstantExpression(
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
  instrs : ArrayView[@types.Instruction],
  globals : Array[@runtime.GlobalInstance],
) -> Int64 raise @runtime.RuntimeError {
  match eval_const_expr(instrs, globals~) {
    I32(value) => value.to_int64() & 0xFFFF_FFFFL
    I64(value) => value
    _ => raise InvalidConstantExpression("expected an integer offset")
  }
}

///|
fn evaluate_element_segments(
  mod : @types.Module,
  store : @runtime.Store,
  func_addrs : Array[Int32],
  globals : Array[@runtime.GlobalInstance],
) -> Array[Array[@types.Value]] raise @runtime.RuntimeError {
  let segments : Array[Array[@types.Value]] = []
  for elem in mod.elems {
    let values : Array[@types.Value] = []
    for expr in elem.init {
      values.push(
        eval_const_expr(
          expr,
          func_addrs~,
          globals~,
          store=Some(store),
          types=mod.types,
        ),
      )
    }
    segments.push(values)
  }
  segments
}

///|
/// Create a module instance with element and data segment initialization
pub fn instantiate_module_with_init(
  mod : @types.Module,
) -> (@runtime.Store, @runtime.ModuleInstance) raise @runtime.RuntimeError {
  instantiate_validated_module_with_init(validate_execution_module(mod))
}

///|
pub fn instantiate_validated_module_with_init(
  validated : @validator.ValidatedModule,
) -> (@runtime.Store, @runtime.ModuleInstance) raise @runtime.RuntimeError {
  instantiate_fresh_module(validated, Initialize)
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
  import_index : Int32
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
pub fn ImportDiagnosticsResult::ImportDiagnosticsResult() -> ImportDiagnosticsResult {
  { ok: true, diagnostics: [], }
}

///|
fn push_import_diagnostic(
  result : ImportDiagnosticsResult,
  import_index : Int32,
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
    Func(_) => "func"
    Memory(_) => "memory"
    Table(_) => "table"
    Global(_) => "global"
    Tag(_) => "tag"
  }
}

///|
fn[T : Show] format_limits_pair(limits : (T, T?)) -> String {
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
) -> ImportDiagnosticsResult raise @runtime.RuntimeError {
  imports.check_store(store)
  let work = store.admit_module_work(mod)
  defer (if work is Some(lease) { lease.release() })
  let validated = validate_execution_module(mod)
  let mod = validated.snapshot()
  let result = ImportDiagnosticsResult::ImportDiagnosticsResult()
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

    if check_import_type(store, mod, imp, extern_val) is Some(mismatch) {
      push_import_diagnostic(
        result,
        import_index,
        imp.mod_name,
        imp.name,
        ImportTypeMismatch,
        mismatch.expected,
        mismatch.actual,
        "import \{imp.mod_name}.\{imp.name} \{mismatch.message}",
      )
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
  let diagnostics = validate_imports_with_diagnostics(store, mod, imports) catch {
    e => return RuntimeFailure(normalize_runtime_error(e))
  }
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
pub fn instantiate_module_with_imports_unstarted(
  store : @runtime.Store,
  mod : @types.Module,
  imports : @runtime.Imports,
) -> @runtime.ModuleInstance raise @runtime.RuntimeError {
  imports.check_store(store)
  let admission = store.reserve_instance(module_=mod)
  errdefer admission.cancel()
  instantiate_validated_module_with_imports_unstarted(
    store,
    validate_execution_module(mod),
    imports,
    admission~,
  )
}

///|
/// Initialize a validated module's Store-owned state without running start.
pub fn instantiate_validated_module_with_imports_unstarted(
  store : @runtime.Store,
  validated : @validator.ValidatedModule,
  imports : @runtime.Imports,
  admission? : @runtime.InstanceAdmission,
) -> @runtime.ModuleInstance raise @runtime.RuntimeError {
  store.with_instantiation(() => {
    instantiate_validated_module_with_imports_impl(
      store,
      validated,
      imports,
      admission?,
    )
  })
}

///|
fn instantiate_validated_module_with_imports_impl(
  store : @runtime.Store,
  validated : @validator.ValidatedModule,
  imports : @runtime.Imports,
  admission? : @runtime.InstanceAdmission,
) -> @runtime.ModuleInstance raise @runtime.RuntimeError {
  let mod = validated.snapshot()
  imports.check_store(store)
  let admission = admission.unwrap_or_else(() => {
    store.reserve_instance(module_=mod)
  })
  store.check_instance_admission(admission, validated~)
  errdefer admission.cancel()
  validate_continuation_gc_storage(mod)
  // Set module types for GC support
  store.set_module_types(mod.types, rec_groups=mod.type_rec_groups)

  let addresses = CoreAddresses()
  for imp in mod.imports {
    guard imports.resolve(imp.mod_name, imp.name) is Some(value) &&
      extern_val_kind(value) == import_desc_kind(imp.desc) else {
      raise UnknownImport(imp.mod_name, imp.name)
    }
    if check_import_type(store, mod, imp, value) is Some(mismatch) {
      raise mismatch.runtime_error
    }
    match value {
      Func(addr) => addresses.functions.push(addr)
      Memory(addr) => addresses.memories.push(addr)
      Table(addr) => addresses.tables.push(addr)
      Global(addr) => addresses.globals.push(addr)
      Tag(addr) => addresses.tags.push(addr)
    }
  }
  allocate_core_instance(store, validated, mod, admission, addresses, Linked)
}

///|
priv enum CoreInstanceSetup {
  Bare
  Initialize
  Linked
}

///|
#valtype
priv struct CoreAddresses {
  functions : Array[Int32]
  tables : Array[Int32]
  memories : Array[Int32]
  globals : Array[Int32]
  tags : Array[Int32]
}

///|
fn CoreAddresses::CoreAddresses() -> CoreAddresses {
  { functions: [], tables: [], memories: [], globals: [], tags: [], }
}

///|
fn allocate_core_instance(
  store : @runtime.Store,
  validated : @validator.ValidatedModule,
  mod : @types.Module,
  admission : @runtime.InstanceAdmission,
  addresses : CoreAddresses,
  setup : CoreInstanceSetup,
) -> @runtime.ModuleInstance raise @runtime.RuntimeError {
  for i in 0..<mod.codes.length() {
    addresses.functions.push(store.alloc_func(validated, i))
  }
  for memory in mod.memories {
    addresses.memories.push(
      store.alloc_mem(
        @runtime.Memory::from_type(
          memory,
          resource_budget=store.resource_budget,
        ),
      ),
    )
  }
  if setup is Linked && addresses.memories.get(0) is Some(memory) {
    store.set_wasi_mem_addr(memory)
  }
  let globals : Array[@runtime.GlobalInstance] = []
  for addr in addresses.globals {
    globals.push(store.get_global(addr))
  }
  for table in mod.tables {
    let init_value = match table.init {
      Some(expr) =>
        eval_const_expr(
          expr,
          func_addrs=addresses.functions,
          globals~,
          store=Some(store),
          types=mod.types,
        )
      None => Null
    }
    addresses.tables.push(
      store.alloc_table(
        @runtime.Table::from_type(
          table.type_,
          init_value~,
          resource_budget=store.resource_budget,
        ),
      ),
    )
  }
  for global in mod.globals {
    let init_value = eval_const_expr(
      global.init,
      func_addrs=addresses.functions,
      globals~,
      store=Some(store),
      types=mod.types,
    )
    let global = @runtime.GlobalInstance::GlobalInstance(
      global.type_,
      init_value,
    )
    addresses.globals.push(store.alloc_global(global))
    globals.push(global)
  }
  for tag in mod.tags {
    addresses.tags.push(
      store.alloc_tag(
        mod.validated_func_type_at(tag.type_idx),
        type_idx=tag.type_idx,
      ),
    )
  }
  let elem_values = evaluate_element_segments(
    mod,
    store,
    addresses.functions,
    globals,
  )
  let instance = store.new_instance(
    validated,
    admission~,
    func_addrs=addresses.functions,
    table_addrs=addresses.tables,
    mem_addrs=addresses.memories,
    global_addrs=addresses.globals,
    tag_addrs=addresses.tags,
    elem_values~,
  )
  if setup is Bare {
    return instance
  }
  // From this point initialization can publish function references into
  // imported tables. Core traps preserve prior writes and their owner.
  if setup is Linked {
    store.publish_core_instance()
  }
  // WebAssembly initializes element segments before data segments.
  for index, elem in mod.elems {
    if elem.mode is Active(table_index, offset_expr) {
      if addresses.tables.get(table_index) is Some(addr) {
        let table = store.get_table(addr)
        let offset = eval_extended_const_expr(offset_expr, globals)
        let values = elem_values[index]
        if offset < 0L ||
          offset > table.size().to_int64() - values.length().to_int64() {
          raise OutOfBoundsTableAccess
        }
        for element, value in values {
          table.set(offset.to_int() + element, value)
        }
      }
      instance.drop_element(index)
    }
  }
  for index, data in mod.datas {
    if data.offset.length() > 0 &&
      addresses.memories.get(data.memory_idx) is Some(addr) {
      let memory = store.get_mem(addr)
      let offset = eval_extended_const_expr(data.offset, globals)
      memory.init_data_at(offset, data.init)
      instance.drop_data(index)
    }
  }
  instance
}

///|
/// Create a module instance and execute its start function synchronously.
///
/// An async host import reached from the start function is rejected; use
/// `instantiate_module_with_imports_async` for that case.
pub fn instantiate_module_with_imports(
  store : @runtime.Store,
  mod : @types.Module,
  imports : @runtime.Imports,
) -> @runtime.ModuleInstance raise @runtime.RuntimeError {
  store.with_instantiation(fn() raise @runtime.RuntimeError {
    imports.check_store(store)
    let admission = store.reserve_instance(module_=mod)
    errdefer admission.cancel()
    let validated = validate_execution_module(mod)
    let instance = instantiate_validated_module_with_imports_unstarted(
      store,
      validated,
      imports,
      admission~,
    )
    if validated.start() is Some(start_func_idx) {
      call_func_by_index(store, instance, start_func_idx, []) |> ignore
    }
    instance
  })
}

///|
/// Create a module instance and allow its start function to call asynchronous
/// host imports without blocking the host thread.
pub async fn instantiate_module_with_imports_async(
  store : @runtime.Store,
  mod : @types.Module,
  imports : @runtime.Imports,
) -> @runtime.ModuleInstance raise @runtime.RuntimeError {
  store.with_async_instantiation(async fn() raise @runtime.RuntimeError {
    imports.check_store(store)
    let admission = store.reserve_instance(module_=mod)
    errdefer admission.cancel()
    let validated = validate_execution_module(mod)
    let instance = instantiate_validated_module_with_imports_unstarted(
      store,
      validated,
      imports,
      admission~,
    )
    if validated.start() is Some(start_func_idx) {
      call_func_by_index_async(store, instance, start_func_idx, []) |> ignore
    }
    instance
  })
}

///|
/// Failure category for controlled export invocation.
#derive(Debug)
pub(all) enum CallExportFailureKind {
  ExportNotFound
  NotFunctionExport
  Trap
  HostInvocation
  Cancelled
  TimedOut
  InvalidOption
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
pub impl Debug for CallExportFailure with fn to_repr(self) {
  Repr::record({
    "kind": Repr(self.kind),
    "message": Repr(self.message),
    "runtime_error": match self.runtime_error {
      Some(error) =>
        Repr::ctor("Some", [(None, Repr::literal(error.to_string()))])
      None => Repr::ctor("None", [])
    },
  })
}

///|
/// Result type for controlled export invocation.
#derive(Debug)
pub(all) enum CallExportResult {
  Ok(Array[@types.Value])
  Err(CallExportFailure)
}

///|
/// Options for controlled export invocation.
///
/// Current engine support:
/// - `cancel` is checked before invocation and at Wasm function and loop
///   safepoints. A blocking host function is not interrupted while it runs.
/// - `timeout_ms` bounds monotonic elapsed time, including host work.
/// - `fuel` and `budget` are parsed and surfaced as structured
///   `UnsupportedOption` errors for integration-time capability probing.
pub struct CallExportOptions {
  timeout_ms : Int32?
  fuel : Int32?
  budget : Int32?
  cancel : (() -> Bool)?
}

///|
pub fn CallExportOptions::CallExportOptions(
  timeout_ms~ : Int32? = None,
  fuel~ : Int32? = None,
  budget~ : Int32? = None,
  cancel~ : (() -> Bool)? = None,
) -> CallExportOptions {
  { timeout_ms, fuel, budget, cancel, }
}

///|
fn call_export_failure(
  kind : CallExportFailureKind,
  message : String,
  runtime_error~ : @runtime.RuntimeError? = None,
) -> CallExportFailure {
  { kind, message, runtime_error, }
}

///|
fn check_call_export_options(options : CallExportOptions) -> CallExportFailure? {
  if options.timeout_ms is Some(timeout_ms) && timeout_ms < 0 {
    return Some(
      call_export_failure(
        InvalidOption,
        "timeout_ms must be nonnegative (requested: \{timeout_ms})",
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
  None
}

///|
/// Controlled export invocation with structured result.
pub fn call_exported_func_with_options(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  name : String,
  args : Array[@types.Value],
  options~ : CallExportOptions = CallExportOptions(),
) -> CallExportResult {
  store.check_instance(instance) catch {
    error =>
      return Err(
        call_export_failure(
          HostInvocation,
          error.to_string(),
          runtime_error=Some(error),
        ),
      )
  }
  if check_call_export_options(options) is Some(failure) {
    return Err(failure)
  }

  guard @control.InvocationControl::new(options.timeout_ms, options.cancel)
    is Some(control) else {
    return Err(call_export_failure(InvalidOption, "invalid timeout"))
  }
  if control.poll() {
    return Err(
      call_export_failure(
        if control.expired() {
          TimedOut
        } else {
          Cancelled
        },
        if control.expired() {
          "invocation deadline exceeded before execution"
        } else {
          "invocation cancelled before execution"
        },
      ),
    )
  }
  match find_export_by_name(instance.exports, name) {
    Some(exp) =>
      match exp.desc {
        Func(func_idx) => {
          let ctx = ExecContext::ExecContext(
            store,
            instance,
            cancel=if options.timeout_ms is Some(_) || options.cancel is Some(_) {
              Some(() => control.poll())
            } else {
              None
            },
          ) catch {
            error =>
              return Err(
                call_export_failure(
                  HostInvocation,
                  error.to_string(),
                  runtime_error=Some(error),
                ),
              )
          }
          let results = ctx.call_func(func_idx, args) catch {
            BranchWith(_, _) | Return =>
              return Err(
                call_export_failure(
                  Trap,
                  "internal control signal escaped during function invocation",
                  runtime_error=Some(Unreachable),
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
            InvocationSignal::Cancelled =>
              return Err(
                call_export_failure(
                  if control.expired() {
                    TimedOut
                  } else {
                    Cancelled
                  },
                  if control.expired() {
                    "invocation deadline exceeded at wasm safepoint"
                  } else {
                    "invocation cancelled at wasm safepoint"
                  },
                ),
              )
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
          if control.expired() {
            Err(call_export_failure(TimedOut, "invocation deadline exceeded"))
          } else {
            Ok(results)
          }
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
          let ctx = ExecContext::ExecContext(store, instance)
          // Catch any leaked ControlSignal and convert to RuntimeError
          ctx.call_func(func_idx, args) catch {
            BranchWith(_, _) | Return => raise Unreachable
            e => raise normalize_runtime_error(e)
          }
        } // Unknown error
        _ => raise UndefinedElement
      }
    None => raise UndefinedElement
  }
}

///|
/// Call a function by module function index
pub fn call_func_by_index(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int32,
  args : Array[@types.Value],
) -> Array[@types.Value] raise @runtime.RuntimeError {
  let ctx = ExecContext::ExecContext(store, instance)
  // Catch any leaked ControlSignal and convert to RuntimeError
  ctx.call_func(func_idx, args) catch {
    BranchWith(_, _) | Return => raise Unreachable
    e => raise normalize_runtime_error(e)
  }
}

///|
/// Interpreter call result for host/JIT bridges that need to preserve
/// `ThrowException(tag_addr, values)` instead of normalizing it to runtime traps.
pub(all) enum InvokeWithExceptionResult {
  Returned(Array[@types.Value])
  Thrown(Int32, Array[@types.Value]) // (tag_addr, payload values)
  HostFailed(@runtime.RuntimeError)
}

///|
/// Call a function by module function index and preserve wasm exceptions.
pub fn call_func_by_index_with_exception(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int32,
  args : Array[@types.Value],
) -> InvokeWithExceptionResult raise @runtime.RuntimeError {
  let ctx = ExecContext::ExecContext(store, instance)
  let results = ctx.call_func(func_idx, args) catch {
    ThrowException(tag_addr, values) => return Thrown(tag_addr, values)
    InvocationSignal::HostInvocation(error) =>
      return HostFailed(normalize_runtime_error(error))
    BranchWith(_, _) | Return => raise Unreachable
    e => raise normalize_runtime_error(e)
  }
  Returned(results)
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
        _ => raise UndefinedElement
      }
    None => raise UndefinedElement
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
  linker.register(name, instance)
  instance
}

///|
/// Instantiate and register a module whose start function may call
/// asynchronous host imports.
pub async fn instantiate_with_linker_async(
  linker : @runtime.Linker,
  name : String,
  mod : @types.Module,
) -> @runtime.ModuleInstance raise @runtime.RuntimeError {
  let imports = linker.build_imports()
  let store = linker.get_store()
  let instance = instantiate_module_with_imports_async(store, mod, imports)
  linker.register(name, instance)
  instance
}

///|
fn validate_execution_module(
  module_ : @types.Module,
) -> @validator.ValidatedModule raise @runtime.RuntimeError {
  @validator.ValidatedModule::new(module_, stack_switching=true) catch {
    error => raise InvalidModule(error.to_string())
  }
}
