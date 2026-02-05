///|
/// Shared types for the ISA policy layer.
///
/// This package exists to avoid dependency cycles between:
/// - `vcode/isa` (facade, exposes `ISA` + dispatch helpers)
/// - `vcode/isa/<backend>` (backend-specific policy implementations)

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
/// Integer physical-register roles used by the JIT backend.
///
/// Step 2 goal: eliminate direct uses of AArch64-specific register constants
/// (e.g. `REG_VMCTX`) in shared lowering/emission code.
pub(all) enum IntRegRole {
  /// Pinned/cached VMContext register.
  Vmctx
  /// Cached memory0 descriptor pointer register (optional).
  Mem0Desc
  /// Cached func_table pointer register (optional).
  FuncTable
  /// Extra results pointer register for multi-value calls.
  ExtraResultsPtr
  /// Scratch temporaries reserved for emission/lowering.
  Scratch1
  Scratch2
  /// Frame pointer / link register (when architecture has them).
  FP
  LR
  /// Struct-return register (when used by ABI).
  SRet
}
