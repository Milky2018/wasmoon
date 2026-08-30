///|
pub type RegClass = @allocation_types.RegClass

///|
pub type OperandTiming = @allocation_types.OperandTiming

///|
pub type OperandRole = @allocation_types.OperandRole

///|
pub type PhysicalReg = @allocation_types.PhysicalReg

///|
pub type OperandConstraint = @allocation_types.AllocationConstraint

///|
pub type VirtualReg = @allocation_types.VirtualReg

///|
pub type Operand = @allocation_types.AllocationOperand

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
