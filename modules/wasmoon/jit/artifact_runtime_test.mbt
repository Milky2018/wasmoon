///|
fn runtime_artifact_manifest() -> @artifact.CompatibilityManifest raise @wasmoon_jit.JitPipelineError {
  let policy : @artifact.CompilationPolicy = {
    optimization_level: O2,
    code_model: Small,
    call_binding: DirectBody,
    cancellation_safepoints: false,
    debug_info: false,
  }
  @wasmoon_jit.build_host_artifact_manifest(
    module_identity=@wasmoon_jit.artifact_module_identity(
      "jit-runtime-test", b"runtime-source", b"baseline",
    ),
    policy~,
  )
}

///|
fn runtime_artifact_code(
  return_value : Int?,
) -> Array[Byte] raise @wasmoon_jit.JitPipelineError {
  match (@wasmoon_jit.host_native_target(), return_value) {
    (X64, Some(value)) =>
      [
        b'\xb8',
        (value & 0xff).to_byte(),
        ((value >> 8) & 0xff).to_byte(),
        ((value >> 16) & 0xff).to_byte(),
        ((value >> 24) & 0xff).to_byte(),
        b'\xc3',
      ]
    (AArch64, Some(value)) => {
      let instruction = 0x52800000 | ((value & 0xffff) << 5)
      [
        (instruction & 0xff).to_byte(),
        ((instruction >> 8) & 0xff).to_byte(),
        ((instruction >> 16) & 0xff).to_byte(),
        ((instruction >> 24) & 0xff).to_byte(),
        b'\xc0',
        b'\x03',
        b'\x5f',
        b'\xd6',
      ]
    }
    (X64, None) => [b'\xe8', b'\x00', b'\x00', b'\x00', b'\x00', b'\xc3']
    (AArch64, None) =>
      [b'\x00', b'\x00', b'\x00', b'\x94', b'\xc0', b'\x03', b'\x5f', b'\xd6']
  }
}

///|
fn runtime_artifact_function(
  function_index : Int,
  code : Array[Byte],
  signature : @machv.Signature,
  relocations? : Array[@code_object.Relocation] = [],
) -> @artifact.FunctionCode {
  {
    identity: {
      function_index,
      symbol: @machv.CodeSymbol::new("wasm.func.\{function_index}"),
      signature,
    },
    entry_offset: 0,
    frame_size: 0,
    code,
    relocations,
    sources: [],
    traps: [],
    safepoints: [],
    unwind: [],
  }
}

///|
fn load_runtime_artifact(
  artifact : @artifact.Artifact,
  runtime_symbols? : Array[@machv.ExternalSymbol] = [],
) -> @wasmoon_jit.LoadedArtifact raise @wasmoon_jit.ArtifactLoadError {
  let compatibility = @wasmoon_jit.artifact_compatibility(
    artifact.manifest,
    available_cpu_features=[],
    runtime_symbols~,
    data_symbols=[],
  )
  @wasmoon_jit.verify_artifact(artifact, compatibility)
}

///|
fn runtime_call_relocation(
  target : @code_object.RelocationTarget,
) -> @code_object.Relocation raise @wasmoon_jit.JitPipelineError {
  match @wasmoon_jit.host_native_target() {
    X64 => @code_object.Relocation::new(1, X64PcRelative32, target)
    AArch64 => @code_object.Relocation::new(0, AArch64Call26, target)
  }
}

///|
test "JITModule publishes a complete installed artifact" {
  let artifact : @artifact.Artifact = {
    manifest: runtime_artifact_manifest(),
    imports: [],
    functions: [
      runtime_artifact_function(
        0,
        runtime_artifact_code(Some(42)),
        @machv.Signature::new([], [I32]),
      ),
    ],
  }
  let jit_module = JITModule::load_artifact(
    load_runtime_artifact(artifact),
    [([], [I32])],
    function_names=["answer"],
  )
  guard jit_module.get_func_by_name("answer") is Some(function) else {
    fail("installed function was not published")
  }
  debug_inspect(
    (jit_module.get_func_count(), jit_module.call_with_context(function, [])),
    content="(1, [42])",
  )
}

///|
test "JITModule resolves imported Code symbols transactionally" {
  let relocation = runtime_call_relocation(
    Code(@machv.CodeSymbol::new("wasm.func.0")),
  )
  let artifact : @artifact.Artifact = {
    manifest: runtime_artifact_manifest(),
    imports: [
      {
        function_index: 0,
        module_name: "env",
        function_name: "host",
        symbol: @machv.ExternalSymbol::new("wasm.func.0"),
        signature: @machv.Signature::new([], []),
      },
    ],
    functions: [
      runtime_artifact_function(
        1,
        runtime_artifact_code(None),
        @machv.Signature::new([], []),
        relocations=[relocation],
      ),
    ],
  }
  let imports : Map[String, Map[String, Int64]] = Map([])
  imports.set("env", Map([("host", @wasmoon_jit.get_spectest_print_ptr())]))
  let jit_module = JITModule::load_artifact_with_imports(
    load_runtime_artifact(artifact),
    [([], []), ([], [])],
    imports,
    function_names=["host", "caller"],
  )
  debug_inspect(
    (
      jit_module.get_func_count(),
      jit_module.get_func_by_name("caller").map(function => function.name),
    ),
    content="(2, Some(\"caller\"))",
  )
}

///|
test "JITModule resolves named Wasmoon runtime symbols" {
  let runtime_symbol = @machv.ExternalSymbol::new("wasmoon.runtime.cancel_poll")
  let artifact : @artifact.Artifact = {
    manifest: runtime_artifact_manifest(),
    imports: [],
    functions: [
      runtime_artifact_function(
        0,
        runtime_artifact_code(None),
        @machv.Signature::new([], []),
        relocations=[runtime_call_relocation(External(runtime_symbol))],
      ),
    ],
  }
  let jit_module = JITModule::load_artifact(
    load_runtime_artifact(
      artifact,
      runtime_symbols=@wasmoon_jit.wasmoon_runtime_external_symbols(),
    ),
    [([], [])],
    function_names=["poller"],
  )
  debug_inspect(
    (
      jit_module.get_func_count(),
      jit_module.get_func_by_name("poller").map(function => function.name),
    ),
    content="(1, Some(\"poller\"))",
  )
}

///|
test "JITModule retains generated hostcall import trampolines" {
  let artifact : @artifact.Artifact = {
    manifest: runtime_artifact_manifest(),
    imports: [
      {
        function_index: 0,
        module_name: "env",
        function_name: "hostcall",
        symbol: @machv.ExternalSymbol::new("wasm.func.0"),
        signature: @machv.Signature::new([], []),
      },
    ],
    functions: [],
  }
  let imports : Map[String, Map[String, Int64]] = Map([])
  imports.set("env", Map([("hostcall", -1L)]))
  let jit_module = JITModule::load_artifact_with_imports(
    load_runtime_artifact(artifact),
    [([], [])],
    imports,
  )
  debug_inspect(jit_module.get_func_count(), content="1")
  assert_not_eq(jit_module.get_func_ptr(0), 0L)
}

///|
test "failed artifact replacement leaves the previous module executable" {
  let good_artifact : @artifact.Artifact = {
    manifest: runtime_artifact_manifest(),
    imports: [],
    functions: [
      runtime_artifact_function(
        0,
        runtime_artifact_code(Some(42)),
        @machv.Signature::new([], [I32]),
      ),
    ],
  }
  let previous = JITModule::load_artifact(
    load_runtime_artifact(good_artifact),
    [([], [I32])],
    function_names=["answer"],
  )
  let missing = @machv.ExternalSymbol::new("missing.runtime.symbol")
  let bad_artifact : @artifact.Artifact = {
    manifest: runtime_artifact_manifest(),
    imports: [],
    functions: [
      runtime_artifact_function(
        0,
        runtime_artifact_code(None),
        @machv.Signature::new([], []),
        relocations=[runtime_call_relocation(External(missing))],
      ),
    ],
  }
  let failed = try
    JITModule::load_artifact(
      load_runtime_artifact(bad_artifact, runtime_symbols=[missing]),
      [([], [])],
    )
  catch {
    error => error
  } noraise {
    _ => abort("expected unresolved runtime symbol to fail")
  }
  guard previous.get_func_by_name("answer") is Some(function) else {
    fail("previous installed function disappeared")
  }
  debug_inspect(
    (failed, previous.call_with_context(function, [])),
    content=(
      #|(
      #|  ArtifactInstallationFailed(cause=ResolutionFailed(kind="external", name="missing.runtime.symbol")),
      #|  [42],
      #|)
    ),
  )
}
