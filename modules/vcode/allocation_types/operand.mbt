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
  /// Keep this operand at a canonical home that survives the instruction's
  /// clobbers without materializing a temporary. This is used for stack maps.
  PreservedHome
  FixedReg(PhysicalReg)
} derive(Eq, Debug)

///|
pub extend AllocationConstraint with Debug::{to_repr}

///|
pub extend AllocationConstraint with Eq::{not_equal, equal}

///|
/// A dense virtual-register identity within one allocation session.
#valtype
pub(all) struct VirtualReg {
  id : Int
  class : RegClass
} derive(Eq, Debug)

///|
pub extend VirtualReg with Debug::{to_repr}

///|
pub extend VirtualReg with Eq::{not_equal, equal}

///|
/// The canonical allocation facts for one instruction operand.
pub(all) struct AllocationOperand {
  vreg : VirtualReg
  role : OperandRole
  constraint : AllocationConstraint
  preference : PhysicalReg?
  tie_id : Int
  timing : OperandTiming
} derive(Eq, Debug)

///|
pub fn AllocationOperand::use_reg(vreg : VirtualReg) -> AllocationOperand {
  {
    vreg,
    role: Use,
    constraint: AnyReg,
    preference: None,
    tie_id: -1,
    timing: Early,
  }
}

///|
pub fn AllocationOperand::def(vreg : VirtualReg) -> AllocationOperand {
  {
    vreg,
    role: Def,
    constraint: AnyReg,
    preference: None,
    tie_id: -1,
    timing: Late,
  }
}

///|
pub fn AllocationOperand::with_constraint(
  self : AllocationOperand,
  constraint : AllocationConstraint,
) -> AllocationOperand {
  { ..self, constraint, }
}

///|
/// Prefer a physical register without making it a correctness constraint.
pub fn AllocationOperand::with_preference(
  self : AllocationOperand,
  preference : PhysicalReg,
) -> AllocationOperand {
  { ..self, preference: Some(preference), }
}

///|
/// Tie operands in one instruction by a shared nonnegative label.
pub fn AllocationOperand::with_tie(
  self : AllocationOperand,
  tie_id : Int,
) -> AllocationOperand {
  { ..self, tie_id, }
}

///|
pub fn AllocationOperand::with_timing(
  self : AllocationOperand,
  timing : OperandTiming,
) -> AllocationOperand {
  { ..self, timing, }
}

///|
pub extend AllocationOperand with Debug::{to_repr}

///|
pub extend AllocationOperand with Eq::{not_equal, equal}
