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
/// Convert JIT Int64 results to @types.Value using result_types
fn jit_results_to_values(
  results : Array[Int64],
  result_types : Array[@types.ValueType],
) -> Array[@types.Value] {
  let values : Array[@types.Value] = []
  for i, ty in result_types {
    let raw = results[i]
    let value : @types.Value = match ty {
      I32 => I32(raw.to_int())
      I64 => I64(raw)
      F32 => F32(Float::from_double(raw.reinterpret_as_double()))
      F64 => F64(raw.reinterpret_as_double())
      _ => I32(0) // fallback for V128, FuncRef, etc.
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
    _ => 0L
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
  try {
    let func_code = mod_.codes[func_idx]
    let func_type_idx = mod_.funcs[func_idx]
    let func_type = mod_.types[func_type_idx]

    // Get locals
    let locals : Array[@types.ValueType] = []
    for loc in func_code.locals {
      locals.push(loc)
    }

    // Translate to IR
    let translator = @ir.Translator::new(
      func_name,
      func_type,
      locals,
      mod_.types,
      mod_.funcs.mapi(fn(i, _) { mod_.funcs[i] }),
      0, // num_imports
      [], // import_func_type_indices
    )
    let ir_func = translator.translate(func_code.body)

    // Lower to VCode
    let vcode = @vcode.lower_function(ir_func)

    // Register allocation
    let allocated_func = @vcode.allocate_registers_aarch64(vcode)

    // Emit machine code
    let mc = @vcode.emit_function(allocated_func)
    let code_bytes = mc.get_bytes()

    // Create JIT module
    let jit_module = @jit.JITModule::from_single_function(
      code_bytes,
      func_name,
      args.length(),
      result_types,
      65536L, // 64KB memory
    )
    guard jit_module is Some(jm) else {
      return Err("Failed to create JIT module")
    }

    // Call and cleanup
    let func = jm.get_func_by_name(func_name)
    guard func is Some(f) else {
      jm.free()
      return Err("Failed to get JIT function")
    }
    let jit_args = args.map(value_to_jit_arg)
    let raw_results = jm.call_with_context(f, jit_args)
    jm.free()

    // Convert to Values
    let values = jit_results_to_values(raw_results, result_types)
    Ok(values)
  } catch {
    e => Err("JIT error: \{e}")
  }
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
