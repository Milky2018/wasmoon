///|
pub(all) enum RegClass {
  Int
  Float32
  Float64
  Vector
} derive(Eq, Debug)

///|
fn RegClass::to_string(self : RegClass) -> String {
  match self {
    Int => "int"
    Float32 => "float"
    Float64 => "double"
    Vector => "vector"
  }
}

///|
pub impl Show for RegClass with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub(all) struct VReg {
  id : Int
  class : RegClass
} derive(Eq, Debug)

///|
fn VReg::to_string(self : VReg) -> String {
  match self.class {
    Int => "v\{self.id}"
    Float32 | Float64 => "f\{self.id}"
    Vector => "vec\{self.id}"
  }
}

///|
pub impl Show for VReg with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub(all) struct PReg {
  index : Int
  class : RegClass
} derive(Eq, Debug)

///|
fn PReg::to_string(self : PReg) -> String {
  match self.class {
    Int => "x\{self.index}"
    Float32 | Float64 => "d\{self.index}"
    Vector => "v\{self.index}"
  }
}

///|
pub impl Show for PReg with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub let spill_slot_base : Int = 256

///|
pub fn PReg::is_spilled(self : PReg) -> Bool {
  self.index >= spill_slot_base
}

///|
pub fn PReg::get_spill_slot(self : PReg) -> Int {
  if self.index >= spill_slot_base {
    self.index - spill_slot_base
  } else {
    -1
  }
}

///|
pub fn PReg::spilled(slot : Int, class : RegClass) -> PReg {
  { index: spill_slot_base + slot, class }
}

///|
pub(all) enum Reg {
  Virtual(VReg)
  Physical(PReg)
} derive(Eq, Debug)

///|
fn Reg::to_string(self : Reg) -> String {
  match self {
    Virtual(vreg) => vreg.to_string()
    Physical(preg) => preg.to_string()
  }
}

///|
pub impl Show for Reg with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub(all) struct Writable {
  reg : Reg
} derive(Eq, Debug)

///|
fn Writable::to_string(self : Writable) -> String {
  self.reg.to_string()
}

///|
pub impl Show for Writable with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub(all) enum OperandConstraint {
  Any
  FixedReg(PReg)
} derive(Eq, Debug)

///|
fn OperandConstraint::to_string(self : OperandConstraint) -> String {
  match self {
    Any => "any"
    FixedReg(preg) => "fixed(\{preg})"
  }
}

///|
pub impl Show for OperandConstraint with fn output(self, logger) {
  logger.write_string(self.to_string())
}

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
