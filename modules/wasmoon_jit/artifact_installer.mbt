///|
/// Structured failures from the Wasmoon-owned executable-code transaction.
pub suberror JitInstallError {
  ResolutionFailed(kind~ : String, name~ : String)
  AllocationFailed(function_index~ : Int)
  RelocationFailed(function_index~ : Int, message~ : String)
  ProtectionFailed(function_index~ : Int)
  RegistrationFailed(function_index~ : Int, message~ : String)
  PublicationFailed(message~ : String)
} derive(Eq, Debug)

///|
/// A resolved import retained by a committed installation.
pub struct InstalledImport {
  priv identity : @artifact.ImportIdentity
  priv address : Int64
}

///|
pub fn InstalledImport::identity(
  self : InstalledImport,
) -> @artifact.ImportIdentity {
  self.identity
}

///|
pub fn InstalledImport::address(self : InstalledImport) -> Int64 {
  self.address
}

///|
/// Address-dependent metadata and entry identity for one committed function.
///
/// Returned metadata arrays are copies. The addresses remain valid only while
/// the owning `InstalledCode` is retained.
pub struct InstalledFunction {
  priv identity : @artifact.FunctionIdentity
  priv code_address : Int64
  priv entry_address : Int64
  priv code_size : Int
  priv entry_offset : Int
  priv frame_size : Int
  priv sources : Array[@code_object.SourceSite]
  priv traps : Array[@code_object.TrapSite]
  priv safepoints : Array[@code_object.SafepointSite]
  priv unwind : Array[@code_object.UnwindDirective]
}

///|
pub fn InstalledFunction::identity(
  self : InstalledFunction,
) -> @artifact.FunctionIdentity {
  self.identity
}

///|
pub fn InstalledFunction::code_address(self : InstalledFunction) -> Int64 {
  self.code_address
}

///|
pub fn InstalledFunction::entry_address(self : InstalledFunction) -> Int64 {
  self.entry_address
}

///|
pub fn InstalledFunction::code_size(self : InstalledFunction) -> Int {
  self.code_size
}

///|
pub fn InstalledFunction::entry_offset(self : InstalledFunction) -> Int {
  self.entry_offset
}

///|
pub fn InstalledFunction::frame_size(self : InstalledFunction) -> Int {
  self.frame_size
}

///|
pub fn InstalledFunction::sources(
  self : InstalledFunction,
) -> Array[@code_object.SourceSite] {
  self.sources.copy()
}

///|
pub fn InstalledFunction::traps(
  self : InstalledFunction,
) -> Array[@code_object.TrapSite] {
  self.traps.copy()
}

///|
pub fn InstalledFunction::safepoints(
  self : InstalledFunction,
) -> Array[@code_object.SafepointSite] {
  self.safepoints.copy()
}

///|
pub fn InstalledFunction::unwind(
  self : InstalledFunction,
) -> Array[@code_object.UnwindDirective] {
  self.unwind.copy()
}

///|
/// Opaque ownership of a fully linked and executable artifact.
///
/// Construction is the publication boundary: no staged address is returned
/// before every mapping, relocation, metadata record, permission transition,
/// and instruction-cache flush has succeeded.
pub struct InstalledCode {
  priv executable_code : Array[ExecCode]
  priv imports : Array[InstalledImport]
  priv functions : Array[InstalledFunction]
}

///|
pub fn InstalledCode::imports(self : InstalledCode) -> Array[InstalledImport] {
  self.imports.copy()
}

///|
pub fn InstalledCode::functions(
  self : InstalledCode,
) -> Array[InstalledFunction] {
  // Keep executable handles reachable whenever address-bearing metadata escapes.
  self.executable_code.length() |> ignore
  self.functions.copy()
}

///|
pub fn InstalledCode::entry_address(
  self : InstalledCode,
  function_index : Int,
) -> Int64? {
  for import_ in self.imports {
    if import_.identity.function_index == function_index {
      return Some(import_.address)
    }
  }
  for function in self.functions {
    if function.identity.function_index == function_index {
      return Some(function.entry_address)
    }
  }
  None
}

///|
/// Installer policy plus the embedding-provided external/data symbol resolver.
pub struct JitCodeInstaller {
  priv resolver : (@code_object.RelocationTarget) -> Int64?
  priv current : Ref[InstalledCode?]
}

///|
pub fn JitCodeInstaller::new(
  resolver : (@code_object.RelocationTarget) -> Int64?,
) -> JitCodeInstaller {
  { resolver, current: { val: None } }
}

///|
/// Return the last fully committed installation, if any.
pub fn JitCodeInstaller::current(self : JitCodeInstaller) -> InstalledCode? {
  self.current.val
}

///|
priv enum InstallFailurePoint {
  Resolution
  Allocation
  Relocation
  Registration
  Protection
  Publication
} derive(Eq)

///|
priv enum PreparedLink {
  PreparedAArch64(@aarch64_target.AArch64LinkPlan)
  PreparedX64(@x64_target.X64LinkPlan)
}

///|
fn PreparedLink::code(self : PreparedLink) -> Array[Byte] {
  match self {
    PreparedAArch64(plan) => plan.code()
    PreparedX64(plan) => plan.code()
  }
}

///|
fn PreparedLink::link(
  self : PreparedLink,
  code_address : Int64,
  resolver : (@code_object.RelocationTarget) -> Int64?,
) -> Array[Byte] raise JitInstallError {
  match self {
    PreparedAArch64(plan) =>
      plan.link(code_address, resolver) catch {
        error =>
          raise RelocationFailed(function_index=-1, message=error.to_string())
      }
    PreparedX64(plan) =>
      plan.link(code_address, resolver) catch {
        error =>
          raise RelocationFailed(function_index=-1, message=error.to_string())
      }
  }
}

///|
fn prepare_links(
  loaded : LoadedArtifact,
) -> Array[PreparedLink] raise JitInstallError {
  let architecture = loaded.artifact().manifest.target.architecture
  let plans : Array[PreparedLink] = []
  let functions = loaded.artifact().functions
  for index, object in loaded.code_objects() {
    let function_index = functions[index].identity.function_index
    match architecture {
      AArch64 => {
        let plan = @aarch64_target.prepare_aarch64_link(object) catch {
          error =>
            raise RelocationFailed(function_index~, message=error.to_string())
        }
        plans.push(PreparedAArch64(plan))
      }
      X64 => {
        let plan = @x64_target.prepare_x64_link(object) catch {
          error =>
            raise RelocationFailed(function_index~, message=error.to_string())
        }
        plans.push(PreparedX64(plan))
      }
    }
  }
  plans
}

///|
fn lookup_resolved_target(
  resolved : Array[(@code_object.RelocationTarget, Int64)],
  target : @code_object.RelocationTarget,
) -> Int64? {
  for entry in resolved {
    if entry.0 == target {
      return Some(entry.1)
    }
  }
  None
}

///|
fn target_kind_and_name(
  target : @code_object.RelocationTarget,
) -> (String, String) {
  match target {
    Code(symbol) => ("code", symbol.name)
    Data(symbol) => ("data", symbol.name)
    External(symbol) => ("external", symbol.name)
  }
}

///|
fn resolve_target_before_allocation(
  installer : JitCodeInstaller,
  resolved : Array[(@code_object.RelocationTarget, Int64)],
  target : @code_object.RelocationTarget,
) -> Unit raise JitInstallError {
  if lookup_resolved_target(resolved, target) is Some(_) {
    return
  }
  let (kind, name) = target_kind_and_name(target)
  let address = match (installer.resolver)(target) {
    Some(address) if address != 0L => address
    _ => raise ResolutionFailed(kind~, name~)
  }
  resolved.push((target, address))
}

///|
fn resolve_static_targets(
  installer : JitCodeInstaller,
  loaded : LoadedArtifact,
) -> Array[(@code_object.RelocationTarget, Int64)] raise JitInstallError {
  let resolved : Array[(@code_object.RelocationTarget, Int64)] = []
  let artifact = loaded.artifact()
  for import_ in artifact.imports {
    let external_target = @code_object.RelocationTarget::External(
      import_.symbol,
    )
    resolve_target_before_allocation(installer, resolved, external_target)
    let address = lookup_resolved_target(resolved, external_target).unwrap()
    resolved.push(
      (Code(@semantic_machv.CodeSymbol::new(import_.symbol.name)), address),
    )
  }
  for function in artifact.functions {
    for relocation in function.relocations {
      match relocation.target {
        Code(_) => ()
        target => resolve_target_before_allocation(installer, resolved, target)
      }
    }
  }
  resolved
}

///|
fn release_staged_code(staged : Array[ExecCode]) -> Unit {
  for code in staged {
    code.release() |> ignore
  }
}

///|
fn first_function_index(artifact : @artifact.Artifact) -> Int {
  if artifact.functions.length() == 0 {
    -1
  } else {
    artifact.functions[0].identity.function_index
  }
}

///|
fn build_installed_imports(
  artifact : @artifact.Artifact,
  resolved : Array[(@code_object.RelocationTarget, Int64)],
) -> Array[InstalledImport] raise JitInstallError {
  let imports : Array[InstalledImport] = []
  for import_ in artifact.imports {
    let target = @code_object.RelocationTarget::External(import_.symbol)
    let address = match lookup_resolved_target(resolved, target) {
      Some(address) => address
      None => raise ResolutionFailed(kind="external", name=import_.symbol.name)
    }
    imports.push({ identity: import_, address })
  }
  imports
}

///|
fn build_installed_function(
  source : @artifact.FunctionCode,
  code_address : Int64,
  linked_code : Array[Byte],
) -> InstalledFunction raise JitInstallError {
  if source.entry_offset < 0 || source.entry_offset >= linked_code.length() {
    raise RegistrationFailed(
      function_index=source.identity.function_index,
      message="entry offset is outside linked code",
    )
  }
  {
    identity: source.identity,
    code_address,
    entry_address: code_address + source.entry_offset.to_int64(),
    code_size: linked_code.length(),
    entry_offset: source.entry_offset,
    frame_size: source.frame_size,
    sources: source.sources.copy(),
    traps: source.traps.copy(),
    safepoints: source.safepoints.copy(),
    unwind: source.unwind.copy(),
  }
}

///|
fn install_artifact_with_failure(
  installer : JitCodeInstaller,
  loaded : LoadedArtifact,
  failure? : InstallFailurePoint,
) -> InstalledCode raise JitInstallError {
  let artifact = loaded.artifact()
  let function_index = first_function_index(artifact)
  if failure == Some(Resolution) {
    raise ResolutionFailed(kind="injected", name="resolution")
  }
  let resolved = resolve_static_targets(installer, loaded)
  let plans = prepare_links(loaded)
  let staged : Array[ExecCode] = []
  try {
    for index, plan in plans {
      let source = artifact.functions[index]
      let code = match ExecCode::try_stage(plan.code().length()) {
        Some(code) => code
        None =>
          raise AllocationFailed(function_index=source.identity.function_index)
      }
      staged.push(code)
      if failure == Some(Allocation) {
        raise AllocationFailed(function_index=source.identity.function_index)
      }
    }
    for index, source in artifact.functions {
      let address = staged[index].ptr() + source.entry_offset.to_int64()
      resolved.push((Code(source.identity.symbol), address))
    }
    if failure == Some(Relocation) {
      raise RelocationFailed(function_index~, message="injected failure")
    }
    let linked_code : Array[Array[Byte]] = []
    for index, plan in plans {
      let current_index = artifact.functions[index].identity.function_index
      let bytes = plan.link(staged[index].ptr(), fn(target) {
        lookup_resolved_target(resolved, target)
      }) catch {
        RelocationFailed(function_index=_, message~) =>
          raise RelocationFailed(function_index=current_index, message~)
        error => raise error
      }
      linked_code.push(bytes)
    }
    if failure == Some(Registration) {
      raise RegistrationFailed(function_index~, message="injected failure")
    }
    let functions : Array[InstalledFunction] = []
    for index, source in artifact.functions {
      functions.push(
        build_installed_function(
          source,
          staged[index].ptr(),
          linked_code[index],
        ),
      )
    }
    let imports = build_installed_imports(artifact, resolved)
    if failure == Some(Protection) {
      raise ProtectionFailed(function_index~)
    }
    for index, code in staged {
      if !code.finalize(linked_code[index]) {
        raise ProtectionFailed(
          function_index=artifact.functions[index].identity.function_index,
        )
      }
    }
    let installed = { executable_code: staged, imports, functions }
    if failure == Some(Publication) {
      raise PublicationFailed(message="injected failure")
    }
    installer.current.val = Some(installed)
    installed
  } catch {
    error => {
      release_staged_code(staged)
      raise error
    }
  }
}

///|
/// Install one verified live or decoded artifact as a single transaction.
pub fn JitCodeInstaller::install(
  self : JitCodeInstaller,
  loaded : LoadedArtifact,
) -> InstalledCode raise JitInstallError {
  install_artifact_with_failure(self, loaded)
}
