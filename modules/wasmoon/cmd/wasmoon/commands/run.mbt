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
      StructRef(idx) => @wasmoon_jit.encode_heap_ref(idx)
      ArrayRef(idx) => @wasmoon_jit.encode_heap_ref(idx)
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
          StructRef(@wasmoon_jit.decode_heap_ref(raw))
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
          StructRef(@wasmoon_jit.decode_heap_ref(raw))
        }
      }
      RefArray(_) | RefNullArray(_) | ArrayRef | RefArrayAbs => {
        let raw = results[slot_idx]
        slot_idx += 1
        if raw == 0L {
          Null
        } else {
          ArrayRef(@wasmoon_jit.decode_heap_ref(raw))
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
        V128(@types.int64_pair_to_v128_le(low, high))
      }
    }
    values.push(value)
  }
  values
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
  match @wasmoon_jit.host_target_arch() {
    AArch64 => "aarch64"
    X86_64 => "x86_64"
    Unknown => "unknown"
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
  let file_name = "v3-\{run_jit_cache_arch_tag()}-o\{opt_level}-d\{dwarf_tag}-f\{func_hash}-m\{mask_hash}-n\{wasm_binary.length()}-h\{module_hash}.cwasm"
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
          let globals_ptr = @wast.init_jit_globals_from_store(
            instance, store, jm,
          )
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
fn normalize_opt_level(opt_level : Int) -> Int {
  if opt_level < 0 {
    0
  } else if opt_level > 3 {
    3
  } else {
    opt_level
  }
}

///|
fn vcode_func_addr_fixups_to_cwasm(
  fixups : Array[@machv_emit.FuncAddrFixup],
) -> Array[@cwasm.FuncAddrFixup] {
  let out : Array[@cwasm.FuncAddrFixup] = []
  for fixup in fixups {
    let func_idx = match
      @wasmoon_jit.machv_reloc_target_to_cwasm_func_idx(fixup.target) {
      Some(idx) => idx
      None => abort("cannot encode external func-addr target: \{fixup.target}")
    }
    out.push({ offset: fixup.offset, func_idx, reg: fixup.reg })
  }
  out
}

///|
fn vcode_call_fixups_to_cwasm(
  fixups : Array[@machv_emit.CallFixup],
) -> Array[@cwasm.CallFixup] {
  let out : Array[@cwasm.CallFixup] = []
  for fixup in fixups {
    let func_idx = match
      @wasmoon_jit.machv_reloc_target_to_cwasm_func_idx(fixup.target) {
      Some(idx) => idx
      None => abort("cannot encode external call target: \{fixup.target}")
    }
    out.push({
      offset: fixup.offset,
      func_idx,
      veneer_offset: fixup.veneer_offset,
    })
  }
  out
}

///|
fn vcode_gc_safepoints_to_cwasm(
  safepoints : Array[@machv_emit.GcSafepoint],
) -> Array[@cwasm.GcSafepoint] {
  let out : Array[@cwasm.GcSafepoint] = []
  for safepoint in safepoints {
    out.push(
      @cwasm.GcSafepoint::new(
        safepoint.code_offset,
        safepoint.live_refs,
        safepoint.metadata,
      ),
    )
  }
  out
}

///|
/// Compile a WASM module to precompiled format in memory
/// actual_memory_max: Override for memory max limit (used for imported memories)
pub fn compile_module_to_jit(
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
  use_reusable_pipeline? : Bool = true,
) -> (@cwasm.PrecompiledModule, @wasmoon_jit.JITDebugDB?)? {
  use_reusable_pipeline |> ignore
  let progress_start = compile_start.unwrap_or(@perf.tick_now())
  let perf_on = @perf.enabled()
  let module_tick = if perf_on { Some(@perf.tick_now()) } else { None }
  let target_arch = @wasmoon_jit.host_target_arch()
  let isa = @wasmoon_jit.target_arch_to_isa(target_arch)
  let precompiled = @cwasm.PrecompiledModule::new(target_arch)
  let debug_db : @wasmoon_jit.JITDebugDB? = if dump_on_trap {
    Some(@wasmoon_jit.JITDebugDB::new())
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
  let default_use_subtype_indirect_check = subtype_check_reason is Some(_)
  let use_subtype_indirect_check = match force_subtype_indirect_check {
    Some(v) => v
    None => default_use_subtype_indirect_check
  }
  if debug {
    if use_subtype_indirect_check {
      let reason = subtype_check_reason.unwrap_or("unknown")
      @logger.debug("JIT: indirect-call subtype check mode enabled (\{reason})")
    } else {
      @logger.debug(
        "JIT: indirect-call exact mode enabled (canonical type ids)",
      )
    }
  }
  let translation_ctx = @ir.TranslationContext::from_module(
    mod_,
    @wasmoon.wasm_frontend_embedding_environment(),
    memory_max_override=actual_memory_max,
  )
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
    let normalized_opt_level = normalize_opt_level(opt_level)
    let code = mod_.codes[i]
    let ir_func = @ir.translate_function_body(
      translation_ctx,
      func_name,
      func_type,
      code.locals,
      code.body,
    )
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
        @milkir.instruction_count(ir_func),
      )
    }
    @milkir.optimize_with_level(
      ir_func,
      @milkir.OptLevel::from_int(normalized_opt_level),
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
    let call_conv = @wasmoon_jit.wasm_calling_convention(isa~)
    let roles = @wasmoon_jit.wasm_embedding_reg_roles(isa~)
    let vcode_func = @wasm_isa_lower.lower_function(
      ir_func,
      isa~,
      embedding_reg_roles=roles,
      num_imports=mod_.imports.length(),
      run_ir_opt=false,
      runtime_layout=Some(@wasmoon_jit.runtime_context_layout()),
      call_conv_layout=Some(call_conv),
      runtime_symbols=@wasmoon_jit.wasm_runtime_symbols(),
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
    let (vcode_ra, ra_output) = @machv_regalloc.allocate_registers_backtracking_output_with_isa(
      vcode_func,
      isa,
      @abi.ABISettings::default(),
      call_conv_layout=Some(call_conv),
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
    let mc = @machv_emit.emit_function_with_regalloc(
      vcode_ra,
      ra_output,
      isa~,
      debug_func_idx=Some(func_idx),
      force_frame_setup=enable_dwarf,
      runtime_layout=Some(@wasmoon_jit.runtime_context_layout()),
      call_conv_layout=Some(call_conv),
      record_disasm=debug_db is Some(_),
    )
    if emit_tick is Some(tick) {
      @perf.record_stage_us("emit", @perf.elapsed_us(tick))
    }
    let mut mc_dump : String? = None
    if debug_db is Some(_) {
      mc_dump = Some(mc.dump_disasm())
    }
    let compiled = @machv_emit.CompiledFunction::new(func_name, mc, 0)
    let num_params = func_type.params.length()
    let num_results = func_type.results.length()
    precompiled.add_function(
      @wasmoon_jit.build_cwasm_entry_from_code(
        func_idx,
        func_name,
        compiled.get_code(),
        compiled.frame_size,
        compiled.entry_offset,
        num_params,
        num_results,
        func_addr_fixups=vcode_func_addr_fixups_to_cwasm(
          compiled.get_func_addr_fixups(),
        ),
        call_fixups=vcode_call_fixups_to_cwasm(compiled.get_call_fixups()),
        gc_safepoints=vcode_gc_safepoints_to_cwasm(compiled.get_gc_safepoints()),
        gc_stackmap_blob=compiled.get_gc_stackmap_blob(),
      ),
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
      @perf.finish_function(
        @milkir.instruction_count(ir_func),
        compiled.code_size,
      )
    }
    if debug_db is Some(db) {
      db.set(
        func_idx,
        @wasmoon_jit.JITFunctionDebug::new(
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
      let has_builtin = @wasmoon_jit.get_import_trampoline(
          imp.mod_name,
          imp.name,
        )
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
    @logger.debug("JIT: unsupported imports: \{joined}")
    false
  } else {
    true
  }
}
