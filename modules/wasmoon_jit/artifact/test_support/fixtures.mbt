///|
pub fn loader_artifact() -> @artifact.Artifact {
  let source = @native.SourceLocation::new("answer.wasm", 12, 4)
  {
    manifest: {
      format_version: @artifact.FORMAT_VERSION,
      target: {
        architecture: AArch64,
        operating_system_abi: MacOS,
        endianness: Little,
        pointer_width: Bits64,
      },
      required_cpu_features: [{ name: "neon", }],
      jit_abi_version: 3,
      codegen_revision: "legacy-codegen-1",
      module_identity: {
        name: "answer",
        source_digest: { bytes: Bytes::make(32, b'\x11'), },
        semantic_features_digest: { bytes: Bytes::make(32, b'\x22'), },
      },
      policy: {
        optimization_level: O2,
        code_model: Small,
        call_binding: DirectBody,
        nan_canonicalization: false,
        cancellation_safepoints: true,
        debug_info: true,
      },
    },
    imports: [
      {
        function_index: 0,
        module_name: "env",
        function_name: "host_log",
        symbol: @native.ExternalSymbol::new("wasm.runtime.host_log"),
        signature: @native.Signature::new([I64], []),
      },
    ],
    functions: [
      {
        identity: {
          function_index: 1,
          symbol: @native.CodeSymbol::new("wasm.function.1"),
          signature: @native.Signature::new([I64], [I64]),
        },
        entry_offset: 0,
        frame_size: 16,
        code: [b'\x00', b'\x00', b'\x00', b'\x94'],
        relocations: [
          @code_object.Relocation::new(
            0,
            AArch64Call26,
            External(@native.ExternalSymbol::new("wasm.runtime.host_log")),
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
            stack_map=@native.StackMapMetadata::new(0, argument_root_count=1),
          ),
        ],
        unwind: [@code_object.UnwindDirective::new(4, StackAlloc(size=16))],
      },
    ],
  }
}

///|
pub fn loader_compatibility(
  artifact : @artifact.Artifact,
) -> @loader.ArtifactCompatibility {
  {
    target: artifact.manifest.target,
    available_cpu_features: [{ name: "neon", }, { name: "crc", }],
    jit_abi_version: artifact.manifest.jit_abi_version,
    codegen_revision: artifact.manifest.codegen_revision,
    module_identity: artifact.manifest.module_identity,
    policy: artifact.manifest.policy,
    runtime_symbols: [],
    data_symbols: [],
  }
}
