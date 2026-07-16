///|
/// A writable register reference (for instruction destinations)
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
