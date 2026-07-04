///|
pub(all) enum RegClass {
  Int
  Float
  Vector
} derive(Eq, Debug)

///|
pub(all) struct VReg {
  id : Int
  class : RegClass
} derive(Eq, Debug)

///|
pub(all) struct PReg {
  index : Int
  class : RegClass
} derive(Eq, Debug)

///|
pub(all) enum Reg {
  Virtual(VReg)
  Physical(PReg)
} derive(Eq, Debug)

///|
pub(all) enum OperandRole {
  Use
  Def
  UseDef
} derive(Eq, Debug)

///|
pub(all) struct Operand {
  reg : Reg
  role : OperandRole
} derive(Eq, Debug)

///|
pub fn Operand::use_reg(reg : Reg) -> Operand {
  { reg, role: Use }
}

///|
pub fn Operand::def(reg : Reg) -> Operand {
  { reg, role: Def }
}

///|
pub fn Operand::use_def(reg : Reg) -> Operand {
  { reg, role: UseDef }
}
