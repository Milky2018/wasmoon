///|
/// Run a precompiled .cwasm file directly using the JIT runtime
fn run_cwasm(
  cwasm_path : String,
  invoke : String?,
  func_args : Array[String],
  wasm_args : Array[String],
  dirs : Array[String],
  envs : Array[String],
  _debug : Bool,
) -> Unit {
  // Read the .cwasm file
  let bytes = @fs.read_file_to_bytes(cwasm_path) catch {
    IOError(e) => {
      @logger.error("failed to read '\{cwasm_path}': \{e}")
      return
    }
  }
  // Convert Bytes to Array[Int]
  let byte_array : Array[Int] = []
  for i in 0..<bytes.length() {
    byte_array.push(bytes[i].to_int())
  }
  // Parse the precompiled module
  let precompiled = @cwasm.deserialize(byte_array) catch {
    e => {
      @logger.error("failed to parse '\{cwasm_path}': \{e}")
      return
    }
  }
  // Build func_signatures array from the precompiled module
  let func_signatures = build_cwasm_signatures(precompiled)
  // Parse WASI configuration
  let program_name = get_basename(cwasm_path)
  let wasi_args = [program_name] + wasm_args
  let wasi_preopens : Array[(String, String)] = []
  for dir in dirs {
    let mapping = parse_dir_mapping(dir)
    match mapping {
      Some((host_path, guest_path)) =>
        wasi_preopens.push((host_path, guest_path))
      None => {
        @logger.error(
          "invalid --dir format '\{dir}', expected HOST_DIR or HOST_DIR::GUEST_DIR",
        )
        return
      }
    }
  }
  let wasi_envs : Array[String] = []
  for env_var in envs {
    let parsed = parse_env_var(env_var)
    match parsed {
      Some((key, value)) => wasi_envs.push("\{key}=\{value}")
      None => {
        @logger.error("invalid --env format '\{env_var}', expected NAME=VALUE")
        return
      }
    }
  }
  // Build JITConfig
  let config = JITConfig::new()
    .with_wasi(wasi_args, wasi_envs, wasi_preopens)
    .with_memories(precompiled.memories, precompiled.data_segments)
    .with_signatures(func_signatures)
  // Create JITRunner from precompiled module
  let runner = match JITRunner::from_precompiled(precompiled, config) {
    Some(r) => r
    None => {
      @logger.error("failed to load JIT module")
      return
    }
  }
  // Initialize JIT runtime
  if not(runner.alloc_wasm_stack()) {
    @logger.warn("failed to allocate WASM stack; falling back to host stack")
  }
  runner.init_wasi(config.wasi_args, config.wasi_envs, config.wasi_preopens)
  if not(runner.init_memories_from_config()) {
    @logger.error("failed to initialize linear memory")
    return
  }
  // Determine which function to call
  let func_name = match invoke {
    Some(name) => name
    None => "_start"
  }
  // Parse arguments (currently only support i64)
  let args : Array[@types.Value] = []
  for arg in func_args {
    let n = @strconv.parse_int64(arg) catch {
      _ => {
        @logger.error("invalid argument '\{arg}'")
        return
      }
    }
    args.push(@types.Value::I64(n))
  }
  // Call the function using JITRunner
  let results = runner.call(func_name, args) catch {
    @jit.JITTrap(msg) => {
      @logger.error("JIT Trap: \{msg}")
      return
    }
  }
  if results is Some(values) {
    if values.length() > 0 {
      let strs = values.map(format_value)
      println(strs.join(" "))
    }
  } else {
    @logger.error("function '\{func_name}' not found")
  }
}

///|
/// Build function signatures from precompiled module
/// For .cwasm files, we default all types to I64 since full type info is not available
fn build_cwasm_signatures(
  precompiled : @cwasm.PrecompiledModule,
) -> Array[(Array[@types.ValueType], Array[@types.ValueType])] {
  let signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])] = []
  for entry in precompiled.functions {
    let param_types : Array[@types.ValueType] = []
    for _ in 0..<entry.num_params {
      param_types.push(@types.ValueType::I64)
    }
    let result_types : Array[@types.ValueType] = []
    for _ in 0..<entry.num_results {
      result_types.push(@types.ValueType::I64)
    }
    signatures.push((param_types, result_types))
  }
  signatures
}
