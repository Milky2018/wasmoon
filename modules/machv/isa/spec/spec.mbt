///|
/// Shared types for the ISA policy layer.
///
/// This package exists to avoid dependency cycles between:
/// - `machv/isa` (facade, exposes `ISA` + dispatch helpers)
/// - `machv/isa/<backend>` (backend-specific policy implementations)

///|
pub(all) struct MachineEnvData {
  preferred_int : Array[@abi.PReg]
  nonpreferred_int : Array[@abi.PReg]
  preferred_float : Array[@abi.PReg]
  nonpreferred_float : Array[@abi.PReg]
  preferred_vector : Array[@abi.PReg]
  nonpreferred_vector : Array[@abi.PReg]
  callee_saved_int : Array[@abi.PReg]
  callee_saved_float : Array[@abi.PReg]
  scratch_int : Array[Int]
  scratch_float : Array[Int]
}

///|
/// Target-owned integer physical-register roles.
pub(all) enum IntRegRole {
  /// Scratch temporaries reserved for emission/lowering.
  Scratch1
  Scratch2
  /// Frame pointer / link register (when architecture has them).
  FP
  LR
  /// Struct-return register (when used by ABI).
  SRet
}
