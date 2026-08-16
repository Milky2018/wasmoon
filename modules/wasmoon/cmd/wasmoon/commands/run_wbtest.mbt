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
test "run JIT cache version tracks the artifact format" {
  inspect(run_jit_cache_version, content="v9")
}

///|
test "run JIT cache encodes the codegen revision as a path-safe component" {
  inspect(
    cache_revision_file_tag("machv-vcode-7"),
    content="006d0061006300680076002d00760063006f00640065002d0037",
  )
}

///|
test "run JIT cache uses platform user cache directories" {
  debug_inspect(
    [
      resolve_run_jit_cache_location(
        Some(MacOS),
        Map([("HOME", "/Users/test")]),
      ),
      resolve_run_jit_cache_location(
        Some(LinuxGnu),
        Map([("XDG_CACHE_HOME", "/var/cache/test")]),
      ),
      resolve_run_jit_cache_location(
        Some(LinuxMusl),
        Map([("HOME", "/home/test")]),
      ),
      resolve_run_jit_cache_location(
        Some(WindowsMsvc),
        Map([("LOCALAPPDATA", "C:/Users/test/AppData/Local")]),
      ),
    ].map(fn(location) {
      match location {
        Some(location) => Some((location.directory, location.parent))
        None => None
      }
    }),
    content=(
      #|[
      #|  Some(
      #|    (
      #|      "/Users/test/Library/Caches/wasmoon",
      #|      Some("/Users/test/Library/Caches"),
      #|    ),
      #|  ),
      #|  Some(("/var/cache/test/wasmoon", Some("/var/cache/test"))),
      #|  Some(("/home/test/.cache/wasmoon", Some("/home/test/.cache"))),
      #|  Some(
      #|    (
      #|      "C:/Users/test/AppData/Local/wasmoon/cache",
      #|      Some("C:/Users/test/AppData/Local/wasmoon"),
      #|    ),
      #|  ),
      #|]
    ),
  )
}

///|
test "run JIT cache override is authoritative and missing user dirs disable cache" {
  debug_inspect(
    [
      resolve_run_jit_cache_location(
        None,
        Map([("WASMOON_JIT_CACHE_DIR", "/explicit/cache")]),
      ),
      resolve_run_jit_cache_location(Some(LinuxGnu), Map([])),
      resolve_run_jit_cache_location(Some(WindowsMsvc), Map([])),
      resolve_run_jit_cache_location(None, Map([])),
    ].map(fn(location) {
      match location {
        Some(location) => Some((location.directory, location.parent))
        None => None
      }
    }),
    content=(
      #|[Some(("/explicit/cache", None)), None, None, None]
    ),
  )
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
    IOError(message) => abort("failed to write cache fixture: \{message}")
  }
}

///|
test "run JIT cache accepts an exactly compatible v9 artifact" {
  guard compile_module(minimal_i32_const_module_bytes()) is Some(artifact) else {
    fail("compile returned unsupported")
  }
  let deterministic_manifest = {
    ..artifact.manifest,
    target: {
      ..artifact.manifest.target,
      architecture: AArch64,
      operating_system_abi: MacOS,
    },
  }
  inspect(
    run_jit_cache_file("/tmp/cache", deterministic_manifest),
    content="/tmp/cache/v9-aarch64-macos-o2-small-direct-no-cancel-no-debug-r006d0061006300680076002d00760063006f00640065002d0037-s32e9891ae7d3cedff10d21cea1ae3a989d4fb5424b89b9c2f93328535cf30af7-x67abdd721024f0ff4e0b3f4c2fc13bc5bad42d0b7851d456d88d203d15aaa450.cwasm",
  )
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
test "run JIT cache rejects an artifact from the previous codegen revision" {
  guard compile_module(minimal_i32_const_module_bytes()) is Some(current) else {
    fail("compile returned unsupported")
  }
  let previous : @artifact.Artifact = {
    ..current,
    manifest: { ..current.manifest, codegen_revision: "machv-vcode-6" },
  }
  let path = cache_test_file("previous-codegen")
  save_run_jit_cache(path, previous)
  let loaded = load_run_jit_cache(
    path,
    jit_artifact_compatibility(current.manifest),
  )
  debug_inspect(
    (
      current.manifest.codegen_revision,
      previous.manifest.codegen_revision,
      loaded is None,
      @fs.path_exists(path),
    ),
    content=(
      #|("machv-vcode-7", "machv-vcode-6", true, false)
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
