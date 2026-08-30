///|
pub type RegClass = @allocation_types.RegClass

///|
pub type OperandTiming = @allocation_types.OperandTiming

///|
pub type OperandRole = @allocation_types.OperandRole

///|
pub type PhysicalReg = @allocation_types.PhysicalReg

///|
#valtype
pub(all) struct VirtualReg {
  id : Int
  class : RegClass
} derive(Eq, Debug)

///|
fn physical_reg_key(reg : PhysicalReg) -> (Int, Int) {
  let class = match reg.class {
    Int => 0
    Float => 1
    Vector => 2
    FpVector => 1
  }
  (class, reg.id)
}

///|
pub(all) enum Location {
  Reg(PhysicalReg)
  Spill(Int)
} derive(Eq, Debug)

///|
pub(all) struct Operand {
  vreg : VirtualReg
  role : OperandRole
  constraint : OperandConstraint
  preference : PhysicalReg?
  tie_id : Int
  timing : OperandTiming
} derive(Eq, Debug)

///|
pub fn Operand::use_reg(vreg : VirtualReg) -> Operand {
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
pub fn Operand::def(vreg : VirtualReg) -> Operand {
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
pub fn Operand::with_constraint(
  self : Operand,
  constraint : OperandConstraint,
) -> Operand {
  {
    vreg: self.vreg,
    role: self.role,
    constraint,
    preference: self.preference,
    tie_id: self.tie_id,
    timing: self.timing,
  }
}

///|
/// Prefer a physical register without making it a correctness constraint.
/// Allocation may ignore the preference when that register is unavailable.
pub fn Operand::with_preference(
  self : Operand,
  preference : PhysicalReg,
) -> Operand {
  { ..self, preference: Some(preference), }
}

///|
/// Tie operands in one instruction by a shared nonnegative label.
/// Labels are opaque and need not be contiguous or bounded by operand count.
pub fn Operand::with_tie(self : Operand, tie_id : Int) -> Operand {
  {
    vreg: self.vreg,
    role: self.role,
    constraint: self.constraint,
    preference: self.preference,
    tie_id,
    timing: self.timing,
  }
}

///|
pub fn Operand::with_timing(self : Operand, timing : OperandTiming) -> Operand {
  {
    vreg: self.vreg,
    role: self.role,
    constraint: self.constraint,
    preference: self.preference,
    tie_id: self.tie_id,
    timing,
  }
}
