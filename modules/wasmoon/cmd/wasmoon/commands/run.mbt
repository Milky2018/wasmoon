///|
extern "c" fn native_exit(code : Int) = "exit"

///|
fn[T] exit_failure() -> T {
  native_exit(1)
  panic()
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
    path[prev_slash + 1:last_slash].to_owned()
  } else {
    path[last_slash + 1:].to_owned()
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
      ExternRef(idx) => @wasmoon_jit.encode_externref(idx)
      Null => @types.NULL_REF
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
        if raw == @types.NULL_REF {
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
        if raw == @types.NULL_REF {
          Null
        } else {
          match @wasmoon_jit.decode_externref(raw) {
            Some(idx) => ExternRef(idx)
            None => ExternRef(raw.to_int())
          }
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
      RefStruct(_) | RefNullStruct(_) | StructRef | RefStructAbs => {
        let raw = results[slot_idx]
        slot_idx += 1
        if raw == 0L {
          Null
        } else {
          StructRef((raw >> 1).to_int())
        }
      }
      RefArray(_) | RefNullArray(_) | ArrayRef | RefArrayAbs => {
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
        let buf : @buffer.Buffer = Buffer(size_hint=16)
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
/// Stage markers for `compile_module` progress callbacks.
pub(all) enum CompileStage {
  Parse
  Verify
  Translate
  Optimize
  Lower
  Regalloc
  Codegen
  Link
  Done
  Failed
}

///|
fn CompileStage::to_string(self : CompileStage) -> String {
  match self {
    Parse => "parse"
    Verify => "verify"
    Translate => "translate"
    Optimize => "optimize"
    Lower => "lower"
    Regalloc => "regalloc"
    Codegen => "codegen"
    Link => "link"
    Done => "done"
    Failed => "failed"
  }
}

///|
pub impl Show for CompileStage with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Structured compile progress event.
pub struct CompileProgress {
  stage : CompileStage
  func_idx : Int?
  func_name : String?
  total_funcs : Int
  compiled_funcs : Int
  elapsed_us : Int64
  message : String?
}

///|
pub fn CompileProgress::new(
  stage : CompileStage,
  total_funcs : Int,
  compiled_funcs : Int,
  elapsed_us : Int64,
  func_idx? : Int? = None,
  func_name? : String? = None,
  message? : String? = None,
) -> CompileProgress {
  {
    stage,
    func_idx,
    func_name,
    total_funcs,
    compiled_funcs,
    elapsed_us,
    message,
  }
}

///|
fn emit_compile_progress(
  on_progress : (CompileProgress) -> Unit?,
  stage : CompileStage,
  compile_start : @perf.PerfTick,
  total_funcs : Int,
  compiled_funcs : Int,
  func_idx? : Int? = None,
  func_name? : String? = None,
  message? : String? = None,
) -> Unit {
  on_progress(
    CompileProgress::new(
      stage,
      total_funcs,
      compiled_funcs,
      @perf.elapsed_us(compile_start),
      func_idx~,
      func_name~,
      message~,
    ),
  )
  |> ignore
}

///|
/// Run a WASM module
/// If invoke is specified, call that function with args
/// Otherwise, run the start function or _start export
pub fn run_wasm(
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
  // Match wasmtime CLI default: stdin is inherited unless explicitly disabled.
  let mut inherit_stdin = true
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
  let explicit_env_keys : Map[String, Bool] = {}
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
        explicit_env_keys[key] = true
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
    let host_envs = @sys.get_env_vars()
    let mut inherited_count = 0
    for key, value in host_envs {
      // Keep explicit --env values authoritative when keys overlap.
      if explicit_env_keys.get(key) is None {
        wasi_builder.env(key, value) |> ignore
        jit_envs.push("\{key}=\{value}")
        inherited_count = inherited_count + 1
      }
    }
    @logger.debug("Inherited \{inherited_count} host environment variables")
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
  let (mod_, wasm_binary) = load_module_with_binary_from_path(wasm_path) catch {
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
    if use_jit {
      // Check if JIT can handle this module.
      let import_ok = check_jit_import_support(mod_, instance, store, debug)
      let has_cross_imports = @wast.has_cross_module_imports(mod_)
      let exports_shared = @wast.exports_shared_resources(mod_)
      let has_unsupported = @wast.has_unsupported_instructions(mod_)
      let can_use_jit = import_ok &&
        !has_cross_imports &&
        !exports_shared &&
        !has_unsupported
      if !can_use_jit {
        let reasons : Array[String] = []
        if !import_ok {
          reasons.push("unsupported imports")
        }
        if has_cross_imports {
          reasons.push("cross-module imports")
        }
        if exports_shared {
          reasons.push("exports shared resources")
        }
        if has_unsupported {
          reasons.push("unsupported instructions")
        }
        let reason_str = if reasons.is_empty() {
          "unknown reason"
        } else {
          reasons.join(", ")
        }
        @logger.error(
          "JIT mode is not supported for this module (" +
          reason_str +
          "). " +
          "Please re-run with --no-jit.",
        )
        exit_failure()
        return
      }

      // JIT execution path
      // Build WASI args: program name + any remaining args after --
      let jit_args : Array[String] = wasi_args
      let jit_stdin_data = if inherit_stdin { None } else { Some(b"") }
      let jit_results = run_with_jit(
        mod_, instance, store, func_name, args, debug, dump_on_trap, jit_args, jit_envs,
        jit_preopens, jit_stdin_data, wasm_binary, opt_level, enable_dwarf,
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
/// Find the index of an exported function
fn find_exported_func_idx(mod_ : @types.Module, func_name : String) -> Int? {
  for exp in mod_.exports {
    if exp.name == func_name && exp.desc is Func(idx) {
      return Some(idx)
    }
  }
  None
}

///|
fn build_run_compile_mask(
  mod_ : @types.Module,
  entry_func_idx : Int,
) -> Array[Bool]? {
  let total_local_funcs = mod_.codes.length()
  if total_local_funcs == 0 {
    return None
  }
  let num_imports = count_func_imports(mod_.imports)
  let compile_mask : Array[Bool] = []
  for _ in 0..<total_local_funcs {
    compile_mask.push(false)
  }
  let pending_locals : Array[Int] = []

  mark_wast_reachable_local_func(
    entry_func_idx, num_imports, compile_mask, pending_locals,
  )
  if mod_.start is Some(func_idx) {
    mark_wast_reachable_local_func(
      func_idx, num_imports, compile_mask, pending_locals,
    )
  }
  for global in mod_.globals {
    collect_wast_reachable_from_instrs(
      global.init,
      num_imports,
      compile_mask,
      pending_locals,
    )
  }
  for elem in mod_.elems {
    if elem.mode is Active(_, offset_expr) {
      collect_wast_reachable_from_instrs(
        offset_expr, num_imports, compile_mask, pending_locals,
      )
    }
    for expr in elem.init {
      collect_wast_reachable_from_instrs(
        expr, num_imports, compile_mask, pending_locals,
      )
    }
  }

  for cursor = 0; cursor < pending_locals.length(); {
    let local_idx = pending_locals[cursor]
    collect_wast_reachable_from_instrs(
      mod_.codes[local_idx].body,
      num_imports,
      compile_mask,
      pending_locals,
    )
    continue cursor + 1
  }

  let selected = count_true(compile_mask)
  if selected == 0 || selected >= total_local_funcs {
    None
  } else {
    Some(compile_mask)
  }
}

///|
fn hash_run_compile_mask(mask : Array[Bool]?) -> Int {
  match mask {
    None => 0
    Some(bits) => {
      let mut h = 5381
      for bit in bits {
        let v = if bit { 1 } else { 0 }
        h = h * 33 + v
      }
      h
    }
  }
}

///|
fn bytes_to_int_array(bytes : Bytes) -> Array[Int] {
  let ints : Array[Int] = []
  for b in bytes {
    ints.push(b.to_int() & 0xFF)
  }
  ints
}

///|
fn int_array_to_bytes(ints : Array[Int]) -> Bytes {
  let bytes : Array[Byte] = []
  for value in ints {
    bytes.push((value & 0xFF).to_byte())
  }
  Bytes::from_array(bytes)
}

///|
fn run_jit_cache_arch_tag() -> String {
  match @isa.ISA::current() {
    AArch64 => "aarch64"
    AMD64 => "x86_64"
  }
}

///|
fn run_jit_cache_dir() -> String {
  match @sys.get_env_var("WASMOON_JIT_CACHE_DIR") {
    Some(dir) if dir.length() > 0 => dir
    _ => "/tmp/wasmoon-jit-cache"
  }
}

///|
fn run_jit_cache_file(
  cache_dir : String,
  wasm_binary : Bytes,
  func_name : String,
  opt_level : Int,
  enable_dwarf : Bool,
  local_compile_mask : Array[Bool]?,
) -> String {
  let module_hash = wasm_binary.hash()
  let func_hash = func_name.hash()
  let mask_hash = hash_run_compile_mask(local_compile_mask)
  let dwarf_tag = if enable_dwarf { 1 } else { 0 }
  // Bump cache key version when generated machine code semantics change.
  let file_name = "v2-\{run_jit_cache_arch_tag()}-o\{opt_level}-d\{dwarf_tag}-f\{func_hash}-m\{mask_hash}-n\{wasm_binary.length()}-h\{module_hash}.cwasm"
  if cache_dir.has_suffix("/") {
    "\{cache_dir}\{file_name}"
  } else {
    "\{cache_dir}/\{file_name}"
  }
}

///|
fn ensure_run_jit_cache_dir(cache_dir : String) -> Bool {
  if @fs.path_exists(cache_dir) {
    @fs.is_dir(cache_dir) catch {
      _ => false
    }
  } else {
    @fs.create_dir(cache_dir) catch {
      _ => return false
    }
    true
  }
}

///|
fn load_run_jit_cache(cache_file : String) -> @cwasm.PrecompiledModule? {
  if !@fs.path_exists(cache_file) {
    return None
  }
  let bytes = @fs.read_file_to_bytes(cache_file) catch { _ => return None }
  let ints = bytes_to_int_array(bytes)
  let precompiled = @cwasm.deserialize(ints) catch {
    _ => {
      @fs.remove_file(cache_file) catch {
        _ => ()
      }
      return None
    }
  }
  Some(precompiled)
}

///|
fn save_run_jit_cache(
  cache_file : String,
  precompiled : @cwasm.PrecompiledModule,
) -> Unit {
  let bytes = int_array_to_bytes(precompiled.serialize())
  @fs.write_bytes_to_file(cache_file, bytes) catch {
    _ => ()
  }
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
fn store_addr_to_module_func_idx(
  store_addr : Int,
  instance : @runtime.ModuleInstance,
) -> Int? {
  // Search for the store address in the instance's func_addrs
  for i, addr in instance.func_addrs {
    if addr == store_addr {
      return Some(i)
    }
  }
  // Not found - treat as null
  None
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
  let globals_ptr = @wasmoon_jit.alloc_memory(size)
  if globals_ptr == 0L {
    return 0L
  }
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
      FuncRef(store_addr) =>
        match store_addr_to_module_func_idx(store_addr, instance) {
          Some(func_idx) => {
            let func_ptr = jit_module.get_func_ptr(func_idx)
            if func_ptr == 0L {
              @wasmoon_jit.encode_funcref_idx(func_idx)
            } else {
              @wasmoon_jit.tag_funcref_ptr(func_ptr)
            }
          }
          None => @types.NULL_REF
        }
      ExternRef(idx) => idx.to_int64()
      ExnRef(idx) => idx.to_int64()
      ArrayRef(gc_ref) => @wasmoon_jit.encode_heap_ref(gc_ref)
      StructRef(gc_ref) => @wasmoon_jit.encode_heap_ref(gc_ref)
      I31(n) => @wasmoon_jit.encode_i31(n)
      Null => @types.NULL_REF // null is encoded as 0 in JIT
      V128(bytes) => {
        // V128 needs special handling - write both 64-bit halves
        let offset = globals_ptr + (i * 16).to_int64()
        let low = bytes_to_int64_le(bytes, 0)
        let high = bytes_to_int64_le(bytes, 8)
        @wasmoon_jit.c_jit_write_i64(offset, low)
        @wasmoon_jit.c_jit_write_i64(offset + 8L, high)
        continue // Skip the normal write below
      }
    }
    // Write value at offset i * 16
    let offset = globals_ptr + (i * 16).to_int64()
    // Use FFI to write the value
    @wasmoon_jit.c_jit_write_i64(offset, raw_value)
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
  use_subtype_indirect_check : Bool,
) -> Unit {
  if instance.table_addrs.is_empty() {
    return
  }
  // Collect JIT tables in module table index order
  let jit_tables : Array[@wasmoon_jit.JITTable?] = []
  for table_addr in instance.table_addrs {
    jit_tables.push(store.get_jit_table(table_addr))
  }
  // Build store func address -> module func index map
  let func_addr_to_idx : Map[Int, Int] = {}
  for i, addr in instance.func_addrs {
    func_addr_to_idx.set(addr, i)
  }
  // Copy table contents into JIT tables as (funcref?, type_idx) pairs
  let elem_init : Array[(Int, Int, Int?, Int)] = []
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
          let func_idx = func_addr_to_idx.get(store_addr)
          let raw_type_idx = match func_idx {
            Some(idx) =>
              if idx >= 0 && idx < instance.func_type_indices.length() {
                instance.func_type_indices[idx]
              } else {
                -1
              }
            None => -1
          }
          let type_idx = if use_subtype_indirect_check {
            raw_type_idx
          } else if raw_type_idx >= 0 &&
            raw_type_idx < instance.canonical_type_indices.length() {
            instance.canonical_type_indices[raw_type_idx]
          } else {
            raw_type_idx
          }
          elem_init.push((table_idx, elem_idx, func_idx, type_idx))
        }
        // Null and non-funcref entries are written as null to keep shared tables consistent.
        _ => elem_init.push((table_idx, elem_idx, None, -1))
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
  wasi_stdin_data : Bytes?,
  wasm_binary : Bytes?,
  opt_level : Int,
  enable_dwarf : Bool,
) -> Array[@types.Value] {
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
  let local_compile_mask = match find_exported_func_idx(mod_, func_name) {
    Some(func_idx) => build_run_compile_mask(mod_, func_idx)
    None => None
  }
  let mut cache_path : String? = None
  let mut cache_precompiled : @cwasm.PrecompiledModule? = None
  if !dump_on_trap {
    match wasm_binary {
      Some(binary) => {
        let cache_dir = run_jit_cache_dir()
        if ensure_run_jit_cache_dir(cache_dir) {
          let path = run_jit_cache_file(
            cache_dir, binary, func_name, opt_level, enable_dwarf, local_compile_mask,
          )
          cache_path = Some(path)
          cache_precompiled = load_run_jit_cache(path)
          if cache_precompiled is Some(_) && debug {
            @logger.debug("JIT: cache hit \{path}")
          }
        }
      }
      None => ()
    }
  }
  // Compile module to precompiled format in memory on cache miss.
  let compiled = match cache_precompiled {
    Some(precompiled) => Some((precompiled, None))
    None =>
      compile_module_to_jit(
        mod_,
        debug,
        dump_on_trap,
        actual_memory_max~,
        opt_level,
        enable_dwarf,
        local_compile_mask~,
      )
  }
  match compiled {
    None => {
      @logger.error("JIT compilation failed")
      return exit_failure()
    }
    Some((pc, debug_db)) => {
      if cache_precompiled is None && cache_path is Some(path) {
        if debug {
          @logger.debug("JIT: cache write \{path}")
        }
        save_run_jit_cache(path, pc)
      }
      // Build func_signatures array for JITModule::load
      let func_signatures = build_jit_func_signatures(mod_)
      let external_imports = @wast.build_external_imports_for_jit(
        mod_, instance, store,
      )
      // Load JIT module
      let jit_module_result : Result[@jit.JITModule, @jit.JITModuleLoadError] = try
        @jit.JITModule::load_with_imports(
          pc,
          func_signatures,
          external_imports,
          debug_db~,
        )
      catch {
        e => Err(e)
      } noraise {
        jm => Ok(jm)
      }
      match jit_module_result {
        Err(err) => {
          @logger.error("Failed to load JIT module: \{err}")
          return exit_failure()
        }
        Ok(jm) => {
          // Enable arbitrary host function imports via JIT -> hostcall bridge.
          @wast.install_jit_hostcall_dispatcher(jm, store, instance)
          // Allocate independent WASM stack with guard page.
          // Use a larger default than 1MB since real-world programs can have
          // large native frames after register allocation.
          let wasm_stack_ok = jm.alloc_wasm_stack(16L * 1024L * 1024L)
          if !wasm_stack_ok {
            @logger.warn(
              "failed to allocate WASM stack; falling back to host stack",
            )
          }
          // Register DWARF debug info with debugger if enabled
          // The DWARF info must stay registered for the duration of JIT execution
          let dwarf_builder : @wasmoon_jit.DWARFBuilder? = if enable_dwarf {
            Some(jm.register_dwarf(verbose=@logger.is_debug_enabled()))
          } else {
            None
          }
          // Initialize WASI context with args, env, and preopens
          jm.init_wasi_with_stdio(
            wasi_args,
            wasi_envs,
            wasi_preopens,
            None,
            None,
            wasi_stdin_data,
          )
          // Initialize all memories (multi-memory support)
          guard @wast.init_jit_memories_from_store(instance, store, jm)
            is Some(_) else {
            @logger.error("Failed to initialize JIT memories")
            return exit_failure()
          }
          // Initialize globals (pass jm for tagged funcref pointers)
          let globals_ptr = init_jit_globals(instance, store, jm)
          if globals_ptr != 0L {
            jm.set_globals(globals_ptr)
          }
          // Initialize tables for call_indirect and table operations
          let use_subtype_indirect_check = module_indirect_subtype_check_reason(
              mod_,
            )
            is Some(_)
          init_jit_tables(instance, store, jm, use_subtype_indirect_check)
          // Initialize per-context data/elem segments for bulk ops (memory.init/table.init/etc).
          @wast.init_bulk_segments(mod_, jm, instance, store) catch {
            err => {
              @logger.error("Failed to initialize JIT bulk segments: \{err}")
              return exit_failure()
            }
          }
          let jit_ctx = @wast.JITModuleContext::new(
            jm,
            globals_ptr,
            instance.global_addrs,
            instance.table_addrs,
            instance.func_addrs,
            instance.func_type_indices,
            instance.canonical_type_indices,
            mod_.types,
            mod_.type_rec_groups,
            use_subtype_indirect_check,
          )

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
                  // Provide func_type_indices + func_table_ptr so libcalls can infer funcref types
                  // (e.g. table.fill) and ref.test can resolve tagged-pointer funcrefs.
                  @wasmoon_jit.gc_setup(
                    heap,
                    store.module_types,
                    canonical,
                    ctx_ptr=jm.get_context_ptr(),
                    func_type_indices=instance.func_type_indices,
                    func_table_ptr=jm.get_func_table_ptr(),
                    num_funcs=jm.get_func_count(),
                  ) catch {
                    err => {
                      @logger.error("JIT GC setup failed: \{err}")
                      return exit_failure()
                    }
                  }
                  // Set GC heap in VMContext for inline allocation
                  jm.set_gc_heap(heap.get_ptr())
                }
                None => ()
              }
              let results = jm.call_with_context(f, i64_args) catch {
                JITExit(code) => {
                  @wasmoon_jit.gc_teardown(jm.get_context_ptr())
                  @wast.sync_jit_globals_to_store(jit_ctx, store)
                  native_exit(code)
                  panic()
                }
                JITTrap(msg) => {
                  @wasmoon_jit.gc_teardown(jm.get_context_ptr())
                  // Sync globals back to interpreter store even on trap.
                  @wast.sync_jit_globals_to_store(jit_ctx, store)
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
                  return exit_failure()
                }
              }
              // Tear down GC context after JIT call
              @wasmoon_jit.gc_teardown(jm.get_context_ptr())
              // Sync JIT globals back to interpreter store for consistency.
              @wast.sync_jit_globals_to_store(jit_ctx, store)
              // Convert Int64 results to Value using shared helper
              let values = convert_jit_results(results, f.result_types)
              // NOTE: Memory and globals are freed automatically by JITContext finalizer (GC-managed)
              values
            }
            None => {
              @logger.error("Function '\{func_name}' not found in JIT module")
              return exit_failure()
            }
          }
        }
      }
    }
  }
}

///|
fn table_elem_type_may_need_subtype_check(elem_type : @types.ValueType) -> Bool {
  match elem_type {
    // Typed funcref tables still use exact signature-id equality unless GC
    // function-subtyping is actually enabled in the module type graph.
    FuncRef | NullFuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) =>
      false
    _ => true
  }
}

///|
fn module_indirect_subtype_check_reason(mod_ : @types.Module) -> String? {
  for subtype in mod_.types {
    if subtype.supertypes.length() > 0 {
      return Some("type has declared supertypes")
    }
    match subtype.composite {
      Func(_) => ()
      _ => return Some("module defines non-func GC composite types")
    }
  }
  for table in mod_.tables {
    if table_elem_type_may_need_subtype_check(table.type_.elem_type) {
      return Some(
        "table element type requires subtype checks: \{table.type_.elem_type.to_string()}",
      )
    }
  }
  None
}

///|
/// Compile module bytes into a precompiled artifact and emit structured progress.
pub fn compile_module(
  module_bytes : Bytes,
  opt_level? : Int = 2,
  enable_dwarf? : Bool = false,
  on_progress? : (CompileProgress) -> Unit? = fn(_event) { None },
) -> @cwasm.PrecompiledModule? {
  let compile_start = @perf.tick_now()
  emit_compile_progress(on_progress, Parse, compile_start, 0, 0)
  let wasm_module = @parser.parse_module(module_bytes) catch {
    e => {
      let message = e.to_string()
      emit_compile_progress(
        on_progress,
        Failed,
        compile_start,
        0,
        0,
        message=Some(message),
      )
      return None
    }
  }
  emit_compile_progress(
    on_progress,
    Verify,
    compile_start,
    wasm_module.codes.length(),
    0,
  )
  @validator.validate_module(wasm_module) catch {
    e => {
      let message = match e {
        WithContext(ctx) => ctx.format()
        _ => @validator.format_validation_error(e)
      }
      emit_compile_progress(
        on_progress,
        Failed,
        compile_start,
        wasm_module.codes.length(),
        0,
        message=Some(message),
      )
      return None
    }
  }
  let compiled = compile_module_to_jit(
    wasm_module,
    false,
    false,
    actual_memory_max=None,
    opt_level,
    enable_dwarf,
    on_progress~,
    compile_start=Some(compile_start),
  )
  match compiled {
    Some((precompiled, _debug_db)) => Some(precompiled)
    None => {
      emit_compile_progress(
        on_progress,
        Failed,
        compile_start,
        wasm_module.codes.length(),
        0,
        message=Some("compile failed"),
      )
      None
    }
  }
}

///|
/// Compile a WASM module to precompiled format in memory
/// actual_memory_max: Override for memory max limit (used for imported memories)
fn compile_module_to_jit(
  mod_ : @types.Module,
  debug : Bool,
  dump_on_trap : Bool,
  actual_memory_max? : Int? = None,
  opt_level : Int,
  enable_dwarf : Bool,
  on_progress? : (CompileProgress) -> Unit? = fn(_event) { None },
  compile_start? : @perf.PerfTick? = None,
  local_compile_mask? : Array[Bool]? = None,
  force_subtype_indirect_check? : Bool? = None,
) -> (@cwasm.PrecompiledModule, @jit.JITDebugDB?)? {
  let progress_start = compile_start.unwrap_or(@perf.tick_now())
  let perf_on = @perf.enabled()
  let module_tick = if perf_on { Some(@perf.tick_now()) } else { None }
  let isa = @isa.ISA::current()
  let target_arch : @cwasm.TargetArch = match isa {
    AArch64 => AArch64
    AMD64 => X86_64
  }
  let precompiled = @cwasm.PrecompiledModule::new(target_arch)
  let debug_db : @jit.JITDebugDB? = if dump_on_trap {
    Some(@jit.JITDebugDB::new())
  } else {
    None
  }
  let num_imports = count_func_imports(mod_.imports)
  let compile_mask = match local_compile_mask {
    Some(mask) =>
      if mask.length() == mod_.codes.length() {
        let mut enabled_count = 0
        for enabled in mask {
          if enabled {
            enabled_count = enabled_count + 1
          }
        }
        if enabled_count > 0 {
          Some(mask)
        } else {
          None
        }
      } else {
        None
      }
    None => None
  }
  let total_compile_funcs = match compile_mask {
    Some(mask) => {
      let mut count = 0
      for enabled in mask {
        if enabled {
          count = count + 1
        }
      }
      count
    }
    None => mod_.codes.length()
  }
  if perf_on {
    @perf.reset_module(total_compile_funcs)
  }
  let canonical_type_indices = @types.compute_canonical_type_indices(
    mod_.types,
    type_rec_groups=mod_.type_rec_groups,
  )
  let subtype_check_reason = module_indirect_subtype_check_reason(mod_)
  // Cranelift-style behavior:
  // - no-GC tables: exact equality on canonicalized type IDs
  // - GC/subtyping tables: keep subtype helper slow path
  let default_use_subtype_indirect_check = subtype_check_reason is Some(_)
  let use_subtype_indirect_check = match force_subtype_indirect_check {
    Some(v) => v
    None => default_use_subtype_indirect_check
  }
  if debug {
    if use_subtype_indirect_check {
      let reason = match subtype_check_reason {
        Some(r) => r
        None => "unknown"
      }
      @logger.debug("JIT: indirect-call subtype check mode enabled (\{reason})")
    } else {
      @logger.debug(
        "JIT: indirect-call exact mode enabled (canonical type ids)",
      )
    }
  }
  let import_func_type_indices : Array[Int] = []
  let global_types : Array[@types.GlobalType] = []
  let all_tags : Array[@types.TagType] = []
  for imp in mod_.imports {
    match imp.desc {
      Func(type_idx) => import_func_type_indices.push(type_idx)
      Global(global_type) => global_types.push(global_type)
      Tag(tag_type_idx) => all_tags.push({ type_idx: tag_type_idx })
      _ => ()
    }
  }
  for global in mod_.globals {
    global_types.push(global.type_)
  }
  for tag in mod_.tags {
    all_tags.push(tag)
  }
  let memory_max_for_translate : Int? = match actual_memory_max {
    Some(_) => actual_memory_max
    None =>
      if mod_.memories.length() > 0 {
        mod_.memories[0].limits.max.map(fn(m) { m.to_int() })
      } else {
        None
      }
  }
  let memory_is_64 = mod_.memories.map(fn(m) { m.is_memory64 })
  let memory_page_size_log2 = mod_.memories.map(fn(m) { m.page_size_log2 })
  let memory_mins = mod_.memories.map(fn(m) {
    m.limits.min * (1L << m.page_size_log2)
  })
  let func_types = @types.extract_func_types(mod_.types)
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
  let mut compiled_count = 0
  for i, _ in mod_.codes {
    let should_compile = match compile_mask {
      Some(mask) => mask[i]
      None => true
    }
    if !should_compile {
      continue
    }
    let func_idx = num_imports + i
    let type_idx = mod_.funcs[i]
    let func_type = mod_.get_func_type(type_idx)
    let func_name = get_func_name(mod_, func_idx)
    emit_compile_progress(
      on_progress,
      Translate,
      progress_start,
      total_compile_funcs,
      compiled_count,
      func_idx=Some(func_idx),
      func_name=Some(func_name),
    )
    // Stage 1: Translate WASM to IR.
    // Reuse per-module metadata across all function translations (Cranelift-style
    // module-environment reuse) to avoid rebuilding import/global/type vectors in
    // every function.
    let code = mod_.codes[i]
    let translator = @ir.Translator::new(
      func_name,
      func_type,
      code.locals,
      func_types,
      mod_.funcs,
      num_imports,
      import_func_type_indices,
      memory_max=memory_max_for_translate,
      memory_is_64~,
      memory_page_size_log2~,
      tables=mod_.tables,
      global_types~,
      type_rec_groups=mod_.type_rec_groups,
      module_types=mod_.types,
      tags=all_tags,
      memory_mins~,
    )
    let ir_func = translator.translate(code.body)
    // Stage 2: Optimize IR (configurable level)
    let normalized_opt_level = if opt_level < 0 {
      0
    } else if opt_level > 3 {
      3
    } else {
      opt_level
    }
    emit_compile_progress(
      on_progress,
      Optimize,
      progress_start,
      total_compile_funcs,
      compiled_count,
      func_idx=Some(func_idx),
      func_name=Some(func_name),
    )
    let optimize_tick = if perf_on { Some(@perf.tick_now()) } else { None }
    if perf_on {
      @perf.begin_function(
        func_idx,
        func_name,
        normalized_opt_level,
        @ir.instruction_count(ir_func),
      )
    }
    @ir.optimize_with_level(
      ir_func,
      @ir.OptLevel::from_int(normalized_opt_level),
    )
    |> ignore
    if optimize_tick is Some(tick) {
      @perf.record_stage_us("optimize", @perf.elapsed_us(tick))
    }
    let lower_tick = if perf_on { Some(@perf.tick_now()) } else { None }
    let mut ir_dump : String? = None
    if debug_db is Some(_) {
      ir_dump = Some(ir_func.print())
    }
    emit_compile_progress(
      on_progress,
      Lower,
      progress_start,
      total_compile_funcs,
      compiled_count,
      func_idx=Some(func_idx),
      func_name=Some(func_name),
    )
    // Stage 3: Lower to VCode
    let vcode_func = @lower.lower_function(
      ir_func,
      num_imports=mod_.imports.length(),
      run_ir_opt=false,
      use_subtype_indirect_check~,
      canonical_type_indices~,
    )
    if lower_tick is Some(tick) {
      @perf.record_stage_us("lower", @perf.elapsed_us(tick))
    }
    let regalloc_tick = if perf_on { Some(@perf.tick_now()) } else { None }
    let mut vcode_before_dump : String? = None
    if debug_db is Some(_) {
      vcode_before_dump = Some(vcode_func.print())
    }
    emit_compile_progress(
      on_progress,
      Regalloc,
      progress_start,
      total_compile_funcs,
      compiled_count,
      func_idx=Some(func_idx),
      func_name=Some(func_name),
    )
    // Stage 4: Register allocation (Cranelift-style output)
    let (vcode_ra, ra_output) = @regalloc.allocate_registers_backtracking_output(
      vcode_func,
    )
    if regalloc_tick is Some(tick) {
      @perf.record_stage_us("regalloc", @perf.elapsed_us(tick))
      let (spills, reloads, reg_moves, spill_to_spill) = ra_output.spill_reload_stats()
      @perf.record_regalloc_stats(
        ra_output.get_num_spillslots(),
        spills,
        reloads,
        reg_moves,
        spill_to_spill,
      )
    }
    let emit_tick = if perf_on { Some(@perf.tick_now()) } else { None }
    let mut vcode_after_dump : String? = None
    if debug_db is Some(_) {
      // Note: VCode is not rewritten; regalloc results are in `ra_output`.
      vcode_after_dump = Some(vcode_ra.print())
    }
    emit_compile_progress(
      on_progress,
      Codegen,
      progress_start,
      total_compile_funcs,
      compiled_count,
      func_idx=Some(func_idx),
      func_name=Some(func_name),
    )
    // Stage 5: Emit machine code
    let debug_func_idx = Some(func_idx)
    let mc = @emit.emit_function_with_regalloc(
      vcode_ra,
      ra_output,
      debug_func_idx~,
      force_frame_setup=enable_dwarf,
      record_disasm=debug_db is Some(_),
    )
    if emit_tick is Some(tick) {
      @perf.record_stage_us("emit", @perf.elapsed_us(tick))
    }
    let mut mc_dump : String? = None
    if debug_db is Some(_) {
      mc_dump = Some(mc.dump_disasm())
    }
    // Stage 6: Add to precompiled module
    let code_size = mc.get_bytes().length()
    let compiled = @vcode.CompiledFunction::new(func_name, mc, 0)
    let num_params = func_type.params.length()
    let num_results = func_type.results.length()
    precompiled.add_function(
      compiled.to_cwasm_entry(func_idx, func_name, num_params, num_results),
    )
    emit_compile_progress(
      on_progress,
      Link,
      progress_start,
      total_compile_funcs,
      compiled_count + 1,
      func_idx=Some(func_idx),
      func_name=Some(func_name),
    )
    if perf_on {
      @perf.finish_function(@ir.instruction_count(ir_func), code_size)
    }
    if debug_db is Some(db) {
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
    }
    compiled_count = compiled_count + 1
    if @logger.is_debug_enabled() &&
      total_compile_funcs > 10 &&
      (compiled_count % 10 == 0 || compiled_count == total_compile_funcs) {
      @logger.debug(
        "JIT: Compiled \{compiled_count}/\{total_compile_funcs} functions",
      )
    }
  }
  if module_tick is Some(tick) {
    @perf.set_module_compile_us(@perf.elapsed_us(tick))
    let report = @perf.export_json()
    let output_path = match @sys.get_env_var("WASMOON_PERF_METRICS_FILE") {
      Some(path) => path
      None => "target/wasmoon-perf-metrics.json"
    }
    @fs.write_string_to_file(output_path, report) catch {
      e =>
        @logger.warn(
          "Failed to write perf metrics report to '\{output_path}': \{e}",
        )
    }
  }
  emit_compile_progress(
    on_progress,
    Done,
    progress_start,
    total_compile_funcs,
    compiled_count,
  )
  Some((precompiled, debug_db))
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
        let n = @string.parse_int(arg) catch {
          _ => {
            // Try parsing as unsigned
            let u = @string.parse_uint(arg) catch {
              _ => raise ArgTypeError(I32, arg)
            }
            u.reinterpret_as_int()
          }
        }
        @types.Value::I32(n)
      }
      I64 => {
        let n = @string.parse_int64(arg) catch {
          _ => {
            let u = @string.parse_uint64(arg) catch {
              _ => raise ArgTypeError(I64, arg)
            }
            u.reinterpret_as_int64()
          }
        }
        I64(n)
      }
      F32 => {
        let n = @string.parse_double(arg) catch {
          _ => raise ArgTypeError(F32, arg)
        }
        F32(Float::from_double(n))
      }
      F64 => {
        let n = @string.parse_double(arg) catch {
          _ => raise ArgTypeError(F64, arg)
        }
        F64(n)
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
  instance : @runtime.ModuleInstance,
  store : @runtime.Store,
  _debug : Bool,
) -> Bool {
  let unsupported : Array[String] = []
  let mut func_imp_idx = 0
  for imp in mod_.imports {
    if imp.desc is Func(_) {
      let has_builtin = @jit.get_import_trampoline(imp.mod_name, imp.name)
        is Some(_)
      if !has_builtin {
        let func_addr = if func_imp_idx < instance.func_addrs.length() {
          instance.func_addrs[func_imp_idx]
        } else {
          -1
        }
        if func_addr < 0 {
          unsupported.push("\{imp.mod_name}.\{imp.name}")
        } else {
          let inst = store.get_func_inst(func_addr) catch {
            _ => {
              unsupported.push("\{imp.mod_name}.\{imp.name}")
              continue
            }
          }
          if !(inst is HostFunc(_)) {
            unsupported.push("\{imp.mod_name}.\{imp.name}")
          }
        }
      }
      func_imp_idx = func_imp_idx + 1
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
