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
pub impl Show for CompareResult with output(self, logger) {
  if self.match_ {
    logger.write_string("matched")
  } else {
    logger.write_string(self.to_string())
  }
}

///|
/// Convert JIT Int64 results to @types.Value using result_types
fn jit_results_to_values(
  results : Array[Int64],
  result_types : Array[@types.ValueType],
) -> Array[@types.Value] {
  let values : Array[@types.Value] = []
  for i, ty in result_types {
    let raw = results[i]
    let value : @types.Value = match ty {
      I32 => I32(@jit.FromInt64::from_int64_bits(raw))
      I64 => I64(@jit.FromInt64::from_int64_bits(raw))
      F32 => F32(@jit.FromInt64::from_int64_bits(raw))
      F64 => F64(@jit.FromInt64::from_int64_bits(raw))
      // Reference types: -1L is null sentinel
      FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) =>
        if raw == -1L {
          Null
        } else {
          FuncRef(raw.to_int())
        }
      ExternRef | RefExtern =>
        if raw == -1L {
          Null
        } else {
          ExternRef(raw.to_int())
        }
      V128 => abort("V128 not supported in JIT")
    }
    values.push(value)
  }
  values
}

///|
/// Convert @types.Value to Int64 for JIT call
fn value_to_jit_arg(value : @types.Value) -> Int64 {
  match value {
    I32(n) => n.to_int64()
    I64(n) => n
    F32(f) => f.reinterpret_as_int().to_int64()
    F64(d) => d.reinterpret_as_int64()
    FuncRef(idx) => idx.to_int64()
    ExternRef(idx) => idx.to_int64()
    Null => -1L // null sentinel
  }
}

///|
/// Compare two Value arrays for equality
fn values_array_equal(a : Array[@types.Value], b : Array[@types.Value]) -> Bool {
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
  let func_type = mod_.types[func_type_idx]
  let result_types = func_type.results

  // Run interpreter
  let interp_result = run_interp(mod_, func_name, args)

  // Run JIT
  let jit_result = run_jit(mod_, func_name, idx, args, result_types)

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
    if exp.name == name {
      if exp.desc is @types.ExportDesc::Func(idx) {
        return Some(idx)
      }
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
    let linker = @runtime.Linker::new()
    let store = linker.get_store()
    let instance = @executor.instantiate_with_linker(linker, "test", mod_)
    let result = @executor.call_exported_func(store, instance, func_name, args)
    Ok(result)
  } catch {
    e => Err("Interpreter error: \{e}")
  }
}

///|
fn run_jit(
  mod_ : @types.Module,
  func_name : String,
  func_idx : Int,
  args : Array[@types.Value],
  result_types : Array[@types.ValueType],
) -> Result[Array[@types.Value], String] {
  ignore(func_idx)
  try {
    // Compile ALL functions in the module (not just the target function)
    // This is necessary because the target function may call other functions
    let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
    let num_imports = count_func_imports(mod_.imports)

    // Build import function type indices
    let import_func_type_indices : Array[Int] = []
    for imp in mod_.imports {
      if imp.desc is Func(type_idx) {
        import_func_type_indices.push(type_idx)
        let func_type = mod_.types[type_idx]
        precompiled.add_import(
          imp.mod_name,
          imp.name,
          func_type.params.length(),
          func_type.results.length(),
        )
      }
    }

    // Get memory max limit from module (if memory is defined)
    let memory_max : Int? = if mod_.memories.length() > 0 {
      mod_.memories[0].limits.max
    } else {
      None
    }

    // Compile each function in the module
    for i, code in mod_.codes {
      let f_idx = num_imports + i
      let type_idx = mod_.funcs[i]
      let func_type = mod_.types[type_idx]
      let f_name = get_func_name(mod_, f_idx)

      // Translate to IR
      let translator = @ir.Translator::new(
        f_name,
        func_type,
        code.locals,
        mod_.types,
        mod_.funcs,
        num_imports,
        import_func_type_indices,
        memory_max~,
      )
      let ir_func = translator.translate(code.body)

      // Lower to VCode
      let vcode = @vcode.lower_function(ir_func)

      // Register allocation
      let allocated_func = @vcode.allocate_registers_aarch64(vcode)

      // Emit machine code
      let mc = @emit.emit_function(allocated_func)

      // Add to precompiled module
      let compiled = @vcode.CompiledFunction::new(f_name, mc, 0)
      precompiled.add_function(
        f_idx,
        f_name,
        compiled,
        func_type.params.length(),
        func_type.results.length(),
      )
    }

    // Build func_signatures for JIT module
    let func_signatures = build_func_signatures(mod_, num_imports)

    // Load JIT module with all functions
    guard @jit.JITModule::load(precompiled, func_signatures) is Some(jm) else {
      return Err("Failed to create JIT module")
    }
    defer jm.free()

    // Allocate memory using JITMemory wrapper (handles memory.grow correctly)
    let mem_size = 65536L // 64KB
    guard @jit.JITMemory::new(mem_size) is Some(memory) else {
      return Err("Failed to allocate memory")
    }
    defer memory.free() // Safe to use defer - JITMemory.free() gets current address
    jm.set_memory(memory.ptr(), mem_size)

    // Initialize indirect table for call_indirect support
    init_elem_segments(mod_, jm)

    // Call the target function
    guard jm.get_func_by_name(func_name) is Some(f) else {
      return Err("Failed to get JIT function")
    }
    let jit_args = args.map(value_to_jit_arg)
    let raw_results = jm.call_with_context(f, jit_args)

    // Convert to Values
    let values = jit_results_to_values(raw_results, result_types)
    Ok(values)
  } catch {
    e => Err("JIT error: \{e}")
  }
}

///|
/// Count function imports in imports array
fn count_func_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is Func(_) {
      count += 1
    }
  }
  count
}

///|
/// Get function name from exports or generate default name
fn get_func_name(mod_ : @types.Module, func_idx : Int) -> String {
  for exp in mod_.exports {
    if exp.desc is Func(idx) && idx == func_idx {
      return exp.name
    }
  }
  "func_\{func_idx}"
}

///|
/// Build func_signatures array for JIT module loading
fn build_func_signatures(
  mod_ : @types.Module,
  num_imports : Int,
) -> Array[(Array[@types.ValueType], Array[@types.ValueType])] {
  let total_funcs = num_imports + mod_.funcs.length()
  let signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])] = []

  // Pre-fill with empty signatures
  for _ in 0..<total_funcs {
    signatures.push(([], []))
  }

  // Fill in signatures for import functions
  let mut func_count = 0
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      if type_idx < mod_.types.length() {
        let func_type = mod_.types[type_idx]
        signatures[func_count] = (
          func_type.params.copy(),
          func_type.results.copy(),
        )
      }
      func_count += 1
    }
  }

  // Fill in signatures for local functions
  for i, type_idx in mod_.funcs {
    let func_idx = num_imports + i
    if type_idx < mod_.types.length() {
      let func_type = mod_.types[type_idx]
      signatures[func_idx] = (func_type.params.copy(), func_type.results.copy())
    }
  }
  signatures
}

///|
/// Initialize element segments for call_indirect support
fn init_elem_segments(mod_ : @types.Module, jm : @jit.JITModule) -> Unit {
  // Calculate total table size from all tables
  let mut table_size = 0
  for table in mod_.tables {
    let min_size = table.type_.limits.min
    table_size = table_size + min_size
  }
  if table_size == 0 {
    return // No tables, nothing to do
  }
  // Build function index to type hash mapping
  // We use structural type hash for type equivalence checking
  let func_type_hashes : Array[Int] = []
  // Import functions
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      let type_hash = if type_idx < mod_.types.length() {
        mod_.types[type_idx].structural_hash()
      } else {
        0
      }
      func_type_hashes.push(type_hash)
    }
  }
  // Local functions
  for type_idx in mod_.funcs {
    let type_hash = if type_idx < mod_.types.length() {
      mod_.types[type_idx].structural_hash()
    } else {
      0
    }
    func_type_hashes.push(type_hash)
  }
  // Collect elem initializers: (table_idx, func_idx, type_hash)
  let elem_init : Array[(Int, Int, Int)] = []
  for elem in mod_.elems {
    // Only process active element segments
    if elem.mode is @types.ElemMode::Active(_table_idx, offset_expr) {
      let offset = match offset_expr {
        [I32Const(n)] => n
        _ => 0
      }
      for i, init_expr in elem.init {
        // Extract function index from init expression
        let func_idx = match init_expr {
          [RefFunc(idx)] => idx
          [I32Const(idx)] => idx
          _ => continue
        }
        // Get the type hash for this function
        let type_hash = if func_idx < func_type_hashes.length() {
          func_type_hashes[func_idx]
        } else {
          0
        }
        elem_init.push((offset + i, func_idx, type_hash))
      }
    }
  }
  // Initialize the indirect table
  jm.init_indirect_table(table_size, elem_init)
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
test "compare_jit_interp: i32 add" {
  let source =
    #|(module
    #|  (func (export "add") (param i32 i32) (result i32)
    #|    (i32.add (local.get 0) (local.get 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "add", [
    @types.Value::I32(3),
    @types.Value::I32(5),
  ])
  inspect(result.match_, content="true")
  inspect(result.jit_result, content="Ok([I32(8)])")
  inspect(result.interp_result, content="Ok([I32(8)])")
}
