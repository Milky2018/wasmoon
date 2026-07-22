///|
extern "c" fn executable_mapping_count() -> Int = "wasmoon_jit_exec_mapping_count"

///|
fn transaction_test_artifact() -> @artifact.Artifact raise @wasmoon_jit.JitPipelineError {
  let code = match @wasmoon_jit.host_native_target() {
    X64 => [b'\xc3']
    AArch64 => [b'\xc0', b'\x03', b'\x5f', b'\xd6']
  }
  {
    manifest: @wasmoon_jit.build_host_artifact_manifest(
      module_identity=@wasmoon_jit.artifact_module_identity(
        "registration-rollback-test", b"registration-rollback-source", b"registration-rollback-features",
      ),
      policy={
        optimization_level: O2,
        code_model: Small,
        call_binding: DirectBody,
        cancellation_safepoints: false,
        debug_info: false,
      },
    ),
    imports: [],
    functions: [
      {
        identity: {
          function_index: 0,
          symbol: @machv.CodeSymbol::new("wasm.func.0"),
          signature: @machv.Signature::new([], []),
        },
        entry_offset: 0,
        frame_size: 0,
        code,
        relocations: [],
        sources: [],
        traps: [],
        safepoints: [],
        unwind: [],
      },
    ],
  }
}

///|
fn transaction_test_loaded_artifact() -> @wasmoon_jit.LoadedArtifact raise {
  let artifact = transaction_test_artifact()
  @wasmoon_jit.verify_artifact(
    artifact,
    @wasmoon_jit.artifact_compatibility(
      artifact.manifest,
      available_cpu_features=[],
      runtime_symbols=[],
      data_symbols=[],
    ),
  )
}

///|
test "safepoint registration failure precedes executable installation" {
  let before = executable_mapping_count()
  let error = try
    load_artifact_with_imports_using_registrar(
      transaction_test_loaded_artifact(),
      [([], [])],
      Map([]),
      [],
      None,
      fn(_, _, _) { false },
    )
  catch {
    error => error
  } noraise {
    _ => abort("expected metadata registration to fail")
  }
  debug_inspect(
    error,
    content=(
      #|FunctionMetadataRegistrationFailed(
      #|  func_idx=0,
      #|  message="failed to register GC safepoints",
      #|)
    ),
  )
  assert_eq(executable_mapping_count(), before)
}
