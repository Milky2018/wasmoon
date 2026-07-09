///|
/// Physical register - a real machine register
pub(all) struct PReg {
  index : Int // Register number (e.g., x0-x30 for AArch64)
  class : RegClass
} derive(Eq, Debug)

///|
fn PReg::to_string(self : PReg) -> String {
  match self.class {
    Int => "x\{self.index}"
    Float32 | Float64 => "d\{self.index}"
    Vector => "v\{self.index}" // SIMD vector registers v0-v31
  }
}

///|
pub impl Show for PReg with fn output(self, logger) {
  logger.write_string(self.to_string())
}
