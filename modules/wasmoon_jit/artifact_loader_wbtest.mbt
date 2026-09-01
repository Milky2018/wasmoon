///|
fn loader_artifact() -> @artifact.Artifact {
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
fn loader_compatibility(artifact : @artifact.Artifact) -> ArtifactCompatibility {
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

///|
fn compatibility_error(
  artifact : @artifact.Artifact,
  compatibility : ArtifactCompatibility,
) -> ArtifactIncompatible {
  try verify_artifact_compatibility(artifact, compatibility) catch {
    error => error
  } noraise {
    _ => abort("expected artifact incompatibility")
  }
}

///|
fn load_error(
  bytes : Bytes,
  compatibility : ArtifactCompatibility,
) -> ArtifactLoadError {
  try load_artifact(bytes, compatibility) catch {
    error => error
  } noraise {
    _ => abort("expected artifact loading to fail")
  }
}

///|
test "artifact loader returns verified code objects without linking" {
  let artifact = loader_artifact()
  let loaded = load_artifact(
    @artifact.encode(artifact),
    loader_compatibility(artifact),
  )
  debug_inspect(
    loaded.code_objects()[0],
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [0x00, 0x00, 0x00, 0x94],
      #|  relocations: [
      #|    {
      #|      offset: 0,
      #|      kind: AArch64Call26,
      #|      target: External({ name: "wasm.runtime.host_log" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [{ offset: 0, source: { file: "answer.wasm", line: 12, column: 4 } }],
      #|  traps: [
      #|    {
      #|      offset: 0,
      #|      reason: User(7),
      #|      source: Some({ file: "answer.wasm", line: 12, column: 4 }),
      #|    },
      #|  ],
      #|  safepoints: [
      #|    {
      #|      offset: 0,
      #|      kind: GcAndCancellation,
      #|      roots: [Stack(offset=8, ty=GcRef64)],
      #|      source: Some({ file: "answer.wasm", line: 12, column: 4 }),
      #|      stack_map: Some({ id: 0, argument_root_count: 1 }),
      #|    },
      #|  ],
      #|  unwind: [{ offset: 4, operation: StackAlloc(size=16) }],
      #|}
    ),
  )
}

///|
test "artifact compatibility reports exact mismatch causes" {
  let artifact = loader_artifact()
  let expected = loader_compatibility(artifact)
  debug_inspect(
    [
      compatibility_error(artifact, { ..expected, available_cpu_features: [], }),
      compatibility_error(artifact, {
        ..expected,
        target: { ..expected.target, operating_system_abi: LinuxGnu, },
      }),
      compatibility_error(artifact, { ..expected, jit_abi_version: 4, }),
      compatibility_error(artifact, {
        ..expected,
        codegen_revision: "different",
      }),
      compatibility_error(artifact, {
        ..expected,
        module_identity: { ..expected.module_identity, name: "other", },
      }),
      compatibility_error(artifact, {
        ..expected,
        policy: { ..expected.policy, optimization_level: O3, },
      }),
    ],
    content=(
      #|[
      #|  MissingCpuFeature(name="neon"),
      #|  TargetMismatch(
      #|    expected={
      #|      architecture: AArch64,
      #|      operating_system_abi: LinuxGnu,
      #|      endianness: Little,
      #|      pointer_width: Bits64,
      #|    },
      #|    actual={
      #|      architecture: AArch64,
      #|      operating_system_abi: MacOS,
      #|      endianness: Little,
      #|      pointer_width: Bits64,
      #|    },
      #|  ),
      #|  JitAbiVersionMismatch(expected=4, actual=3),
      #|  CodegenRevisionMismatch(
      #|    expected="different",
      #|    actual="machv-2026-07-22",
      #|  ),
      #|  ModuleIdentityMismatch(
      #|    expected={
      #|      name: "other",
      #|      source_digest: sha256:1111111111111111111111111111111111111111111111111111111111111111,
      #|      semantic_features_digest: sha256:2222222222222222222222222222222222222222222222222222222222222222,
      #|    },
      #|    actual={
      #|      name: "answer",
      #|      source_digest: sha256:1111111111111111111111111111111111111111111111111111111111111111,
      #|      semantic_features_digest: sha256:2222222222222222222222222222222222222222222222222222222222222222,
      #|    },
      #|  ),
      #|  CompilationPolicyMismatch(
      #|    expected={
      #|      optimization_level: O3,
      #|      code_model: Small,
      #|      call_binding: DirectBody,
      #|      cancellation_safepoints: true,
      #|      debug_info: true,
      #|    },
      #|    actual={
      #|      optimization_level: O2,
      #|      code_model: Small,
      #|      call_binding: DirectBody,
      #|      cancellation_safepoints: true,
      #|      debug_info: true,
      #|    },
      #|  ),
      #|]
    ),
  )
}

///|
test "artifact identity verification rejects unknown symbols" {
  let artifact = loader_artifact()
  let unknown_target = @native.ExternalSymbol::new("unknown.runtime")
  let function = artifact.functions[0]
  let malformed : @artifact.Artifact = {
    ..artifact,
    functions: [
      {
        ..function,
        relocations: [
          @code_object.Relocation::new(
            0,
            AArch64Call26,
            External(unknown_target),
          ),
        ],
      },
    ],
  }
  let error = try
    verify_artifact_identities(malformed, loader_compatibility(malformed))
  catch {
    error => error
  } noraise {
    _ => abort("expected unknown symbol rejection")
  }
  debug_inspect(
    error,
    content="UnknownSymbol(kind=\"external\", name=\"unknown.runtime\")",
  )
}

///|
test "artifact loader propagates code object verification" {
  let artifact = loader_artifact()
  let function = artifact.functions[0]
  let malformed : @artifact.Artifact = {
    ..artifact,
    functions: [{ ..function, code: [b'\x00', b'\x00', b'\x00', b'\x00'], }],
  }
  let decoded = @artifact.decode(@artifact.encode(malformed))
  let error = try build_verified_code_objects(decoded) catch {
    error => error
  } noraise {
    _ => abort("expected code object verification failure")
  }
  debug_inspect(
    error,
    content=(
      #|InvalidRelocation(
      #|  index=0,
      #|  message="kind, alignment, or range does not match the code object",
      #|)
    ),
  )
}

///|
test "artifact loader preserves structured failure classes" {
  let artifact = loader_artifact()
  let compatibility = loader_compatibility(artifact)
  let bad_magic_bytes : Array[Byte] = []
  for byte in @artifact.encode(artifact) {
    bad_magic_bytes.push(byte)
  }
  bad_magic_bytes[0] = b'x'
  let bad_magic = Bytes::from_array(bad_magic_bytes)
  let function = artifact.functions[0]
  let malformed_code : @artifact.Artifact = {
    ..artifact,
    functions: [{ ..function, code: [b'\x00', b'\x00', b'\x00', b'\x00'], }],
  }
  debug_inspect(
    [
      load_error(bad_magic, compatibility),
      load_error(@artifact.encode(artifact), {
        ..compatibility,
        available_cpu_features: [],
      }),
      load_error(@artifact.encode(malformed_code), compatibility),
    ],
    content=(
      #|[
      #|  DecodeFailed(cause=BadMagic),
      #|  Incompatible(cause=MissingCpuFeature(name="neon")),
      #|  CodeObjectInvalid(
      #|    cause=InvalidRelocation(
      #|      index=0,
      #|      message="kind, alignment, or range does not match the code object",
      #|    ),
      #|  ),
      #|]
    ),
  )
}
