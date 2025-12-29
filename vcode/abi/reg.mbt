///|
/// Register class - categorizes registers by their purpose
pub(all) enum RegClass {
  Int // Integer/general-purpose registers
  Float32 // 32-bit floating-point registers
  Float64 // 64-bit floating-point registers
  Vector // 128-bit SIMD vector registers
}

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
pub impl Show for RegClass with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// A register reference - either virtual or physical
pub(all) enum Reg {
  Virtual(VReg)
  Physical(PReg)
}

///|
fn Reg::to_string(self : Reg) -> String {
  match self {
    Virtual(vreg) => vreg.to_string()
    Physical(preg) => preg.to_string()
  }
}

///|
pub impl Show for Reg with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Operand constraint for register allocation
/// Fixed register constraint handling
pub(all) enum OperandConstraint {
  Any // Any register is acceptable
  FixedReg(PReg) // Must use specific physical register
}

///|
fn OperandConstraint::to_string(self : OperandConstraint) -> String {
  match self {
    Any => "any"
    FixedReg(preg) => "fixed(\{preg})"
  }
}

///|
pub impl Show for OperandConstraint with output(self, logger) {
  logger.write_string(self.to_string())
}
