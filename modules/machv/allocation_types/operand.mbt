///|
/// The point within an instruction where an allocation operand is read or
/// written.
pub(all) enum OperandTiming {
  Early
  Late
} derive(Eq, Debug)

///|
pub extend OperandTiming with Debug::{to_repr}

///|
pub extend OperandTiming with Eq::{not_equal, equal}

///|
/// Whether an allocation operand reads, writes, or both reads and writes its
/// virtual register.
///
/// SSA VCode producers use `Use` and `Def`. `UseDef` remains available to
/// standalone register-allocation clients that model in-place updates.
pub(all) enum OperandRole {
  Use
  Def
  UseDef
} derive(Eq, Debug)

///|
pub extend OperandRole with Debug::{to_repr}

///|
pub extend OperandRole with Eq::{not_equal, equal}

///|
/// A normalized register-allocation constraint.
///
/// Operand ties are represented separately by a shared nonnegative tie label,
/// so this type contains only location constraints.
pub(all) enum AllocationConstraint {
  AnyReg
  AnyLocation
  FixedReg(PhysicalReg)
} derive(Eq, Debug)

///|
pub extend AllocationConstraint with Debug::{to_repr}

///|
pub extend AllocationConstraint with Eq::{not_equal, equal}
