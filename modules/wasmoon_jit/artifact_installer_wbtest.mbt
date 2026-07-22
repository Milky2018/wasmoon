///|
struct InstalledImportSnapshot {
  function_index : Int
  symbol : String
} derive(Eq, Debug)

///|
struct InstalledFunctionSnapshot {
  function_index : Int
  symbol : String
  code_size : Int
  entry_offset : Int
  source_count : Int
  trap_count : Int
  safepoint_count : Int
  unwind_count : Int
} derive(Eq, Debug)

///|
struct InstallationSnapshot {
  imports : Array[InstalledImportSnapshot]
  functions : Array[InstalledFunctionSnapshot]
} derive(Eq, Debug)

///|
fn installation_snapshot(installed : InstalledCode) -> InstallationSnapshot {
  {
    imports: installed.imports.map(import_ => {
      function_index: import_.identity.function_index,
      symbol: import_.identity.symbol.name,
    }),
    functions: installed.functions.map(function => {
      function_index: function.identity.function_index,
      symbol: function.identity.symbol.name,
      code_size: function.code_size,
      entry_offset: function.entry_offset,
      source_count: function.sources.length(),
      trap_count: function.traps.length(),
      safepoint_count: function.safepoints.length(),
      unwind_count: function.unwind.length(),
    }),
  }
}

///|
fn executable_mapping_count() -> Int {
  @jit_ffi.c_jit_exec_mapping_count()
}

///|
fn installer_for_tests() -> JitCodeInstaller {
  JitCodeInstaller::new(fn(target) {
    match target {
      External(symbol) if symbol.name == "wasm.runtime.host_log" =>
        Some(0x0000000100000000L)
      _ => None
    }
  })
}

///|
fn install_error_for_tests(
  installer : JitCodeInstaller,
  loaded : LoadedArtifact,
  failure : InstallFailurePoint,
) -> JitInstallError {
  try install_artifact_with_failure(installer, loaded, failure~) catch {
    error => error
  } noraise {
    _ => abort("expected installation to fail")
  }
}

///|
test "artifact installer rolls every failed phase back before publication" {
  let artifact = loader_artifact()
  let loaded = verify_artifact(artifact, loader_compatibility(artifact))
  let installer = installer_for_tests()
  let baseline = executable_mapping_count()
  let errors = [
    install_error_for_tests(installer, loaded, Resolution),
    install_error_for_tests(installer, loaded, Allocation),
    install_error_for_tests(installer, loaded, Relocation),
    install_error_for_tests(installer, loaded, Registration),
    install_error_for_tests(installer, loaded, Protection),
    install_error_for_tests(installer, loaded, Publication),
  ]
  debug_inspect(
    (errors, baseline, executable_mapping_count()),
    content=(
      #|(
      #|  [
      #|    ResolutionFailed(kind="injected", name="resolution"),
      #|    AllocationFailed(function_index=1),
      #|    RelocationFailed(function_index=1, message="injected failure"),
      #|    RegistrationFailed(function_index=1, message="injected failure"),
      #|    ProtectionFailed(function_index=1),
      #|    PublicationFailed(message="injected failure"),
      #|  ],
      #|  0,
      #|  0,
      #|)
    ),
  )
}

///|
test "artifact installer reports real resolution and registration failures" {
  let artifact = loader_artifact()
  let compatibility = loader_compatibility(artifact)
  let unresolved = JitCodeInstaller::new(fn(_) { None })
  let resolution_error = try
    unresolved.install(verify_artifact(artifact, compatibility))
  catch {
    error => error
  } noraise {
    _ => abort("expected unresolved import to fail")
  }
  let invalid_entry = {
    ..artifact,
    functions: artifact.functions.map(function => {
      ..function,
      entry_offset: 4096,
    }),
  }
  let registration_error = try
    installer_for_tests().install(verify_artifact(invalid_entry, compatibility))
  catch {
    error => error
  } noraise {
    _ => abort("expected invalid entry metadata to fail")
  }
  debug_inspect(
    (resolution_error, registration_error, executable_mapping_count()),
    content=(
      #|(
      #|  ResolutionFailed(kind="external", name="wasm.runtime.host_log"),
      #|  RegistrationFailed(
      #|    function_index=1,
      #|    message="entry offset is outside linked code",
      #|  ),
      #|  0,
      #|)
    ),
  )
}

///|
test "artifact installer preserves a committed installation after later failure" {
  let artifact = loader_artifact()
  let loaded = verify_artifact(artifact, loader_compatibility(artifact))
  let installer = installer_for_tests()
  let installed = installer.install(loaded)
  let before = executable_mapping_count()
  let error = install_error_for_tests(installer, loaded, Publication)
  guard installer.current() is Some(current) else {
    fail("expected committed installation to remain published")
  }
  debug_inspect(
    (
      error,
      before,
      executable_mapping_count(),
      installation_snapshot(installed),
      installation_snapshot(current),
    ),
    content=(
      #|(
      #|  PublicationFailed(message="injected failure"),
      #|  1,
      #|  1,
      #|  {
      #|    imports: [{ function_index: 0, symbol: "wasm.runtime.host_log" }],
      #|    functions: [
      #|      {
      #|        function_index: 1,
      #|        symbol: "wasm.function.1",
      #|        code_size: 20,
      #|        entry_offset: 0,
      #|        source_count: 1,
      #|        trap_count: 1,
      #|        safepoint_count: 1,
      #|        unwind_count: 1,
      #|      },
      #|    ],
      #|  },
      #|  {
      #|    imports: [{ function_index: 0, symbol: "wasm.runtime.host_log" }],
      #|    functions: [
      #|      {
      #|        function_index: 1,
      #|        symbol: "wasm.function.1",
      #|        code_size: 20,
      #|        entry_offset: 0,
      #|        source_count: 1,
      #|        trap_count: 1,
      #|        safepoint_count: 1,
      #|        unwind_count: 1,
      #|      },
      #|    ],
      #|  },
      #|)
    ),
  )
}

///|
test "live and decoded artifacts use the same installer transaction" {
  let artifact = loader_artifact()
  let compatibility = loader_compatibility(artifact)
  let live = verify_artifact(artifact, compatibility)
  let decoded = load_artifact(@artifact.encode(artifact), compatibility)
  let installer = installer_for_tests()
  debug_inspect(
    (
      installation_snapshot(installer.install(live)),
      installation_snapshot(installer.install(decoded)),
    ),
    content=(
      #|(
      #|  {
      #|    imports: [{ function_index: 0, symbol: "wasm.runtime.host_log" }],
      #|    functions: [
      #|      {
      #|        function_index: 1,
      #|        symbol: "wasm.function.1",
      #|        code_size: 20,
      #|        entry_offset: 0,
      #|        source_count: 1,
      #|        trap_count: 1,
      #|        safepoint_count: 1,
      #|        unwind_count: 1,
      #|      },
      #|    ],
      #|  },
      #|  {
      #|    imports: [{ function_index: 0, symbol: "wasm.runtime.host_log" }],
      #|    functions: [
      #|      {
      #|        function_index: 1,
      #|        symbol: "wasm.function.1",
      #|        code_size: 20,
      #|        entry_offset: 0,
      #|        source_count: 1,
      #|        trap_count: 1,
      #|        safepoint_count: 1,
      #|        unwind_count: 1,
      #|      },
      #|    ],
      #|  },
      #|)
    ),
  )
}
