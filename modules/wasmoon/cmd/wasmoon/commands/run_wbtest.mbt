///|
fn minimal_i32_const_module_bytes() -> Bytes {
  Bytes::from_array([
    // Magic + version
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    // Type section: (func) -> i32
     0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f,
    // Function section: one local function of type 0
     0x03, 0x02, 0x01, 0x00,
    // Export section: (export "run" (func 0))
     0x07, 0x07, 0x01, 0x03, 0x72, 0x75, 0x6e, 0x00, 0x00,
    // Code section: i32.const 42; end
     0x0a, 0x06, 0x01, 0x04, 0x00, 0x41, 0x2a, 0x0b,
  ])
}

///|
test "run validation seam rejects invalid decoded module" {
  let invalid = @types.Module::simple([], [], [LocalGet(0)], "invalid_local")
  let error = try {
    validate_module_for_execution(invalid)
    None
  } catch {
    err => Some(Show::to_string(err))
  }
  guard error is Some(message) else {
    fail("invalid module unexpectedly passed run validation")
  }
  inspect(
    message.contains(
      "validate wasm module error: validation error: invalid local index: 0",
    ),
    content="true",
  )
  inspect(message.contains("in function: func[0]"), content="true")
  inspect(message.contains("instruction: LocalGet(0)"), content="true")
}

///|
test "compile api: emits stage progress and returns artifact" {
  let events : Array[CompileProgress] = []
  let compiled = compile_module(minimal_i32_const_module_bytes(), on_progress=fn(
    event,
  ) {
    events.push(event)
    None
  })
  inspect(compiled is Some(_), content="true")
  inspect(events.length() > 0, content="true")
  inspect(events[0].stage.to_string(), content="parse")
  let last = events[events.length() - 1]
  inspect(last.stage.to_string(), content="done")
  inspect(last.compiled_funcs, content="1")
}

///|
test "compile api: records cancellation safepoints" {
  guard compile_module(
      minimal_i32_const_module_bytes(),
      enable_cancellation=true,
    )
    is Some(compiled) else {
    fail("compile returned unsupported")
  }
  debug_inspect(
    compiled.manifest.policy,
    content=(
      #|{
      #|  optimization_level: O2,
      #|  code_model: Small,
      #|  call_binding: DirectBody,
      #|  cancellation_safepoints: true,
      #|  debug_info: false,
      #|}
    ),
  )
}

///|
test "compile api: parse failure emits failed stage" {
  let events : Array[CompileProgress] = []
  let compiled = compile_module(Bytes::from_array([0x00, 0x01, 0x02]), on_progress=fn(
    event,
  ) {
    events.push(event)
    None
  })
  inspect(compiled is Some(_), content="false")
  inspect(events.length() >= 2, content="true")
  let last = events[events.length() - 1]
  inspect(last.stage.to_string(), content="failed")
}

///|
test "run JIT cache version tracks machine-code semantics" {
  inspect(run_jit_cache_version, content="v9")
}

///|
fn cache_test_file(label : String) -> String {
  "/tmp/wasmoon-v9-cache-\{label}.cwasm"
}

///|
fn write_cache_test_bytes(path : String, bytes : Bytes) -> Unit {
  @fs.remove_file(path) catch {
    _ => ()
  }
  @fs.write_bytes_to_file(path, bytes) catch {
    err => abort("failed to write cache fixture: \{err}")
  }
}

///|
test "run JIT cache accepts an exactly compatible v9 artifact" {
  guard compile_module(minimal_i32_const_module_bytes()) is Some(artifact) else {
    fail("compile returned unsupported")
  }
  let path = cache_test_file("compatible")
  save_run_jit_cache(path, artifact)
  guard load_run_jit_cache(path, jit_artifact_compatibility(artifact.manifest))
    is Some(loaded) else {
    fail("compatible cache entry was rejected")
  }
  debug_inspect(
    loaded.artifact().manifest.policy,
    content=(
      #|{
      #|  optimization_level: O2,
      #|  code_model: Small,
      #|  call_binding: DirectBody,
      #|  cancellation_safepoints: false,
      #|  debug_info: false,
      #|}
    ),
  )
  @fs.remove_file(path)
}

///|
test "run JIT cache removes corrupt and old entries" {
  guard compile_module(minimal_i32_const_module_bytes()) is Some(artifact) else {
    fail("compile returned unsupported")
  }
  let compatibility = jit_artifact_compatibility(artifact.manifest)
  let outcomes : Array[(String, Bool, Bool)] = []
  for
    fixture in [
      ("corrupt", Bytes::from_array([b'n', b'o', b'p', b'e'])),
      ("old", Bytes::from_array([b'c', b'w', b'a', b's', 8, 0, 0, 0])),
    ] {
    let (label, bytes) = fixture
    let path = cache_test_file(label)
    write_cache_test_bytes(path, bytes)
    let rejected = load_run_jit_cache(path, compatibility) is None
    outcomes.push((label, rejected, @fs.path_exists(path)))
  }
  debug_inspect(
    outcomes,
    content=(
      #|[("corrupt", true, false), ("old", true, false)]
    ),
  )
}

///|
test "run JIT cache removes incompatible and oversized entries" {
  guard compile_module(minimal_i32_const_module_bytes(), opt_level=2)
    is Some(artifact) else {
    fail("compile returned unsupported")
  }
  guard compile_module(minimal_i32_const_module_bytes(), opt_level=3)
    is Some(other_policy) else {
    fail("compile returned unsupported")
  }
  let bytes = @artifact.encode(artifact)
  let incompatible_path = cache_test_file("incompatible")
  write_cache_test_bytes(incompatible_path, bytes)
  let incompatible = load_run_jit_cache(
    incompatible_path,
    jit_artifact_compatibility(other_policy.manifest),
  )
  let oversized_path = cache_test_file("oversized")
  write_cache_test_bytes(oversized_path, bytes)
  let oversized = load_run_jit_cache(
    oversized_path,
    jit_artifact_compatibility(artifact.manifest),
    limits={
      ..@artifact.DecodeLimits::default(),
      max_artifact_bytes: bytes.length() - 1,
    },
  )
  debug_inspect(
    [
      ("incompatible", incompatible is None, @fs.path_exists(incompatible_path)),
      ("oversized", oversized is None, @fs.path_exists(oversized_path)),
    ],
    content=(
      #|[("incompatible", true, false), ("oversized", true, false)]
    ),
  )
}

///|
test "compile metrics bypass the run JIT cache" {
  inspect(should_use_run_jit_cache(false, false), content="true")
  inspect(should_use_run_jit_cache(true, false), content="false")
  inspect(should_use_run_jit_cache(false, true), content="false")
  inspect(should_use_run_jit_cache(true, true), content="false")
}
