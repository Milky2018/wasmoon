///|
/// Host and module contract used to accept or reject a decoded artifact.
pub(all) struct ArtifactCompatibility {
  target : @artifact.TargetSpec
  available_cpu_features : Array[@artifact.CpuFeature]
  jit_abi_version : Int
  codegen_revision : String
  module_identity : @artifact.ModuleIdentity
  policy : @artifact.CompilationPolicy
  runtime_symbols : Array[@semantic_machv.ExternalSymbol]
  data_symbols : Array[@semantic_machv.DataSymbol]
} derive(Eq, Debug)

///|
pub suberror ArtifactIncompatible {
  TargetMismatch(
    expected~ : @artifact.TargetSpec,
    actual~ : @artifact.TargetSpec
  )
  MissingCpuFeature(name~ : String)
  DuplicateCpuFeature(name~ : String)
  JitAbiVersionMismatch(expected~ : Int, actual~ : Int)
  CodegenRevisionMismatch(expected~ : String, actual~ : String)
  ModuleIdentityMismatch(
    expected~ : @artifact.ModuleIdentity,
    actual~ : @artifact.ModuleIdentity
  )
  CompilationPolicyMismatch(
    expected~ : @artifact.CompilationPolicy,
    actual~ : @artifact.CompilationPolicy
  )
  DuplicateFunctionIndex(index~ : Int)
  DuplicateSymbol(name~ : String)
  UnknownSymbol(kind~ : String, name~ : String)
} derive(Eq, Debug)

///|
pub suberror ArtifactLoadError {
  DecodeFailed(cause~ : @artifact.ArtifactDecodeError)
  Incompatible(cause~ : ArtifactIncompatible)
  CodeObjectInvalid(cause~ : @code_object.CodeObjectVerifyError)
} derive(Eq, Debug)

///|
/// A decoded artifact whose manifest and every code object have been checked.
pub struct LoadedArtifact {
  artifact : @artifact.Artifact
  code_objects : Array[@code_object.UnlinkedCodeObject]
}

///|
pub fn LoadedArtifact::artifact(self : LoadedArtifact) -> @artifact.Artifact {
  self.artifact
}

///|
pub fn LoadedArtifact::code_objects(
  self : LoadedArtifact,
) -> Array[@code_object.UnlinkedCodeObject] {
  self.code_objects.copy()
}

///|
fn contains_cpu_feature(
  features : Array[@artifact.CpuFeature],
  name : String,
) -> Bool {
  features.any(fn(feature) { feature.name == name })
}

///|
fn contains_external_symbol(
  symbols : Array[@semantic_machv.ExternalSymbol],
  name : String,
) -> Bool {
  symbols.any(fn(symbol) { symbol.name == name })
}

///|
fn contains_data_symbol(
  symbols : Array[@semantic_machv.DataSymbol],
  name : String,
) -> Bool {
  symbols.any(fn(symbol) { symbol.name == name })
}

///|
fn contains_function_symbol(
  functions : Array[@artifact.FunctionCode],
  name : String,
) -> Bool {
  functions.any(fn(function) { function.identity.symbol.name == name })
}

///|
fn contains_import_symbol(
  imports : Array[@artifact.ImportIdentity],
  name : String,
) -> Bool {
  imports.any(fn(import_) { import_.symbol.name == name })
}

///|
fn verify_artifact_compatibility(
  decoded : @artifact.Artifact,
  expected : ArtifactCompatibility,
) -> Unit raise ArtifactIncompatible {
  let manifest = decoded.manifest
  if manifest.target != expected.target {
    raise TargetMismatch(expected=expected.target, actual=manifest.target)
  }
  let required_feature_names : Array[String] = []
  for feature in manifest.required_cpu_features {
    if required_feature_names.contains(feature.name) {
      raise DuplicateCpuFeature(name=feature.name)
    }
    required_feature_names.push(feature.name)
    if !contains_cpu_feature(expected.available_cpu_features, feature.name) {
      raise MissingCpuFeature(name=feature.name)
    }
  }
  if manifest.jit_abi_version != expected.jit_abi_version {
    raise JitAbiVersionMismatch(
      expected=expected.jit_abi_version,
      actual=manifest.jit_abi_version,
    )
  }
  if manifest.codegen_revision != expected.codegen_revision {
    raise CodegenRevisionMismatch(
      expected=expected.codegen_revision,
      actual=manifest.codegen_revision,
    )
  }
  if manifest.module_identity != expected.module_identity {
    raise ModuleIdentityMismatch(
      expected=expected.module_identity,
      actual=manifest.module_identity,
    )
  }
  if manifest.policy != expected.policy {
    raise CompilationPolicyMismatch(
      expected=expected.policy,
      actual=manifest.policy,
    )
  }
}

///|
fn verify_artifact_identities(
  decoded : @artifact.Artifact,
  expected : ArtifactCompatibility,
) -> Unit raise ArtifactIncompatible {
  let function_indices : Array[Int] = []
  let symbols : Array[String] = []
  for import_ in decoded.imports {
    if function_indices.contains(import_.function_index) {
      raise DuplicateFunctionIndex(index=import_.function_index)
    }
    function_indices.push(import_.function_index)
    if import_.symbol.name.is_empty() || symbols.contains(import_.symbol.name) {
      raise DuplicateSymbol(name=import_.symbol.name)
    }
    symbols.push(import_.symbol.name)
  }
  for function in decoded.functions {
    if function_indices.contains(function.identity.function_index) {
      raise DuplicateFunctionIndex(index=function.identity.function_index)
    }
    function_indices.push(function.identity.function_index)
    if function.identity.symbol.name.is_empty() ||
      symbols.contains(function.identity.symbol.name) {
      raise DuplicateSymbol(name=function.identity.symbol.name)
    }
    symbols.push(function.identity.symbol.name)
    for relocation in function.relocations {
      match relocation.target {
        Code(symbol) =>
          if !contains_function_symbol(decoded.functions, symbol.name) &&
            !contains_import_symbol(decoded.imports, symbol.name) {
            raise UnknownSymbol(kind="code", name=symbol.name)
          }
        External(symbol) =>
          if !contains_import_symbol(decoded.imports, symbol.name) &&
            !contains_external_symbol(expected.runtime_symbols, symbol.name) {
            raise UnknownSymbol(kind="external", name=symbol.name)
          }
        Data(symbol) =>
          if !contains_data_symbol(expected.data_symbols, symbol.name) {
            raise UnknownSymbol(kind="data", name=symbol.name)
          }
      }
    }
  }
}

///|
fn build_verified_code_objects(
  decoded : @artifact.Artifact,
) -> Array[@code_object.UnlinkedCodeObject] raise @code_object.CodeObjectVerifyError {
  let code_objects : Array[@code_object.UnlinkedCodeObject] = []
  for function in decoded.functions {
    code_objects.push(
      @code_object.build(
        decoded.manifest.target.architecture,
        function.code,
        relocations=function.relocations,
        sources=function.sources,
        traps=function.traps,
        safepoints=function.safepoints,
        unwind=function.unwind,
      ),
    )
  }
  code_objects
}

///|
/// Check compatibility and reconstruct verified unlinked code objects from an
/// in-memory artifact produced by the live compiler.
///
/// No symbol is resolved and no executable memory is allocated or published.
pub fn verify_artifact(
  decoded : @artifact.Artifact,
  compatibility : ArtifactCompatibility,
) -> LoadedArtifact raise ArtifactLoadError {
  verify_artifact_compatibility(decoded, compatibility) catch {
    error => raise Incompatible(cause=error)
  }
  verify_artifact_identities(decoded, compatibility) catch {
    error => raise Incompatible(cause=error)
  }
  let code_objects = build_verified_code_objects(decoded) catch {
    error => raise CodeObjectInvalid(cause=error)
  }
  { artifact: decoded, code_objects }
}

///|
/// Decode, check compatibility, and reconstruct verified unlinked code objects.
///
/// Decoded and live artifacts converge on `verify_artifact`, before the shared
/// installer resolves any symbol or allocates executable memory.
pub fn load_artifact(
  bytes : Bytes,
  compatibility : ArtifactCompatibility,
  limits? : @artifact.DecodeLimits = @artifact.DecodeLimits::default(),
) -> LoadedArtifact raise ArtifactLoadError {
  let decoded = @artifact.decode(bytes, limits~) catch {
    error => raise DecodeFailed(cause=error)
  }
  verify_artifact(decoded, compatibility)
}
