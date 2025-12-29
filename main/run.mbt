///|
/// Convert 8 bytes from Bytes at given offset to Int64 (little-endian)
fn bytes_to_int64_le(bytes : Bytes, offset : Int) -> Int64 {
  let b0 = bytes[offset].to_int64() & 0xFFL
  let b1 = bytes[offset + 1].to_int64() & 0xFFL
  let b2 = bytes[offset + 2].to_int64() & 0xFFL
  let b3 = bytes[offset + 3].to_int64() & 0xFFL
  let b4 = bytes[offset + 4].to_int64() & 0xFFL
  let b5 = bytes[offset + 5].to_int64() & 0xFFL
  let b6 = bytes[offset + 6].to_int64() & 0xFFL
  let b7 = bytes[offset + 7].to_int64() & 0xFFL
  b0 |
  (b1 << 8) |
  (b2 << 16) |
  (b3 << 24) |
  (b4 << 32) |
  (b5 << 40) |
  (b6 << 48) |
  (b7 << 56)
}

///|
/// Run a WASM module
/// If invoke is specified, call that function with args
/// Otherwise, run the start function or _start export
fn run_wasm(
  wasm_path : String,
  invoke : String?,
  func_args : Array[String],
  preloads : Array[String],
  dirs : Array[String],
  envs : Array[String],
  wasi_options : Array[String],
  debug : Bool,
  use_jit : Bool,
) -> Unit {
  if debug {
    @logger.enable_debug()
  }
  @logger.debug("Loading module: \{wasm_path}")
  let jit_status = if use_jit { "enabled" } else { "disabled" }
  @logger.debug("JIT: \{jit_status}")
  // Create linker for module linking
  let linker = @runtime.Linker::new()

  // Parse WASI options
  let mut inherit_env = false
  let mut inherit_stdin = false
  let mut inherit_stdout = false
  let mut inherit_stderr = false
  for opt in wasi_options {
    // Support both "key" and "key=value" formats
    let (key, value) = parse_wasi_option(opt)
    match key {
      "inherit-env" => inherit_env = value != "false"
      "inherit-stdin" => inherit_stdin = value != "false"
      "inherit-stdout" => inherit_stdout = value != "false"
      "inherit-stderr" => inherit_stderr = value != "false"
      "common" =>
        // Enable common settings: inherit all stdio
        if value != "false" {
          inherit_stdin = true
          inherit_stdout = true
          inherit_stderr = true
        }
      _ => @logger.warn("unknown WASI option '\{key}'")
    }
  }

  // Build WASI context with directory mappings and environment variables
  let wasi_builder = @wasi.WasiContextBuilder::new()
  for dir in dirs {
    let mapping = parse_dir_mapping(dir)
    match mapping {
      Some((host_path, guest_path)) => {
        @logger.debug("Preopen dir: \{host_path} -> \{guest_path}")
        wasi_builder.preopen_dir(host_path, guest_path) |> ignore
      }
      None => {
        @logger.error(
          "invalid --dir format '\{dir}', expected HOST_DIR or HOST_DIR::GUEST_DIR",
        )
        return
      }
    }
  }
  for env_var in envs {
    let parsed = parse_env_var(env_var)
    match parsed {
      Some((key, value)) => {
        @logger.debug("Environment: \{key}=\{value}")
        wasi_builder.env(key, value) |> ignore
      }
      None => {
        @logger.error("invalid --env format '\{env_var}', expected NAME=VALUE")
        return
      }
    }
  }
  // Handle inherit-env option
  if inherit_env {
    @logger.debug("Inheriting host environment variables")
    // Note: MoonBit doesn't have direct access to host environment variables
    // This would require a native FFI call. For now, we just note that it's requested.
    // In a full implementation, we would iterate over host env vars and add them.
  }
  // Note: inherit-stdin/stdout/stderr would require modifying WasiContextBuilder
  // to use native stdio instead of callbacks. For now, the default behavior
  // already uses stdout/stderr for output.
  ignore(inherit_stdin)
  ignore(inherit_stdout)
  ignore(inherit_stderr)
  let wasi_ctx = wasi_builder.build()

  // Register WASI functions
  @wasi.register_wasi(linker, wasi_ctx)
  // Register spectest module (standard test functions)
  let spectest_instance = @wast.create_spectest_module(linker.get_store())
  linker.register("spectest", spectest_instance)
  // Load preloaded modules
  for preload in preloads {
    // Parse NAME=PATH format
    let parts = split_preload(preload)
    match parts {
      Some((name, path)) => {
        let preload_mod = load_module_from_path(path) catch {
          e => {
            @logger.error("loading preload module '\{name}': \{e}")
            return
          }
        }
        let preload_instance = @executor.instantiate_with_linker(
          linker, name, preload_mod,
        ) catch {
          e => {
            @logger.error("instantiating preload module '\{name}': \{e}")
            return
          }
        }
        linker.register(name, preload_instance)
      }
      None => {
        @logger.error("invalid preload format '\{preload}', expected NAME=PATH")
        return
      }
    }
  }
  // Load main module
  let mod_ = load_module_from_path(wasm_path) catch {
    e => {
      @logger.error("loading main module: \{e}")
      return
    }
  }
  @logger.debug(
    "Module loaded: \{mod_.codes.length()} functions, \{mod_.imports.length()} imports",
  )
  // Instantiate the main module
  // Note: instantiate_module_with_imports already handles:
  // - Data segment initialization
  // - Element segment initialization
  // - Start function execution
  let store = linker.get_store()
  // Enable C heap for JIT mode (required for GC operations)
  if use_jit {
    store.enable_c_heap()
  }
  let imports = linker.build_imports()
  let instance = @executor.instantiate_module_with_imports(store, mod_, imports) catch {
    e => {
      @logger.error("instantiating module: \{e}")
      return
    }
  }
  @logger.debug("Module instantiated successfully")
  // Determine which function to call
  let func_name = match invoke {
    Some(name) => name
    None => "_start" // Default to WASI-style entry point
  }
  @logger.debug("Calling function: \{func_name}")
  // Find the function type to parse arguments correctly
  let func_type = find_exported_func_type(mod_, func_name)
  if func_type is Some(ft) {
    // Parse arguments according to function type
    let args = parse_func_args(ft.params, func_args) catch {
      e => {
        @logger.error("parsing arguments: \{e}")
        return
      }
    }
    // Call the function
    // Check if JIT can handle all imports
    let can_use_jit = if use_jit {
      check_jit_import_support(mod_, debug)
    } else {
      false
    }
    if can_use_jit {
      // JIT execution path
      let jit_results = run_with_jit(
        mod_, instance, store, func_name, args, debug,
      )
      if jit_results.length() > 0 {
        // Print all results separated by spaces
        let strs = jit_results.map(format_value)
        println(strs.join(" "))
      }
    } else {
      // Interpreter execution path
      let results = @executor.call_exported_func(
        store, instance, func_name, args,
      ) catch {
        e => {
          @logger.error("\{e}")
          return
        }
      }
      // Print results
      if results.length() > 0 {
        let result_strs = results.map(format_value)
        println(result_strs.join(" "))
      }
    }
    // No exported function found, check if there's a start function
  } else if invoke is Some(name) {
    @logger.error("function '\{name}' not found")
  }
}

///|
/// Split preload string in NAME=PATH format
fn split_preload(s : String) -> (String, String)? {
  let mut eq_idx = -1
  for i in 0..<s.length() {
    if s.code_unit_at(i) == '=' {
      eq_idx = i
      break
    }
  }
  if eq_idx <= 0 {
    return None
  }
  // Build name and path strings manually
  let name_builder = StringBuilder::new()
  for i in 0..<eq_idx {
    name_builder.write_char(s.code_unit_at(i).unsafe_to_char())
  }
  let path_builder = StringBuilder::new()
  let path_start = eq_idx + 1
  for i in path_start..<s.length() {
    path_builder.write_char(s.code_unit_at(i).unsafe_to_char())
  }
  Some((name_builder.to_string(), path_builder.to_string()))
}

///|
/// Parse environment variable in NAME=VALUE format
fn parse_env_var(s : String) -> (String, String)? {
  let mut eq_idx = -1
  for i in 0..<s.length() {
    if s.code_unit_at(i) == '=' {
      eq_idx = i
      break
    }
  }
  if eq_idx <= 0 {
    return None
  }
  // Build name and value strings
  let name_builder = StringBuilder::new()
  for i in 0..<eq_idx {
    name_builder.write_char(s.code_unit_at(i).unsafe_to_char())
  }
  let value_builder = StringBuilder::new()
  let value_start = eq_idx + 1
  for i in value_start..<s.length() {
    value_builder.write_char(s.code_unit_at(i).unsafe_to_char())
  }
  Some((name_builder.to_string(), value_builder.to_string()))
}

///|
/// Format a WASM value for display
fn format_value(v : @types.Value) -> String {
  match v {
    I32(n) => n.to_string()
    I64(n) => n.to_string()
    F32(n) => n.to_string()
    F64(n) => n.to_string()
    Null => "null"
    FuncRef(idx) => "funcref(\{idx})"
    ExternRef(idx) => "externref(\{idx})"
    ExnRef(idx) => "exnref(\{idx})"
    ArrayRef(idx) => "arrayref(\{idx})"
    StructRef(idx) => "structref(\{idx})"
    I31(n) => "i31(\{n})"
    V128(bytes) => {
      let hex_chars = "0123456789abcdef"
      let hex = StringBuilder::new()
      for i in 0..<bytes.length() {
        if i > 0 {
          hex.write_string(" ")
        }
        let b = bytes[i].to_int()
        hex.write_char(hex_chars.code_unit_at(b / 16).unsafe_to_char())
        hex.write_char(hex_chars.code_unit_at(b % 16).unsafe_to_char())
      }
      "v128(\{hex.to_string()})"
    }
  }
}

///|
/// Parse WASI option in KEY or KEY=VALUE format
/// Returns (key, value) where value is "true" if not specified
fn parse_wasi_option(s : String) -> (String, String) {
  let mut eq_idx = -1
  for i in 0..<s.length() {
    if s.code_unit_at(i) == '=' {
      eq_idx = i
      break
    }
  }
  if eq_idx <= 0 {
    // No '=' found, treat as bare flag with value "true"
    return (s, "true")
  }
  // Build key and value strings
  let key_builder = StringBuilder::new()
  for i in 0..<eq_idx {
    key_builder.write_char(s.code_unit_at(i).unsafe_to_char())
  }
  let value_builder = StringBuilder::new()
  let value_start = eq_idx + 1
  for i in value_start..<s.length() {
    value_builder.write_char(s.code_unit_at(i).unsafe_to_char())
  }
  (key_builder.to_string(), value_builder.to_string())
}

///|
/// Parse directory mapping in HOST_DIR or HOST_DIR::GUEST_DIR format
fn parse_dir_mapping(s : String) -> (String, String)? {
  // Look for "::" separator
  let mut sep_idx = -1
  let len = s.length()
  let search_end = len - 1
  for i in 0..<search_end {
    if s.code_unit_at(i) == ':' && s.code_unit_at(i + 1) == ':' {
      sep_idx = i
      break
    }
  }
  if sep_idx < 0 {
    // No separator, use same path for host and guest
    if len == 0 {
      return None
    }
    Some((s, s))
  } else {
    if sep_idx == 0 {
      return None // Empty host path
    }
    // Build host and guest path strings
    let host_builder = StringBuilder::new()
    for i in 0..<sep_idx {
      host_builder.write_char(s.code_unit_at(i).unsafe_to_char())
    }
    let guest_builder = StringBuilder::new()
    let guest_start = sep_idx + 2
    for i in guest_start..<len {
      guest_builder.write_char(s.code_unit_at(i).unsafe_to_char())
    }
    let guest_path = guest_builder.to_string()
    // If guest path is empty, use host path
    if guest_path.length() == 0 {
      Some((host_builder.to_string(), host_builder.to_string()))
    } else {
      Some((host_builder.to_string(), guest_path))
    }
  }
}

///|
/// Find the type of an exported function
fn find_exported_func_type(
  mod_ : @types.Module,
  func_name : String,
) -> @types.FuncType? {
  for exp in mod_.exports {
    if exp.name == func_name && exp.desc is Func(idx) {
      // Get the type index for this function
      // Account for imported functions
      let num_imports = count_func_imports(mod_.imports)
      let type_idx = if idx < num_imports {
        // It's an imported function
        get_import_func_type_idx(mod_.imports, idx)
      } else {
        // It's a defined function
        let func_idx = idx - num_imports
        if func_idx < mod_.funcs.length() {
          Some(mod_.funcs[func_idx])
        } else {
          None
        }
      }
      if type_idx is Some(tidx) && tidx < mod_.types.length() {
        return Some(mod_.get_func_type(tidx))
      }
    }
  }
  None
}

///|
/// Count function imports
fn count_func_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is Func(_) {
      count = count + 1
    }
  }
  count
}

///|
/// Get function name from exports or generate default name
fn get_func_name(mod_ : @types.Module, func_idx : Int) -> String {
  // Look for exported name
  for exp in mod_.exports {
    if exp.desc is Func(idx) && idx == func_idx {
      return exp.name
    }
  }
  // Default name
  "func_\{func_idx}"
}

///|
/// Get type index for an imported function
fn get_import_func_type_idx(imports : Array[@types.Import], idx : Int) -> Int? {
  let mut func_count = 0
  for imp in imports {
    if imp.desc is Func(type_idx) {
      if func_count == idx {
        return Some(type_idx)
      }
      func_count = func_count + 1
    }
  }
  None
}

///|
/// Convert a store function address to module function index
/// Returns -1 if not found (for null reference sentinel)
fn store_addr_to_module_func_idx(
  store_addr : Int,
  instance : @runtime.ModuleInstance,
) -> Int {
  // Search for the store address in the instance's func_addrs
  for i, addr in instance.func_addrs {
    if addr == store_addr {
      return i
    }
  }
  // Not found - this shouldn't happen for valid function references
  // Return -1 to trigger a null reference trap
  -1
}

///|
/// Allocate and initialize globals array for JIT
/// Returns the pointer to the allocated array, or 0 on failure
/// The caller is responsible for freeing the memory
/// jit_module: The JIT module (needed for FuncRef globals to get tagged function pointers)
fn init_jit_globals(
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  jit_module : @jit.JITModule,
) -> Int64 {
  let num_globals = instance.global_addrs.length()
  if num_globals == 0 {
    return 0L // No globals, no need to allocate
  }
  // Allocate 16 bytes per global (8 bytes value + 8 bytes tag)
  let size = (num_globals * 16).to_int64()
  let globals_ptr = @jit.alloc_memory(size)
  if globals_ptr == 0L {
    return 0L
  }
  // FUNCREF_TAG: bit 61 set for tagged function pointers (same as lower_get_func_ref)
  let funcref_tag = 0x2000000000000000L
  // Write each global value to the array
  for i in 0..<num_globals {
    let global_addr = instance.global_addrs[i]
    let global_inst = store.globals[global_addr]
    let value = global_inst.get()
    // Convert value to Int64 for storage
    // For FuncRef, we need to get the tagged function pointer from JIT module
    // This matches the encoding used by ref.func (via GetFuncRef)
    let raw_value = match value {
      I32(n) => @types.ToInt64::to_int64_bits(n)
      I64(n) => @types.ToInt64::to_int64_bits(n)
      F32(f) => @types.ToInt64::to_int64_bits(f)
      F64(d) => @types.ToInt64::to_int64_bits(d)
      FuncRef(store_addr) => {
        // Convert store address to module function index
        let func_idx = store_addr_to_module_func_idx(store_addr, instance)
        // Get function pointer from JIT module and tag it
        let func_ptr = jit_module.get_func_ptr(func_idx)
        if func_ptr == 0L {
          @types.NULL_REF
        } else { // null funcref
          func_ptr | funcref_tag // Tagged function pointer
        }
      }
      ExternRef(idx) => idx.to_int64()
      ExnRef(idx) => idx.to_int64()
      ArrayRef(gc_ref) => @jit.encode_heap_ref(gc_ref)
      StructRef(gc_ref) => @jit.encode_heap_ref(gc_ref)
      I31(n) => @jit.encode_i31(n)
      Null => @types.NULL_REF // null is encoded as 0 in JIT
      V128(bytes) => {
        // V128 needs special handling - write both 64-bit halves
        let offset = globals_ptr + (i * 16).to_int64()
        let low = bytes_to_int64_le(bytes, 0)
        let high = bytes_to_int64_le(bytes, 8)
        @jit.c_jit_write_i64(offset, low)
        @jit.c_jit_write_i64(offset + 8L, high)
        continue // Skip the normal write below
      }
    }
    // Write value at offset i * 16
    let offset = globals_ptr + (i * 16).to_int64()
    // Use FFI to write the value
    @jit.c_jit_write_i64(offset, raw_value)
  }
  globals_ptr
}

///|
/// Run a function using JIT compilation
fn run_with_jit(
  mod_ : @types.Module,
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  func_name : String,
  args : Array[@types.Value],
  debug : Bool,
) -> Array[@types.Value] {
  ignore(debug)
  @logger.debug("JIT: Compiling module...")
  // Get actual memory max from the store (for imported memories)
  // This is crucial for memory.grow to enforce the correct max limit
  let actual_memory_max : Int? = if instance.mem_addrs.length() > 0 {
    let mem = store.get_mem(instance.mem_addrs[0]) catch {
      _ => abort("Memory not found")
    }
    let (_, max) = mem.get_limits()
    max
  } else {
    None
  }
  // Compile module to precompiled format in memory
  let precompiled = compile_module_to_jit(mod_, debug, actual_memory_max~)
  match precompiled {
    None => {
      @logger.error("JIT compilation failed")
      return []
    }
    Some(pc) => {
      // Build func_signatures array for JITModule::load
      let func_signatures = build_jit_func_signatures(mod_)
      // Load JIT module
      let jit_module = @jit.JITModule::load(pc, func_signatures)
      match jit_module {
        None => {
          @logger.error("Failed to load JIT module")
          return []
        }
        Some(jm) => {
          // Allocate independent WASM stack with guard page (1MB)
          // This provides controlled stack overflow behavior
          let _ = jm.alloc_wasm_stack(1048576L)
          // Initialize all memories (multi-memory support)
          if not(init_jit_memories(instance, store, jm)) {
            @logger.error("Failed to initialize JIT memories")
            return []
          }
          // Initialize globals (pass jm for tagged funcref pointers)
          let globals_ptr = init_jit_globals(instance, store, jm)
          if globals_ptr != 0L {
            jm.set_globals(globals_ptr)
          }
          // Find and call the function
          let jit_func = jm.get_func_by_name(func_name)
          match jit_func {
            Some(f) => {
              // Convert args to Int64
              let i64_args : Array[Int64] = []
              for arg in args {
                let v = match arg {
                  I32(n) => @types.ToInt64::to_int64_bits(n)
                  I64(n) => @types.ToInt64::to_int64_bits(n)
                  F32(n) => @types.ToInt64::to_int64_bits(n)
                  F64(n) => @types.ToInt64::to_int64_bits(n)
                  FuncRef(idx) => idx.to_int64()
                  ExternRef(idx) => idx.to_int64()
                  ExnRef(idx) => idx.to_int64()
                  ArrayRef(idx) => idx.to_int64()
                  StructRef(idx) => idx.to_int64()
                  I31(n) => n.to_int64()
                  Null => @types.FUNCREF_NULL_SENTINEL // Sentinel value for null reference
                  V128(_) => abort("V128 args not yet supported in JIT")
                }
                i64_args.push(v)
              }
              @logger.debug("JIT: Calling function '\{func_name}'")
              // Set up GC heap for JIT execution if c_heap is available
              match store.c_heap {
                Some(heap) => {
                  // Compute canonical type indices for proper type equivalence checking
                  let canonical = @types.compute_canonical_type_indices(
                    store.module_types,
                  )
                  @jit.gc_setup(heap, store.module_types, canonical)
                }
                None => ()
              }
              let results = jm.call_with_context(f, i64_args) catch {
                @jit.JITTrap(msg) => {
                  @jit.gc_teardown()
                  @logger.error("JIT Trap: \{msg}")
                  // NOTE: Memory and globals are now freed by JITContext finalizer (GC-managed)
                  return []
                }
              }
              // Tear down GC context after JIT call
              @jit.gc_teardown()
              // Convert Int64 results to Value based on result types
              let values : Array[@types.Value] = []
              for i, r in results {
                if i < f.result_types.length() {
                  @logger.debug(
                    "result[\{i}] type: \{f.result_types[i]}, raw value: \{r}",
                  )
                  let v = match f.result_types[i] {
                    I32 =>
                      @types.Value::I32(@types.FromInt64::from_int64_bits(r))
                    I64 =>
                      @types.Value::I64(@types.FromInt64::from_int64_bits(r))
                    F32 =>
                      @types.Value::F32(@types.FromInt64::from_int64_bits(r))
                    F64 =>
                      @types.Value::F64(@types.FromInt64::from_int64_bits(r))
                    FuncRef
                    | RefFunc
                    | RefFuncTyped(_)
                    | RefNullFuncTyped(_)
                    | NullFuncRef =>
                      if r == @types.FUNCREF_NULL_SENTINEL {
                        @types.Value::Null
                      } else {
                        @types.Value::FuncRef(r.to_int())
                      }
                    ExternRef | RefExtern | NullExternRef =>
                      if r == @types.FUNCREF_NULL_SENTINEL {
                        @types.Value::Null
                      } else {
                        @types.Value::ExternRef(r.to_int())
                      }
                    // GC reference types - treat as null for now
                    AnyRef | NullRef => @types.Value::Null
                    ExnRef | NullExnRef => @types.Value::Null
                    V128 => @types.Value::I64(r) // Placeholder for V128
                    // New GC reference types
                    RefStruct(_) | RefNullStruct(_) => @types.Value::Null
                    RefArray(_) | RefNullArray(_) => @types.Value::Null
                    RefAny | RefEq | RefNullEq => @types.Value::Null
                    RefI31 | RefNullI31 => @types.Value::Null
                    RefNone => @types.Value::Null
                  }
                  values.push(v)
                }
              }
              // NOTE: Memory and globals are freed automatically by JITContext finalizer (GC-managed)
              values
            }
            None => {
              @logger.error("Function '\{func_name}' not found in JIT module")
              []
            }
          }
        }
      }
    }
  }
}

///|
/// Compile a WASM module to precompiled format in memory
/// actual_memory_max: Override for memory max limit (used for imported memories)
fn compile_module_to_jit(
  mod_ : @types.Module,
  _debug : Bool,
  actual_memory_max? : Int? = None,
) -> @cwasm.PrecompiledModule? {
  let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
  let num_imports = count_func_imports(mod_.imports)
  // Build import function type indices and record imports
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
  // Build global types array (imports + module globals)
  let global_types : Array[@types.GlobalType] = []
  for imp in mod_.imports {
    if imp.desc is Global(global_type) {
      global_types.push(global_type)
    }
  }
  for global in mod_.globals {
    global_types.push(global.type_)
  }
  // Get memory max limit - prefer actual_memory_max (for imported memories),
  // otherwise fall back to module's declared memory limits
  let memory_max : Int? = match actual_memory_max {
    Some(_) => actual_memory_max
    None =>
      if mod_.memories.length() > 0 {
        mod_.memories[0].limits.max.map(fn(m) { m.to_int() })
      } else {
        None
      }
  }
  // Compile each function
  for i, code in mod_.codes {
    let func_idx = num_imports + i
    let type_idx = mod_.funcs[i]
    let func_type = mod_.get_func_type(type_idx)
    let func_name = get_func_name(mod_, func_idx)
    // Build memory_is_64 array for memory64 support
    let memory_is_64 = mod_.memories.map(fn(m) { m.is_memory64 })
    // Stage 1: Translate WASM to IR
    let translator = @ir.Translator::new(
      func_name,
      func_type,
      code.locals,
      @types.extract_func_types(mod_.types),
      mod_.funcs,
      num_imports,
      import_func_type_indices,
      memory_max~,
      memory_is_64~,
      tables=mod_.tables,
      global_types~,
      type_rec_groups=mod_.type_rec_groups,
      module_types=mod_.types,
      tags=mod_.tags,
    )
    let ir_func = translator.translate(code.body)
    // Stage 2: Optimize IR (O2 level)
    @ir.optimize_with_level(ir_func, @ir.OptLevel::from_int(2)) |> ignore
    // DEBUG: Print IR
    if @logger.is_debug_enabled() {
      @logger.debug("IR for \{func_name}:")
      @logger.info(ir_func.print())
    }
    // Stage 3: Lower to VCode
    let vcode_func = @lower.lower_function(ir_func)
    // DEBUG: Print VCode before regalloc
    if @logger.is_debug_enabled() {
      @logger.debug("VCode before regalloc for \{func_name}:")
      @logger.info(vcode_func.print())
    }
    // Stage 4: Register allocation
    let allocated = @lower.allocate_registers_aarch64(vcode_func)
    // DEBUG: Print VCode after regalloc
    if @logger.is_debug_enabled() {
      @logger.debug("VCode after regalloc for \{func_name}:")
      @logger.info(allocated.print())
    }
    // Stage 5: Emit machine code
    let mc = @emit.emit_function(allocated)
    // Stage 6: Add to precompiled module
    let compiled = @vcode.CompiledFunction::new(func_name, mc, 0)
    let num_params = func_type.params.length()
    let num_results = func_type.results.length()
    precompiled.add_function(
      func_idx, func_name, compiled, num_params, num_results,
    )
    if @logger.is_debug_enabled() &&
      mod_.codes.length() > 10 &&
      (i + 1) % 10 == 0 {
      @logger.debug("JIT: Compiled \{i + 1}/\{mod_.codes.length()} functions")
    }
  }
  Some(precompiled)
}

///|
/// Copy interpreter memory to JIT memory (for a specific memory index)
/// This preserves any modifications made by the start function
fn copy_interp_memory_to_jit_indexed(
  store : @runtime.Store,
  mem_addr : Int,
  jit_mem_ptr : Int64,
) -> Unit {
  let mem = store.get_memory(mem_addr)
  let size = mem.size_pages() * 65536 // Convert pages to bytes
  if size > 0 {
    let data = mem.read_bytes(0, size)
    @jit.memory_init(jit_mem_ptr, 0L, data) |> ignore
  }
}

///|
/// Initialize all JIT memories from interpreter memories (multi-memory support)
/// Returns true on success, false on failure
fn init_jit_memories(
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  jm : @jit.JITModule,
) -> Bool {
  if instance.mem_addrs.is_empty() {
    return true // No memories to initialize
  }
  let memories : Array[@jit.MemoryInfo] = []
  // Allocate and copy each memory
  for mem_addr in instance.mem_addrs {
    let mem = store.get_mem(mem_addr) catch { _ => return false }
    let size = mem.size_pages().to_int64() * 65536L
    let (_, max) = mem.get_limits()
    // Allocate JIT memory
    let mem_ptr = @jit.alloc_memory(size)
    if mem_ptr == 0L && size > 0L {
      return false // Allocation failed
    }
    // Copy interpreter memory data to JIT memory
    copy_interp_memory_to_jit_indexed(store, mem_addr, mem_ptr)
    memories.push(@jit.MemoryInfo::new(mem_ptr, size, max))
  }
  // Set up multi-memory in JIT context
  jm.set_memory_pointers(memories)
  // Also set fast path for memory 0 (backward compatibility)
  if memories.length() > 0 {
    jm.set_memory(memories[0].ptr, memories[0].size)
  }
  true
}

///|
/// Build func_signatures array for JIT module loading
/// Returns Array[(param_types, result_types)] for each function
fn build_jit_func_signatures(
  mod_ : @types.Module,
) -> Array[(Array[@types.ValueType], Array[@types.ValueType])] {
  let num_imports = count_func_imports(mod_.imports)
  let total_funcs = num_imports + mod_.funcs.length()
  let signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])] = []
  // Pre-fill with empty signatures for all functions
  for _ in 0..<total_funcs {
    signatures.push(([], []))
  }
  // Fill in signatures for import functions
  for i, imp in mod_.imports {
    if imp.desc is Func(type_idx) && type_idx < mod_.types.length() {
      let func_type = mod_.get_func_type(type_idx)
      signatures[i] = (func_type.params.copy(), func_type.results.copy())
    }
  }
  // Fill in signatures for local functions
  for i, type_idx in mod_.funcs {
    let func_idx = num_imports + i
    if type_idx < mod_.types.length() {
      let func_type = mod_.get_func_type(type_idx)
      signatures[func_idx] = (func_type.params.copy(), func_type.results.copy())
    }
  }
  signatures
}

///|
/// Parse function arguments according to parameter types
fn parse_func_args(
  params : Array[@types.ValueType],
  args : Array[String],
) -> Array[@types.Value] raise CliError {
  if args.length() != params.length() {
    raise FuncArgNumError(params.length(), args.length())
  }
  let result : Array[@types.Value] = []
  for i, param in params {
    let arg = args[i]
    let value = match param {
      I32 => {
        let n = @strconv.parse_int(arg) catch {
          _ => {
            // Try parsing as unsigned
            let u = @strconv.parse_uint(arg) catch {
              _ => raise ArgTypeError(I32, arg)
            }
            u.reinterpret_as_int()
          }
        }
        @types.Value::I32(n)
      }
      I64 => {
        let n = @strconv.parse_int64(arg) catch {
          _ => {
            let u = @strconv.parse_uint64(arg) catch {
              _ => raise ArgTypeError(I64, arg)
            }
            u.reinterpret_as_int64()
          }
        }
        @types.Value::I64(n)
      }
      F32 => {
        let n = @strconv.parse_double(arg) catch {
          _ => raise ArgTypeError(F32, arg)
        }
        @types.Value::F32(Float::from_double(n))
      }
      F64 => {
        let n = @strconv.parse_double(arg) catch {
          _ => raise ArgTypeError(F64, arg)
        }
        @types.Value::F64(n)
      }
      t => raise UnsupportedArgTypeError(t, arg)
    }
    result.push(value)
  }
  result
}

///|
/// Check if all imports are supported by JIT trampolines
fn check_jit_import_support(mod_ : @types.Module, _debug : Bool) -> Bool {
  let unsupported : Array[String] = []
  for imp in mod_.imports {
    if imp.desc is Func(_) &&
      @jit.get_import_trampoline(imp.mod_name, imp.name) is None {
      unsupported.push("\{imp.mod_name}.\{imp.name}")
    }
  }
  if unsupported.length() > 0 {
    let joined = unsupported.join(", ")
    @logger.debug(
      "JIT: Falling back to interpreter - unsupported imports: \{joined}",
    )
    false
  } else {
    true
  }
}
