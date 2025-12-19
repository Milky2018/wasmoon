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
  debug_config : DebugConfig,
  wasm_config : WasmConfig,
  use_jit : Bool,
) -> Unit {
  ignore(wasm_config) // Will be used in full implementation
  if debug_config.verbose {
    println("[DEBUG] Loading module: \{wasm_path}")
    let jit_status = if use_jit { "enabled" } else { "disabled" }
    println("[DEBUG] JIT: \{jit_status}")
  }
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
      _ => println("Warning: unknown WASI option '\{key}'")
    }
  }

  // Build WASI context with directory mappings and environment variables
  let wasi_builder = @wasi.WasiContextBuilder::new()
  for dir in dirs {
    let mapping = parse_dir_mapping(dir)
    match mapping {
      Some((host_path, guest_path)) => {
        if debug_config.verbose {
          println("[DEBUG] Preopen dir: \{host_path} -> \{guest_path}")
        }
        wasi_builder.preopen_dir(host_path, guest_path) |> ignore
      }
      None => {
        println(
          "Error: invalid --dir format '\{dir}', expected HOST_DIR or HOST_DIR::GUEST_DIR",
        )
        return
      }
    }
  }
  for env_var in envs {
    let parsed = parse_env_var(env_var)
    match parsed {
      Some((key, value)) => {
        if debug_config.verbose {
          println("[DEBUG] Environment: \{key}=\{value}")
        }
        wasi_builder.env(key, value) |> ignore
      }
      None => {
        println("Error: invalid --env format '\{env_var}', expected NAME=VALUE")
        return
      }
    }
  }
  // Handle inherit-env option
  if inherit_env {
    if debug_config.verbose {
      println("[DEBUG] Inheriting host environment variables")
    }
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
  // Load preloaded modules
  for preload in preloads {
    // Parse NAME=PATH format
    let parts = split_preload(preload)
    match parts {
      Some((name, path)) => {
        let preload_mod = load_module_from_path(path) catch {
          e => {
            println("Error loading preload module '\{name}': \{e}")
            return
          }
        }
        let preload_instance = @executor.instantiate_with_linker(
          linker, name, preload_mod,
        ) catch {
          e => {
            println("Error instantiating preload module '\{name}': \{e}")
            return
          }
        }
        linker.register(name, preload_instance)
      }
      None => {
        println(
          "Error: invalid preload format '\{preload}', expected NAME=PATH",
        )
        return
      }
    }
  }
  // Load main module
  let mod_ = load_module_from_path(wasm_path) catch {
    e => {
      println("Error loading main module: \{e}")
      return
    }
  }
  if debug_config.verbose {
    println(
      "[DEBUG] Module loaded: \{mod_.codes.length()} functions, \{mod_.imports.length()} imports",
    )
  }
  // Instantiate the main module
  // Note: instantiate_module_with_imports already handles:
  // - Data segment initialization
  // - Element segment initialization
  // - Start function execution
  let store = linker.get_store()
  let imports = linker.build_imports()
  let instance = @executor.instantiate_module_with_imports(store, mod_, imports) catch {
    e => {
      println("Error instantiating module: \{e}")
      return
    }
  }
  if debug_config.verbose {
    println("[DEBUG] Module instantiated successfully")
  }
  // Determine which function to call
  let func_name = match invoke {
    Some(name) => name
    None => "_start" // Default to WASI-style entry point
  }
  if debug_config.verbose {
    println("[DEBUG] Calling function: \{func_name}")
  }
  // Find the function type to parse arguments correctly
  let func_type = find_exported_func_type(mod_, func_name)
  if func_type is Some(ft) {
    // Parse arguments according to function type
    let args = parse_func_args(ft.params, func_args) catch {
      e => {
        println("Error parsing arguments: \{e}")
        return
      }
    }
    // Call the function
    // Check if JIT can handle all imports
    let can_use_jit = if use_jit {
      check_jit_import_support(mod_, debug_config)
    } else {
      false
    }
    if can_use_jit {
      // JIT execution path
      let jit_results = run_with_jit(
        mod_, instance, store, func_name, args, debug_config,
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
          println("Error: \{e}")
          return
        }
      }
      // Print results
      if results.length() > 0 {
        let result_strs = results.map(format_value)
        println(result_strs.join(" "))
      }
    }
  } else {
    // No exported function found, check if there's a start function
    match invoke {
      Some(name) => println("Error: function '\{name}' not found")
      None =>
        // Module was already initialized with start function if present
        ()
    }
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
        return Some(mod_.types[tidx])
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
fn init_jit_globals(
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
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
  // Write each global value to the array
  for i in 0..<num_globals {
    let global_addr = instance.global_addrs[i]
    let global_inst = store.globals[global_addr]
    let value = global_inst.get()
    // Convert value to Int64 for storage
    // Note: -1L is used as null sentinel in JIT
    // For FuncRef, we need to convert store address to module function index
    // because JIT func_table is indexed by module function index
    let raw_value = match value {
      I32(n) => n.to_int64()
      I64(n) => n
      F32(f) => f.reinterpret_as_int().to_int64()
      F64(d) => d.reinterpret_as_int64()
      FuncRef(store_addr) =>
        store_addr_to_module_func_idx(store_addr, instance).to_int64()
      ExternRef(idx) => idx.to_int64()
      Null => -1L // null sentinel
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
  debug_config : DebugConfig,
) -> Array[@types.Value] {
  if debug_config.verbose {
    println("[DEBUG] JIT: Compiling module...")
  }
  // Compile module to precompiled format in memory
  let precompiled = compile_module_to_jit(mod_, debug_config)
  match precompiled {
    None => {
      println("Error: JIT compilation failed")
      return []
    }
    Some(pc) => {
      // Build func_signatures array for JITModule::load
      let func_signatures = build_jit_func_signatures(mod_)
      // Load JIT module
      let jit_module = @jit.JITModule::load(pc, func_signatures)
      match jit_module {
        None => {
          println("Error: Failed to load JIT module")
          return []
        }
        Some(jm) => {
          // Allocate linear memory
          let mem_size = get_memory_size(instance, store)
          let mem_ptr = @jit.alloc_memory(mem_size)
          if mem_ptr == 0L {
            println("Error: Failed to allocate linear memory")
            // NOTE: No need to manually free - GC handles cleanup
            return []
          }
          // Copy interpreter memory to JIT memory (preserves start function effects)
          copy_interp_memory_to_jit(instance, store, mem_ptr)
          // Set memory in JIT context
          jm.set_memory(mem_ptr, mem_size)
          // Initialize globals
          let globals_ptr = init_jit_globals(instance, store)
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
                  I32(n) => n.to_int64()
                  I64(n) => n
                  F32(n) => n.reinterpret_as_int().to_int64()
                  F64(n) => n.reinterpret_as_int64()
                  FuncRef(idx) => idx.to_int64()
                  ExternRef(idx) => idx.to_int64()
                  Null => -1L // Sentinel value for null reference
                }
                i64_args.push(v)
              }
              if debug_config.verbose {
                println("[DEBUG] JIT: Calling function '\{func_name}'")
              }
              let results = jm.call_with_context(f, i64_args) catch {
                @jit.JITTrap(msg) => {
                  println("JIT Trap: \{msg}")
                  // NOTE: Memory and globals are now freed by JITContext finalizer (GC-managed)
                  return []
                }
              }
              // Convert Int64 results to Value based on result types
              let values : Array[@types.Value] = []
              for i, r in results {
                if i < f.result_types.length() {
                  if debug_config.verbose {
                    println(
                      "[DEBUG] result[\{i}] type: \{f.result_types[i]}, raw value: \{r}",
                    )
                  }
                  let v = match f.result_types[i] {
                    I32 => @types.Value::I32(r.to_int())
                    I64 => @types.Value::I64(r)
                    F32 => {
                      // r contains bits of f64, convert to f32
                      let f64_val = r.reinterpret_as_double()
                      @types.Value::F32(Float::from_double(f64_val))
                    }
                    F64 => @types.Value::F64(r.reinterpret_as_double())
                    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) =>
                      if r == -1L {
                        @types.Value::Null
                      } else {
                        @types.Value::FuncRef(r.to_int())
                      }
                    ExternRef | RefExtern =>
                      if r == -1L {
                        @types.Value::Null
                      } else {
                        @types.Value::ExternRef(r.to_int())
                      }
                    V128 => @types.Value::I64(r) // Placeholder for V128
                  }
                  values.push(v)
                }
              }
              // NOTE: Memory and globals are freed automatically by JITContext finalizer (GC-managed)
              values
            }
            None => {
              println("Error: Function '\{func_name}' not found in JIT module")
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
fn compile_module_to_jit(
  mod_ : @types.Module,
  debug_config : DebugConfig,
) -> @cwasm.PrecompiledModule? {
  let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
  let num_imports = count_func_imports(mod_.imports)
  // Build import function type indices and record imports
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
  // Get memory max limit from module (if memory is defined)
  let memory_max : Int? = if mod_.memories.length() > 0 {
    mod_.memories[0].limits.max
  } else {
    None
  }
  // Compile each function
  for i, code in mod_.codes {
    let func_idx = num_imports + i
    let type_idx = mod_.funcs[i]
    let func_type = mod_.types[type_idx]
    let func_name = get_func_name(mod_, func_idx)
    // Stage 1: Translate WASM to IR
    let translator = @ir.Translator::new(
      func_name,
      func_type,
      code.locals,
      mod_.types,
      mod_.funcs,
      num_imports,
      import_func_type_indices,
      memory_max~,
      tables=mod_.tables,
      global_types~,
    )
    let ir_func = translator.translate(code.body)
    // Stage 2: Optimize IR (O2 level)
    @ir.optimize_with_level(ir_func, @ir.OptLevel::from_int(2)) |> ignore
    // DEBUG: Print IR
    if debug_config.verbose {
      println("[DEBUG] IR for \{func_name}:")
      println(ir_func.print())
    }
    // Stage 3: Lower to VCode
    let vcode_func = @lower.lower_function(ir_func)
    // DEBUG: Print VCode before regalloc
    if debug_config.verbose {
      println("[DEBUG] VCode before regalloc for \{func_name}:")
      println(vcode_func.print())
    }
    // Stage 4: Register allocation
    let allocated = @lower.allocate_registers_aarch64(vcode_func)
    // DEBUG: Print VCode after regalloc
    if debug_config.verbose {
      println("[DEBUG] VCode after regalloc for \{func_name}:")
      println(allocated.print())
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
    if debug_config.verbose && mod_.codes.length() > 10 && (i + 1) % 10 == 0 {
      println("[DEBUG] JIT: Compiled \{i + 1}/\{mod_.codes.length()} functions")
    }
  }
  Some(precompiled)
}

///|
/// Get memory size from module instance
fn get_memory_size(
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
) -> Int64 {
  if instance.mem_addrs.length() > 0 {
    let mem = store.get_mem(instance.mem_addrs[0]) catch {
      _ => return 65536L // Default 1 page
    }
    mem.size_pages().to_int64() * 65536L // pages to bytes
  } else {
    65536L // Default 1 page = 64KB
  }
}

///|
/// Copy interpreter memory to JIT memory
/// This preserves any modifications made by the start function
fn copy_interp_memory_to_jit(
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  mem_ptr : Int64,
) -> Unit {
  if instance.mem_addrs.is_empty() {
    return
  }
  let mem = store.get_memory(instance.mem_addrs[0])
  let size = mem.size_pages() * 65536 // Convert pages to bytes
  if size > 0 {
    let data = mem.read_bytes(0, size)
    @jit.memory_init(mem_ptr, 0L, data) |> ignore
  }
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
      let func_type = mod_.types[type_idx]
      signatures[i] = (func_type.params.copy(), func_type.results.copy())
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
fn check_jit_import_support(
  mod_ : @types.Module,
  debug_config : DebugConfig,
) -> Bool {
  let unsupported : Array[String] = []
  for imp in mod_.imports {
    if imp.desc is Func(_) &&
      !@jit.has_import_trampoline(imp.mod_name, imp.name) {
      unsupported.push("\{imp.mod_name}.\{imp.name}")
    }
  }
  if unsupported.length() > 0 {
    if debug_config.verbose {
      let joined = unsupported.join(", ")
      println(
        "[DEBUG] JIT: Falling back to interpreter - unsupported imports: \{joined}",
      )
    }
    false
  } else {
    true
  }
}
