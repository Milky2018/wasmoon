///|
/// The first breaking Cwasm format after the legacy v8 representation.
pub const FORMAT_VERSION : Int = 9

///|
/// Operating-system ABI assumed by generated code and unwind metadata.
pub(all) enum OperatingSystemAbi {
  MacOS
  LinuxGnu
  LinuxMusl
  WindowsMsvc
} derive(Eq, Debug)

///|
/// Pointer width assumed by the Wasmoon JIT ABI.
pub(all) enum PointerWidth {
  Bits64
} derive(Eq, Debug)

///|
/// Exact target and platform contract for the persisted machine code.
pub(all) struct TargetSpec {
  architecture : @code_object.Architecture
  operating_system_abi : OperatingSystemAbi
  endianness : @machv.Endianness
  pointer_width : PointerWidth
} derive(Eq, Debug)

///|
/// A target CPU feature required by every function in the artifact.
///
/// Names are stable wire identities. Compatibility validation rejects names
/// that are not known for `TargetSpec::architecture`; it never guesses a
/// fallback feature.
pub(all) struct CpuFeature {
  name : String
} derive(Eq, Debug)

///|
/// Content digest used for source-module and semantic-feature identity.
///
/// The Cwasm codec accepts exactly 32 bytes and interprets them as SHA-256.
pub(all) struct Digest {
  bytes : Bytes
} derive(Eq, Debug)

///|
/// Identity of the validated WebAssembly module that produced this artifact.
pub(all) struct ModuleIdentity {
  name : String
  source_digest : Digest
  semantic_features_digest : Digest
} derive(Eq, Debug)

///|
/// MilkIR optimization level used before target lowering.
pub(all) enum OptimizationLevel {
  O0
  O1
  O2
  O3
} derive(Eq, Debug)

///|
/// Addressing range selected by target emission.
pub(all) enum CodeModel {
  Small
  Large
} derive(Eq, Debug)

///|
/// Binding policy for internal direct and tail calls.
pub(all) enum CallBinding {
  StableEntry
  DirectBody
} derive(Eq, Debug)

///|
/// Compilation choices that change generated code or its runtime contract.
pub(all) struct CompilationPolicy {
  optimization_level : OptimizationLevel
  code_model : CodeModel
  call_binding : CallBinding
  cancellation_safepoints : Bool
  debug_info : Bool
} derive(Eq, Debug)

///|
/// Complete compatibility contract checked before code-object verification.
///
/// Every field matches exactly except `required_cpu_features`, for which the
/// installing host may provide a strict superset.
pub(all) struct CompatibilityManifest {
  format_version : Int
  target : TargetSpec
  required_cpu_features : Array[CpuFeature]
  jit_abi_version : Int
  codegen_revision : String
  module_identity : ModuleIdentity
  policy : CompilationPolicy
} derive(Eq, Debug)

///|
/// Stable identity and logical signature for an imported function.
pub(all) struct ImportIdentity {
  function_index : Int
  module_name : String
  function_name : String
  symbol : @machv.ExternalSymbol
  signature : @machv.Signature
} derive(Eq, Debug)

///|
/// Stable identity and logical signature for a defined function.
pub(all) struct FunctionIdentity {
  function_index : Int
  symbol : @machv.CodeSymbol
  signature : @machv.Signature
} derive(Eq, Debug)

///|
/// Serializable ordinary-data form of one unlinked target code object.
///
/// This record deliberately contains symbolic relocations and no resolved
/// process or executable-memory address. The Wasmoon JIT root reconstructs and
/// verifies `UnlinkedCodeObject` values from these fields before installation.
pub(all) struct FunctionCode {
  identity : FunctionIdentity
  entry_offset : Int
  frame_size : Int
  code : Array[Byte]
  relocations : Array[@code_object.Relocation]
  sources : Array[@code_object.SourceSite]
  traps : Array[@code_object.TrapSite]
  safepoints : Array[@code_object.SafepointSite]
  unwind : Array[@code_object.UnwindDirective]
} derive(Eq, Debug)

///|
/// Target-portable ordinary data contained in one Cwasm file or cache entry.
pub(all) struct Artifact {
  manifest : CompatibilityManifest
  imports : Array[ImportIdentity]
  functions : Array[FunctionCode]
} derive(Eq, Debug)
