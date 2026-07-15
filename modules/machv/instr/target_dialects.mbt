///|
/// AMD64-only MachV operations.
///
/// These operations expose architectural behavior that is not part of the
/// cross-target MachV instruction set.
pub(all) enum AMD64Opcode {
  /// Checked signed remainder using the implicit x86 dividend registers.
  SRem(Bool)
  /// Unsigned remainder using the implicit x86 dividend registers.
  URem(Bool)
} derive(Debug)

///|
fn AMD64Opcode::to_string(self : AMD64Opcode) -> String {
  match self {
    SRem(is_64) => if is_64 { "srem" } else { "srem32" }
    URem(is_64) => if is_64 { "urem" } else { "urem32" }
  }
}

///|
pub impl Show for AMD64Opcode with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// AMD64-only flag conditions.
pub(all) enum AMD64Cond {
  ParitySet
  ParityClear
} derive(Debug, Eq)

///|
fn AMD64Cond::to_string(self : AMD64Cond) -> String {
  match self {
    ParitySet => "ps"
    ParityClear => "pc"
  }
}

///|
fn AMD64Cond::invert(self : AMD64Cond) -> AMD64Cond {
  match self {
    ParitySet => ParityClear
    ParityClear => ParitySet
  }
}

///|
pub impl Show for AMD64Cond with fn output(self, logger) {
  logger.write_string(self.to_string())
}
