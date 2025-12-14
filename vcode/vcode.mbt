// VCode - Virtual-register code representation
// A low-level IR that is closer to machine code than the high-level IR
//
// VCode is structured with traditional basic blocks, where each block is
// terminated by an unconditional branch, conditional branch, or return.
// Register slots can refer to virtual registers in addition to physical registers.

// ============ Operands ============

///|
/// Operand - an instruction operand with constraints
pub(all) struct Operand {
  reg : VReg
  kind : OperandKind
  constraint : OperandConstraint
}

///|
/// Operand kind - how the operand is used
#warnings("-unused_constructor")
pub enum OperandKind {
  Use // Read from
  Def // Written to
  UseDef // Both read and written
}

///|
#warnings("-unused_value")
fn OperandKind::to_string(self : OperandKind) -> String {
  match self {
    Use => "use"
    Def => "def"
    UseDef => "use-def"
  }
}

///|
/// Operand constraint - register allocation constraint
#warnings("-unused_constructor")
pub enum OperandConstraint {
  Any // Any register in the class
  Fixed(PReg) // Must be this specific physical register
  Reuse(Int) // Must reuse the same register as operand at index
}

///|
#warnings("-unused_value")
fn OperandConstraint::to_string(self : OperandConstraint) -> String {
  match self {
    Any => "any"
    Fixed(preg) => "fixed(\{preg})"
    Reuse(idx) => "reuse(\{idx})"
  }
}

// ============ VCode Structure ============
