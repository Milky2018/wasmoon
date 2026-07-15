///|
/// Decode JIT GC reference value to @types.Value
/// JIT GC encoding: null=0, i31=(val<<1)|1, struct/array=gc_ref<<1
fn decode_gc_ref(raw : Int64) -> @types.Value {
  if raw == 0L {
    Null
  } else if (raw & 1L) == 1L {
    // i31: (value << 1) | 1, decode by shifting right
    I31((raw >> 1).to_int())
  } else {
    // Heap reference: gc_ref << 1, decode by shifting right
    // Note: Could be struct or array, we use StructRef as default
    StructRef((raw >> 1).to_int())
  }
}

///|
/// Decode JIT struct reference
fn decode_struct_ref(raw : Int64) -> @types.Value {
  if raw == 0L {
    Null
  } else {
    // gc_ref = raw >> 1 (1-based)
    StructRef((raw >> 1).to_int())
  }
}

///|
/// Decode JIT array reference
fn decode_array_ref(raw : Int64) -> @types.Value {
  if raw == 0L {
    Null
  } else {
    // gc_ref = raw >> 1 (1-based)
    ArrayRef((raw >> 1).to_int())
  }
}

///|
/// Decode JIT i31 reference
fn decode_i31_ref(raw : Int64) -> @types.Value {
  if raw == 0L {
    Null
  } else if (raw & 1L) == 1L {
    // i31: (value << 1) | 1
    I31((raw >> 1).to_int())
  } else {
    // Unexpected: non-i31 value in i31 slot
    Null
  }
}

///|
/// Compare JIT and interpreter execution results
/// Returns (jit_result, interp_result, match)

///|
/// Result of comparing JIT and interpreter execution
struct CompareResult {
  jit_result : Result[Array[@types.Value], String]
  interp_result : Result[Array[@types.Value], String]
  match_ : Bool
}

///|
pub fn compare_result_is_match(result : CompareResult) -> Bool {
  result.match_
}

///|
/// Return whether both execution paths failed with the expected trap text.
pub fn compare_result_errors_contain(
  result : CompareResult,
  expected : String,
) -> Bool {
  match (result.jit_result, result.interp_result) {
    (Err(jit_error), Err(interp_error)) =>
      jit_error.contains(expected) && interp_error.contains(expected)
    _ => false
  }
}

///|
pub impl Show for CompareResult with fn output(self, logger) {
  if self.match_ {
    logger.write_string("matched")
  } else {
    logger.write_string(self.to_string())
  }
}

///|
/// Convert JIT Int64 results to @types.Value using result_types
/// Note: V128 results use 2 Int64 slots (low and high parts)
pub fn jit_results_to_values(
  results : Array[Int64],
  result_types : Array[@types.ValueType],
) -> Array[@types.Value] {
  let values : Array[@types.Value] = []
  let mut slot_idx = 0
  for ty in result_types {
    let value : @types.Value = match ty {
      I32 => {
        let raw = results[slot_idx]
        slot_idx += 1
        I32(@types.FromInt64::from_int64_bits(raw))
      }
      I64 => {
        let raw = results[slot_idx]
        slot_idx += 1
        I64(@types.FromInt64::from_int64_bits(raw))
      }
      F32 => {
        let raw = results[slot_idx]
        slot_idx += 1
        F32(@types.FromInt64::from_int64_bits(raw))
      }
      F64 => {
        let raw = results[slot_idx]
        slot_idx += 1
        F64(@types.FromInt64::from_int64_bits(raw))
      }
      // Reference types: JIT null is 0
      FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef => {
        let raw = results[slot_idx]
        slot_idx += 1
        if raw == 0L {
          Null
        } else if raw < 0L {
          FuncRef((-(raw + 1L)).to_int())
        } else {
          FuncRef(raw.to_int())
        }
      }
      ExternRef | RefExtern | NullExternRef => {
        let raw = results[slot_idx]
        slot_idx += 1
        if raw == 0L {
          Null
        } else {
          match @wasmoon_jit.decode_externref(raw) {
            Some(idx) => ExternRef(idx)
            None => ExternRef(raw.to_int())
          }
        }
      }
      // GC reference types - decode using JIT encoding:
      // null = 0, i31 = (value << 1) | 1, struct/array = gc_ref << 1
      AnyRef | NullRef | RefAny | RefEq | RefNullEq => {
        let raw = results[slot_idx]
        slot_idx += 1
        decode_gc_ref(raw)
      }
      ExnRef | NullExnRef => {
        let raw = results[slot_idx]
        slot_idx += 1
        if raw == 0L {
          Null
        } else {
          ExnRef(raw.to_int())
        }
      }
      // GC struct/array reference types
      RefStruct(_) | RefNullStruct(_) | StructRef | RefStructAbs => {
        let raw = results[slot_idx]
        slot_idx += 1
        decode_struct_ref(raw)
      }
      RefArray(_) | RefNullArray(_) | ArrayRef | RefArrayAbs => {
        let raw = results[slot_idx]
        slot_idx += 1
        decode_array_ref(raw)
      }
      RefI31 | RefNullI31 => {
        let raw = results[slot_idx]
        slot_idx += 1
        decode_i31_ref(raw)
      }
      RefNone => {
        slot_idx += 1
        Null
      }
      V128 => {
        // V128 uses 2 slots: low 64 bits and high 64 bits
        let low = results[slot_idx]
        let high = results[slot_idx + 1]
        slot_idx += 2
        V128(@types.int64_pair_to_v128_le(low, high))
      }
    }
    values.push(value)
  }
  values
}

///|
/// Convert @types.Value to Int64 for JIT call with type context
/// Uses JIT encoding for GC types: null=0, i31=(val<<1)|1, struct/array=gc_ref<<1
/// For funcref/externref: null=0
pub fn value_to_jit_arg_typed(
  value : @types.Value,
  ty : @types.ValueType,
) -> Int64 {
  match value {
    I32(n) => @types.ToInt64::to_int64_bits(n)
    I64(n) => @types.ToInt64::to_int64_bits(n)
    F32(f) => @types.ToInt64::to_int64_bits(f)
    F64(d) => @types.ToInt64::to_int64_bits(d)
    // Reference types
    FuncRef(idx) =>
      match ty {
        FuncRef
        | RefFunc
        | RefFuncTyped(_)
        | RefNullFuncTyped(_)
        | NullFuncRef => @wasmoon_jit.encode_funcref_idx(idx)
        _ => idx.to_int64()
      }
    ExternRef(idx) =>
      match ty {
        ExternRef | RefExtern | NullExternRef =>
          @wasmoon_jit.encode_externref(idx)
        _ => idx.to_int64()
      }
    ExnRef(idx) => idx.to_int64()
    // GC references: encoding uses 0 for null
    ArrayRef(gc_ref) => @wasmoon_jit.encode_gc_heap_ref(gc_ref)
    StructRef(gc_ref) => @wasmoon_jit.encode_gc_heap_ref(gc_ref)
    I31(n) => (n.to_int64() << 1) | 1L
    Null => 0L
    V128(_) => abort("V128 not yet supported in testsuite")
  }
}

///|
/// Convert a value to the default single-slot JIT argument encoding used without static parameter type context.
/// Typed call sites use static parameter types so values such as V128 can expand to multiple JIT argument slots.
pub fn value_to_jit_arg(value : @types.Value) -> Int64 {
  value_to_jit_arg_typed(value, I64)
}

///|
fn append_jit_arg_slots(
  out : Array[Int64],
  value : @types.Value,
  ty : @types.ValueType,
) -> Unit {
  match (value, ty) {
    (V128(bytes), V128) => {
      out.push(@types.bytes_to_int64_le(bytes, 0))
      out.push(@types.bytes_to_int64_le(bytes, 8))
    }
    _ => out.push(value_to_jit_arg_typed(value, ty))
  }
}

///|
/// Compare two Value arrays for equality
pub fn values_array_equal(
  a : Array[@types.Value],
  b : Array[@types.Value],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if !values_equal(a[i], b[i]) {
      return false
    }
  }
  true
}

///|
/// Run a function with both JIT and interpreter, compare results
/// source: WAT source code (must be a complete module)
/// func_name: name of the exported function to call
/// args: arguments to pass to the function
pub fn compare_jit_interp(
  source : String,
  func_name : String,
  args : Array[@types.Value],
) -> CompareResult {
  compare_jit_interp_with_opt_level(source, func_name, args, 0)
}

///|
/// Run the interpreter and a JIT compiled at the requested optimization level.
pub fn compare_jit_interp_with_opt_level(
  source : String,
  func_name : String,
  args : Array[@types.Value],
  opt_level : Int,
) -> CompareResult {
  // Parse the WAT source
  let mod_ = @wat.parse(source) catch {
    e => {
      let err = "Failed to parse WAT: \{e}"
      return { jit_result: Err(err), interp_result: Err(err), match_: true }
    }
  } // Both failed with same error

  // Find the function index by name
  let func_idx = find_func_index_by_name(mod_, func_name)
  guard func_idx is Some(idx) else {
    let err = "Function '\{func_name}' not found"
    return { jit_result: Err(err), interp_result: Err(err), match_: true }
  }

  // Get function type
  let func_type_idx = mod_.funcs[idx]
  let func_type = mod_.get_func_type(func_type_idx)
  let param_types = func_type.params
  let result_types = func_type.results

  // Run interpreter
  let interp_result = run_interp(mod_, func_name, args)

  // Run JIT
  let jit_result = run_jit_with_opt_level(
    mod_, func_name, idx, args, param_types, result_types, opt_level,
  )

  // Compare results
  let match_ = match (jit_result, interp_result) {
    (Ok(jit_vals), Ok(interp_vals)) => values_array_equal(jit_vals, interp_vals)
    (Err(_), Err(_)) => true // Both errored (may or may not be same error)
    _ => false // One succeeded, one failed
  }
  { jit_result, interp_result, match_ }
}

///|
fn find_func_index_by_name(mod_ : @types.Module, name : String) -> Int? {
  for exp in mod_.exports {
    if exp.name == name && exp.desc is Func(idx) {
      return Some(idx)
    }
  }
  None
}

///|
fn run_interp(
  mod_ : @types.Module,
  func_name : String,
  args : Array[@types.Value],
) -> Result[Array[@types.Value], String] {
  try {
    // Convert module to binary for parser - need to use the binary encoder
    let linker = @runtime.Linker::Linker()
    let store = linker.get_store()
    let instance = @executor.instantiate_with_linker(linker, "test", mod_)
    let result = @executor.call_exported_func(store, instance, func_name, args)
    Ok(result)
  } catch {
    e => Err("Interpreter error: \{e}")
  }
}

///|
pub fn run_jit(
  mod_ : @types.Module,
  func_name : String,
  func_idx : Int,
  args : Array[@types.Value],
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> Result[Array[@types.Value], String] {
  run_jit_with_opt_level(
    mod_, func_name, func_idx, args, param_types, result_types, 0,
  )
}

///|
fn run_jit_with_opt_level(
  mod_ : @types.Module,
  func_name : String,
  func_idx : Int,
  args : Array[@types.Value],
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  opt_level : Int,
) -> Result[Array[@types.Value], String] {
  func_name |> ignore
  let mut jm_opt : @jit.JITModule? = None
  try {
    let linker = @runtime.Linker::Linker()
    let store = linker.get_store()
    let instance = @executor.instantiate_with_linker(linker, "test", mod_)
    let mut compile_error : String? = None
    guard @commands.compile_module_to_jit(
        mod_,
        false,
        false,
        opt_level,
        false,
        on_progress=fn(event) {
          if event.stage is Failed {
            compile_error = event.message
          }
          None
        },
      )
      is Some((precompiled, debug_db)) else {
      return Err(compile_error.unwrap_or("JIT compile returned unsupported"))
    }
    let func_signatures = @wast.build_func_signatures(mod_)
    let external_imports = @wast.build_external_imports_for_jit(
      mod_, instance, store,
    )
    let jm = @jit.JITModule::load_with_imports(
      precompiled,
      func_signatures,
      external_imports,
      debug_db~,
    )
    jm_opt = Some(jm)
    @wast.register_instance_funcrefs_for_jit(jm, instance)
    @wast.install_jit_hostcall_dispatcher(jm, store, instance)
    jm.alloc_wasm_stack(1048576L) |> ignore
    guard @wast.init_jit_memories_from_store(instance, store, jm) is Some(_) else {
      return Err("JIT memory initialization failed")
    }
    let globals_ptr = @wast.init_jit_globals_from_store(instance, store, jm)
    let use_subtype_indirect_check = true
    @wast.init_elem_segments(
      mod_,
      jm,
      instance,
      store,
      use_subtype_indirect_check~,
    )
    @wast.init_bulk_segments(
      mod_,
      jm,
      instance,
      store,
      use_subtype_indirect_check~,
    )
    @wast.sync_tables_to_jit(instance, store, jm, use_subtype_indirect_check~)
    let global_addrs : Array[Int] = []
    for addr in instance.global_addrs {
      global_addrs.push(addr)
    }
    let table_addrs : Array[Int] = []
    for addr in instance.table_addrs {
      table_addrs.push(addr)
    }
    let func_addrs : Array[Int] = []
    for addr in instance.func_addrs {
      func_addrs.push(addr)
    }
    let func_type_indices : Array[Int] = []
    for type_idx in instance.func_type_indices {
      func_type_indices.push(type_idx)
    }
    let canonical_type_indices : Array[Int] = []
    for canonical_idx in instance.canonical_type_indices {
      canonical_type_indices.push(canonical_idx)
    }
    let module_types : Array[@types.SubType] = []
    for subtype in mod_.types {
      module_types.push(subtype)
    }
    let module_rec_groups : Array[Int] = []
    for group in mod_.type_rec_groups {
      module_rec_groups.push(group)
    }
    @wast.JITModuleContext::JITModuleContext(
      jm, globals_ptr, global_addrs, table_addrs, func_addrs, func_type_indices,
      canonical_type_indices, module_types, module_rec_groups, use_subtype_indirect_check,
    )
    |> ignore
    let c_heap = @wasmoon_jit.CHeap::CHeap()
    @wasmoon_jit.gc_setup(
      c_heap,
      module_types,
      canonical_type_indices,
      ctx_ptr=jm.get_context_ptr(),
      func_type_indices~,
      func_table_ptr=jm.get_func_table_ptr(),
      num_funcs=jm.get_func_count(),
    ) catch {
      err => return Err("GC setup failed: \{err}")
    }
    jm.set_gc_heap(c_heap.get_ptr())
    guard jm.get_func(func_idx) is Some(func) else {
      @wasmoon_jit.gc_teardown(jm.get_context_ptr())
      jm.clear_segments()
      return Err("JIT function \{func_idx} not loaded")
    }
    let jit_args : Array[Int64] = []
    for i, arg in args {
      guard i < param_types.length() else {
        return Err("too many JIT arguments")
      }
      append_jit_arg_slots(jit_args, arg, param_types[i])
    }
    let raw_results = jm.call_with_context(func, jit_args)
    @wasmoon_jit.gc_teardown(jm.get_context_ptr())
    jm.clear_segments()
    Ok(jit_results_to_values(raw_results, result_types))
  } catch {
    e => {
      if jm_opt is Some(jm) {
        @wasmoon_jit.gc_teardown(jm.get_context_ptr())
        jm.clear_segments()
      }
      Err("JIT error: \{e}")
    }
  }
}

///|
pub fn current_target_arch() -> @cwasm.TargetArch {
  @wasmoon_jit.host_target_arch()
}

///|
/// Evaluate element segment offset constant expression
/// Supports i32.const, i64.const (for table64), i32.add, i32.sub, i32.mul, global.get for computing offsets
fn eval_elem_offset_expr(
  instrs : Array[@types.Instruction],
  globals : Array[@runtime.GlobalInstance],
) -> Int {
  let stack : Array[Int] = []
  for instr in instrs {
    match instr {
      I32Const(n) => stack.push(n)
      I64Const(n) => stack.push(n.to_int()) // For table64 offset expressions
      GlobalGet(idx) =>
        if idx < globals.length() {
          match globals[idx].get() {
            I32(n) => stack.push(n)
            I64(n) => stack.push(n.to_int()) // For table64
            _ => ()
          }
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
      I64Add =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() + b.unwrap())
        }
      I64Sub =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() - b.unwrap())
        }
      I64Mul =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() * b.unwrap())
        }
      _ => () // Ignore other instructions
    }
  }
  if stack.length() > 0 {
    stack[stack.length() - 1]
  } else {
    0
  }
}

///|
/// Initialize element segments for call_indirect support
pub fn init_elem_segments(
  mod_ : @types.Module,
  jm : @jit.JITModule,
  globals : Array[@runtime.GlobalInstance],
) -> Unit {
  // Multi-table support: create a separate JIT table for each WebAssembly table
  if mod_.tables.is_empty() {
    return // No tables, nothing to do
  }

  // Compute canonical type indices for structural type equivalence
  // Structurally equivalent types will have the same canonical index
  let canonical_types = @types.compute_canonical_type_indices(
    mod_.types,
    type_rec_groups=mod_.type_rec_groups,
  )

  // Build function index to canonical type index mapping
  let func_canonical_types : Array[Int] = []
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      let canonical_idx = if type_idx < canonical_types.length() {
        canonical_types[type_idx]
      } else {
        0
      }
      func_canonical_types.push(canonical_idx)
    }
  }
  for type_idx in mod_.funcs {
    let canonical_idx = if type_idx < canonical_types.length() {
      canonical_types[type_idx]
    } else {
      0
    }
    func_canonical_types.push(canonical_idx)
  }

  // Create a JIT table for each WebAssembly table
  let jit_tables : Array[@wasmoon_jit.JITTable?] = []
  for table in mod_.tables {
    let min_size = table.type_.limits.min.to_int()
    let max_size = table.type_.limits.max.map(fn(m) { m.to_int() })
    match @wasmoon_jit.JITTable::try_alloc(min_size, max_size) {
      Some(jit_table) => jit_tables.push(Some(jit_table))
      None => jit_tables.push(None)
    }
  }

  // Process elem segments: build (table_idx, elem_idx, func_idx?, type_hash) tuples
  let elem_init : Array[(Int, Int, Int?, Int)] = []
  for table_idx, _table in mod_.tables {
    // Process elem segments for this table
    for elem in mod_.elems {
      if elem.mode is Active(elem_table_idx, offset_expr) &&
        elem_table_idx == table_idx {
        let offset = eval_elem_offset_expr(offset_expr, globals)
        for i, init_expr in elem.init {
          let func_idx = match init_expr {
            [RefFunc(idx)] => Some(idx)
            [I32Const(idx)] => Some(idx)
            [RefNull(_)] => None
            _ => continue
          }
          let canonical_type_idx = match func_idx {
            Some(idx) =>
              if idx >= 0 && idx < func_canonical_types.length() {
                func_canonical_types[idx]
              } else {
                0
              }
            None => 0
          }
          // Element index within this specific table
          let elem_idx = offset + i
          elem_init.push((table_idx, elem_idx, func_idx, canonical_type_idx))
        }
      }
    }
  }

  // Initialize shared tables (new multi-table approach)
  jm.init_shared_tables(jit_tables, elem_init)
}

///|
/// Helper to format CompareResult for display
pub fn CompareResult::to_string(self : CompareResult) -> String {
  let jit_str = match self.jit_result {
    Ok(vals) => format_values(vals)
    Err(e) => "Error: \{e}"
  }
  let interp_str = match self.interp_result {
    Ok(vals) => format_values(vals)
    Err(e) => "Error: \{e}"
  }
  let match_str = if self.match_ { "MATCH" } else { "MISMATCH" }
  "JIT: \{jit_str}\nInterpreter: \{interp_str}\nResult: \{match_str}"
}

///|
pub fn CompareResult::matched(self : CompareResult) -> Bool {
  self.match_
}

///|
fn format_values(vals : Array[@types.Value]) -> String {
  if vals.is_empty() {
    return "(void)"
  }
  let parts : Array[String] = []
  for v in vals {
    parts.push(v.to_string())
  }
  parts.join(", ")
}

///|
/// Helper to run interpreter only (no JIT comparison)
/// Useful for testing instructions that JIT doesn't fully support yet
pub fn run_interp_only(
  source : String,
  func_name : String,
  args : Array[@types.Value],
) -> Result[Array[@types.Value], String] {
  try {
    let mod_ = @wat.parse(source) catch {
      e => return Err("Failed to parse WAT: \{e}")
    }
    let linker = @runtime.Linker::Linker()
    let store = linker.get_store()
    let instance = @executor.instantiate_with_linker(linker, "test", mod_)
    let result = @executor.call_exported_func(store, instance, func_name, args)
    Ok(result)
  } catch {
    e => Err("Interpreter error: \{e}")
  }
}

///|
test "compare_jit_interp: i32 add" {
  let source =
    #|(module
    #|  (func (export "add") (param i32 i32) (result i32)
    #|    (i32.add (local.get 0) (local.get 1))
    #|  )
    #|)
  // Debug: Only run JIT, not interpreter
  let mod_ = @wat.parse(source) catch { _ => abort("parse failed") }
  let func_idx = 0
  let func_type_idx = mod_.funcs[func_idx]
  let func_type = mod_.get_func_type(func_type_idx)
  let param_types = func_type.params
  let result_types = func_type.results
  let args = [@types.Value::I32(3), I32(5)]
  let jit_result = run_jit(
    mod_, "add", func_idx, args, param_types, result_types,
  )
  debug_inspect(jit_result, content="Ok([I32(8)])")
}
