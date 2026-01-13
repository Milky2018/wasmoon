///|
extern "c" fn native_exit(code : Int) = "exit"

///|
fn exit_failure() -> Unit {
  native_exit(1)
}

///|
/// Get the basename from a file path (last component after /)
fn get_basename(path : String) -> String {
  // Find last '/' character
  let mut last_slash = -1
  for i in 0..<path.length() {
    if path.code_unit_at(i) == '/' {
      last_slash = i
    }
  }
  if last_slash == -1 {
    path
  } else if last_slash == path.length() - 1 {
    // Trailing slash, find previous
    let mut prev_slash = -1
    for i in 0..<last_slash {
      if path.code_unit_at(i) == '/' {
        prev_slash = i
      }
    }
    try! path[prev_slash + 1:last_slash].to_string()
  } else {
    try! path[last_slash + 1:].to_string()
  }
}

///|
/// Format a Value for output
fn format_value(v : @types.Value) -> String {
  match v {
    I32(n) => n.to_string()
    I64(n) => n.to_string()
    F32(f) => f.to_string()
    F64(d) => d.to_string()
    FuncRef(idx) => "funcref:\{idx}"
    ExternRef(idx) => "externref:\{idx}"
    V128(bytes) => {
      let mut hex = "v128:"
      for i in 0..<bytes.length() {
        hex = hex + @types.to_hex_byte(bytes[i].to_int())
      }
      hex
    }
    Null => "null"
    StructRef(idx) => "struct:\{idx}"
    ArrayRef(idx) => "array:\{idx}"
    I31(n) => "i31:\{n}"
    ExnRef(idx) => "exn:\{idx}"
  }
}

///|
/// Convert Value array to Int64 array for JIT call
fn convert_args_to_jit(args : Array[@types.Value]) -> Array[Int64] {
  args.map(fn(v) {
    match v {
      I32(n) => n.to_int64()
      I64(n) => n
      F32(f) => f.reinterpret_as_int().to_int64()
      F64(d) => d.reinterpret_as_int64()
      FuncRef(idx) => idx.to_int64()
      ExternRef(idx) => idx.to_int64()
      Null => @types.FUNCREF_NULL_SENTINEL
      V128(_) => abort("V128 args not yet supported")
      StructRef(idx) => idx.to_int64() << 1
      ArrayRef(idx) => idx.to_int64() << 1
      I31(n) => (n.to_int64() << 1) | 1L
      ExnRef(idx) => idx.to_int64()
    }
  })
}

///|
/// Convert JIT Int64 results to Value array using result types
fn convert_jit_results(
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
        I32(raw.to_int())
      }
      I64 => {
        let raw = results[slot_idx]
        slot_idx += 1
        I64(raw)
      }
      F32 => {
        let raw = results[slot_idx]
        slot_idx += 1
        F32(Float::reinterpret_from_int(raw.to_int()))
      }
      F64 => {
        let raw = results[slot_idx]
        slot_idx += 1
        F64(raw.reinterpret_as_double())
      }
      FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef => {
        let raw = results[slot_idx]
        slot_idx += 1
        if raw == @types.FUNCREF_NULL_SENTINEL {
          Null
        } else {
          FuncRef(raw.to_int())
        }
      }
      ExternRef | RefExtern | NullExternRef => {
        let raw = results[slot_idx]
        slot_idx += 1
        if raw == @types.FUNCREF_NULL_SENTINEL {
          Null
        } else {
          ExternRef(raw.to_int())
        }
      }
      AnyRef | NullRef | RefAny | RefEq | RefNullEq => {
        let raw = results[slot_idx]
        slot_idx += 1
        if raw == 0L {
          Null
        } else if (raw & 1L) == 1L {
          I31((raw >> 1).to_int())
        } else {
          StructRef((raw >> 1).to_int())
        }
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
      RefStruct(_) | RefNullStruct(_) => {
        let raw = results[slot_idx]
        slot_idx += 1
        if raw == 0L {
          Null
        } else {
          StructRef((raw >> 1).to_int())
        }
      }
      RefArray(_) | RefNullArray(_) => {
        let raw = results[slot_idx]
        slot_idx += 1
        if raw == 0L {
          Null
        } else {
          ArrayRef((raw >> 1).to_int())
        }
      }
      RefI31 | RefNullI31 => {
        let raw = results[slot_idx]
        slot_idx += 1
        if raw == 0L {
          Null
        } else if (raw & 1L) == 1L {
          I31((raw >> 1).to_int())
        } else {
          Null
        }
      }
      RefNone => {
        slot_idx += 1
        Null
      }
      V128 => {
        let low = results[slot_idx]
        let high = results[slot_idx + 1]
        slot_idx += 2
        let buf : @buffer.Buffer = @buffer.new(size_hint=16)
        for i in 0..<8 {
          buf.write_byte(((low >> (i * 8)) & 0xFFL).to_byte())
        }
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
  wasm_args : Array[String],
  preloads : Array[String],
  dirs : Array[String],
  envs : Array[String],
  wasi_options : Array[String],
  debug : Bool,
  dump_on_trap : Bool,
  use_jit : Bool,
  opt_level : Int,
  enable_dwarf : Bool,
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
  // Also collect preopens and env for JIT mode
  let wasi_builder = @wasi.WasiContextBuilder::new()
  // argv[0] is the basename of the wasm file (like wasmtime), followed by wasm_args
  let program_name = get_basename(wasm_path)
  let wasi_args = [program_name] + wasm_args
  wasi_builder.args(wasi_args) |> ignore
  let jit_preopens : Array[(String, String)] = []
  let jit_envs : Array[String] = []
  for dir in dirs {
    let mapping = parse_dir_mapping(dir)
    match mapping {
      Some((host_path, guest_path)) => {
        @logger.debug("Preopen dir: \{host_path} -> \{guest_path}")
        wasi_builder.preopen_dir(host_path, guest_path) |> ignore
        jit_preopens.push((host_path, guest_path))
      }
      None => {
        @logger.error(
          "invalid --dir format '\{dir}', expected HOST_DIR or HOST_DIR::GUEST_DIR",
        )
        exit_failure()
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
        jit_envs.push("\{key}=\{value}")
      }
      None => {
        @logger.error("invalid --env format '\{env_var}', expected NAME=VALUE")
        exit_failure()
        return
      }
    }
  }
  // Handle inherit-env option
  if inherit_env {
    @logger.debug("Inheriting host environment variables")
    // TODO: Implement environ enumeration FFI in wasi/ffi_native.c to support this.
    // For now, use explicit --env NAME=VALUE flags to set environment variables.
    @logger.warn(
      "--inherit-env not yet implemented; use --env NAME=VALUE instead",
    )
  }
  // Handle inherit-stdin/stdout/stderr options
  if inherit_stdin {
    @logger.debug("Inheriting stdin from host")
    wasi_builder.inherit_stdin() |> ignore
  }
  if inherit_stdout {
    @logger.debug("Inheriting stdout from host")
    wasi_builder.inherit_stdout() |> ignore
  }
  if inherit_stderr {
    @logger.debug("Inheriting stderr from host")
    wasi_builder.inherit_stderr() |> ignore
  }
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
            exit_failure()
            return
          }
        }
        let preload_instance = @executor.instantiate_with_linker(
          linker, name, preload_mod,
        ) catch {
          e => {
            @logger.error("instantiating preload module '\{name}': \{e}")
            exit_failure()
            return
          }
        }
        linker.register(name, preload_instance)
      }
      None => {
        @logger.error("invalid preload format '\{preload}', expected NAME=PATH")
        exit_failure()
        return
      }
    }
  }
  // Load main module
  let mod_ = load_module_from_path(wasm_path) catch {
    e => {
      @logger.error("loading main module: \{e}")
      exit_failure()
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
      exit_failure()
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
        exit_failure()
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
      // Build WASI args: program name + any remaining args after --
      let jit_args : Array[String] = wasi_args
      let jit_results = run_with_jit(
        mod_, instance, store, func_name, args, debug, dump_on_trap, jit_args, jit_envs,
        jit_preopens, opt_level, enable_dwarf,
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
          exit_failure()
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
    exit_failure()
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
/// Initialize JIT tables from runtime table state.
/// This is required for call_indirect and table operations in JIT mode.
fn init_jit_tables(
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  jm : @jit.JITModule,
) -> Unit {
  if instance.table_addrs.is_empty() {
    return
  }
  // Collect JIT tables in module table index order
  let jit_tables : Array[@jit.JITTable?] = []
  for table_addr in instance.table_addrs {
    jit_tables.push(store.get_jit_table(table_addr))
  }
  // Build store func address -> module func index map
  let func_addr_to_idx : Map[Int, Int] = {}
  for i, addr in instance.func_addrs {
    func_addr_to_idx.set(addr, i)
  }
  // Copy table contents into JIT tables as (func_ptr, type_idx) pairs
  let elem_init : Array[(Int, Int, Int, Int)] = []
  for table_idx, table_addr in instance.table_addrs {
    let runtime_table = store.get_table(table_addr) catch { _ => continue }
    // Avoid writing past the allocated JIT table size (JIT tables are sized at instantiation).
    let max_entries = match jit_tables[table_idx] {
      Some(t) => t.get_size()
      None => 0
    }
    let size = runtime_table.size().min(max_entries)
    for elem_idx in 0..<size {
      let value = runtime_table.get(elem_idx) catch { _ => continue }
      match value {
        FuncRef(store_addr) => {
          let func_idx = match func_addr_to_idx.get(store_addr) {
            Some(idx) => idx
            None => -1
          }
          let type_idx = if func_idx >= 0 &&
            func_idx < instance.func_type_indices.length() {
            instance.func_type_indices[func_idx]
          } else {
            -1
          }
          elem_init.push((table_idx, elem_idx, func_idx, type_idx))
        }
        // Null and non-funcref entries are written as null to keep shared tables consistent.
        _ => elem_init.push((table_idx, elem_idx, -1, -1))
      }
    }
  }
  jm.init_shared_tables(jit_tables, elem_init)
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
  dump_on_trap : Bool,
  wasi_args : Array[String],
  wasi_envs : Array[String],
  wasi_preopens : Array[(String, String)],
  opt_level : Int,
  enable_dwarf : Bool,
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
  let compiled = compile_module_to_jit(
    mod_,
    debug,
    dump_on_trap,
    actual_memory_max~,
    opt_level,
    enable_dwarf,
  )
  match compiled {
    None => {
      @logger.error("JIT compilation failed")
      return []
    }
    Some((pc, debug_db)) => {
      // Build func_signatures array for JITModule::load
      let func_signatures = build_jit_func_signatures(mod_)
      // Load JIT module
      let jit_module = @jit.JITModule::load(pc, func_signatures, debug_db~)
      match jit_module {
        None => {
          @logger.error("Failed to load JIT module")
          return []
        }
        Some(jm) => {
          // Allocate independent WASM stack with guard page.
          // Use a larger default than 1MB since real-world programs can have
          // large native frames after register allocation.
          let wasm_stack_ok = jm.alloc_wasm_stack(16L * 1024L * 1024L)
          if not(wasm_stack_ok) {
            @logger.warn(
              "failed to allocate WASM stack; falling back to host stack",
            )
          }
          // Register DWARF debug info with debugger if enabled
          // The DWARF info must stay registered for the duration of JIT execution
          let dwarf_builder : @jit.DWARFBuilder? = if enable_dwarf {
            Some(jm.register_dwarf(verbose=@logger.is_debug_enabled()))
          } else {
            None
          }
          // Initialize WASI context with args, env, and preopens
          jm.init_wasi(wasi_args, wasi_envs, wasi_preopens)
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
          // Initialize tables for call_indirect and table operations
          init_jit_tables(instance, store, jm)
          // Find and call the function
          let jit_func = jm.get_func_by_name(func_name)
          match jit_func {
            Some(f) => {
              // Convert args to Int64 using shared helper
              let i64_args = convert_args_to_jit(args)
              @logger.debug("JIT: Calling function '\{func_name}'")
              // Set up GC heap for JIT execution if c_heap is available
              match store.c_heap {
                Some(heap) => {
                  // Compute canonical type indices for proper type equivalence checking
                  let canonical = @types.compute_canonical_type_indices(
                    store.module_types,
                  )
                  @jit.gc_setup(heap, store.module_types, canonical)
                  // Set GC heap in VMContext for inline allocation
                  jm.set_gc_heap(heap.get_ptr())
                }
                None => ()
              }
              let results = jm.call_with_context(f, i64_args) catch {
                @jit.JITTrap(msg) => {
                  @jit.gc_teardown()
                  // Capture and display backtrace if DWARF is enabled
                  match dwarf_builder {
                    Some(dwarf) => {
                      let frames = dwarf.capture_backtrace()
                      if frames.length() > 0 {
                        @logger.error("JIT Trap: \{msg}")
                        @logger.error("Backtrace:")
                        let bt = dwarf.format_backtrace(frames)
                        // Print backtrace lines without the logger prefix
                        for line in bt.split("\n") {
                          if line.length() > 0 {
                            println(line)
                          }
                        }
                      } else {
                        @logger.error("JIT Trap: \{msg}")
                      }
                    }
                    None => @logger.error("JIT Trap: \{msg}")
                  }
                  // NOTE: Memory and globals are now freed by JITContext finalizer (GC-managed)
                  return []
                }
              }
              // Tear down GC context after JIT call
              @jit.gc_teardown()
              // Convert Int64 results to Value using shared helper
              let values = convert_jit_results(results, f.result_types)
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
  dump_on_trap : Bool,
  actual_memory_max? : Int? = None,
  opt_level : Int,
  enable_dwarf : Bool,
) -> (@cwasm.PrecompiledModule, @jit.JITDebugDB?)? {
  let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
  let debug_db : @jit.JITDebugDB? = if dump_on_trap {
    Some(@jit.JITDebugDB::new())
  } else {
    None
  }
  let num_imports = count_func_imports(mod_.imports)
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
  // Compile each function
  for i, _ in mod_.codes {
    let func_idx = num_imports + i
    let type_idx = mod_.funcs[i]
    let func_type = mod_.get_func_type(type_idx)
    let func_name = get_func_name(mod_, func_idx)
    // Stage 1: Translate WASM to IR - use simplified from_module API
    let ir_func = @ir.translate_function(
      mod_,
      i,
      name=func_name,
      memory_max_override=actual_memory_max,
    )
    // Stage 2: Optimize IR (configurable level)
    let normalized_opt_level = if opt_level < 0 {
      0
    } else if opt_level > 3 {
      3
    } else {
      opt_level
    }
    @ir.optimize_with_level(
      ir_func,
      @ir.OptLevel::from_int(normalized_opt_level),
    )
    |> ignore
    let mut ir_dump : String? = None
    if debug_db is Some(_) {
      ir_dump = Some(ir_func.print())
    }
    // Stage 3: Lower to VCode
    let vcode_func = @lower.lower_function(ir_func)
    let mut vcode_before_dump : String? = None
    if debug_db is Some(_) {
      vcode_before_dump = Some(vcode_func.print())
    }
    // Stage 4: Register allocation
    let allocated = @regalloc.allocate_registers_backtracking(vcode_func)
    let mut vcode_after_dump : String? = None
    if debug_db is Some(_) {
      vcode_after_dump = Some(allocated.print())
    }
    // Stage 5: Emit machine code
    let mc = @emit.emit_function(
      allocated,
      debug_func_idx=Some(func_idx),
      force_frame_setup=enable_dwarf,
    )
    let mut mc_dump : String? = None
    if debug_db is Some(_) {
      mc_dump = Some(mc.dump_disasm())
    }
    // Stage 6: Add to precompiled module
    let compiled = @vcode.CompiledFunction::new(func_name, mc, 0)
    // DEBUG: Check MC sizes
    if func_name == "_start" || func_idx == 9 {
      @logger.debug(
        "[COMPILE] \{func_name} (func_\{func_idx}): mc.size()=\{mc.size()}, mc.get_bytes().length()=\{mc.get_bytes().length()}, compiled.code_size=\{compiled.code_size}, get_code().length()=\{compiled.get_code().length()}",
      )
    }
    let num_params = func_type.params.length()
    let num_results = func_type.results.length()
    precompiled.add_function(
      func_idx, func_name, compiled, num_params, num_results,
    )
    match debug_db {
      Some(db) =>
        // Store best-effort dumps (empty string if unavailable for a stage).
        db.set(
          func_idx,
          @jit.JITFunctionDebug::new(
            ir_dump.unwrap_or(""),
            vcode_before_dump.unwrap_or(""),
            vcode_after_dump.unwrap_or(""),
            mc_dump.unwrap_or(""),
          ),
        )
      None => ()
    }
    if @logger.is_debug_enabled() &&
      mod_.codes.length() > 10 &&
      ((i + 1) % 10 == 0 || i + 1 == mod_.codes.length()) {
      @logger.debug("JIT: Compiled \{i + 1}/\{mod_.codes.length()} functions")
    }
  }
  Some((precompiled, debug_db))
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
/// Uses guarded memory allocation for memory 0 to enable bounds check elimination
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
  for i, mem_addr in instance.mem_addrs {
    let mem = store.get_mem(mem_addr) catch { _ => return false }
    let pages = mem.size_pages()
    let size = pages.to_int64() * 65536L
    let (_, max) = mem.get_limits()
    // Allocate JIT memory - use guarded memory for memory 0 (memory32 only)
    let mem_ptr = if i == 0 && not(mem.is_memory64()) {
      // Use guarded memory allocation with mmap + guard pages.
      // This enables bounds check elimination in JIT code for memory32.
      jm.alloc_guarded_memory(pages, max)
    } else {
      // Regular allocation for memory64 and non-zero memories.
      @jit.alloc_memory(size)
    }
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
