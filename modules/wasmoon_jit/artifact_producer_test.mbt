///|
fn artifact_test_function(name : String) -> @milkir.Function {
  let function = @milkir.Function::with_signature(
    name,
    Signature([Ptr, I64, I64], [I64]),
  )
  let lhs = function.param(1).unwrap()
  let rhs = function.param(2).unwrap()
  let result = function.new_value(I64)
  let entry = function.new_block([])
  entry.append_inst(
    function.new_inst(Scalar(IntBinary(Add)), [lhs, rhs], [result]),
  )
  entry.set_terminator(Return([result]))
  function
}

///|
fn artifact_test_manifest(
  target : @wasmoon_jit.NativeTarget,
) -> @artifact.CompatibilityManifest {
  let policy : @artifact.CompilationPolicy = {
    optimization_level: O2,
    code_model: Small,
    call_binding: DirectBody,
    nan_canonicalization: false,
    cancellation_safepoints: true,
    debug_info: false,
  }
  @wasmoon_jit.build_artifact_manifest(
    target,
    MacOS,
    module_identity=@wasmoon_jit.artifact_module_identity(
      "artifact-producer", b"source-module", b"gc,simd,reference-types",
    ),
    policy~,
  )
}

///|
test "live compiler produces complete x64 and AArch64 artifact functions" {
  let signature = @native.Signature::new([I64, I64], [I64])
  let function = artifact_test_function("artifact_add")
  let validation_context = @wasm_milkir.WasmValidationContext::empty()
  let x64 = @wasmoon_jit.compile_wasm_body_artifact_function(
    function,
    validation_context,
    X64,
    function_index=3,
    signature~,
  )
  let aarch64 = @wasmoon_jit.compile_wasm_body_artifact_function(
    function,
    validation_context,
    AArch64,
    function_index=3,
    signature~,
  )
  debug_inspect(
    (x64, aarch64),
    content=(
      #|(
      #|  {
      #|    identity: {
      #|      function_index: 3,
      #|      symbol: { name: "wasm.func.3" },
      #|      signature: { params: [I64, I64], results: [I64] },
      #|    },
      #|    entry_offset: 0,
      #|    frame_size: 8,
      #|    code: [
      #|      0x55,
      #|      0x48,
      #|      0x89,
      #|      0xe5,
      #|      0x48,
      #|      0x89,
      #|      0xf0,
      #|      0x48,
      #|      0x01,
      #|      0xd0,
      #|      0x5d,
      #|      0xc3,
      #|    ],
      #|    relocations: [],
      #|    sources: [],
      #|    traps: [],
      #|    safepoints: [],
      #|    unwind: [
      #|      { offset: 1, operation: StackAlloc(size=8) },
      #|      { offset: 1, operation: SaveRegister(Int, 5, cfa_offset=-16) },
      #|      { offset: 4, operation: SetFramePointer(Int, 5, cfa_offset=16) },
      #|    ],
      #|  },
      #|  {
      #|    identity: {
      #|      function_index: 3,
      #|      symbol: { name: "wasm.func.3" },
      #|      signature: { params: [I64, I64], results: [I64] },
      #|    },
      #|    entry_offset: 0,
      #|    frame_size: 16,
      #|    code: [
      #|      0xff,
      #|      0x43,
      #|      0x00,
      #|      0xd1,
      #|      0xfd,
      #|      0x7b,
      #|      0x00,
      #|      0xa9,
      #|      0xfd,
      #|      0x03,
      #|      0x00,
      #|      0x91,
      #|      0x20,
      #|      0x00,
      #|      0x02,
      #|      0x8b,
      #|      0xfd,
      #|      0x7b,
      #|      0x40,
      #|      0xa9,
      #|      0xff,
      #|      0x43,
      #|      0x00,
      #|      0x91,
      #|      0xc0,
      #|      0x03,
      #|      0x5f,
      #|      0xd6,
      #|    ],
      #|    relocations: [],
      #|    sources: [],
      #|    traps: [],
      #|    safepoints: [],
      #|    unwind: [
      #|      { offset: 4, operation: StackAlloc(size=16) },
      #|      { offset: 8, operation: SaveRegister(Int, 29, cfa_offset=-16) },
      #|      { offset: 8, operation: SaveRegister(Int, 30, cfa_offset=-8) },
      #|      { offset: 12, operation: SetFramePointer(Int, 29, cfa_offset=16) },
      #|    ],
      #|  },
      #|)
    ),
  )
}

///|
test "live artifact and encoded artifact share verification" {
  let manifest = artifact_test_manifest(X64)
  let function = @wasmoon_jit.compile_wasm_body_artifact_function(
    artifact_test_function("artifact_roundtrip"),
    @wasm_milkir.WasmValidationContext::empty(),
    X64,
    function_index=1,
    signature=@native.Signature::new([I64, I64], [I64]),
  )
  let artifact : @artifact.Artifact = {
    manifest,
    imports: [],
    functions: [function],
  }
  let compatibility = @wasmoon_jit.artifact_compatibility(
    manifest,
    available_cpu_features=[],
    runtime_symbols=[],
    data_symbols=[],
  )
  let live = @wasmoon_jit.verify_artifact(artifact, compatibility).artifact()
  let encoded = @artifact.encode(artifact)
  let decoded = @wasmoon_jit.load_artifact(encoded, compatibility).artifact()
  debug_inspect(
    artifact,
    content=(
      #|{
      #|  manifest: {
      #|    format_version: 11,
      #|    target: {
      #|      architecture: X64,
      #|      operating_system_abi: MacOS,
      #|      endianness: Little,
      #|      pointer_width: Bits64,
      #|    },
      #|    required_cpu_features: [],
      #|    jit_abi_version: 8,
      #|    codegen_revision: "direct-vcode-18",
      #|    module_identity: {
      #|      name: "artifact-producer",
      #|      source_digest: sha256:211dcf04280f2ac1d686baab63a361ea45dd13543dac493b14e3af963860a86c,
      #|      semantic_features_digest: sha256:db16a81b3b565b635f74daa02c4509ba368390794c615783c40d28ccd8db40c1,
      #|    },
      #|    policy: {
      #|      optimization_level: O2,
      #|      code_model: Small,
      #|      call_binding: DirectBody,
      #|      nan_canonicalization: false,
      #|      cancellation_safepoints: true,
      #|      debug_info: false,
      #|    },
      #|    context_shape: Legacy,
      #|  },
      #|  imports: [],
      #|  functions: [
      #|    {
      #|      identity: {
      #|        function_index: 1,
      #|        symbol: { name: "wasm.func.1" },
      #|        signature: { params: [I64, I64], results: [I64] },
      #|      },
      #|      entry_offset: 0,
      #|      frame_size: 8,
      #|      code: [
      #|        0x55,
      #|        0x48,
      #|        0x89,
      #|        0xe5,
      #|        0x48,
      #|        0x89,
      #|        0xf0,
      #|        0x48,
      #|        0x01,
      #|        0xd0,
      #|        0x5d,
      #|        0xc3,
      #|      ],
      #|      relocations: [],
      #|      sources: [],
      #|      traps: [],
      #|      safepoints: [],
      #|      unwind: [
      #|        { offset: 1, operation: StackAlloc(size=8) },
      #|        { offset: 1, operation: SaveRegister(Int, 5, cfa_offset=-16) },
      #|        { offset: 4, operation: SetFramePointer(Int, 5, cfa_offset=16) },
      #|      ],
      #|    },
      #|  ],
      #|}
    ),
  )
  assert_eq(live, artifact)
  assert_eq(decoded, artifact)
}

///|
test "current runtime rejects artifacts using the old function reference ABI" {
  let legacy = { ..artifact_test_manifest(X64), jit_abi_version: 7, }
  let artifact : @artifact.Artifact = {
    manifest: legacy,
    imports: [],
    functions: [],
  }
  let compatibility = @wasmoon_jit.artifact_compatibility(
    legacy,
    available_cpu_features=[],
    runtime_symbols=[],
    data_symbols=[],
  )
  try @wasmoon_jit.verify_artifact(artifact, compatibility) catch {
    Incompatible(cause=JitAbiVersionMismatch(expected~, actual~)) => {
      assert_eq(expected, @wasmoon_jit.WASMOON_JIT_ABI_VERSION)
      assert_eq(actual, 7)
    }
    error => raise error
  } noraise {
    _ =>
      fail("old reference representations must not enter the current runtime")
  }
}
