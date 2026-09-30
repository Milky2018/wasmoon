///|
pub using @artifact_loader {
  type ArtifactCompatibility,
  type ArtifactIncompatible,
  type ArtifactLoadError,
}

///|
/// Native preparation of a verified portable artifact. Instances retain the
/// immutable safepoint owner independently of this wrapper.
pub struct LoadedArtifact {
  priv verified : @artifact_loader.LoadedArtifact
  priv safepoints : @jit_ffi.PreparedSafepoints?
}

///|
fn prepare_loaded_artifact(
  verified : @artifact_loader.LoadedArtifact,
) -> LoadedArtifact {
  let functions = verified.artifact().functions
  let safepoints = if functions.any(f => !f.safepoints.is_empty()) {
    let mut count = 0
    for function in functions {
      if !function.safepoints.is_empty() {
        count = Int::max(count, function.identity.function_index + 1)
      }
    }
    let blobs = FixedArray::make(count, b"")
    let offsets : FixedArray[FixedArray[Int]] = FixedArray::make(count, [])
    for function in functions {
      if !function.safepoints.is_empty() {
        let (blob, sites) = prepare_code_object_safepoints(function.safepoints)
        blobs[function.identity.function_index] = blob
        offsets[function.identity.function_index] = sites
      }
    }
    Some(@jit_ffi.PreparedSafepoints::new(blobs, offsets))
  } else {
    None
  }
  { verified, safepoints, }
}

///|
pub fn verify_artifact(
  artifact : @artifact.Artifact,
  compatibility : ArtifactCompatibility,
) -> LoadedArtifact raise ArtifactLoadError {
  prepare_loaded_artifact(
    @artifact_loader.verify_artifact(artifact, compatibility),
  )
}

///|
pub fn load_artifact(
  bytes : Bytes,
  compatibility : ArtifactCompatibility,
  limits? : @artifact.DecodeLimits = @artifact.DecodeLimits::default(),
) -> LoadedArtifact raise ArtifactLoadError {
  prepare_loaded_artifact(
    @artifact_loader.load_artifact(bytes, compatibility, limits~),
  )
}

///|
/// Portable verified input for code installation and inspection.
pub fn LoadedArtifact::verified(
  self : LoadedArtifact,
) -> @artifact_loader.LoadedArtifact {
  self.verified
}

///|
pub fn LoadedArtifact::artifact(self : LoadedArtifact) -> @artifact.Artifact {
  self.verified.artifact()
}

///|
pub fn LoadedArtifact::code_objects(
  self : LoadedArtifact,
) -> Array[@code_object.UnlinkedCodeObject] {
  self.verified.code_objects()
}

///|
pub fn LoadedArtifact::context_layout(self : LoadedArtifact) -> ContextLayout? {
  self.verified.context_layout()
}

///|
/// Bind only to a fresh context, before any invocation can reference its metadata.
pub fn LoadedArtifact::bind_safepoints(
  self : LoadedArtifact,
  context : NativeJITContext,
) -> Bool {
  match self.safepoints {
    Some(prepared) => context.handle.bind_prepared_safepoints(prepared)
    None => true
  }
}
