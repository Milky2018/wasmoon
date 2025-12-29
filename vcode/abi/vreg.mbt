// ============ Virtual Registers ============

///|
/// Virtual register - an abstract register before register allocation
pub(all) struct VReg {
  id : Int
  class : RegClass // Which register class this vreg belongs to
}

///|
fn VReg::to_string(self : VReg) -> String {
  match self.class {
    Int => "v\{self.id}"
    Float32 | Float64 => "f\{self.id}"
    Vector => "vec\{self.id}" // Virtual SIMD vector register
  }
}

///|
pub impl Show for VReg with output(self, logger) {
  logger.write_string(self.to_string())
}
