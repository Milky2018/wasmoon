///|
pub(all) enum GprEncodingWidth {
  R32
  R64
}

///|
pub(all) enum GprRegisterOp {
  Add
  Sub
  And
  Or
  Xor
  Imul
  Mov
  Cmp
  Test
}

///|
pub(all) enum GprUnaryOp {
  Not
  Neg
}

///|
pub(all) enum GprShiftOp {
  Shl
  Shr
  Sar
  Ror
}

///|
fn CodeBuffer::emit_gpr_rex(
  self : CodeBuffer,
  width : GprEncodingWidth,
  reg : Int32,
  rm : Int32,
) -> Unit {
  let r = (reg >> 3) & 1
  let b = (rm >> 3) & 1
  match width {
    R64 => emit_rex_w(self, r, b)
    R32 => if r != 0 || b != 0 { emit_rex(self, r, b) }
  }
}

///|
pub fn CodeBuffer::x86_emit_gpr(
  self : CodeBuffer,
  operation : GprRegisterOp,
  width : GprEncodingWidth,
  left : Int32,
  right : Int32,
) -> Unit {
  let (opcode, reg, rm) = match operation {
    Add => (0x01, right, left)
    Sub => (0x29, right, left)
    And => (0x21, right, left)
    Or => (0x09, right, left)
    Xor => (0x31, right, left)
    Mov => (0x89, right, left)
    Cmp => (0x39, right, left)
    Test => (0x85, right, left)
    // IMUL writes the ModRM reg operand and uses the escaped opcode map.
    Imul => (0xAF, left, right)
  }
  self.emit_gpr_rex(width, reg, rm)
  if operation is Imul {
    self.emit_byte(0x0F)
  }
  self.emit_byte(opcode)
  emit_modrm(self, 3, reg, rm)
}

///|
fn CodeBuffer::emit_gpr_group(
  self : CodeBuffer,
  width : GprEncodingWidth,
  opcode : Int32,
  extension : Int32,
  operand : Int32,
) -> Unit {
  self.emit_gpr_rex(width, 0, operand)
  self.emit_byte(opcode)
  emit_modrm(self, 3, extension, operand)
}

///|
pub fn CodeBuffer::x86_emit_gpr_unary(
  self : CodeBuffer,
  operation : GprUnaryOp,
  width : GprEncodingWidth,
  operand : Int32,
) -> Unit {
  let extension = match operation {
    Not => 2
    Neg => 3
  }
  self.emit_gpr_group(width, 0xF7, extension, operand)
}

///|
fn GprShiftOp::extension(self : GprShiftOp) -> Int32 {
  match self {
    Ror => 1
    Shl => 4
    Shr => 5
    Sar => 7
  }
}

///|
pub fn CodeBuffer::x86_emit_gpr_shift_cl(
  self : CodeBuffer,
  operation : GprShiftOp,
  width : GprEncodingWidth,
  operand : Int32,
) -> Unit {
  self.emit_gpr_group(width, 0xD3, operation.extension(), operand)
}

///|
pub fn CodeBuffer::x86_emit_gpr_shift_imm8(
  self : CodeBuffer,
  operation : GprShiftOp,
  width : GprEncodingWidth,
  operand : Int32,
  amount : Int32,
) -> Unit {
  self.emit_gpr_group(width, 0xC1, operation.extension(), operand)
  self.emit_byte(amount & 255)
}
