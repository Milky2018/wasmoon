///|
fn artifact_wbtest_manifest(
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
test "artifact producer preserves symbolic imported and internal code targets" {
  let source = @semantic_machv.SourceLocation::new("calls.wat", 9, 4)
  let object = @code_object.build(
    X64,
    [
      b'\xe8', b'\x00', b'\x00', b'\x00', b'\x00', b'\xe8', b'\x00', b'\x00', b'\x00',
      b'\x00', b'\xc3',
    ],
    relocations=[
      @code_object.Relocation::new(
        1,
        X64PcRelative32,
        Code(@semantic_machv.CodeSymbol::new("wasm.func.0")),
      ),
      @code_object.Relocation::new(
        6,
        X64PcRelative32,
        Code(@semantic_machv.CodeSymbol::new("wasm.func.2")),
      ),
    ],
    sources=[@code_object.SourceSite::new(0, source)],
    traps=[@code_object.TrapSite::new(5, User(7), source~)],
    safepoints=[
      @code_object.SafepointSite::new(
        5,
        GcAndCancellation,
        [Stack(offset=8, ty=GcRef64)],
        source~,
        stack_map=@semantic_machv.StackMapMetadata::new(
          0,
          argument_root_count=1,
        ),
      ),
    ],
    unwind=[@code_object.UnwindDirective::new(1, StackAlloc(size=16))],
  )
  let function = artifact_function_from_code_object(
    object,
    frame_size=16,
    function_index=2,
    signature=@semantic_machv.Signature::new([], []),
  )
  debug_inspect(
    function,
    content=(
      #|{
      #|  identity: {
      #|    function_index: 2,
      #|    symbol: { name: "wasm.func.2" },
      #|    signature: { params: [], results: [] },
      #|  },
      #|  entry_offset: 0,
      #|  frame_size: 16,
      #|  code: [0xe8, 0x00, 0x00, 0x00, 0x00, 0xe8, 0x00, 0x00, 0x00, 0x00, 0xc3],
      #|  relocations: [
      #|    {
      #|      offset: 1,
      #|      kind: X64PcRelative32,
      #|      target: Code({ name: "wasm.func.0" }),
      #|      addend: 0,
      #|    },
      #|    {
      #|      offset: 6,
      #|      kind: X64PcRelative32,
      #|      target: Code({ name: "wasm.func.2" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [{ offset: 0, source: { file: "calls.wat", line: 9, column: 4 } }],
      #|  traps: [
      #|    {
      #|      offset: 5,
      #|      reason: User(7),
      #|      source: Some({ file: "calls.wat", line: 9, column: 4 }),
      #|    },
      #|  ],
      #|  safepoints: [
      #|    {
      #|      offset: 5,
      #|      kind: GcAndCancellation,
      #|      roots: [Stack(offset=8, ty=GcRef64)],
      #|      source: Some({ file: "calls.wat", line: 9, column: 4 }),
      #|      stack_map: Some({ id: 0, argument_root_count: 1 }),
      #|    },
      #|  ],
      #|  unwind: [{ offset: 1, operation: StackAlloc(size=16) }],
      #|}
    ),
  )
  let artifact : @artifact.Artifact = {
    manifest: artifact_wbtest_manifest(X64),
    imports: [
      wasm_import_identity(0, "env", "host", { params: [], results: [], }),
    ],
    functions: [function],
  }
  let compatibility = artifact_compatibility(
    artifact.manifest,
    available_cpu_features=[],
    runtime_symbols=[],
    data_symbols=[],
  )
  let loaded = verify_artifact(artifact, compatibility)
  debug_inspect(
    loaded.artifact(),
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
      #|  imports: [
      #|    {
      #|      function_index: 0,
      #|      module_name: "env",
      #|      function_name: "host",
      #|      symbol: { name: "wasm.func.0" },
      #|      signature: { params: [], results: [] },
      #|    },
      #|  ],
      #|  functions: [
      #|    {
      #|      identity: {
      #|        function_index: 2,
      #|        symbol: { name: "wasm.func.2" },
      #|        signature: { params: [], results: [] },
      #|      },
      #|      entry_offset: 0,
      #|      frame_size: 16,
      #|      code: [0xe8, 0x00, 0x00, 0x00, 0x00, 0xe8, 0x00, 0x00, 0x00, 0x00, 0xc3],
      #|      relocations: [
      #|        {
      #|          offset: 1,
      #|          kind: X64PcRelative32,
      #|          target: Code({ name: "wasm.func.0" }),
      #|          addend: 0,
      #|        },
      #|        {
      #|          offset: 6,
      #|          kind: X64PcRelative32,
      #|          target: Code({ name: "wasm.func.2" }),
      #|          addend: 0,
      #|        },
      #|      ],
      #|      sources: [{ offset: 0, source: { file: "calls.wat", line: 9, column: 4 } }],
      #|      traps: [
      #|        {
      #|          offset: 5,
      #|          reason: User(7),
      #|          source: Some({ file: "calls.wat", line: 9, column: 4 }),
      #|        },
      #|      ],
      #|      safepoints: [
      #|        {
      #|          offset: 5,
      #|          kind: GcAndCancellation,
      #|          roots: [Stack(offset=8, ty=GcRef64)],
      #|          source: Some({ file: "calls.wat", line: 9, column: 4 }),
      #|          stack_map: Some({ id: 0, argument_root_count: 1 }),
      #|        },
      #|      ],
      #|      unwind: [{ offset: 1, operation: StackAlloc(size=16) }],
      #|    },
      #|  ],
      #|}
    ),
  )
  let resolved = resolve_static_targets(
    JitCodeInstaller::new(fn(target) {
      match target {
        External(symbol) if symbol.name == "wasm.func.0" => Some(42L)
        _ => None
      }
    }),
    loaded,
  )
  debug_inspect(
    resolved,
    content=(
      #|[
      #|  (External({ name: "wasm.func.0" }), 42),
      #|  (Code({ name: "wasm.func.0" }), 42),
      #|]
    ),
  )
}

///|
test "artifact Wasm signatures preserve scalar vector and reference carriers" {
  debug_inspect(
    wasm_function_signature({
      params: [I32, I64, F32, F64, V128, FuncRef, ExternRef, AnyRef],
      results: [RefFuncTyped(7), RefNullArray(3)],
    }),
    content=(
      #|{
      #|  params: [I32, I64, F32, F64, V128, GcRef64, GcRef64, GcRef64],
      #|  results: [GcRef64, GcRef64],
      #|}
    ),
  )
}
