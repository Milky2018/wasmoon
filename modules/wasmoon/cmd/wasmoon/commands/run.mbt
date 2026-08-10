///|
/// Exit seam for the failure paths, which all use status 1.
///
/// Typed to return `T` so a caller can end an expression with it; the
/// `panic()` is unreachable and only satisfies that type.
fn[T] exit_failure() -> T {
  @sys.exit(1)
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
      Null => @wasm_milkir.NULL_REF
      V128(_) => {
        @logger.error("V128 args not yet supported")
        exit_failure()
      }
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
        if raw == @wasm_milkir.NULL_REF {
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
        if raw == @wasm_milkir.NULL_REF {
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
pub fn CompileProgress::CompileProgress(
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
    CompileProgress(
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
  let linker = @runtime.Linker::Linker()

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
  let wasi_builder = @wasi.WasiContextBuilder::WasiContextBuilder()
  // argv[0] is the basename of the wasm file (like wasmtime), followed by wasm_args
  let program_name = get_basename(wasm_path)
  let wasi_args = [program_name] + wasm_args
  wasi_builder.args(wasi_args) |> ignore
  let jit_preopens : Array[(String, String)] = []
  let jit_envs : Array[String] = []
  let explicit_env_keys : Map[String, Bool] = Map([])
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
    let host_envs = @env.get_env_vars()
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
  try! @wasi.register_wasi(linker, wasi_ctx)
  // Register spectest module (standard test functions)
  let spectest_instance = try! @wast.create_spectest_module(linker.get_store())
  try! linker.register("spectest", spectest_instance)
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
        validate_module_for_execution(preload_mod) catch {
          e => {
            @logger.error("validating preload module '\{name}': \{e}")
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
        try! linker.register(name, preload_instance)
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
  validate_module_for_execution(mod_) catch {
    e => {
      @logger.error("validating main module: \{e}")
      exit_failure()
      return
    }
  }
  // Instantiate the main module
  // Note: instantiate_module_with_imports already handles:
  // - Data segment initialization
  // - Element segment initialization
  // - Start function execution
  let store = linker.get_store()
  // Enable C heap for JIT mode (required for GC operations)
  if use_jit {
    try! store.enable_c_heap()
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
  let name_builder = StringBuilder::StringBuilder()
  for i in 0..<eq_idx {
    name_builder.write_char(s.code_unit_at(i).unsafe_to_char())
  }
  let path_builder = StringBuilder::StringBuilder()
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
  let name_builder = StringBuilder::StringBuilder()
  for i in 0..<eq_idx {
    name_builder.write_char(s.code_unit_at(i).unsafe_to_char())
  }
  let value_builder = StringBuilder::StringBuilder()
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
  let key_builder = StringBuilder::StringBuilder()
  for i in 0..<eq_idx {
    key_builder.write_char(s.code_unit_at(i).unsafe_to_char())
  }
  let value_builder = StringBuilder::StringBuilder()
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
    let host_builder = StringBuilder::StringBuilder()
    for i in 0..<sep_idx {
      host_builder.write_char(s.code_unit_at(i).unsafe_to_char())
    }
    let guest_builder = StringBuilder::StringBuilder()
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
        return Some(mod_.validated_func_type_at(tidx))
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
fn int_array_to_bytes(ints : Array[Int]) -> Bytes {
  let bytes : Array[Byte] = []
  for value in ints {
    bytes.push((value & 0xFF).to_byte())
  }
  Bytes::from_array(bytes)
}

///|
fn run_jit_cache_dir() -> String {
  match @env.get_env_var("WASMOON_JIT_CACHE_DIR") {
    Some(dir) if dir.length() > 0 => dir
    _ => "/tmp/wasmoon-jit-cache"
  }
}

///|
let run_jit_cache_version = "v9"

///|
fn artifact_optimization_level(level : Int) -> @artifact.OptimizationLevel {
  match normalize_opt_level(level) {
    0 => O0
    1 => O1
    2 => O2
    _ => O3
  }
}

///|
fn jit_artifact_policy(
  opt_level : Int,
  enable_cancellation : Bool,
) -> @artifact.CompilationPolicy {
  {
    optimization_level: artifact_optimization_level(opt_level),
    code_model: Small,
    call_binding: DirectBody,
    cancellation_safepoints: enable_cancellation,
    debug_info: false,
  }
}

///|
fn append_i64_identity_bytes(bytes : Array[Byte], value : Int64) -> Unit {
  for shift in 0..<8 {
    bytes.push((value >> (shift * 8)).to_byte())
  }
}

///|
fn jit_semantic_feature_bytes(
  actual_memory_max : Int?,
  use_subtype_indirect_check : Bool,
  local_compile_mask : Array[Bool]?,
) -> Bytes {
  let bytes : Array[Byte] = [1]
  match actual_memory_max {
    Some(max) => {
      bytes.push(1)
      append_i64_identity_bytes(bytes, max.to_int64())
    }
    None => bytes.push(0)
  }
  bytes.push(if use_subtype_indirect_check { 1 } else { 0 })
  match local_compile_mask {
    Some(mask) => {
      bytes.push(1)
      append_i64_identity_bytes(bytes, mask.length().to_int64())
      for enabled in mask {
        bytes.push(if enabled { 1 } else { 0 })
      }
    }
    None => bytes.push(0)
  }
  Bytes::from_array(bytes)
}

///|
fn build_jit_artifact_manifest(
  mod_ : @types.Module,
  source_module? : Bytes? = None,
  actual_memory_max? : Int? = None,
  opt_level : Int,
  local_compile_mask? : Array[Bool]? = None,
  force_subtype_indirect_check? : Bool? = None,
  enable_cancellation? : Bool = false,
) -> @artifact.CompatibilityManifest raise @wasmoon_jit.JitPipelineError {
  let use_subtype_indirect_check = force_subtype_indirect_check.unwrap_or(
    module_indirect_subtype_check_reason(mod_) is Some(_),
  )
  let source = source_module.unwrap_or_else(fn() {
    int_array_to_bytes(@encoder.encode(mod_))
  })
  let identity = @wasmoon_jit.artifact_module_identity(
    "wasm-module",
    source,
    jit_semantic_feature_bytes(
      actual_memory_max, use_subtype_indirect_check, local_compile_mask,
    ),
  )
  @wasmoon_jit.build_host_artifact_manifest(
    module_identity=identity,
    policy=jit_artifact_policy(opt_level, enable_cancellation),
  )
}

///|
fn jit_artifact_compatibility(
  manifest : @artifact.CompatibilityManifest,
) -> @wasmoon_jit.ArtifactCompatibility {
  @wasmoon_jit.artifact_compatibility(
    manifest,
    available_cpu_features=[],
    runtime_symbols=@wasmoon_jit.wasmoon_runtime_external_symbols(),
    data_symbols=[],
  )
}

///|
/// Verify a freshly compiled v9 artifact before executable installation.
pub fn verify_compiled_jit_artifact(
  artifact : @artifact.Artifact,
) -> @wasmoon_jit.LoadedArtifact raise @wasmoon_jit.ArtifactLoadError {
  @wasmoon_jit.verify_artifact(
    artifact,
    jit_artifact_compatibility(artifact.manifest),
  )
}

///|
fn run_jit_cache_file(
  cache_dir : String,
  manifest : @artifact.CompatibilityManifest,
) -> String {
  let source_digest = manifest.module_identity.source_digest.bytes
  let semantic_digest = manifest.module_identity.semantic_features_digest.bytes
  let target_tag = match manifest.target.architecture {
    X64 => "x86_64"
    AArch64 => "aarch64"
  }
  let os_tag = match manifest.target.operating_system_abi {
    MacOS => "macos"
    LinuxGnu => "linux-gnu"
    LinuxMusl => "linux-musl"
    WindowsMsvc => "windows-msvc"
  }
  let opt_tag = match manifest.policy.optimization_level {
    O0 => "o0"
    O1 => "o1"
    O2 => "o2"
    O3 => "o3"
  }
  let code_model_tag = match manifest.policy.code_model {
    Small => "small"
    Large => "large"
  }
  let call_binding_tag = match manifest.policy.call_binding {
    StableEntry => "stable"
    DirectBody => "direct"
  }
  let cancellation_tag = if manifest.policy.cancellation_safepoints {
    "cancel"
  } else {
    "no-cancel"
  }
  let debug_tag = if manifest.policy.debug_info { "debug" } else { "no-debug" }
  let revision_tag = cache_revision_file_tag(manifest.codegen_revision)
  let file_name = "\{run_jit_cache_version}-\{target_tag}-\{os_tag}-\{opt_tag}-\{code_model_tag}-\{call_binding_tag}-\{cancellation_tag}-\{debug_tag}-r\{revision_tag}-s\{digest_hex(source_digest)}-x\{digest_hex(semantic_digest)}.cwasm"
  if cache_dir.has_suffix("/") {
    "\{cache_dir}\{file_name}"
  } else {
    "\{cache_dir}/\{file_name}"
  }
}

///|
fn cache_revision_file_tag(revision : String) -> String {
  let digits = "0123456789abcdef"
  let output = StringBuilder::StringBuilder()
  for index in 0..<revision.length() {
    let value = revision.code_unit_at(index).to_int()
    for shift in [12, 8, 4, 0] {
      output.write_char(
        digits.code_unit_at((value >> shift) & 0x0F).to_int().unsafe_to_char(),
      )
    }
  }
  output.to_string()
}

///|
fn digest_hex(bytes : Bytes) -> String {
  let digits = "0123456789abcdef"
  let output = StringBuilder::StringBuilder()
  for byte in bytes {
    let value = byte.to_int()
    output.write_char(digits.code_unit_at(value >> 4).to_int().unsafe_to_char())
    output.write_char(
      digits.code_unit_at(value & 0x0F).to_int().unsafe_to_char(),
    )
  }
  output.to_string()
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
fn load_run_jit_cache(
  cache_file : String,
  compatibility : @wasmoon_jit.ArtifactCompatibility,
  limits? : @artifact.DecodeLimits = @artifact.DecodeLimits::default(),
) -> @wasmoon_jit.LoadedArtifact? {
  if !@fs.path_exists(cache_file) {
    return None
  }
  let bytes = @fs.read_file_to_bytes(cache_file) catch { _ => return None }
  let loaded = @wasmoon_jit.load_artifact(bytes, compatibility, limits~) catch {
    _ => {
      @fs.remove_file(cache_file) catch {
        _ => ()
      }
      return None
    }
  }
  Some(loaded)
}

///|
fn save_run_jit_cache(
  cache_file : String,
  artifact : @artifact.Artifact,
) -> Unit {
  let bytes = @artifact.encode(artifact) catch { _ => return }
  @fs.write_bytes_to_file(cache_file, bytes) catch {
    _ => ()
  }
}

///|
fn should_use_run_jit_cache(
  dump_on_trap : Bool,
  perf_metrics_enabled : Bool,
) -> Bool {
  !dump_on_trap && !perf_metrics_enabled
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
  let func_addr_to_idx : Map[Int, Int] = Map([])
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
      _ => {
        @logger.error("memory not found")
        exit_failure()
      }
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
  let expected_manifest = build_jit_artifact_manifest(
    mod_,
    source_module=wasm_binary,
    actual_memory_max~,
    opt_level,
    local_compile_mask~,
  ) catch {
    err => {
      @logger.error("Failed to build JIT artifact manifest: \{err}")
      return exit_failure()
    }
  }
  let compatibility = jit_artifact_compatibility(expected_manifest)
  let mut cache_path : String? = None
  let mut cached_artifact : @wasmoon_jit.LoadedArtifact? = None
  if should_use_run_jit_cache(dump_on_trap, @perf.enabled()) {
    match wasm_binary {
      Some(_) => {
        let cache_dir = run_jit_cache_dir()
        if ensure_run_jit_cache_dir(cache_dir) {
          let path = run_jit_cache_file(cache_dir, expected_manifest)
          cache_path = Some(path)
          cached_artifact = load_run_jit_cache(path, compatibility)
          if cached_artifact is Some(_) && debug {
            @logger.debug("JIT: cache hit \{path}")
          }
        }
      }
      None => ()
    }
  }
  // Compile and verify the same v9 artifact shape used by persisted cache hits.
  let compiled = match cached_artifact {
    Some(loaded) => Some((loaded, None, None))
    None => {
      // The compiler already knows why it gave up, and the stage event
      // carries the reason. Dropping it left `run` reporting nothing but
      // "JIT compilation failed" for a module the compiler had a precise
      // complaint about.
      let failure : Ref[String?] = { val: None }
      let fresh = compile_validated_module_to_jit(
        mod_,
        debug,
        dump_on_trap,
        actual_memory_max~,
        opt_level,
        enable_dwarf,
        local_compile_mask~,
        source_module=wasm_binary,
        on_progress=fn(event) {
          if event.stage is Failed && event.message is Some(message) {
            failure.val = Some(message)
          }
          None
        },
      )
      if fresh is None && failure.val is Some(message) {
        @logger.error("JIT compilation failed: \{message}")
        return exit_failure()
      }
      match fresh {
        None => None
        Some((artifact, debug_db)) => {
          let loaded = @wasmoon_jit.verify_artifact(artifact, compatibility) catch {
            err => {
              @logger.error(
                "Fresh JIT artifact failed validation: \{Repr(err)}",
              )
              return exit_failure()
            }
          }
          Some((loaded, debug_db, Some(artifact)))
        }
      }
    }
  }
  match compiled {
    None => {
      @logger.error("JIT compilation failed")
      return exit_failure()
    }
    Some((loaded, debug_db, fresh_artifact)) => {
      if fresh_artifact is Some(artifact) && cache_path is Some(path) {
        if debug {
          @logger.debug("JIT: cache write \{path}")
        }
        save_run_jit_cache(path, artifact)
      }
      // Build func_signatures array for JITModule::load
      let func_signatures = build_jit_func_signatures(mod_)
      let external_imports = @wast.build_external_imports_for_jit(
        mod_, instance, store,
      )
      // Load JIT module
      let jit_module_result : Result[@jit.JITModule, @jit.JITModuleLoadError] = try
        @jit.JITModule::load_artifact_with_imports(
          loaded,
          func_signatures,
          external_imports,
          function_names=build_jit_function_names(mod_),
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
          let jit_ctx = @wast.JITModuleContext::JITModuleContext(
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
                  jm.setup_gc(
                    heap,
                    store.module_types,
                    canonical,
                    instance.func_type_indices,
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
                  jm.teardown_gc()
                  @wast.sync_jit_globals_to_store(jit_ctx, store)
                  @sys.exit(code)
                  panic()
                }
                JITTrap(msg) => {
                  jm.teardown_gc()
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
                JITCancelled => {
                  jm.teardown_gc()
                  @wast.sync_jit_globals_to_store(jit_ctx, store)
                  @logger.error("JIT invocation cancelled")
                  return exit_failure()
                }
              }
              // Tear down GC context after JIT call
              jm.teardown_gc()
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
/// Compile module bytes into a v9 JIT artifact and emit structured progress.
pub fn compile_module(
  module_bytes : Bytes,
  opt_level? : Int = 2,
  enable_dwarf? : Bool = false,
  on_progress? : (CompileProgress) -> Unit? = fn(_event) { None },
  enable_cancellation? : Bool = false,
) -> @artifact.Artifact? {
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
  let compiled = compile_validated_module_to_jit(
    wasm_module,
    false,
    false,
    actual_memory_max=None,
    opt_level,
    enable_dwarf,
    source_module=Some(module_bytes),
    on_progress~,
    compile_start=Some(compile_start),
    enable_cancellation~,
  )
  match compiled {
    Some((artifact, _debug_db)) => Some(artifact)
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
/// Compile a WASM module to a v9 JIT artifact in memory.
///
/// Decoded modules are untrusted at this public seam and are fully validated
/// before frontend translation. `actual_memory_max` overrides the memory limit
/// used for imported memories.
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
  enable_cancellation? : Bool = false,
) -> (@artifact.Artifact, @wasmoon_jit.JITDebugDB?)? {
  let progress_start = compile_start.unwrap_or(@perf.tick_now())
  @validator.validate_module(mod_) catch {
    error => {
      let message = match error {
        WithContext(context) => context.format()
        _ => @validator.format_validation_error(error)
      }
      emit_compile_progress(
        on_progress,
        Failed,
        progress_start,
        mod_.codes.length(),
        0,
        message=Some(message),
      )
      return None
    }
  }
  compile_validated_module_to_jit(
    mod_,
    debug,
    dump_on_trap,
    actual_memory_max~,
    opt_level,
    enable_dwarf,
    on_progress~,
    compile_start=Some(progress_start),
    local_compile_mask~,
    force_subtype_indirect_check~,
    use_reusable_pipeline~,
    enable_cancellation~,
  )
}

///|
/// Compile a decoded module through the trusted post-validation path.
fn compile_validated_module_to_jit(
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
  enable_cancellation? : Bool = false,
  source_module? : Bytes? = None,
) -> (@artifact.Artifact, @wasmoon_jit.JITDebugDB?)? {
  use_reusable_pipeline |> ignore
  // DWARF registration consumes the completed artifact when the JIT module is
  // loaded; target compilation itself has no separate debug path.
  enable_dwarf |> ignore
  let progress_start = compile_start.unwrap_or(@perf.tick_now())
  let perf_on = @perf.enabled()
  let module_tick = if perf_on { Some(@perf.tick_now()) } else { None }
  let native_target = @wasmoon_jit.host_native_target() catch {
    err => {
      emit_compile_progress(
        on_progress,
        Failed,
        progress_start,
        mod_.codes.length(),
        0,
        message=Some(err.to_string()),
      )
      return None
    }
  }
  let debug_db : @wasmoon_jit.JITDebugDB? = if dump_on_trap {
    Some(JITDebugDB())
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
  let translation_ctx = @wasm_frontend.translation_context_from_module(
    mod_,
    @wasmoon.wasm_frontend_embedding_environment(
      cancellation_safepoints=enable_cancellation,
    ),
    memory_max_override=actual_memory_max,
  )
  let wasm_validation_context = @wasm_frontend.wasm_validation_context(
    translation_ctx,
  )
  let mut compiled_count = 0
  let manifest = build_jit_artifact_manifest(
    mod_,
    source_module~,
    actual_memory_max~,
    opt_level,
    local_compile_mask=compile_mask,
    force_subtype_indirect_check=Some(use_subtype_indirect_check),
    enable_cancellation~,
  ) catch {
    err => {
      emit_compile_progress(
        on_progress,
        Failed,
        progress_start,
        total_compile_funcs,
        compiled_count,
        message=Some(err.to_string()),
      )
      return None
    }
  }
  let imports : Array[@artifact.ImportIdentity] = []
  let functions : Array[@artifact.FunctionCode] = []
  let mut import_func_idx = 0
  for imp in mod_.imports {
    if imp.desc is Func(type_idx) {
      let func_type = mod_.validated_func_type_at(type_idx)
      imports.push(
        @wasmoon_jit.wasm_import_identity(
          import_func_idx,
          imp.mod_name,
          imp.name,
          func_type,
        ),
      )
      import_func_idx = import_func_idx + 1
    }
  }
  // Compile each function
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
    let func_type = mod_.validated_func_type_at(type_idx)
    let func_name = get_func_name(mod_, func_idx)
    let compiler_name = if func_name.is_empty() {
      "func_\{func_idx}"
    } else {
      func_name
    }
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
    let ir_func = @wasm_frontend.translate_function_body(
      translation_ctx,
      compiler_name,
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
      @perf.install_milkir_metrics_sink()
    }
    @milkir.optimize_with_level(
      ir_func,
      @milkir.OptLevel::from_int(normalized_opt_level),
    )
    |> ignore
    if perf_on {
      @perf.clear_milkir_metrics_sink()
    }
    if optimize_tick is Some(tick) {
      @perf.record_stage_us(Optimize, @perf.elapsed_us(tick))
    }
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
    let entry = @wasmoon_jit.compile_wasm_body_artifact_function(
      ir_func,
      wasm_validation_context,
      native_target,
      function_index=func_idx,
      signature=@wasmoon_jit.wasm_function_signature(func_type),
      use_subtype_indirect_check~,
      canonical_type_indices~,
    ) catch {
      err => {
        emit_compile_progress(
          on_progress,
          Failed,
          progress_start,
          total_compile_funcs,
          compiled_count,
          func_idx=Some(func_idx),
          func_name=Some(func_name),
          message=Some(err.to_string()),
        )
        return None
      }
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
    emit_compile_progress(
      on_progress,
      Codegen,
      progress_start,
      total_compile_funcs,
      compiled_count,
      func_idx=Some(func_idx),
      func_name=Some(func_name),
    )
    functions.push(entry)
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
        entry.code.length(),
      )
    }
    if debug_db is Some(db) {
      db.set(
        func_idx,
        JITFunctionDebug(
          ir_dump.unwrap_or(""),
          "",
          "",
          entry.code
          .map(fn(byte) { @types.to_hex_byte(byte.to_int()) })
          .join(" "),
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
    let output_path = match @env.get_env_var("WASMOON_PERF_METRICS_FILE") {
      Some(path) => path
      None => "target/wasmoon-perf-metrics.json"
    }
    @fs.write_string_to_file(output_path, report) catch {
      IOError(message) =>
        @logger.warn(
          "Failed to write perf metrics report to '\{output_path}': \{message}",
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
  Some(({ manifest, imports, functions }, debug_db))
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
      let func_type = mod_.validated_func_type_at(type_idx)
      signatures[i] = (func_type.params.copy(), func_type.results.copy())
    }
  }
  // Fill in signatures for local functions
  for i, type_idx in mod_.funcs {
    let func_idx = num_imports + i
    if type_idx < mod_.types.length() {
      let func_type = mod_.validated_func_type_at(type_idx)
      signatures[func_idx] = (func_type.params.copy(), func_type.results.copy())
    }
  }
  signatures
}

///|
pub fn build_jit_function_names(mod_ : @types.Module) -> Array[String] {
  let total_funcs = count_func_imports(mod_.imports) + mod_.funcs.length()
  Array::makei(total_funcs, fn(index) { get_func_name(mod_, index) })
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
