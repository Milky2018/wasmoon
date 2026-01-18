///|
/// Decode JIT GC reference value to @types.Value
/// JIT GC encoding: null=0, i31=(val<<1)|1, struct/array=gc_ref<<1
fn decode_gc_ref(raw : Int64) -> @types.Value {
  if raw == 0L {
    @types.Value::Null
  } else if (raw & 1L) == 1L {
    // i31: (value << 1) | 1, decode by shifting right
    @types.Value::I31((raw >> 1).to_int())
  } else {
    // Heap reference: gc_ref << 1, decode by shifting right
    // Note: Could be struct or array, we use StructRef as default
    @types.Value::StructRef((raw >> 1).to_int())
  }
}

///|
/// Decode JIT struct reference
fn decode_struct_ref(raw : Int64) -> @types.Value {
  if raw == 0L {
    @types.Value::Null
  } else {
    // gc_ref = raw >> 1 (1-based)
    @types.Value::StructRef((raw >> 1).to_int())
  }
}

///|
/// Decode JIT array reference
fn decode_array_ref(raw : Int64) -> @types.Value {
  if raw == 0L {
    @types.Value::Null
  } else {
    // gc_ref = raw >> 1 (1-based)
    @types.Value::ArrayRef((raw >> 1).to_int())
  }
}

///|
/// Decode JIT i31 reference
fn decode_i31_ref(raw : Int64) -> @types.Value {
  if raw == 0L {
    @types.Value::Null
  } else if (raw & 1L) == 1L {
    // i31: (value << 1) | 1
    @types.Value::I31((raw >> 1).to_int())
  } else {
    // Unexpected: non-i31 value in i31 slot
    @types.Value::Null
  }
}

///|
fn bytes_to_int64_le(bytes : Bytes, offset : Int) -> Int64 {
  let mut result = 0L
  for i in 0..<8 {
    let b = bytes[offset + i].to_int64() & 0xFFL
    result = result | (b << (i * 8))
  }
  result
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
pub impl Show for CompareResult with output(self, logger) {
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
          match @jit.decode_externref(raw) {
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
        // Reconstruct 16 bytes from two Int64 values using Buffer
        let buf : @buffer.Buffer = @buffer.new(size_hint=16)
        // Low 8 bytes (little-endian)
        for i in 0..<8 {
          buf.write_byte(((low >> (i * 8)) & 0xFFL).to_byte())
        }
        // High 8 bytes (little-endian)
        for i in 0..<8 {
          buf.write_byte(((high >> (i * 8)) & 0xFFL).to_byte())
        }
        V128(buf.contents())
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
        | NullFuncRef => @jit.encode_funcref_idx(idx)
        _ => idx.to_int64()
      }
    ExternRef(idx) =>
      match ty {
        ExternRef | RefExtern | NullExternRef => @jit.encode_externref(idx)
        _ => idx.to_int64()
      }
    ExnRef(idx) => idx.to_int64()
    // GC references: encoding uses 0 for null
    ArrayRef(gc_ref) => @jit.encode_gc_heap_ref(gc_ref)
    StructRef(gc_ref) => @jit.encode_gc_heap_ref(gc_ref)
    I31(n) => (n.to_int64() << 1) | 1L
    Null => 0L
    V128(_) => abort("V128 not yet supported in testsuite")
  }
}

///|
/// Convert @types.Value to Int64 for JIT call (legacy)
pub fn value_to_jit_arg(value : @types.Value) -> Int64 {
  value_to_jit_arg_typed(value, @types.ValueType::I64)
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
  let param_types = func_type.params
  let result_types = func_type.results

  // Run interpreter
  let interp_result = run_interp(mod_, func_name, args)

  // Run JIT
  let jit_result = run_jit(
    mod_, func_name, idx, args, param_types, result_types,
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
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> Result[Array[@types.Value], String] {
  ignore(func_idx)
  try {
    // Compile ALL functions in the module (not just the target function)
    // This is necessary because the target function may call other functions
    let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
    let num_imports = @wast.count_func_imports(mod_.imports)

    // Record imports in precompiled module
    for imp in mod_.imports {
      if imp.desc is Func(type_idx) {
        let func_type = mod_.get_func_type(type_idx)
        precompiled.add_import(
          imp.mod_name,
          imp.name,
          func_type.params.length(),
          func_type.results.length(),
        )
      }
    }

    // Compile each function in the module
    for i, _ in mod_.codes {
      let f_idx = num_imports + i
      let type_idx = mod_.funcs[i]
      let func_type = mod_.get_func_type(type_idx)
      let f_name = get_func_name(mod_, f_idx)

      // Translate to IR - use simplified from_module API
      let ir_func = @ir.translate_function(mod_, i, name=f_name)

      // Lower to VCode
      let vcode = @lower.lower_function(ir_func)

      // Register allocation
      let allocated_func = @regalloc.allocate_registers_backtracking(vcode)

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

    // Allocate independent WASM stack with guard page (1MB)
    // This provides controlled stack overflow behavior
    let _ = jm.alloc_wasm_stack(1048576L)

    // Allocate linear memories.
    // We pass memory *descriptors* (wasmoon_memory_t*) into the JIT context.
    // Memory 0 (memory32) uses guarded allocation to support bounds-check elimination.
    let memories : Array[@jit.MemoryInfo] = []
    for i, mem_ty in mod_.memories {
      let pages = mem_ty.limits.min.to_int()
      let size = pages.to_int64() * 65536L
      let max_pages = mem_ty.limits.max.map(fn(m) { m.to_int() })
      let mem_desc_ptr = if i == 0 && not(mem_ty.is_memory64) {
        jm.alloc_guarded_memory(pages, max_pages)
      } else {
        @jit.alloc_memory_desc(size, max_pages, is_memory64=mem_ty.is_memory64)
      }
      if mem_desc_ptr == 0L && size > 0L {
        return Err("Failed to allocate memory")
      }
      memories.push(@jit.MemoryInfo::new(mem_desc_ptr, size, max_pages))
    }
    if not(memories.is_empty()) {
      jm.set_memory_pointers(memories)
    }

    // Initialize indirect table for call_indirect support
    init_elem_segments(mod_, jm, [])

    // Set up data segments for memory.init and data.drop
    @jit.setup_data_segments(mod_.datas)

    // Set up element segment values for table.init and elem.drop
    let elem_values = extract_elem_segment_values(mod_)
    @jit.setup_elem_segments(elem_values)

    // Set up GC heap for GC operations (struct, array, i31)
    let c_heap = @jit.CHeap::new()
    let canonical_indices = @types.compute_canonical_type_indices(
      mod_.types,
      type_rec_groups=mod_.type_rec_groups,
    )
    @jit.gc_setup(c_heap, mod_.types, canonical_indices)
    // Set GC heap in VMContext for inline allocation
    jm.set_gc_heap(c_heap.get_ptr())

    // Call the target function
    guard jm.get_func_by_name(func_name) is Some(f) else {
      @jit.gc_teardown()
      @jit.clear_segments()
      return Err("Failed to get JIT function")
    }
    // Encode args with type context for correct null handling
    let jit_args : Array[Int64] = []
    for i, arg in args {
      let ty = if i < param_types.length() {
        param_types[i]
      } else {
        @types.ValueType::I64
      }
      if ty is @types.ValueType::V128 {
        match arg {
          V128(bytes) => {
            guard bytes.length() == 16 else {
              return Err("Invalid V128 argument length: \{bytes.length()}")
            }
            let low = bytes_to_int64_le(bytes, 0)
            let high = bytes_to_int64_le(bytes, 8)
            jit_args.push(low)
            jit_args.push(high)
          }
          _ => return Err("Expected V128 argument, got \{arg}")
        }
      } else {
        jit_args.push(value_to_jit_arg_typed(arg, ty))
      }
    }
    let raw_results = jm.call_with_context(f, jit_args)

    // Tear down GC context and segments after JIT call
    @jit.gc_teardown()
    @jit.clear_segments()

    // Convert to Values
    let values = jit_results_to_values(raw_results, result_types)
    Ok(values)
  } catch {
    e => {
      // Ensure GC teardown and segment cleanup on error path
      @jit.gc_teardown()
      @jit.clear_segments()
      Err("JIT error: \{e}")
    }
  }
}

///|
/// Extract element segment values for JIT segment setup
/// Returns an array of Int64 arrays, one per element segment
/// Each Int64 is a function index or 0 for null
fn extract_elem_segment_values(mod_ : @types.Module) -> Array[Array[Int64]] {
  let result : Array[Array[Int64]] = []
  for elem in mod_.elems {
    let values : Array[Int64] = []
    for init_expr in elem.init {
      let func_idx : Int64 = match init_expr {
        [RefFunc(idx)] => idx.to_int64()
        [I32Const(idx)] => idx.to_int64()
        [RefNull(_)] => 0L // null reference
        _ => 0L
      }
      values.push(func_idx)
    }
    result.push(values)
  }
  result
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
  let jit_tables : Array[@jit.JITTable?] = []
  for table in mod_.tables {
    let min_size = table.type_.limits.min.to_int()
    let max_size = table.type_.limits.max.map(fn(m) { m.to_int() })
    match @jit.JITTable::new(min_size, max_size) {
      Some(jit_table) => jit_tables.push(Some(jit_table))
      None => jit_tables.push(None)
    }
  }

  // Process elem segments: build (table_idx, elem_idx, func_idx?, type_hash) tuples
  let elem_init : Array[(Int, Int, Int?, Int)] = []
  for table_idx, _table in mod_.tables {
    // Process elem segments for this table
    for elem in mod_.elems {
      if elem.mode is @types.ElemMode::Active(elem_table_idx, offset_expr) &&
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
  let args = [@types.Value::I32(3), @types.Value::I32(5)]
  let jit_result = run_jit(
    mod_, "add", func_idx, args, param_types, result_types,
  )
  inspect(jit_result, content="Ok([I32(8)])")
}
