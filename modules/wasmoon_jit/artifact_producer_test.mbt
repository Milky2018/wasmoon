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
  target : NativeTarget,
) -> @artifact.CompatibilityManifest {
  let policy : @artifact.CompilationPolicy = {
    optimization_level: O2,
    code_model: Small,
    call_binding: DirectBody,
    cancellation_safepoints: true,
    debug_info: false,
  }
  build_artifact_manifest(
    target,
    MacOS,
    module_identity=artifact_module_identity(
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
  let x64 = compile_wasm_body_artifact_function(
    function,
    validation_context,
    X64,
    function_index=3,
    signature~,
  )
  let aarch64 = compile_wasm_body_artifact_function(
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
      #|    frame_size: 0,
      #|    code: [0x48, 0x89, 0xf0, 0x48, 0x01, 0xd0, 0xc3],
      #|    relocations: [],
      #|    sources: [],
      #|    traps: [],
      #|    safepoints: [],
      #|    unwind: [],
      #|  },
      #|  {
      #|    identity: {
      #|      function_index: 3,
      #|      symbol: { name: "wasm.func.3" },
      #|      signature: { params: [I64, I64], results: [I64] },
      #|    },
      #|    entry_offset: 0,
      #|    frame_size: 0,
      #|    code: [0x20, 0x00, 0x02, 0x8b, 0xc0, 0x03, 0x5f, 0xd6],
      #|    relocations: [],
      #|    sources: [],
      #|    traps: [],
      #|    safepoints: [],
      #|    unwind: [],
      #|  },
      #|)
    ),
  )
}

///|
test "live artifact and encoded artifact share verification" {
  let manifest = artifact_test_manifest(X64)
  let function = compile_wasm_body_artifact_function(
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
  let compatibility = artifact_compatibility(
    manifest,
    available_cpu_features=[],
    runtime_symbols=[],
    data_symbols=[],
  )
  let live = verify_artifact(artifact, compatibility).artifact()
  let encoded = @artifact.encode(artifact)
  let decoded = load_artifact(encoded, compatibility).artifact()
  debug_inspect(
    artifact,
    content=(
      #|{
      #|  manifest: {
      #|    format_version: 9,
      #|    target: {
      #|      architecture: X64,
      #|      operating_system_abi: MacOS,
      #|      endianness: Little,
      #|      pointer_width: Bits64,
      #|    },
      #|    required_cpu_features: [],
      #|    jit_abi_version: 3,
      #|    codegen_revision: "machv-vcode-9",
      #|    module_identity: {
      #|      name: "artifact-producer",
      #|      source_digest: sha256:211dcf04280f2ac1d686baab63a361ea45dd13543dac493b14e3af963860a86c,
      #|      semantic_features_digest: sha256:db16a81b3b565b635f74daa02c4509ba368390794c615783c40d28ccd8db40c1,
      #|    },
      #|    policy: {
      #|      optimization_level: O2,
      #|      code_model: Small,
      #|      call_binding: DirectBody,
      #|      cancellation_safepoints: true,
      #|      debug_info: false,
      #|    },
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
      #|      frame_size: 0,
      #|      code: [0x48, 0x89, 0xf0, 0x48, 0x01, 0xd0, 0xc3],
      #|      relocations: [],
      #|      sources: [],
      #|      traps: [],
      #|      safepoints: [],
      #|      unwind: [],
      #|    },
      #|  ],
      #|}
    ),
  )
  assert_eq(live, artifact)
  assert_eq(decoded, artifact)
}
