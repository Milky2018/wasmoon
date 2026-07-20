///|
pub(all) enum RegClass {
  Int
  Float
  Vector
} derive(Eq, Debug)

///|
pub(all) struct VirtualReg {
  id : Int
  class : RegClass
} derive(Eq, Debug)

///|
pub(all) struct PhysicalReg {
  id : Int
  class : RegClass
} derive(Eq, Debug)

///|
fn physical_reg_key(reg : PhysicalReg) -> (Int, Int) {
  let class = match reg.class {
    Int => 0
    Float => 1
    Vector => 2
  }
  (class, reg.id)
}

///|
pub(all) enum Location {
  Reg(PhysicalReg)
  Spill(Int)
} derive(Eq, Debug)

///|
pub(all) enum OperandRole {
  Use
  Def
  UseDef
} derive(Eq, Debug)

///|
pub(all) enum OperandTiming {
  Early
  Late
} derive(Eq, Debug)

///|
pub(all) struct Operand {
  vreg : VirtualReg
  role : OperandRole
  constraint : OperandConstraint
  tie_id : Int
  timing : OperandTiming
} derive(Eq, Debug)

///|
pub fn Operand::use_reg(vreg : VirtualReg) -> Operand {
  { vreg, role: Use, constraint: AnyReg, tie_id: -1, timing: Early }
}

///|
pub fn Operand::def(vreg : VirtualReg) -> Operand {
  { vreg, role: Def, constraint: AnyReg, tie_id: -1, timing: Late }
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
    tie_id: self.tie_id,
    timing: self.timing,
  }
}

///|
pub fn Operand::with_tie(self : Operand, tie_id : Int) -> Operand {
  {
    vreg: self.vreg,
    role: self.role,
    constraint: self.constraint,
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
    tie_id: self.tie_id,
    timing,
  }
}
