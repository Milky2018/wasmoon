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
