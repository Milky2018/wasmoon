///|
/// Cwasm format with an explicit arithmetic NaN compilation policy.
pub const FORMAT_VERSION : Int32 = 12

///|
/// Operating-system ABI assumed by generated code and unwind metadata.
#derive(Eq, Debug)
pub(all) enum OperatingSystemAbi {
  MacOS
  LinuxGnu
  LinuxMusl
  WindowsMsvc
}

///|
/// Pointer width assumed by the Wasmoon JIT ABI.
#derive(Eq, Debug)
pub(all) enum PointerWidth {
  Bits64
}

///|
/// Exact target and platform contract for the persisted machine code.
#derive(Eq, Debug)
pub(all) struct TargetSpec {
  architecture : @code_object.Architecture
  operating_system_abi : OperatingSystemAbi
  endianness : @native.Endianness
  pointer_width : PointerWidth
}

///|
/// A target CPU feature required by every function in the artifact.
///
/// Names are stable wire identities. Compatibility validation rejects names
/// that are not known for `TargetSpec::architecture`; it never guesses a
/// fallback feature.
#derive(Eq, Debug)
pub(all) struct CpuFeature {
  name : String
}

///|
/// Content digest used for source-module and semantic-feature identity.
///
/// The Cwasm codec accepts exactly 32 bytes and interprets them as SHA-256.
#derive(Eq)
pub(all) struct Digest {
  bytes : Bytes
}

///|
pub impl Debug for Digest with fn to_repr(self) {
  let hex = "0123456789abcdef"
  let text = StringBuilder::StringBuilder()
  text.write_string("sha256:")
  for byte in self.bytes {
    let value = byte.to_int()
    text.write_char(hex.code_unit_at(value >> 4).to_int().unsafe_to_char())
    text.write_char(hex.code_unit_at(value & 0x0F).to_int().unsafe_to_char())
  }
  Repr::literal(text.to_string())
}

///|
/// Identity of the validated WebAssembly module that produced this artifact.
#derive(Eq, Debug)
pub(all) struct ModuleIdentity {
  name : String
  source_digest : Digest
  semantic_features_digest : Digest
}

///|
/// MilkIR optimization level used before target lowering.
#derive(Eq, Debug)
pub(all) enum OptimizationLevel {
  O0
  O1
  O2
  O3
}

///|
/// Addressing range selected by target emission.
#derive(Eq, Debug)
pub(all) enum CodeModel {
  Small
  Large
}

///|
/// Binding policy for internal direct and tail calls.
#derive(Eq, Debug)
pub(all) enum CallBinding {
  StableEntry
  DirectBody
}

///|
/// Compilation choices that change generated code or its runtime contract.
#derive(Eq, Debug)
pub(all) struct CompilationPolicy {
  optimization_level : OptimizationLevel
  code_model : CodeModel
  call_binding : CallBinding
  nan_canonicalization : Bool
  cancellation_safepoints : Bool
  debug_info : Bool
}

///|
/// Complete compatibility contract checked before code-object verification.
///
/// Every field matches exactly except `required_cpu_features`, for which the
/// installing host may provide a strict superset.
#derive(Eq, Debug)
pub(all) struct CompatibilityManifest {
  format_version : Int32
  target : TargetSpec
  required_cpu_features : Array[CpuFeature]
  jit_abi_version : Int32
  codegen_revision : String
  module_identity : ModuleIdentity
  policy : CompilationPolicy
  context_shape : @context_layout.ContextShape
}

///|
/// Stable identity and logical signature for an imported function.
#derive(Eq, Debug)
pub(all) struct ImportIdentity {
  function_index : Int32
  module_name : String
  function_name : String
  symbol : @native.ExternalSymbol
  signature : @native.Signature
}

///|
/// Stable identity and logical signature for a defined function.
#derive(Eq, Debug)
pub(all) struct FunctionIdentity {
  function_index : Int32
  symbol : @native.CodeSymbol
  signature : @native.Signature
}

///|
/// Serializable ordinary-data form of one unlinked target code object.
///
/// This record deliberately contains symbolic relocations and no resolved
/// process or executable-memory address. The Wasmoon JIT root reconstructs and
/// verifies `UnlinkedCodeObject` values from these fields before installation.
#derive(Eq, Debug)
pub(all) struct FunctionCode {
  identity : FunctionIdentity
  entry_offset : Int32
  frame_size : Int32
  code : Array[Byte]
  relocations : Array[@code_object.Relocation]
  sources : Array[@code_object.SourceSite]
  traps : Array[@code_object.TrapSite]
  safepoints : Array[@code_object.SafepointSite]
  unwind : Array[@code_object.UnwindDirective]
}

///|
/// Target-portable ordinary data contained in one Cwasm file or cache entry.
#derive(Eq, Debug)
pub(all) struct Artifact {
  manifest : CompatibilityManifest
  imports : Array[ImportIdentity]
  functions : Array[FunctionCode]
}
