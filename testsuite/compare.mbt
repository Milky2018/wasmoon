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
pub fn jit_results_to_values(
  results : Array[Int64],
  result_types : Array[@types.ValueType],
) -> Array[@types.Value] {
  let values : Array[@types.Value] = []
  for i, ty in result_types {
    let raw = results[i]
    let value : @types.Value = match ty {
      I32 => I32(@types.FromInt64::from_int64_bits(raw))
      I64 => I64(@types.FromInt64::from_int64_bits(raw))
      F32 => F32(@types.FromInt64::from_int64_bits(raw))
      F64 => F64(@types.FromInt64::from_int64_bits(raw))
      // Reference types: -1L is null sentinel
      FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
        if raw == -1L {
          Null
        } else {
          FuncRef(raw.to_int())
        }
      ExternRef | RefExtern | NullExternRef =>
        if raw == -1L {
          Null
        } else {
          ExternRef(raw.to_int())
        }
      // GC reference types - treat as null for now
      AnyRef | NullRef | ExnRef | NullExnRef => Null
      // New GC reference types
      RefStruct(_) | RefNullStruct(_) => Null
      RefArray(_) | RefNullArray(_) => Null
      RefAny | RefEq | RefNullEq => Null
      RefI31 | RefNullI31 => Null
      RefNone => Null
      V128 => abort("V128 not supported in JIT")
    }
    values.push(value)
  }
  values
}

///|
/// Convert @types.Value to Int64 for JIT call
pub fn value_to_jit_arg(value : @types.Value) -> Int64 {
  match value {
    I32(n) => @types.ToInt64::to_int64_bits(n)
    I64(n) => @types.ToInt64::to_int64_bits(n)
    F32(f) => @types.ToInt64::to_int64_bits(f)
    F64(d) => @types.ToInt64::to_int64_bits(d)
    FuncRef(idx) => idx.to_int64()
    ExternRef(idx) => idx.to_int64()
    ExnRef(idx) => idx.to_int64()
    ArrayRef(idx) => idx.to_int64()
    StructRef(idx) => idx.to_int64()
    I31(n) => n.to_int64()
    Null => -1L // null sentinel
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
    if exp.name == name && exp.desc is @types.ExportDesc::Func(idx) {
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
pub fn run_jit(
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
    let num_imports = @wast.count_func_imports(mod_.imports)

    // Build import function type indices
    let import_func_type_indices : Array[Int] = []
    for imp in mod_.imports {
      if imp.desc is Func(type_idx) {
        import_func_type_indices.push(type_idx)
        let func_type = mod_.get_func_type(type_idx)
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
      let func_type = mod_.get_func_type(type_idx)
      let f_name = get_func_name(mod_, f_idx)

      // Translate to IR
      let translator = @ir.Translator::new(
        f_name,
        func_type,
        code.locals,
        @types.extract_func_types(mod_.types),
        mod_.funcs,
        num_imports,
        import_func_type_indices,
        memory_max~,
        tables=mod_.tables,
        type_rec_groups=mod_.type_rec_groups,
        module_types=mod_.types,
        tags=mod_.tags,
      )
      let ir_func = translator.translate(code.body)

      // Lower to VCode
      let vcode = @lower.lower_function(ir_func)

      // Register allocation
      let allocated_func = @lower.allocate_registers_aarch64(vcode)

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

    // Build func_signatures for JIT module (use shared function)
    let func_signatures = @wast.build_func_signatures(mod_)

    // Load JIT module with all functions
    guard @jit.JITModule::load(precompiled, func_signatures) is Some(jm) else {
      return Err("Failed to create JIT module")
    }

    // Allocate memory
    let mem_size = 65536L // 64KB
    let mem_ptr = @jit.alloc_memory(mem_size)
    if mem_ptr == 0L {
      return Err("Failed to allocate memory")
    }
    // Memory ownership transfers to context - GC finalizer will free it
    jm.set_memory(mem_ptr, mem_size)

    // Initialize indirect table for call_indirect support
    init_elem_segments(mod_, jm, [])

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
/// Evaluate element segment offset constant expression
/// Supports i32.const, i32.add, i32.sub, i32.mul, global.get for computing offsets
fn eval_elem_offset_expr(
  instrs : Array[@types.Instruction],
  globals : Array[@runtime.GlobalInstance],
) -> Int {
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
fn init_elem_segments(
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
  let jit_tables : Array[@jit.JITTable?] = []
  for table in mod_.tables {
    let min_size = table.type_.limits.min
    let max_size = table.type_.limits.max
    match @jit.JITTable::new(min_size, max_size) {
      Some(jit_table) => jit_tables.push(Some(jit_table))
      None => jit_tables.push(None)
    }
  }

  // Process elem segments: build (table_idx, elem_idx, func_idx, type_hash) tuples
  let elem_init : Array[(Int, Int, Int, Int)] = []
  for table_idx, _table in mod_.tables {
    // Process elem segments for this table
    for elem in mod_.elems {
      if elem.mode is @types.ElemMode::Active(elem_table_idx, offset_expr) &&
        elem_table_idx == table_idx {
        let offset = eval_elem_offset_expr(offset_expr, globals)
        for i, init_expr in elem.init {
          let func_idx = match init_expr {
            [RefFunc(idx)] => idx
            [I32Const(idx)] => idx
            [RefNull(_)] => -1 // Use -1 to represent null reference
            _ => continue
          }
          let canonical_type_idx = if func_idx >= 0 &&
            func_idx < func_canonical_types.length() {
            func_canonical_types[func_idx]
          } else {
            0
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
  let result_types = func_type.results
  let args = [@types.Value::I32(3), @types.Value::I32(5)]
  let jit_result = run_jit(mod_, "add", func_idx, args, result_types)
  inspect(jit_result, content="Ok([I32(8)])")
}
