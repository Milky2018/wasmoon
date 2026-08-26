///|
fn sample_artifact() -> Artifact {
  let source = @machv.SourceLocation::new("answer.wasm", 12, 4)
  let function_signature = @machv.Signature::new([I64], [I64])
  {
    manifest: {
      format_version: FORMAT_VERSION,
      target: {
        architecture: AArch64,
        operating_system_abi: MacOS,
        endianness: Little,
        pointer_width: Bits64,
      },
      required_cpu_features: [{ name: "neon", }],
      jit_abi_version: 3,
      codegen_revision: "machv-2026-07-22",
      module_identity: {
        name: "answer",
        source_digest: { bytes: Bytes::make(32, b'\x11'), },
        semantic_features_digest: { bytes: Bytes::make(32, b'\x22'), },
      },
      policy: {
        optimization_level: O2,
        code_model: Small,
        call_binding: DirectBody,
        cancellation_safepoints: true,
        debug_info: true,
      },
    },
    imports: [
      {
        function_index: 0,
        module_name: "env",
        function_name: "host_log",
        symbol: @machv.ExternalSymbol::new("wasm.runtime.host_log"),
        signature: @machv.Signature::new([I64], []),
      },
    ],
    functions: [
      {
        identity: {
          function_index: 1,
          symbol: @machv.CodeSymbol::new("wasm.function.1"),
          signature: function_signature,
        },
        entry_offset: 0,
        frame_size: 16,
        code: [b'\x00', b'\x00', b'\x00', b'\x94'],
        relocations: [
          @code_object.Relocation::new(
            0,
            AArch64Call26,
            External(@machv.ExternalSymbol::new("wasm.runtime.host_log")),
          ),
        ],
        sources: [@code_object.SourceSite::new(0, source)],
        traps: [@code_object.TrapSite::new(0, User(7), source~)],
        safepoints: [
          @code_object.SafepointSite::new(
            0,
            GcAndCancellation,
            [Stack(offset=8, ty=GcRef64)],
            source~,
            stack_map=@machv.StackMapMetadata::new(0, argument_root_count=1),
          ),
        ],
        unwind: [@code_object.UnwindDirective::new(4, StackAlloc(size=16))],
      },
    ],
  }
}

///|
test "artifact preserves the complete unlinked function contract" {
  let artifact = sample_artifact()
  debug_inspect(
    artifact,
    content=(
      #|{
      #|  manifest: {
      #|    format_version: 9,
      #|    target: {
      #|      architecture: AArch64,
      #|      operating_system_abi: MacOS,
      #|      endianness: Little,
      #|      pointer_width: Bits64,
      #|    },
      #|    required_cpu_features: [{ name: "neon" }],
      #|    jit_abi_version: 3,
      #|    codegen_revision: "machv-2026-07-22",
      #|    module_identity: {
      #|      name: "answer",
      #|      source_digest: sha256:1111111111111111111111111111111111111111111111111111111111111111,
      #|      semantic_features_digest: sha256:2222222222222222222222222222222222222222222222222222222222222222,
      #|    },
      #|    policy: {
      #|      optimization_level: O2,
      #|      code_model: Small,
      #|      call_binding: DirectBody,
      #|      cancellation_safepoints: true,
      #|      debug_info: true,
      #|    },
      #|  },
      #|  imports: [
      #|    {
      #|      function_index: 0,
      #|      module_name: "env",
      #|      function_name: "host_log",
      #|      symbol: { name: "wasm.runtime.host_log" },
      #|      signature: { params: [I64], results: [] },
      #|    },
      #|  ],
      #|  functions: [
      #|    {
      #|      identity: {
      #|        function_index: 1,
      #|        symbol: { name: "wasm.function.1" },
      #|        signature: { params: [I64], results: [I64] },
      #|      },
      #|      entry_offset: 0,
      #|      frame_size: 16,
      #|      code: [0x00, 0x00, 0x00, 0x94],
      #|      relocations: [
      #|        {
      #|          offset: 0,
      #|          kind: AArch64Call26,
      #|          target: External({ name: "wasm.runtime.host_log" }),
      #|          addend: 0,
      #|        },
      #|      ],
      #|      sources: [{ offset: 0, source: { file: "answer.wasm", line: 12, column: 4 } }],
      #|      traps: [
      #|        {
      #|          offset: 0,
      #|          reason: User(7),
      #|          source: Some({ file: "answer.wasm", line: 12, column: 4 }),
      #|        },
      #|      ],
      #|      safepoints: [
      #|        {
      #|          offset: 0,
      #|          kind: GcAndCancellation,
      #|          roots: [Stack(offset=8, ty=GcRef64)],
      #|          source: Some({ file: "answer.wasm", line: 12, column: 4 }),
      #|          stack_map: Some({ id: 0, argument_root_count: 1 }),
      #|        },
      #|      ],
      #|      unwind: [{ offset: 4, operation: StackAlloc(size=16) }],
      #|    },
      #|  ],
      #|}
    ),
  )
}
