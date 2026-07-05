///|
fn opcode_debug_name(opcode : @machv.Opcode) -> String {
  match opcode {
    Target(name) => name
    _ => "machv." + to_repr(opcode).to_string()
  }
}

///|
fn terminator_debug_name(term : @machv.Terminator) -> String {
  "machv." + to_repr(term).to_string()
}

///|
pub suberror EmitError {
  UnsupportedOpcode(opcode~ : String)
  UnsupportedOperand(message~ : String)
  BranchFixupError(message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for EmitError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn emit_u32_le(object : CodeObject, word : Int) -> Unit {
  object.code.push(word & 0xff)
  object.code.push((word >> 8) & 0xff)
  object.code.push((word >> 16) & 0xff)
  object.code.push((word >> 24) & 0xff)
}

///|
fn emit_u64_le(object : CodeObject, word : Int64) -> Unit {
  let mut x = word
  for _ in 0..<8 {
    object.code.push((x & 0xffL).to_int())
    x = x >> 8
  }
}

///|
fn emit_x64_rex_w(object : CodeObject, r : Int, b : Int) -> Unit {
  object.code.push(0x48 | ((r & 1) << 2) | (b & 1))
}

///|
fn emit_x64_modrm(object : CodeObject, mod_ : Int, reg : Int, rm : Int) -> Unit {
  object.code.push(((mod_ & 3) << 6) | ((reg & 7) << 3) | (rm & 7))
}

///|
fn emit_x64_mov_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: mov r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x89)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_mov_rr32(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: mov r/m32, r32.
  emit_x64_rex_if_needed(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x89)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_add_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: add r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x01)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_sub_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: sub r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x29)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_and_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: and r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x21)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_or_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: or r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x09)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_and_rr32(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: and r/m32, r32.
  emit_x64_rex_if_needed(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x21)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_or_rr32(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: or r/m32, r32.
  emit_x64_rex_if_needed(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x09)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_xor_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: xor r/m64, r64.
  emit_x64_rex_w(object, (src >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x31)
  emit_x64_modrm(object, 3, src, dst)
}

///|
fn emit_x64_imul_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: imul r64, r/m64.
  emit_x64_rex_w(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0xaf)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_div_r64(object : CodeObject, rhs : Int, signed : Bool) -> Unit {
  emit_x64_rex_w(object, 0, (rhs >> 3) & 1)
  object.code.push(0xf7)
  emit_x64_modrm(object, 3, if signed { 7 } else { 6 }, rhs)
}

///|
fn emit_x64_mul_high_r64(object : CodeObject, rhs : Int, signed : Bool) -> Unit {
  emit_x64_rex_w(object, 0, (rhs >> 3) & 1)
  object.code.push(0xf7)
  emit_x64_modrm(object, 3, if signed { 5 } else { 4 }, rhs)
}

///|
fn emit_x64_not_r64(object : CodeObject, reg : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: not r/m64.
  emit_x64_rex_w(object, 0, (reg >> 3) & 1)
  object.code.push(0xf7)
  emit_x64_modrm(object, 3, 2, reg)
}

///|
fn emit_x64_shift_r_cl(object : CodeObject, dst : Int, subopcode : Int) -> Unit {
  emit_x64_rex_w(object, 0, (dst >> 3) & 1)
  object.code.push(0xd3)
  emit_x64_modrm(object, 3, subopcode, dst)
}

///|
fn emit_x64_movd_r32_xmm(object : CodeObject, dst : Int, src_xmm : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: movd r/m32, xmm.
  object.code.push(0x66)
  emit_x64_rex_if_needed(object, (src_xmm >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x7e)
  emit_x64_modrm(object, 3, src_xmm, dst)
}

///|
fn emit_x64_movd_xmm_r32(object : CodeObject, dst_xmm : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: movd xmm, r/m32.
  object.code.push(0x66)
  emit_x64_rex_if_needed(object, (dst_xmm >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x6e)
  emit_x64_modrm(object, 3, dst_xmm, src)
}

///|
fn emit_x64_movq_r64_xmm(object : CodeObject, dst : Int, src_xmm : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: movq r/m64, xmm.
  object.code.push(0x66)
  emit_x64_rex_w(object, (src_xmm >> 3) & 1, (dst >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x7e)
  emit_x64_modrm(object, 3, src_xmm, dst)
}

///|
fn emit_x64_movq_xmm_r64(object : CodeObject, dst_xmm : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: movq xmm, r/m64.
  object.code.push(0x66)
  emit_x64_rex_w(object, (dst_xmm >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x6e)
  emit_x64_modrm(object, 3, dst_xmm, src)
}

///|
fn emit_x64_ucomis_rr(
  object : CodeObject,
  lhs : Int,
  rhs : Int,
  class : @machv.RegClass,
) -> Unit {
  match class {
    Float32 => ()
    Float64 => object.code.push(0x66)
    _ => abort("unreachable float compare class")
  }
  emit_x64_rex_if_needed(object, (lhs >> 3) & 1, (rhs >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x2e)
  emit_x64_modrm(object, 3, lhs, rhs)
}

///|
fn emit_x64_movsx_r64_r8(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: movsx r64, r/m8.
  emit_x64_rex_w(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0xbe)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_movsx_r64_r16(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: movsx r64, r/m16.
  emit_x64_rex_w(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0xbf)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_movsxd_r64_r32(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: movsxd r64, r/m32.
  emit_x64_rex_w(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x63)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_mov_imm64(object : CodeObject, dst : Int, imm : Int64) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: mov r64, imm64.
  emit_x64_rex_w(object, 0, (dst >> 3) & 1)
  object.code.push(0xb8 + (dst & 7))
  emit_u64_le(object, imm)
}

///|
fn emit_x64_test_rr(object : CodeObject, reg : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: test r/m64, r64.
  emit_x64_rex_w(object, (reg >> 3) & 1, (reg >> 3) & 1)
  object.code.push(0x85)
  emit_x64_modrm(object, 3, reg, reg)
}

///|
fn emit_x64_test_rr32(object : CodeObject, reg : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: test r/m32, r32.
  emit_x64_rex_if_needed(object, (reg >> 3) & 1, (reg >> 3) & 1)
  object.code.push(0x85)
  emit_x64_modrm(object, 3, reg, reg)
}

///|
fn emit_x64_cmp_rr(object : CodeObject, lhs : Int, rhs : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: cmp r/m64, r64.
  emit_x64_rex_w(object, (rhs >> 3) & 1, (lhs >> 3) & 1)
  object.code.push(0x39)
  emit_x64_modrm(object, 3, rhs, lhs)
}

///|
fn emit_x64_setcc_r8(
  object : CodeObject,
  cond : @machv.Cond,
  dst : Int,
) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: setcc r/m8.
  let b = (dst >> 3) & 1
  if b != 0 || (dst & 7) >= 4 {
    emit_x64_rex_if_needed(object, 0, b)
  }
  object.code.push(0x0f)
  object.code.push(x64_jcc_opcode(cond) + 0x10)
  emit_x64_modrm(object, 3, 0, dst)
}

///|
fn emit_x64_movzx_r32_r8(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: movzx r32, r/m8.
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  if r != 0 || b != 0 || (src & 7) >= 4 {
    emit_x64_rex_if_needed(object, r, b)
  }
  object.code.push(0x0f)
  object.code.push(0xb6)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_cmp_imm32(object : CodeObject, lhs : Int, imm : Int) -> Unit {
  // Copied from legacy `vcode/emit/amd64_bytes`: cmp r/m64, imm32.
  emit_x64_rex_w(object, 0, (lhs >> 3) & 1)
  object.code.push(0x81)
  emit_x64_modrm(object, 3, 7, lhs)
  emit_u32_le(object, imm)
}

///|
fn emit_x64_cmovcc_rr(
  object : CodeObject,
  cond : @machv.Cond,
  dst : Int,
  src : Int,
) -> Unit {
  let cc = x64_jcc_opcode(cond) & 15
  emit_x64_rex_w(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x40 + cc)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_rex_if_needed(object : CodeObject, r : Int, b : Int) -> Unit {
  if r != 0 || b != 0 {
    object.code.push(0x40 | ((r & 1) << 2) | (b & 1))
  }
}

///|
fn emit_x64_load_base_disp32(
  object : CodeObject,
  dst : Int,
  base : Int,
  offset : Int,
  is_64 : Bool,
) -> Unit {
  let r = (dst >> 3) & 1
  let b = (base >> 3) & 1
  if is_64 {
    emit_x64_rex_w(object, r, b)
  } else {
    emit_x64_rex_if_needed(object, r, b)
  }
  object.code.push(0x8b)
  emit_x64_modrm(object, 2, dst, base)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_store_base_disp32(
  object : CodeObject,
  base : Int,
  src : Int,
  offset : Int,
  is_64 : Bool,
) -> Unit {
  let r = (src >> 3) & 1
  let b = (base >> 3) & 1
  if is_64 {
    emit_x64_rex_w(object, r, b)
  } else {
    emit_x64_rex_if_needed(object, r, b)
  }
  object.code.push(0x89)
  emit_x64_modrm(object, 2, src, base)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_load_narrow_base_disp32(
  object : CodeObject,
  dst : Int,
  base : Int,
  bits : Int,
  signed : Bool,
  offset : Int,
) -> Unit raise EmitError {
  let r = (dst >> 3) & 1
  let b = (base >> 3) & 1
  match (bits, signed) {
    (8, true) => {
      emit_x64_rex_w(object, r, b)
      object.code.push(0x0f)
      object.code.push(0xbe)
    }
    (8, false) => {
      emit_x64_rex_if_needed(object, r, b)
      object.code.push(0x0f)
      object.code.push(0xb6)
    }
    (16, true) => {
      emit_x64_rex_w(object, r, b)
      object.code.push(0x0f)
      object.code.push(0xbf)
    }
    (16, false) => {
      emit_x64_rex_if_needed(object, r, b)
      object.code.push(0x0f)
      object.code.push(0xb7)
    }
    (32, true) => {
      emit_x64_rex_w(object, r, b)
      object.code.push(0x63)
    }
    (32, false) => {
      emit_x64_rex_if_needed(object, r, b)
      object.code.push(0x8b)
    }
    _ =>
      raise UnsupportedOperand(
        message="X64 narrow load requires 8, 16, or 32-bit access",
      )
  }
  emit_x64_modrm(object, 2, dst, base)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_store_narrow_base_disp32(
  object : CodeObject,
  base : Int,
  src : Int,
  bits : Int,
  offset : Int,
) -> Unit raise EmitError {
  let r = (src >> 3) & 1
  let b = (base >> 3) & 1
  match bits {
    8 => {
      emit_x64_rex_if_needed(object, r, b)
      object.code.push(0x88)
    }
    16 => {
      object.code.push(0x66)
      emit_x64_rex_if_needed(object, r, b)
      object.code.push(0x89)
    }
    32 => {
      emit_x64_rex_if_needed(object, r, b)
      object.code.push(0x89)
    }
    _ =>
      raise UnsupportedOperand(
        message="X64 narrow store requires 8, 16, or 32-bit access",
      )
  }
  emit_x64_modrm(object, 2, src, base)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_float_load_base_disp32(
  object : CodeObject,
  dst : Int,
  base : Int,
  offset : Int,
  class : @machv.RegClass,
) -> Unit {
  object.code.push(if class == Float32 { 0xf3 } else { 0xf2 })
  emit_x64_rex_if_needed(object, (dst >> 3) & 1, (base >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x10)
  emit_x64_modrm(object, 2, dst, base)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_float_store_base_disp32(
  object : CodeObject,
  base : Int,
  src : Int,
  offset : Int,
  class : @machv.RegClass,
) -> Unit {
  object.code.push(if class == Float32 { 0xf3 } else { 0xf2 })
  emit_x64_rex_if_needed(object, (src >> 3) & 1, (base >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x11)
  emit_x64_modrm(object, 2, src, base)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_vector_load_base_disp32(
  object : CodeObject,
  dst : Int,
  base : Int,
  offset : Int,
) -> Unit {
  object.code.push(0xf3)
  emit_x64_rex_if_needed(object, (dst >> 3) & 1, (base >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x6f)
  emit_x64_modrm(object, 2, dst, base)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_vector_store_base_disp32(
  object : CodeObject,
  base : Int,
  src : Int,
  offset : Int,
) -> Unit {
  object.code.push(0xf3)
  emit_x64_rex_if_needed(object, (src >> 3) & 1, (base >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x7f)
  emit_x64_modrm(object, 2, src, base)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_vector_move(object : CodeObject, dst : Int, src : Int) -> Unit {
  object.code.push(0xf3)
  emit_x64_rex_if_needed(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x6f)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_int_stack_load(
  object : CodeObject,
  dst : Int,
  offset : Int,
) -> Unit {
  emit_x64_rex_w(object, (dst >> 3) & 1, 0)
  object.code.push(0x8b)
  emit_x64_modrm(object, 2, dst, 4)
  object.code.push(0x24)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_int_stack_store(
  object : CodeObject,
  src : Int,
  offset : Int,
) -> Unit {
  emit_x64_rex_w(object, (src >> 3) & 1, 0)
  object.code.push(0x89)
  emit_x64_modrm(object, 2, src, 4)
  object.code.push(0x24)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_float_stack_load(
  object : CodeObject,
  dst : Int,
  offset : Int,
) -> Unit {
  object.code.push(0xf2)
  emit_x64_rex_if_needed(object, (dst >> 3) & 1, 0)
  object.code.push(0x0f)
  object.code.push(0x10)
  emit_x64_modrm(object, 2, dst, 4)
  object.code.push(0x24)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_float_stack_store(
  object : CodeObject,
  src : Int,
  offset : Int,
) -> Unit {
  object.code.push(0xf2)
  emit_x64_rex_if_needed(object, (src >> 3) & 1, 0)
  object.code.push(0x0f)
  object.code.push(0x11)
  emit_x64_modrm(object, 2, src, 4)
  object.code.push(0x24)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_vector_stack_load(
  object : CodeObject,
  dst : Int,
  offset : Int,
) -> Unit {
  object.code.push(0xf3)
  emit_x64_rex_if_needed(object, (dst >> 3) & 1, 0)
  object.code.push(0x0f)
  object.code.push(0x6f)
  emit_x64_modrm(object, 2, dst, 4)
  object.code.push(0x24)
  emit_u32_le(object, offset)
}

///|
fn emit_x64_vector_stack_store(
  object : CodeObject,
  src : Int,
  offset : Int,
) -> Unit {
  object.code.push(0xf3)
  emit_x64_rex_if_needed(object, (src >> 3) & 1, 0)
  object.code.push(0x0f)
  object.code.push(0x7f)
  emit_x64_modrm(object, 2, src, 4)
  object.code.push(0x24)
  emit_u32_le(object, offset)
}

///|
fn x64_jcc_opcode(cond : @machv.Cond) -> Int {
  match cond {
    Eq => 0x84
    Ne => 0x85
    Lt => 0x8c
    Le => 0x8e
    Gt => 0x8f
    Ge => 0x8d
    Ult => 0x82
    Ule => 0x86
    Ugt => 0x87
    Uge => 0x83
    Mi => abort("x64_jcc_opcode: mi condition is AArch64-only")
    Parity => 0x8a
    NotParity => 0x8b
    Custom(name) =>
      abort("x64_jcc_opcode: unsupported custom condition \{name}")
  }
}

///|
fn aarch64_cond_bits(cond : @machv.Cond) -> Int {
  match cond {
    Eq => 0
    Ne => 1
    Uge => 2
    Ult => 3
    Ugt => 8
    Ule => 9
    Ge => 10
    Lt => 11
    Gt => 12
    Le => 13
    Mi => 4
    Parity | NotParity =>
      abort("aarch64_cond_bits: parity conditions are x64-only")
    Custom(name) =>
      abort("aarch64_cond_bits: unsupported custom condition \{name}")
  }
}

///|
fn emit_x64_jcc_rel32(object : CodeObject, cond : @machv.Cond) -> Unit {
  object.code.push(0x0f)
  object.code.push(x64_jcc_opcode(cond))
  emit_u32_le(object, 0)
}

///|
fn emit_x64_jmp_rel32(object : CodeObject) -> Unit {
  object.code.push(0xe9)
  emit_u32_le(object, 0)
}

///|
fn emit_x64_call_reg(object : CodeObject, reg : Int) -> Unit {
  emit_x64_rex_w(object, 0, (reg >> 3) & 1)
  object.code.push(0xff)
  emit_x64_modrm(object, 3, 2, reg)
}

///|
fn emit_aarch64_b_cond(object : CodeObject, cond : @machv.Cond) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: B.cond with patched imm19.
  emit_u32_le(object, 0x54000000 | aarch64_cond_bits(cond))
}

///|
fn emit_aarch64_cset(
  object : CodeObject,
  dst : Int,
  cond : @machv.Cond,
) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: CSET as CSINC.
  let inv_cond = aarch64_cond_bits(cond) ^ 1
  let b0 = (dst & 31) | 0xe0
  let b1 = 0x07 | ((inv_cond & 15) << 4) | 0x04
  emit_u32_le(object, b0 | (b1 << 8) | (159 << 16) | (154 << 24))
}

///|
fn emit_aarch64_csel(
  object : CodeObject,
  dst : Int,
  true_reg : Int,
  false_reg : Int,
  cond : @machv.Cond,
) -> Unit {
  emit_u32_le(
    object,
    (dst & 31) |
    ((true_reg & 7) << 5) |
    ((((true_reg >> 3) & 3) | ((aarch64_cond_bits(cond) & 15) << 4)) << 8) |
    (((false_reg & 31) | 128) << 16) |
    (154 << 24),
  )
}

///|
fn emit_aarch64_cbz(
  object : CodeObject,
  reg : Int,
  is_nonzero : Bool,
  is_64 : Bool,
) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: CBZ/CBNZ with patched imm19.
  let base = match (is_nonzero, is_64) {
    (false, true) => 0xb4000000
    (true, true) => 0xb5000000
    (false, false) => 0x34000000
    (true, false) => 0x35000000
  }
  emit_u32_le(object, base | (reg & 0x1f))
}

///|
fn emit_aarch64_cmp_rr(
  object : CodeObject,
  lhs : Int,
  rhs : Int,
  is_64 : Bool,
) -> Unit {
  // CMP is SUBS with XZR/WZR destination.
  let base = if is_64 { 0xeb00001f } else { 0x6b00001f }
  emit_u32_le(object, base | ((rhs & 0x1f) << 16) | ((lhs & 0x1f) << 5))
}

///|
fn emit_aarch64_fcmp_rr(
  object : CodeObject,
  lhs : Int,
  rhs : Int,
  class : @machv.RegClass,
) -> Unit {
  let b0 = (lhs & 7) << 5
  let b1 = ((lhs >> 3) & 3) | 0x20
  let b2 = match class {
    Float32 => 0x20 | (rhs & 31)
    Float64 => 0x60 | (rhs & 31)
    _ => abort("unreachable float compare class")
  }
  emit_u32_le(object, b0 | (b1 << 8) | (b2 << 16) | (0x1e << 24))
}

///|
fn emit_aarch64_fmov_d_to_x(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: FMOV Xd, Dn.
  emit_u32_le(
    object,
    (dst & 31) | ((src & 7) << 5) | (((src >> 3) & 3) << 8) | 0x9e660000,
  )
}

///|
fn emit_aarch64_fmov_s_to_w(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: FMOV Wd, Sn.
  emit_u32_le(
    object,
    (dst & 31) | ((src & 7) << 5) | (((src >> 3) & 3) << 8) | 0x1e260000,
  )
}

///|
fn emit_aarch64_fmov_x_to_d(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: FMOV Dd, Xn.
  emit_u32_le(
    object,
    (dst & 31) | ((src & 7) << 5) | (((src >> 3) & 3) << 8) | 0x9e670000,
  )
}

///|
fn emit_aarch64_fmov_w_to_s(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: FMOV Sd, Wn.
  emit_u32_le(
    object,
    (dst & 31) | ((src & 7) << 5) | (((src >> 3) & 3) << 8) | 0x1e270000,
  )
}

///|
fn emit_aarch64_fcvt_d_s(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: FCVT Dd, Sn.
  emit_u32_le(
    object,
    (dst & 31) |
    ((src & 7) << 5) |
    ((((src >> 3) & 3) | 0xc0) << 8) |
    0x1e220000,
  )
}

///|
fn emit_aarch64_fcvt_s_d(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: FCVT Sd, Dn.
  emit_u32_le(
    object,
    (dst & 31) |
    ((src & 7) << 5) |
    ((((src >> 3) & 3) | 0x40) << 8) |
    0x1e620000,
  )
}

///|
fn emit_aarch64_sxtb_x(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: SXTB Xd, Wn.
  emit_u32_le(
    object,
    (dst & 31) |
    ((src & 7) << 5) |
    ((((src >> 3) & 3) | 0x1c) << 8) |
    0x93400000,
  )
}

///|
fn emit_aarch64_sxth_x(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: SXTH Xd, Wn.
  emit_u32_le(
    object,
    (dst & 31) |
    ((src & 7) << 5) |
    ((((src >> 3) & 3) | 0x3c) << 8) |
    0x93400000,
  )
}

///|
fn emit_aarch64_sxtw(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: SXTW Xd, Wn.
  emit_u32_le(
    object,
    (dst & 31) |
    ((src & 7) << 5) |
    ((((src >> 3) & 3) | 0x7c) << 8) |
    0x93400000,
  )
}

///|
fn emit_aarch64_mov_w(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: MOV Wd, Wn.
  emit_u32_le(
    object,
    (dst & 31) |
    ((31 & 7) << 5) |
    (((31 >> 3) & 3) << 8) |
    ((src & 31) << 16) |
    (0x2a << 24),
  )
}

///|
fn emit_aarch64_vector_move(object : CodeObject, dst : Int, src : Int) -> Unit {
  emit_u32_le(
    object,
    0x4ea01c00 | ((src & 0x1f) << 16) | ((src & 0x1f) << 5) | (dst & 0x1f),
  )
}

///|
fn emit_aarch64_fmov_reg(
  object : CodeObject,
  dst : Int,
  src : Int,
  class : @machv.RegClass,
) -> Unit raise EmitError {
  let base = match class {
    Float32 => 0x1e204000
    Float64 => 0x1e604000
    _ =>
      raise UnsupportedOperand(
        message="AArch64 float move requires f32/f64 physical registers",
      )
  }
  emit_u32_le(object, base | ((src & 0x1f) << 5) | (dst & 0x1f))
}

///|
fn emit_aarch64_clz(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: CLZ Xd, Xn.
  emit_u32_le(
    object,
    (dst & 31) | ((src & 7) << 5) | (((src >> 3) & 3) << 8) | 0xdac01000,
  )
}

///|
fn emit_aarch64_rbit(object : CodeObject, dst : Int, src : Int) -> Unit {
  // Copied from legacy `vcode/emit/instructions_bytes`: RBIT Xd, Xn.
  emit_u32_le(
    object,
    (dst & 31) | ((src & 7) << 5) | (((src >> 3) & 3) << 8) | 0xdac00000,
  )
}

///|
fn emit_aarch64_cmp_imm(
  object : CodeObject,
  lhs : Int,
  imm : Int,
  is_64 : Bool,
) -> Unit raise EmitError {
  guard imm >= 0 && imm <= 0xfff else {
    raise UnsupportedOperand(
      message="AArch64 branch compare immediate requires an unsigned 12-bit immediate",
    )
  }
  // TODO(machv_emit): support shifted CMP immediates once target lowering preserves the immediate form.
  let base = if is_64 { 0xf100001f } else { 0x7100001f }
  emit_u32_le(object, base | ((imm & 0xfff) << 10) | ((lhs & 0x1f) << 5))
}

///|
fn emit_aarch64_b(object : CodeObject) -> Unit {
  emit_u32_le(object, 0x14000000)
}

///|
fn emit_aarch64_blr(object : CodeObject, reg : Int) -> Unit {
  emit_u32_le(object, 0xd63f0000 | ((reg & 0x1f) << 5))
}

///|
fn require_int_preg(
  operand : @machv.Operand,
  context : String,
) -> Int raise EmitError {
  match operand.reg {
    Physical(preg) =>
      if preg.class == Int && !preg.is_spilled() {
        preg.index
      } else {
        raise UnsupportedOperand(
          message="\{context} requires an integer physical register",
        )
      }
    Virtual(_) =>
      raise UnsupportedOperand(
        message="\{context} requires register allocation before emission",
      )
  }
}

///|
fn require_float_preg(
  operand : @machv.Operand,
  context : String,
) -> (Int, @machv.RegClass) raise EmitError {
  match operand.reg {
    Physical(preg) =>
      if (preg.class == Float32 || preg.class == Float64) && !preg.is_spilled() {
        (preg.index, preg.class)
      } else {
        raise UnsupportedOperand(
          message="\{context} requires a floating-point physical register",
        )
      }
    Virtual(_) =>
      raise UnsupportedOperand(
        message="\{context} requires register allocation before emission",
      )
  }
}

///|
fn require_physical_preg(
  operand : @machv.Operand,
  context : String,
) -> (Int, @machv.RegClass) raise EmitError {
  match operand.reg {
    Physical(preg) =>
      if !preg.is_spilled() {
        (preg.index, preg.class)
      } else {
        raise UnsupportedOperand(
          message="\{context} requires a non-spilled physical register",
        )
      }
    Virtual(_) =>
      raise UnsupportedOperand(
        message="\{context} requires register allocation before emission",
      )
  }
}

///|
fn require_same_float_class(
  lhs : @machv.RegClass,
  rhs : @machv.RegClass,
  context : String,
) -> Unit raise EmitError {
  guard lhs == rhs else {
    raise UnsupportedOperand(
      message="\{context} requires matching floating-point register classes",
    )
  }
}

///|
fn find_operand(
  inst : @machv.Instruction,
  role : @machv.OperandRole,
  index : Int,
  context : String,
) -> @machv.Operand raise EmitError {
  let mut seen = 0
  for operand in inst.operands {
    if operand.role == role {
      if seen == index {
        return operand
      }
      seen = seen + 1
    }
  }
  raise UnsupportedOperand(message="\{context} missing operand \{index}")
}

///|
fn emit_aarch64_move(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let (src, src_class) = require_physical_preg(
    find_operand(inst, Use, 0, "mov"),
    "mov source",
  )
  let (dst, dst_class) = require_physical_preg(
    find_operand(inst, Def, 0, "mov"),
    "mov destination",
  )
  guard src_class == dst_class else {
    raise UnsupportedOperand(message="mov requires matching register classes")
  }
  match dst_class {
    Int =>
      // TODO(machv_emit): choose 32-bit encodings from MachV value width.
      emit_u32_le(object, 0xaa0003e0 | (src << 16) | dst)
    Float32 | Float64 => emit_aarch64_fmov_reg(object, dst, src, dst_class)
    Vector => emit_aarch64_vector_move(object, dst, src)
  }
}

///|
fn emit_aarch64_int_add(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let lhs = require_int_preg(find_operand(inst, Use, 0, "add"), "add lhs")
  let rhs = require_int_preg(find_operand(inst, Use, 1, "add"), "add rhs")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "add"),
    "add destination",
  )
  // TODO(machv_emit): encode 32-bit integer adds and immediate forms once MachV carries lane width/legalization info.
  emit_u32_le(object, 0x8b000000 | (rhs << 16) | (lhs << 5) | dst)
}

///|
fn emit_aarch64_int_binop3(
  object : CodeObject,
  inst : @machv.Instruction,
  base : Int,
  context : String,
) -> Unit raise EmitError {
  let lhs = require_int_preg(
    find_operand(inst, Use, 0, context),
    "\{context} lhs",
  )
  let rhs = require_int_preg(
    find_operand(inst, Use, 1, context),
    "\{context} rhs",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  // TODO(machv_emit): encode 32-bit and immediate/legalized forms once MachV carries lane width.
  emit_u32_le(
    object,
    base | ((rhs & 0x1f) << 16) | ((lhs & 0x1f) << 5) | (dst & 0x1f),
  )
}

///|
fn emit_aarch64_int_mul(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let lhs = require_int_preg(find_operand(inst, Use, 0, "mul"), "mul lhs")
  let rhs = require_int_preg(find_operand(inst, Use, 1, "mul"), "mul rhs")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "mul"),
    "mul destination",
  )
  // Copied from legacy `vcode/emit/instructions_bytes`: MUL as MADD rd, rn, rm, xzr.
  emit_u32_le(
    object,
    0x9b000000 |
    ((rhs & 0x1f) << 16) |
    (31 << 10) |
    ((lhs & 0x1f) << 5) |
    (dst & 0x1f),
  )
}

///|
fn emit_aarch64_int_not(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let src = require_int_preg(find_operand(inst, Use, 0, "not"), "not source")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "not"),
    "not destination",
  )
  // TODO(machv_emit): encode 32-bit integer not once MachV carries lane width.
  emit_u32_le(
    object,
    (dst & 31) |
    ((31 & 7) << 5) |
    (((31 >> 3) & 3) << 8) |
    (((src & 31) | 32) << 16) |
    (170 << 24),
  )
}

///|
fn emit_aarch64_int_cmp(
  object : CodeObject,
  inst : @machv.Instruction,
  cond : @machv.Cond,
) -> Unit raise EmitError {
  let lhs = require_int_preg(find_operand(inst, Use, 0, "cmp"), "cmp lhs")
  let rhs = require_int_preg(find_operand(inst, Use, 1, "cmp"), "cmp rhs")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "cmp"),
    "cmp destination",
  )
  // TODO(machv_emit): encode 32-bit comparisons once MachV carries lane width.
  emit_aarch64_cmp_rr(object, lhs, rhs, true)
  emit_aarch64_cset(object, dst, cond)
}

///|
fn emit_aarch64_float_cmp(
  object : CodeObject,
  inst : @machv.Instruction,
  cond : @machv.Cond,
) -> Unit raise EmitError {
  let (lhs, lhs_class) = require_float_preg(
    find_operand(inst, Use, 0, "fcmp"),
    "fcmp lhs",
  )
  let (rhs, rhs_class) = require_float_preg(
    find_operand(inst, Use, 1, "fcmp"),
    "fcmp rhs",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "fcmp"),
    "fcmp destination",
  )
  require_same_float_class(lhs_class, rhs_class, "fcmp")
  // AArch64 FCMP reports unordered operands as NZCV=0011. The condition mapping
  // matches WebAssembly ordered comparisons, with Ne intentionally true for NaN.
  emit_aarch64_fcmp_rr(object, lhs, rhs, lhs_class)
  emit_aarch64_cset(object, dst, cond)
}

///|
fn emit_aarch64_int_clz(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let src = require_int_preg(find_operand(inst, Use, 0, "clz"), "clz source")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "clz"),
    "clz destination",
  )
  // TODO(machv_emit): encode 32-bit CLZ once MachV carries lane width.
  emit_aarch64_clz(object, dst, src)
}

///|
fn emit_aarch64_int_ctz(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let src = require_int_preg(find_operand(inst, Use, 0, "ctz"), "ctz source")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "ctz"),
    "ctz destination",
  )
  // TODO(machv_emit): encode 32-bit CTZ once MachV carries lane width.
  emit_aarch64_rbit(object, dst, src)
  emit_aarch64_clz(object, dst, dst)
}

///|
fn emit_aarch64_int_shift(
  object : CodeObject,
  inst : @machv.Instruction,
  kind : Int,
  context : String,
) -> Unit raise EmitError {
  let value = require_int_preg(
    find_operand(inst, Use, 0, context),
    "\{context} value",
  )
  let count = require_int_preg(
    find_operand(inst, Use, 1, context),
    "\{context} count",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  // TODO(machv_emit): encode 32-bit shifts once MachV carries lane width.
  emit_u32_le(
    object,
    (dst & 31) |
    ((value & 7) << 5) |
    (((value >> 3) & 3) << 8) |
    ((kind & 15) << 10) |
    ((0xc0 | (count & 31)) << 16) |
    (0x9a << 24),
  )
}

///|
fn emit_aarch64_int_mul_high(
  object : CodeObject,
  inst : @machv.Instruction,
  signed : Bool,
) -> Unit raise EmitError {
  let context = if signed { "smulh" } else { "umulh" }
  let lhs = require_int_preg(
    find_operand(inst, Use, 0, context),
    "\{context} lhs",
  )
  let rhs = require_int_preg(
    find_operand(inst, Use, 1, context),
    "\{context} rhs",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  // TODO(machv_emit): encode 32-bit multiply-high lowering once MachV carries lane width.
  emit_u32_le(
    object,
    (dst & 31) |
    ((lhs & 7) << 5) |
    ((((lhs >> 3) & 3) | 0x7c) << 8) |
    (((if signed { 0x40 } else { 0xc0 }) | (rhs & 31)) << 16) |
    (0x9b << 24),
  )
}

///|
fn emit_aarch64_bitcast(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let (src, src_class) = require_physical_preg(
    find_operand(inst, Use, 0, "bitcast"),
    "bitcast source",
  )
  let (dst, dst_class) = require_physical_preg(
    find_operand(inst, Def, 0, "bitcast"),
    "bitcast destination",
  )
  match (src_class, dst_class) {
    (Int, Float64) => emit_aarch64_fmov_x_to_d(object, dst, src)
    (Float64, Int) => emit_aarch64_fmov_d_to_x(object, dst, src)
    (Int, Float32) => emit_aarch64_fmov_w_to_s(object, dst, src)
    (Float32, Int) => emit_aarch64_fmov_s_to_w(object, dst, src)
    _ =>
      raise UnsupportedOperand(
        message="bitcast requires int<->f32/f64 physical registers",
      )
  }
}

///|
fn emit_aarch64_sign_extend(
  object : CodeObject,
  inst : @machv.Instruction,
  from_bits : Int,
) -> Unit raise EmitError {
  let src = require_int_preg(
    find_operand(inst, Use, 0, "sextend"),
    "sextend source",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "sextend"),
    "sextend destination",
  )
  // TODO(machv_emit): choose W-result encodings once MachV carries lane width.
  match from_bits {
    8 => emit_aarch64_sxtb_x(object, dst, src)
    16 => emit_aarch64_sxth_x(object, dst, src)
    32 => emit_aarch64_sxtw(object, dst, src)
    _ => abort("unreachable sign-extension width")
  }
}

///|
fn emit_aarch64_zero_extend32(
  object : CodeObject,
  inst : @machv.Instruction,
  context : String,
) -> Unit raise EmitError {
  let src = require_int_preg(
    find_operand(inst, Use, 0, context),
    "\{context} source",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  // TODO(machv_emit): generalize integer width conversions once MachV carries
  // source and destination lane widths instead of only a generic Int class.
  emit_aarch64_mov_w(object, dst, src)
}

///|
fn emit_aarch64_select(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let cond = require_int_preg(
    find_operand(inst, Use, 0, "select"),
    "select condition",
  )
  let true_reg = require_int_preg(
    find_operand(inst, Use, 1, "select"),
    "select true value",
  )
  let false_reg = require_int_preg(
    find_operand(inst, Use, 2, "select"),
    "select false value",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "select"),
    "select destination",
  )
  // TODO(machv_emit): add Float32/Float64 FCSEL and vector select emission once
  // MachV select carries result class-specific lowering metadata.
  emit_aarch64_cmp_imm(object, cond, 0, false)
  emit_aarch64_csel(object, dst, true_reg, false_reg, Ne)
}

///|
fn emit_aarch64_float_width_convert(
  object : CodeObject,
  inst : @machv.Instruction,
  promote : Bool,
) -> Unit raise EmitError {
  let context = if promote { "fpromote" } else { "fdemote" }
  let (src, src_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} source",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  match (promote, src_class, dst_class) {
    (true, Float32, Float64) => emit_aarch64_fcvt_d_s(object, dst, src)
    (false, Float64, Float32) => emit_aarch64_fcvt_s_d(object, dst, src)
    _ =>
      raise UnsupportedOperand(
        message="\{context} requires f32->f64 or f64->f32 registers",
      )
  }
}

///|
fn emit_aarch64_movz(
  object : CodeObject,
  rd : Int,
  imm16 : Int,
  shift : Int,
) -> Unit {
  emit_u32_le(
    object,
    0xd2800000 | ((shift / 16) << 21) | ((imm16 & 0xffff) << 5) | (rd & 0x1f),
  )
}

///|
fn emit_aarch64_movn(
  object : CodeObject,
  rd : Int,
  imm16 : Int,
  shift : Int,
) -> Unit {
  emit_u32_le(
    object,
    0x92800000 | ((shift / 16) << 21) | ((imm16 & 0xffff) << 5) | (rd & 0x1f),
  )
}

///|
fn emit_aarch64_movk(
  object : CodeObject,
  rd : Int,
  imm16 : Int,
  shift : Int,
) -> Unit {
  emit_u32_le(
    object,
    0xf2800000 | ((shift / 16) << 21) | ((imm16 & 0xffff) << 5) | (rd & 0x1f),
  )
}

///|
fn emit_aarch64_int_const(
  object : CodeObject,
  inst : @machv.Instruction,
  imm : Int64,
) -> Unit raise EmitError {
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "iconst"),
    "iconst destination",
  )
  let halfwords = FixedArray::make(4, 0)
  for i in 0..<4 {
    halfwords[i] = ((imm >> (i * 16)) & 0xffffL).to_int()
  }
  let mut non_zero = 0
  let mut non_ffff = 0
  for i in 0..<4 {
    if halfwords[i] != 0 {
      non_zero = non_zero + 1
    }
    if halfwords[i] != 0xffff {
      non_ffff = non_ffff + 1
    }
  }
  let movz_count = if non_zero == 0 { 1 } else { non_zero }
  let movn_count = if non_ffff == 0 { 1 } else { non_ffff }
  if movn_count < movz_count {
    if non_ffff == 0 {
      emit_aarch64_movn(object, dst, 0, 0)
    } else {
      let mut first = 0
      while first < 4 && halfwords[first] == 0xffff {
        first = first + 1
      }
      emit_aarch64_movn(object, dst, halfwords[first] ^ 0xffff, first * 16)
      for i in 0..<4 {
        if i != first && halfwords[i] != 0xffff {
          emit_aarch64_movk(object, dst, halfwords[i], i * 16)
        }
      }
    }
  } else if non_zero == 0 {
    emit_aarch64_movz(object, dst, 0, 0)
  } else {
    let mut first = 0
    while first < 4 && halfwords[first] == 0 {
      first = first + 1
    }
    emit_aarch64_movz(object, dst, halfwords[first], first * 16)
    for i in 0..<4 {
      if i != first && halfwords[i] != 0 {
        emit_aarch64_movk(object, dst, halfwords[i], i * 16)
      }
    }
  }
}

///|
fn mem_access_scale(mem_type : @machv.MemType) -> Int {
  match mem_type {
    MemI32 | MemF32 => 4
    MemI64 | MemF64 | MemPtr => 8
    MemV128 => 16
  }
}

///|
fn mem_access_is_64(mem_type : @machv.MemType) -> Bool raise EmitError {
  match mem_type {
    MemI32 => false
    MemI64 | MemPtr => true
    _ =>
      raise UnsupportedOperand(
        message="machv_emit integer memory access requires i32, i64, or ptr",
      )
  }
}

///|
fn float_class_for_mem_type(mem_type : @machv.MemType) -> @machv.RegClass? {
  match mem_type {
    MemF32 => Some(Float32)
    MemF64 => Some(Float64)
    _ => None
  }
}

///|
fn emit_aarch64_load_ptr(
  object : CodeObject,
  inst : @machv.Instruction,
  mem_type : @machv.MemType,
  offset : Int,
) -> Unit raise EmitError {
  let base_reg = require_int_preg(
    find_operand(inst, Use, 0, "load_ptr"),
    "load_ptr base",
  )
  let scale = mem_access_scale(mem_type)
  guard offset >= 0 && offset % scale == 0 && offset / scale <= 0xfff else {
    raise UnsupportedOperand(
      message="AArch64 load_ptr requires a non-negative scaled unsigned 12-bit offset",
    )
  }
  let imm12 = offset / scale
  match float_class_for_mem_type(mem_type) {
    Some(expected_class) => {
      let (dst, dst_class) = require_float_preg(
        find_operand(inst, Def, 0, "load_ptr"),
        "load_ptr destination",
      )
      require_same_float_class(dst_class, expected_class, "load_ptr")
      let base = if expected_class == Float32 { 0xbd400000 } else { 0xfd400000 }
      emit_u32_le(
        object,
        base | ((imm12 & 0xfff) << 10) | ((base_reg & 0x1f) << 5) | (dst & 0x1f),
      )
    }
    None => {
      if mem_type == MemV128 {
        let (dst, dst_class) = require_physical_preg(
          find_operand(inst, Def, 0, "load_ptr"),
          "load_ptr destination",
        )
        if dst_class != Vector {
          raise UnsupportedOperand(
            message="AArch64 v128 load requires a vector destination",
          )
        }
        let base = 0x3dc00000
        emit_u32_le(
          object,
          base |
          ((imm12 & 0xfff) << 10) |
          ((base_reg & 0x1f) << 5) |
          (dst & 0x1f),
        )
        return
      }
      let dst = require_int_preg(
        find_operand(inst, Def, 0, "load_ptr"),
        "load_ptr destination",
      )
      let base = if mem_access_is_64(mem_type) {
        0xf9400000
      } else {
        0xb9400000
      }
      emit_u32_le(
        object,
        base | ((imm12 & 0xfff) << 10) | ((base_reg & 0x1f) << 5) | (dst & 0x1f),
      )
    }
  }
}

///|
fn emit_aarch64_store_ptr(
  object : CodeObject,
  inst : @machv.Instruction,
  mem_type : @machv.MemType,
  offset : Int,
) -> Unit raise EmitError {
  let base_reg = require_int_preg(
    find_operand(inst, Use, 0, "store_ptr"),
    "store_ptr base",
  )
  let scale = mem_access_scale(mem_type)
  guard offset >= 0 && offset % scale == 0 && offset / scale <= 0xfff else {
    raise UnsupportedOperand(
      message="AArch64 store_ptr requires a non-negative scaled unsigned 12-bit offset",
    )
  }
  let imm12 = offset / scale
  match float_class_for_mem_type(mem_type) {
    Some(expected_class) => {
      let (src, src_class) = require_float_preg(
        find_operand(inst, Use, 1, "store_ptr"),
        "store_ptr source",
      )
      require_same_float_class(src_class, expected_class, "store_ptr")
      let base = if expected_class == Float32 { 0xbd000000 } else { 0xfd000000 }
      emit_u32_le(
        object,
        base | ((imm12 & 0xfff) << 10) | ((base_reg & 0x1f) << 5) | (src & 0x1f),
      )
    }
    None => {
      if mem_type == MemV128 {
        let (src, src_class) = require_physical_preg(
          find_operand(inst, Use, 1, "store_ptr"),
          "store_ptr source",
        )
        if src_class != Vector {
          raise UnsupportedOperand(
            message="AArch64 v128 store requires a vector source",
          )
        }
        let base = 0x3d800000
        emit_u32_le(
          object,
          base |
          ((imm12 & 0xfff) << 10) |
          ((base_reg & 0x1f) << 5) |
          (src & 0x1f),
        )
        return
      }
      let src = require_int_preg(
        find_operand(inst, Use, 1, "store_ptr"),
        "store_ptr source",
      )
      let base = if mem_access_is_64(mem_type) {
        0xf9000000
      } else {
        0xb9000000
      }
      emit_u32_le(
        object,
        base | ((imm12 & 0xfff) << 10) | ((base_reg & 0x1f) << 5) | (src & 0x1f),
      )
    }
  }
}

///|
fn emit_aarch64_load_ptr_narrow(
  object : CodeObject,
  inst : @machv.Instruction,
  bits : Int,
  signed : Bool,
  offset : Int,
) -> Unit raise EmitError {
  let base_reg = require_int_preg(
    find_operand(inst, Use, 0, "load_ptr_narrow"),
    "load_ptr_narrow base",
  )
  let scale = match bits {
    8 => 1
    16 => 2
    32 => 4
    _ =>
      raise UnsupportedOperand(
        message="AArch64 narrow load requires 8, 16, or 32-bit access",
      )
  }
  guard offset >= 0 && offset % scale == 0 && offset / scale <= 0xfff else {
    raise UnsupportedOperand(
      message="AArch64 narrow load requires a non-negative scaled unsigned 12-bit offset",
    )
  }
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "load_ptr_narrow"),
    "load_ptr_narrow destination",
  )
  let imm12 = offset / scale
  let base = match (bits, signed) {
    (8, true) => 0x39800000
    (8, false) => 0x39400000
    (16, true) => 0x79800000
    (16, false) => 0x79400000
    (32, true) => 0xb9800000
    (32, false) => 0xb9400000
    _ =>
      raise UnsupportedOperand(
        message="AArch64 narrow load requires 8, 16, or 32-bit access",
      )
  }
  emit_u32_le(
    object,
    base | ((imm12 & 0xfff) << 10) | ((base_reg & 0x1f) << 5) | (dst & 0x1f),
  )
}

///|
fn emit_aarch64_store_ptr_narrow(
  object : CodeObject,
  inst : @machv.Instruction,
  bits : Int,
  offset : Int,
) -> Unit raise EmitError {
  let base_reg = require_int_preg(
    find_operand(inst, Use, 0, "store_ptr_narrow"),
    "store_ptr_narrow base",
  )
  let scale = match bits {
    8 => 1
    16 => 2
    32 => 4
    _ =>
      raise UnsupportedOperand(
        message="AArch64 narrow store requires 8, 16, or 32-bit access",
      )
  }
  guard offset >= 0 && offset % scale == 0 && offset / scale <= 0xfff else {
    raise UnsupportedOperand(
      message="AArch64 narrow store requires a non-negative scaled unsigned 12-bit offset",
    )
  }
  let src = require_int_preg(
    find_operand(inst, Use, 1, "store_ptr_narrow"),
    "store_ptr_narrow source",
  )
  let imm12 = offset / scale
  let base = match bits {
    8 => 0x39000000
    16 => 0x79000000
    32 => 0xb9000000
    _ =>
      raise UnsupportedOperand(
        message="AArch64 narrow store requires 8, 16, or 32-bit access",
      )
  }
  emit_u32_le(
    object,
    base | ((imm12 & 0xfff) << 10) | ((base_reg & 0x1f) << 5) | (src & 0x1f),
  )
}

///|
fn require_scaled_stack_offset(
  offset : Int,
  scale : Int,
  context : String,
) -> Int raise EmitError {
  guard offset >= 0 && offset % scale == 0 && offset / scale <= 0xfff else {
    raise UnsupportedOperand(
      message="\{context} requires a non-negative scaled unsigned 12-bit stack offset",
    )
  }
  offset / scale
}

///|
fn emit_aarch64_stack_load(
  object : CodeObject,
  inst : @machv.Instruction,
  slot : @machv.StackSlot,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  let (dst, dst_class) = require_physical_preg(
    find_operand(inst, Def, 0, "stack load"),
    "stack load destination",
  )
  let offset = frame.get_spill_offset(slot.id)
  match dst_class {
    Int => {
      let imm12 = require_scaled_stack_offset(offset, 8, "AArch64 stack load")
      emit_u32_le(
        object,
        0xf9400000 | ((imm12 & 0xfff) << 10) | (31 << 5) | (dst & 0x1f),
      )
    }
    Float32 | Float64 => {
      let imm12 = require_scaled_stack_offset(
        offset, 8, "AArch64 float stack load",
      )
      emit_u32_le(
        object,
        0xfd400000 | ((imm12 & 0xfff) << 10) | (31 << 5) | (dst & 0x1f),
      )
    }
    Vector => {
      let imm12 = require_scaled_stack_offset(
        offset, 16, "AArch64 vector stack load",
      )
      emit_u32_le(
        object,
        0x3dc00000 | ((imm12 & 0xfff) << 10) | (31 << 5) | (dst & 0x1f),
      )
    }
  }
}

///|
fn emit_aarch64_stack_store(
  object : CodeObject,
  inst : @machv.Instruction,
  slot : @machv.StackSlot,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  let (src, src_class) = require_physical_preg(
    find_operand(inst, Use, 0, "stack store"),
    "stack store source",
  )
  let offset = frame.get_spill_offset(slot.id)
  match src_class {
    Int => {
      let imm12 = require_scaled_stack_offset(offset, 8, "AArch64 stack store")
      emit_u32_le(
        object,
        0xf9000000 | ((imm12 & 0xfff) << 10) | (31 << 5) | (src & 0x1f),
      )
    }
    Float32 | Float64 => {
      let imm12 = require_scaled_stack_offset(
        offset, 8, "AArch64 float stack store",
      )
      emit_u32_le(
        object,
        0xfd000000 | ((imm12 & 0xfff) << 10) | (31 << 5) | (src & 0x1f),
      )
    }
    Vector => {
      let imm12 = require_scaled_stack_offset(
        offset, 16, "AArch64 vector stack store",
      )
      emit_u32_le(
        object,
        0x3d800000 | ((imm12 & 0xfff) << 10) | (31 << 5) | (src & 0x1f),
      )
    }
  }
}

///|
fn emit_aarch64_outgoing_arg_store(
  object : CodeObject,
  src : Int,
  src_class : @machv.RegClass,
  offset : Int,
) -> Unit raise EmitError {
  match src_class {
    Int => {
      let imm12 = require_scaled_stack_offset(
        offset, 8, "AArch64 outgoing stack argument store",
      )
      emit_u32_le(
        object,
        0xf9000000 | ((imm12 & 0xfff) << 10) | (31 << 5) | (src & 0x1f),
      )
    }
    Float32 | Float64 => {
      let imm12 = require_scaled_stack_offset(
        offset, 8, "AArch64 outgoing float stack argument store",
      )
      emit_u32_le(
        object,
        0xfd000000 | ((imm12 & 0xfff) << 10) | (31 << 5) | (src & 0x1f),
      )
    }
    Vector => {
      let imm12 = require_scaled_stack_offset(
        offset, 16, "AArch64 outgoing vector stack argument store",
      )
      emit_u32_le(
        object,
        0x3d800000 | ((imm12 & 0xfff) << 10) | (31 << 5) | (src & 0x1f),
      )
    }
  }
}

///|
fn emit_aarch64_outgoing_arg_stores(
  object : CodeObject,
  inst : @machv.Instruction,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  for operand_index, location in inst.abi_arg_locations {
    if location is Stack(offset~, ..) {
      let (src, src_class) = require_physical_preg(
        find_operand(inst, Use, operand_index, "outgoing stack argument"),
        "outgoing stack argument source",
      )
      emit_aarch64_outgoing_arg_store(
        object,
        src,
        src_class,
        frame.get_outgoing_arg_offset(offset),
      )
    }
  }
}

///|
fn emit_aarch64_call_ptr(
  object : CodeObject,
  inst : @machv.Instruction,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  emit_aarch64_outgoing_arg_stores(object, inst, frame)
  let target = require_int_preg(
    find_operand(inst, Use, 0, "call_ptr"),
    "call_ptr target",
  )
  emit_aarch64_blr(object, target)
}

///|
fn emit_aarch64_sp_adjust(
  object : CodeObject,
  frame_size : Int,
  subtract : Bool,
) -> Unit raise EmitError {
  if frame_size == 0 {
    return
  }
  guard frame_size >= 0 && frame_size <= 0xfff else {
    raise UnsupportedOperand(
      message="AArch64 frame size requires unsigned 12-bit SP adjustment",
    )
  }
  let base = if subtract { 0xd10003ff } else { 0x910003ff }
  emit_u32_le(object, base | ((frame_size & 0xfff) << 10))
}

///|
fn emit_aarch64_save_restore_gpr(
  object : CodeObject,
  reg : Int,
  offset : Int,
  save : Bool,
) -> Unit raise EmitError {
  let imm12 = require_scaled_stack_offset(offset, 8, "AArch64 callee-save GPR")
  let base = if save { 0xf9000000 } else { 0xf9400000 }
  emit_u32_le(object, base | ((imm12 & 0xfff) << 10) | (31 << 5) | (reg & 0x1f))
}

///|
fn emit_aarch64_save_restore_fpr(
  object : CodeObject,
  reg : Int,
  offset : Int,
  save : Bool,
) -> Unit raise EmitError {
  let imm12 = require_scaled_stack_offset(offset, 8, "AArch64 callee-save FPR")
  let base = if save { 0xfd000000 } else { 0xfd400000 }
  emit_u32_le(object, base | ((imm12 & 0xfff) << 10) | (31 << 5) | (reg & 0x1f))
}

///|
fn emit_aarch64_prologue(
  object : CodeObject,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  emit_aarch64_sp_adjust(object, frame.frame_size, true)
  for reg in frame.saved_gprs {
    emit_aarch64_save_restore_gpr(
      object,
      reg,
      frame.get_gpr_save_offset(reg),
      true,
    )
  }
  for reg in frame.saved_fprs {
    emit_aarch64_save_restore_fpr(
      object,
      reg,
      frame.get_fpr_save_offset(reg),
      true,
    )
  }
}

///|
fn emit_aarch64_epilogue(
  object : CodeObject,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  for offset in 0..<frame.saved_fprs.length() {
    let i = frame.saved_fprs.length() - 1 - offset
    let reg = frame.saved_fprs[i]
    emit_aarch64_save_restore_fpr(
      object,
      reg,
      frame.get_fpr_save_offset(reg),
      false,
    )
  }
  for offset in 0..<frame.saved_gprs.length() {
    let i = frame.saved_gprs.length() - 1 - offset
    let reg = frame.saved_gprs[i]
    emit_aarch64_save_restore_gpr(
      object,
      reg,
      frame.get_gpr_save_offset(reg),
      false,
    )
  }
  emit_aarch64_sp_adjust(object, frame.frame_size, false)
}

///|
fn emit_aarch64_stack_addr(
  object : CodeObject,
  inst : @machv.Instruction,
  slot_id : Int,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "stack_addr"),
    "stack_addr destination",
  )
  let offset = frame.get_spill_offset(slot_id)
  guard offset >= 0 && offset <= 0xfff else {
    raise UnsupportedOperand(
      message="AArch64 stack_addr requires a non-negative unsigned 12-bit stack offset",
    )
  }
  emit_u32_le(object, 0x91000000 | ((offset & 0xfff) << 10) | (31 << 5) | dst)
}

///|
fn emit_aarch64_float_binop3(
  object : CodeObject,
  inst : @machv.Instruction,
  f32_mid : Int,
  f64_mid : Int,
  context : String,
) -> Unit raise EmitError {
  let (lhs, lhs_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} lhs",
  )
  let (rhs, rhs_class) = require_float_preg(
    find_operand(inst, Use, 1, context),
    "\{context} rhs",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  require_same_float_class(dst_class, lhs_class, context)
  require_same_float_class(dst_class, rhs_class, context)
  let mid = match dst_class {
    Float32 => f32_mid
    Float64 => f64_mid
    _ => abort("unreachable float class")
  }
  emit_u32_le(
    object,
    (dst & 31) |
    ((lhs & 7) << 5) |
    (((lhs >> 3) & 3) << 8) |
    (mid << 8) |
    ((rhs & 31) << 16) |
    (0x1e << 24),
  )
}

///|
fn emit_aarch64_float_unop(
  object : CodeObject,
  inst : @machv.Instruction,
  f32_mid : Int,
  f64_mid : Int,
  context : String,
) -> Unit raise EmitError {
  let (src, src_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} source",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  require_same_float_class(dst_class, src_class, context)
  let mid = match dst_class {
    Float32 => f32_mid
    Float64 => f64_mid
    _ => abort("unreachable float class")
  }
  emit_u32_le(
    object,
    (dst & 31) |
    ((src & 7) << 5) |
    (((src >> 3) & 3) << 8) |
    (mid << 8) |
    (0x1e << 24),
  )
}

///|
fn emit_aarch64_float_round(
  object : CodeObject,
  inst : @machv.Instruction,
  f32_b1_base : Int,
  f32_b2 : Int,
  f64_b1_base : Int,
  f64_b2 : Int,
  context : String,
) -> Unit raise EmitError {
  let (src, src_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} source",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  require_same_float_class(dst_class, src_class, context)
  let (b1_base, b2) = match dst_class {
    Float32 => (f32_b1_base, f32_b2)
    Float64 => (f64_b1_base, f64_b2)
    _ => abort("unreachable float class")
  }
  emit_u32_le(
    object,
    (dst & 31) |
    ((src & 7) << 5) |
    ((((src >> 3) & 3) | b1_base) << 8) |
    (b2 << 16) |
    (0x1e << 24),
  )
}

///|
fn emit_x64_move(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let (src, src_class) = require_physical_preg(
    find_operand(inst, Use, 0, "mov"),
    "mov source",
  )
  let (dst, dst_class) = require_physical_preg(
    find_operand(inst, Def, 0, "mov"),
    "mov destination",
  )
  guard src_class == dst_class else {
    raise UnsupportedOperand(message="mov requires matching register classes")
  }
  match dst_class {
    Int =>
      // TODO(machv_emit): choose 32-bit encodings from MachV value width.
      emit_x64_mov_rr(object, dst, src)
    Float32 | Float64 => emit_x64_float_move(object, dst, src, dst_class)
    Vector => emit_x64_vector_move(object, dst, src)
  }
}

///|
fn emit_x64_int_add(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let lhs = require_int_preg(find_operand(inst, Use, 0, "add"), "add lhs")
  let rhs = require_int_preg(find_operand(inst, Use, 1, "add"), "add rhs")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "add"),
    "add destination",
  )
  // TODO(machv_emit): replace this copy-first lowering with an X64 legalization pass that can pick two-address forms before emission.
  if dst != lhs {
    emit_x64_mov_rr(object, dst, lhs)
  }
  emit_x64_add_rr(object, dst, rhs)
}

///|
fn emit_x64_int_binop3(
  object : CodeObject,
  inst : @machv.Instruction,
  emit_rr : (CodeObject, Int, Int) -> Unit,
  context : String,
) -> Unit raise EmitError {
  let lhs = require_int_preg(
    find_operand(inst, Use, 0, context),
    "\{context} lhs",
  )
  let rhs = require_int_preg(
    find_operand(inst, Use, 1, context),
    "\{context} rhs",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  // TODO(machv_emit): replace this copy-first lowering with an X64 legalization pass that can pick two-address forms before emission.
  if dst != lhs {
    emit_x64_mov_rr(object, dst, lhs)
  }
  emit_rr(object, dst, rhs)
}

///|
fn emit_x64_int_const(
  object : CodeObject,
  inst : @machv.Instruction,
  imm : Int64,
) -> Unit raise EmitError {
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "iconst"),
    "iconst destination",
  )
  emit_x64_mov_imm64(object, dst, imm)
}

///|
fn emit_x64_load_ptr(
  object : CodeObject,
  inst : @machv.Instruction,
  mem_type : @machv.MemType,
  offset : Int,
) -> Unit raise EmitError {
  let base = require_int_preg(
    find_operand(inst, Use, 0, "load_ptr"),
    "load_ptr base",
  )
  match float_class_for_mem_type(mem_type) {
    Some(expected_class) => {
      let (dst, dst_class) = require_float_preg(
        find_operand(inst, Def, 0, "load_ptr"),
        "load_ptr destination",
      )
      require_same_float_class(dst_class, expected_class, "load_ptr")
      emit_x64_float_load_base_disp32(object, dst, base, offset, expected_class)
    }
    None => {
      if mem_type == MemV128 {
        let (dst, dst_class) = require_physical_preg(
          find_operand(inst, Def, 0, "load_ptr"),
          "load_ptr destination",
        )
        if dst_class != Vector {
          raise UnsupportedOperand(
            message="X64 v128 load requires a vector destination",
          )
        }
        emit_x64_vector_load_base_disp32(object, dst, base, offset)
        return
      }
      let dst = require_int_preg(
        find_operand(inst, Def, 0, "load_ptr"),
        "load_ptr destination",
      )
      emit_x64_load_base_disp32(
        object,
        dst,
        base,
        offset,
        mem_access_is_64(mem_type),
      )
    }
  }
}

///|
fn emit_x64_store_ptr(
  object : CodeObject,
  inst : @machv.Instruction,
  mem_type : @machv.MemType,
  offset : Int,
) -> Unit raise EmitError {
  let base = require_int_preg(
    find_operand(inst, Use, 0, "store_ptr"),
    "store_ptr base",
  )
  match float_class_for_mem_type(mem_type) {
    Some(expected_class) => {
      let (src, src_class) = require_float_preg(
        find_operand(inst, Use, 1, "store_ptr"),
        "store_ptr source",
      )
      require_same_float_class(src_class, expected_class, "store_ptr")
      emit_x64_float_store_base_disp32(
        object, base, src, offset, expected_class,
      )
    }
    None => {
      if mem_type == MemV128 {
        let (src, src_class) = require_physical_preg(
          find_operand(inst, Use, 1, "store_ptr"),
          "store_ptr source",
        )
        if src_class != Vector {
          raise UnsupportedOperand(
            message="X64 v128 store requires a vector source",
          )
        }
        emit_x64_vector_store_base_disp32(object, base, src, offset)
        return
      }
      let src = require_int_preg(
        find_operand(inst, Use, 1, "store_ptr"),
        "store_ptr source",
      )
      emit_x64_store_base_disp32(
        object,
        base,
        src,
        offset,
        mem_access_is_64(mem_type),
      )
    }
  }
}

///|
fn emit_x64_load_ptr_narrow(
  object : CodeObject,
  inst : @machv.Instruction,
  bits : Int,
  signed : Bool,
  offset : Int,
) -> Unit raise EmitError {
  let base = require_int_preg(
    find_operand(inst, Use, 0, "load_ptr_narrow"),
    "load_ptr_narrow base",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "load_ptr_narrow"),
    "load_ptr_narrow destination",
  )
  emit_x64_load_narrow_base_disp32(object, dst, base, bits, signed, offset)
}

///|
fn emit_x64_store_ptr_narrow(
  object : CodeObject,
  inst : @machv.Instruction,
  bits : Int,
  offset : Int,
) -> Unit raise EmitError {
  let base = require_int_preg(
    find_operand(inst, Use, 0, "store_ptr_narrow"),
    "store_ptr_narrow base",
  )
  let src = require_int_preg(
    find_operand(inst, Use, 1, "store_ptr_narrow"),
    "store_ptr_narrow source",
  )
  emit_x64_store_narrow_base_disp32(object, base, src, bits, offset)
}

///|
fn emit_x64_sse_rr(
  object : CodeObject,
  prefix : Int,
  opcode : Int,
  dst : Int,
  src : Int,
) -> Unit {
  object.code.push(prefix)
  emit_x64_rex_if_needed(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(opcode)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_sse_rr_no_prefix(
  object : CodeObject,
  opcode : Int,
  dst : Int,
  src : Int,
) -> Unit {
  emit_x64_rex_if_needed(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(opcode)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_pcmpeqd_rr(object : CodeObject, dst : Int, src : Int) -> Unit {
  object.code.push(0x66)
  emit_x64_rex_if_needed(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x76)
  emit_x64_modrm(object, 3, dst, src)
}

///|
fn emit_x64_pshift_imm(
  object : CodeObject,
  opcode : Int,
  ext : Int,
  dst : Int,
  amount : Int,
) -> Unit {
  object.code.push(0x66)
  emit_x64_rex_if_needed(object, 0, (dst >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(opcode)
  emit_x64_modrm(object, 3, ext, dst)
  object.code.push(amount & 0xff)
}

///|
fn emit_x64_float_move(
  object : CodeObject,
  dst : Int,
  src : Int,
  class : @machv.RegClass,
) -> Unit {
  let prefix = match class {
    Float32 => 0xf3
    Float64 => 0xf2
    _ => abort("unreachable float class")
  }
  emit_x64_sse_rr(object, prefix, 0x10, dst, src)
}

///|
fn emit_x64_float_abs_or_neg(
  object : CodeObject,
  inst : @machv.Instruction,
  is_abs : Bool,
  context : String,
) -> Unit raise EmitError {
  let (src, src_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} source",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  require_same_float_class(dst_class, src_class, context)
  if dst != src {
    emit_x64_float_move(object, dst, src, dst_class)
  }
  let scratch = if dst == 14 { 15 } else { 14 }
  emit_x64_pcmpeqd_rr(object, scratch, scratch)
  match (is_abs, dst_class) {
    (true, Float32) => emit_x64_pshift_imm(object, 0x72, 2, scratch, 1)
    (true, Float64) => emit_x64_pshift_imm(object, 0x73, 2, scratch, 1)
    (false, Float32) => emit_x64_pshift_imm(object, 0x72, 6, scratch, 31)
    (false, Float64) => emit_x64_pshift_imm(object, 0x73, 6, scratch, 63)
    _ => abort("unreachable float class")
  }
  let opcode = if is_abs { 0x54 } else { 0x57 }
  match dst_class {
    Float32 => emit_x64_sse_rr_no_prefix(object, opcode, dst, scratch)
    Float64 => emit_x64_sse_rr(object, 0x66, opcode, dst, scratch)
    _ => abort("unreachable float class")
  }
}

///|
fn emit_x64_float_binop3(
  object : CodeObject,
  inst : @machv.Instruction,
  opcode : Int,
  context : String,
) -> Unit raise EmitError {
  let (lhs, lhs_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} lhs",
  )
  let (rhs, rhs_class) = require_float_preg(
    find_operand(inst, Use, 1, context),
    "\{context} rhs",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  require_same_float_class(dst_class, lhs_class, context)
  require_same_float_class(dst_class, rhs_class, context)
  if dst != lhs {
    emit_x64_float_move(object, dst, lhs, dst_class)
  }
  let prefix = match dst_class {
    Float32 => 0xf3
    Float64 => 0xf2
    _ => abort("unreachable float class")
  }
  emit_x64_sse_rr(object, prefix, opcode, dst, rhs)
}

///|
fn emit_x64_float_unop(
  object : CodeObject,
  inst : @machv.Instruction,
  opcode : Int,
  context : String,
) -> Unit raise EmitError {
  let (src, src_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} source",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  require_same_float_class(dst_class, src_class, context)
  let prefix = match dst_class {
    Float32 => 0xf3
    Float64 => 0xf2
    _ => abort("unreachable float class")
  }
  emit_x64_sse_rr(object, prefix, opcode, dst, src)
}

///|
fn emit_x64_float_round(
  object : CodeObject,
  inst : @machv.Instruction,
  imm8 : Int,
  context : String,
) -> Unit raise EmitError {
  let (src, src_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} source",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  require_same_float_class(dst_class, src_class, context)
  let opcode = match dst_class {
    Float32 => 0x0a
    Float64 => 0x0b
    _ => abort("unreachable float class")
  }
  // TODO(machv_emit): plumb target feature flags before admitting x64 targets
  // without SSE4.1 scalar ROUNDSS/ROUNDSD support.
  object.code.push(0x66)
  emit_x64_rex_if_needed(object, (dst >> 3) & 1, (src >> 3) & 1)
  object.code.push(0x0f)
  object.code.push(0x3a)
  object.code.push(opcode)
  emit_x64_modrm(object, 3, dst, src)
  object.code.push(imm8 & 0xff)
}

///|
fn emit_x64_int_div(
  object : CodeObject,
  inst : @machv.Instruction,
  signed : Bool,
) -> Unit raise EmitError {
  let context = if signed { "idiv" } else { "div" }
  let lhs = require_int_preg(
    find_operand(inst, Use, 0, context),
    "\{context} dividend",
  )
  let rhs = require_int_preg(
    find_operand(inst, Use, 1, context),
    "\{context} divisor",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, context),
    "\{context} quotient",
  )
  let rdx = require_int_preg(
    find_operand(inst, Def, 1, context),
    "\{context} rdx side effect",
  )
  if lhs != 0 || dst != 0 || rdx != 3 {
    raise UnsupportedOperand(
      message="\{context} requires dividend/result in rax and rdx side-effect def",
    )
  }
  if rhs == 0 || rhs == 3 {
    raise UnsupportedOperand(
      message="\{context} divisor must not be rax or rdx",
    )
  }
  if signed {
    // cqo: sign-extend RAX into RDX:RAX before IDIV.
    object.code.push(0x48)
    object.code.push(0x99)
  } else {
    // xor edx, edx: zero the high dividend half before DIV.
    object.code.push(0x31)
    object.code.push(0xd2)
  }
  emit_x64_div_r64(object, rhs, signed)
}

///|
fn emit_x64_int_rem(
  object : CodeObject,
  inst : @machv.Instruction,
  signed : Bool,
) -> Unit raise EmitError {
  let context = if signed { "irem" } else { "urem" }
  let lhs = require_int_preg(
    find_operand(inst, Use, 0, context),
    "\{context} dividend",
  )
  let rhs = require_int_preg(
    find_operand(inst, Use, 1, context),
    "\{context} divisor",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, context),
    "\{context} remainder",
  )
  let rax = require_int_preg(
    find_operand(inst, Def, 1, context),
    "\{context} rax side effect",
  )
  if lhs != 0 || rax != 0 || dst != 3 {
    raise UnsupportedOperand(
      message="\{context} requires dividend/quotient in rax and remainder in rdx",
    )
  }
  if rhs == 0 || rhs == 3 {
    raise UnsupportedOperand(
      message="\{context} divisor must not be rax or rdx",
    )
  }
  if signed {
    // cqo: sign-extend RAX into RDX:RAX before IDIV.
    object.code.push(0x48)
    object.code.push(0x99)
  } else {
    // xor edx, edx: zero the high dividend half before DIV.
    object.code.push(0x31)
    object.code.push(0xd2)
  }
  emit_x64_div_r64(object, rhs, signed)
}

///|
fn emit_x64_int_mul_high(
  object : CodeObject,
  inst : @machv.Instruction,
  signed : Bool,
) -> Unit raise EmitError {
  let context = if signed { "smulh" } else { "umulh" }
  let lhs = require_int_preg(
    find_operand(inst, Use, 0, context),
    "\{context} lhs",
  )
  let rhs = require_int_preg(
    find_operand(inst, Use, 1, context),
    "\{context} rhs",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, context),
    "\{context} high result",
  )
  let rax = require_int_preg(
    find_operand(inst, Def, 1, context),
    "\{context} rax side effect",
  )
  if lhs != 0 || rax != 0 || dst != 3 {
    raise UnsupportedOperand(
      message="\{context} requires lhs/low result in rax and high result in rdx",
    )
  }
  if rhs == 0 || rhs == 3 {
    raise UnsupportedOperand(message="\{context} rhs must not be rax or rdx")
  }
  emit_x64_mul_high_r64(object, rhs, signed)
}

///|
fn emit_x64_int_not(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let src = require_int_preg(find_operand(inst, Use, 0, "not"), "not source")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "not"),
    "not destination",
  )
  // TODO(machv_emit): encode 32-bit integer not once MachV carries lane width.
  if dst != src {
    emit_x64_mov_rr(object, dst, src)
  }
  emit_x64_not_r64(object, dst)
}

///|
fn emit_x64_int_cmp(
  object : CodeObject,
  inst : @machv.Instruction,
  cond : @machv.Cond,
) -> Unit raise EmitError {
  let lhs = require_int_preg(find_operand(inst, Use, 0, "cmp"), "cmp lhs")
  let rhs = require_int_preg(find_operand(inst, Use, 1, "cmp"), "cmp rhs")
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "cmp"),
    "cmp destination",
  )
  // TODO(machv_emit): encode 32-bit comparisons once MachV carries lane width.
  emit_x64_cmp_rr(object, lhs, rhs)
  emit_x64_setcc_r8(object, cond, dst)
  emit_x64_movzx_r32_r8(object, dst, dst)
}

///|
fn emit_x64_float_cmp(
  object : CodeObject,
  inst : @machv.Instruction,
  cond : @machv.Cond,
) -> Unit raise EmitError {
  let (lhs, lhs_class) = require_float_preg(
    find_operand(inst, Use, 0, "fcmp"),
    "fcmp lhs",
  )
  let (rhs, rhs_class) = require_float_preg(
    find_operand(inst, Use, 1, "fcmp"),
    "fcmp rhs",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "fcmp"),
    "fcmp destination",
  )
  require_same_float_class(lhs_class, rhs_class, "fcmp")
  // UCOMIS* sets ZF/CF/PF. PF=1 means unordered; Eq is ordered-and-equal, while
  // Ne is unordered-or-not-equal, matching WebAssembly scalar float comparisons.
  match cond {
    Eq | Ne => {
      let scratch = require_int_preg(
        find_operand(inst, UseDef, 0, "fcmp"),
        "fcmp parity scratch",
      )
      if scratch == dst {
        raise UnsupportedOperand(
          message="x64 fcmp eq/ne requires a scratch register distinct from the destination",
        )
      }
      emit_x64_ucomis_rr(object, lhs, rhs, lhs_class)
      if cond == Eq {
        emit_x64_setcc_r8(object, Eq, dst)
        emit_x64_setcc_r8(object, NotParity, scratch)
        emit_x64_movzx_r32_r8(object, dst, dst)
        emit_x64_movzx_r32_r8(object, scratch, scratch)
        emit_x64_and_rr32(object, dst, scratch)
      } else {
        emit_x64_setcc_r8(object, Ne, dst)
        emit_x64_setcc_r8(object, Parity, scratch)
        emit_x64_movzx_r32_r8(object, dst, dst)
        emit_x64_movzx_r32_r8(object, scratch, scratch)
        emit_x64_or_rr32(object, dst, scratch)
      }
    }
    Gt | Ge => {
      emit_x64_ucomis_rr(object, lhs, rhs, lhs_class)
      emit_x64_setcc_r8(object, if cond == Gt { Ugt } else { Uge }, dst)
      emit_x64_movzx_r32_r8(object, dst, dst)
    }
    Lt | Le => {
      emit_x64_ucomis_rr(object, rhs, lhs, lhs_class)
      emit_x64_setcc_r8(object, if cond == Lt { Ugt } else { Uge }, dst)
      emit_x64_movzx_r32_r8(object, dst, dst)
    }
    Ult | Ule | Ugt | Uge | Mi | Parity | NotParity | Custom(_) =>
      raise UnsupportedOperand(
        message="x64 fcmp requires a scalar float comparison condition",
      )
  }
}

///|
fn emit_x64_int_shift(
  object : CodeObject,
  inst : @machv.Instruction,
  subopcode : Int,
  context : String,
) -> Unit raise EmitError {
  let value = require_int_preg(
    find_operand(inst, Use, 0, context),
    "\{context} value",
  )
  let count = require_int_preg(
    find_operand(inst, Use, 1, context),
    "\{context} count",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  if count != 1 {
    raise UnsupportedOperand(message="\{context} count must be in rcx")
  }
  // TODO(machv_emit): encode 32-bit shifts once MachV carries lane width.
  if dst != value {
    emit_x64_mov_rr(object, dst, value)
  }
  emit_x64_shift_r_cl(object, dst, subopcode)
}

///|
fn emit_x64_bitcast(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let (src, src_class) = require_physical_preg(
    find_operand(inst, Use, 0, "bitcast"),
    "bitcast source",
  )
  let (dst, dst_class) = require_physical_preg(
    find_operand(inst, Def, 0, "bitcast"),
    "bitcast destination",
  )
  match (src_class, dst_class) {
    (Float32, Int) => emit_x64_movd_r32_xmm(object, dst, src)
    (Float64, Int) => emit_x64_movq_r64_xmm(object, dst, src)
    (Int, Float32) => emit_x64_movd_xmm_r32(object, dst, src)
    (Int, Float64) => emit_x64_movq_xmm_r64(object, dst, src)
    _ =>
      raise UnsupportedOperand(
        message="bitcast requires int<->f32/f64 physical registers",
      )
  }
}

///|
fn emit_x64_sign_extend(
  object : CodeObject,
  inst : @machv.Instruction,
  from_bits : Int,
) -> Unit raise EmitError {
  let src = require_int_preg(
    find_operand(inst, Use, 0, "sextend"),
    "sextend source",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "sextend"),
    "sextend destination",
  )
  // TODO(machv_emit): choose 32-bit result encodings once MachV carries lane width.
  match from_bits {
    8 => emit_x64_movsx_r64_r8(object, dst, src)
    16 => emit_x64_movsx_r64_r16(object, dst, src)
    32 => emit_x64_movsxd_r64_r32(object, dst, src)
    _ => abort("unreachable sign-extension width")
  }
}

///|
fn emit_x64_zero_extend32(
  object : CodeObject,
  inst : @machv.Instruction,
  context : String,
) -> Unit raise EmitError {
  let src = require_int_preg(
    find_operand(inst, Use, 0, context),
    "\{context} source",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  // TODO(machv_emit): generalize integer width conversions once MachV carries
  // source and destination lane widths instead of only a generic Int class.
  emit_x64_mov_rr32(object, dst, src)
}

///|
fn emit_x64_select(
  object : CodeObject,
  inst : @machv.Instruction,
) -> Unit raise EmitError {
  let cond = require_int_preg(
    find_operand(inst, Use, 0, "select"),
    "select condition",
  )
  let true_reg = require_int_preg(
    find_operand(inst, Use, 1, "select"),
    "select true value",
  )
  let false_reg = require_int_preg(
    find_operand(inst, Use, 2, "select"),
    "select false value",
  )
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "select"),
    "select destination",
  )
  // TODO(machv_emit): add branch-based Float32/Float64 and vector select
  // lowering once MachV select carries result class-specific lowering metadata.
  emit_x64_test_rr32(object, cond)
  if dst == true_reg {
    emit_x64_cmovcc_rr(object, Eq, dst, false_reg)
  } else {
    if dst != false_reg {
      emit_x64_mov_rr(object, dst, false_reg)
    }
    emit_x64_cmovcc_rr(object, Ne, dst, true_reg)
  }
}

///|
fn emit_x64_float_width_convert(
  object : CodeObject,
  inst : @machv.Instruction,
  promote : Bool,
) -> Unit raise EmitError {
  let context = if promote { "fpromote" } else { "fdemote" }
  let (src, src_class) = require_float_preg(
    find_operand(inst, Use, 0, context),
    "\{context} source",
  )
  let (dst, dst_class) = require_float_preg(
    find_operand(inst, Def, 0, context),
    "\{context} destination",
  )
  match (promote, src_class, dst_class) {
    (true, Float32, Float64) => emit_x64_sse_rr(object, 0xf3, 0x5a, dst, src)
    (false, Float64, Float32) => emit_x64_sse_rr(object, 0xf2, 0x5a, dst, src)
    _ =>
      raise UnsupportedOperand(
        message="\{context} requires f32->f64 or f64->f32 registers",
      )
  }
}

///|
fn emit_x64_stack_load(
  object : CodeObject,
  inst : @machv.Instruction,
  slot : @machv.StackSlot,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  let (dst, dst_class) = require_physical_preg(
    find_operand(inst, Def, 0, "stack load"),
    "stack load destination",
  )
  let offset = frame.get_spill_offset(slot.id)
  match dst_class {
    Int => emit_x64_int_stack_load(object, dst, offset)
    Float32 | Float64 => emit_x64_float_stack_load(object, dst, offset)
    Vector => emit_x64_vector_stack_load(object, dst, offset)
  }
}

///|
fn emit_x64_stack_store(
  object : CodeObject,
  inst : @machv.Instruction,
  slot : @machv.StackSlot,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  let (src, src_class) = require_physical_preg(
    find_operand(inst, Use, 0, "stack store"),
    "stack store source",
  )
  let offset = frame.get_spill_offset(slot.id)
  match src_class {
    Int => emit_x64_int_stack_store(object, src, offset)
    Float32 | Float64 => emit_x64_float_stack_store(object, src, offset)
    Vector => emit_x64_vector_stack_store(object, src, offset)
  }
}

///|
fn emit_x64_outgoing_arg_store(
  object : CodeObject,
  src : Int,
  src_class : @machv.RegClass,
  offset : Int,
) -> Unit {
  match src_class {
    Int => emit_x64_int_stack_store(object, src, offset)
    Float32 | Float64 => emit_x64_float_stack_store(object, src, offset)
    Vector => emit_x64_vector_stack_store(object, src, offset)
  }
}

///|
fn emit_x64_outgoing_arg_stores(
  object : CodeObject,
  inst : @machv.Instruction,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  for operand_index, location in inst.abi_arg_locations {
    if location is Stack(offset~, ..) {
      let (src, src_class) = require_physical_preg(
        find_operand(inst, Use, operand_index, "outgoing stack argument"),
        "outgoing stack argument source",
      )
      emit_x64_outgoing_arg_store(
        object,
        src,
        src_class,
        frame.get_outgoing_arg_offset(offset),
      )
    }
  }
}

///|
fn emit_x64_call_ptr(
  object : CodeObject,
  inst : @machv.Instruction,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  emit_x64_outgoing_arg_stores(object, inst, frame)
  let target = require_int_preg(
    find_operand(inst, Use, 0, "call_ptr"),
    "call_ptr target",
  )
  emit_x64_call_reg(object, target)
}

///|
fn emit_x64_sp_adjust(
  object : CodeObject,
  frame_size : Int,
  subtract : Bool,
) -> Unit {
  if frame_size == 0 {
    return
  }
  object.code.push(0x48)
  object.code.push(0x81)
  object.code.push(if subtract { 0xec } else { 0xc4 })
  emit_u32_le(object, frame_size)
}

///|
fn emit_x64_prologue(object : CodeObject, frame : StackFrameLayout) -> Unit {
  emit_x64_sp_adjust(object, frame.frame_size, true)
  for reg in frame.saved_gprs {
    emit_x64_int_stack_store(object, reg, frame.get_gpr_save_offset(reg))
  }
}

///|
fn emit_x64_epilogue(object : CodeObject, frame : StackFrameLayout) -> Unit {
  for offset in 0..<frame.saved_gprs.length() {
    let i = frame.saved_gprs.length() - 1 - offset
    let reg = frame.saved_gprs[i]
    emit_x64_int_stack_load(object, reg, frame.get_gpr_save_offset(reg))
  }
  emit_x64_sp_adjust(object, frame.frame_size, false)
}

///|
fn emit_x64_stack_addr(
  object : CodeObject,
  inst : @machv.Instruction,
  slot_id : Int,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  let dst = require_int_preg(
    find_operand(inst, Def, 0, "stack_addr"),
    "stack_addr destination",
  )
  let offset = frame.get_spill_offset(slot_id)
  emit_x64_rex_w(object, (dst >> 3) & 1, 0)
  object.code.push(0x8d)
  emit_x64_modrm(object, 2, dst, 4)
  object.code.push(0x24)
  emit_u32_le(object, offset)
}

///|
fn write_aarch64_inst_bytes(
  object : CodeObject,
  inst : @machv.Instruction,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  match inst.opcode {
    IntConst(imm) => emit_aarch64_int_const(object, inst, imm)
    Move => emit_aarch64_move(object, inst)
    IntAdd => emit_aarch64_int_add(object, inst)
    IntSub => emit_aarch64_int_binop3(object, inst, 0xcb000000, "sub")
    IntMul => emit_aarch64_int_mul(object, inst)
    IntMulHigh(signed) => emit_aarch64_int_mul_high(object, inst, signed)
    IntDiv(signed) =>
      emit_aarch64_int_binop3(
        object,
        inst,
        if signed {
          0x9ac00c00
        } else {
          0x9ac00800
        },
        if signed {
          "sdiv"
        } else {
          "udiv"
        },
      )
    IntNot => emit_aarch64_int_not(object, inst)
    IntAnd => emit_aarch64_int_binop3(object, inst, 0x8a000000, "and")
    IntOr => emit_aarch64_int_binop3(object, inst, 0xaa000000, "or")
    IntXor => emit_aarch64_int_binop3(object, inst, 0xca000000, "xor")
    IntCmp(cond) => emit_aarch64_int_cmp(object, inst, cond)
    IntClz => emit_aarch64_int_clz(object, inst)
    IntCtz => emit_aarch64_int_ctz(object, inst)
    IntShl => emit_aarch64_int_shift(object, inst, 8, "shl")
    IntShr(signed) =>
      emit_aarch64_int_shift(
        object,
        inst,
        if signed {
          10
        } else {
          9
        },
        if signed {
          "sshr"
        } else {
          "ushr"
        },
      )
    IntRotr => emit_aarch64_int_shift(object, inst, 11, "rotr")
    FloatAdd => emit_aarch64_float_binop3(object, inst, 0x2028, 0x6028, "fadd")
    FloatSub => emit_aarch64_float_binop3(object, inst, 0x2038, 0x6038, "fsub")
    FloatMul => emit_aarch64_float_binop3(object, inst, 0x2008, 0x6008, "fmul")
    FloatDiv => emit_aarch64_float_binop3(object, inst, 0x2018, 0x6018, "fdiv")
    FloatMin => emit_aarch64_float_binop3(object, inst, 0x2058, 0x6058, "fmin")
    FloatMax => emit_aarch64_float_binop3(object, inst, 0x2048, 0x6048, "fmax")
    FloatCmp(cond) => emit_aarch64_float_cmp(object, inst, cond)
    FloatSqrt => emit_aarch64_float_unop(object, inst, 0x21c0, 0x61c0, "fsqrt")
    FloatAbs => emit_aarch64_float_unop(object, inst, 0x20c0, 0x60c0, "fabs")
    FloatNeg => emit_aarch64_float_unop(object, inst, 0x2140, 0x6140, "fneg")
    FloatCeil =>
      emit_aarch64_float_round(object, inst, 0xc0, 0x24, 0xc0, 0x64, "fceil")
    FloatFloor =>
      emit_aarch64_float_round(object, inst, 0x40, 0x25, 0x40, 0x65, "ffloor")
    FloatTrunc =>
      emit_aarch64_float_round(object, inst, 0xc0, 0x25, 0xc0, 0x65, "ftrunc")
    FloatNearest =>
      emit_aarch64_float_round(object, inst, 0x40, 0x24, 0x40, 0x64, "fnearest")
    Fpromote => emit_aarch64_float_width_convert(object, inst, true)
    Fdemote => emit_aarch64_float_width_convert(object, inst, false)
    Bitcast => emit_aarch64_bitcast(object, inst)
    Sextend => emit_aarch64_sign_extend(object, inst, 32)
    Uextend => emit_aarch64_zero_extend32(object, inst, "uextend")
    Ireduce => emit_aarch64_zero_extend32(object, inst, "ireduce")
    Sextend8 => emit_aarch64_sign_extend(object, inst, 8)
    Sextend16 => emit_aarch64_sign_extend(object, inst, 16)
    Sextend32 => emit_aarch64_sign_extend(object, inst, 32)
    Select => emit_aarch64_select(object, inst)
    LoadMemory(mem_type, offset) =>
      emit_aarch64_load_ptr(object, inst, mem_type, offset)
    StoreMemory(mem_type, offset) =>
      emit_aarch64_store_ptr(object, inst, mem_type, offset)
    LoadPtr(mem_type, offset) =>
      emit_aarch64_load_ptr(object, inst, mem_type, offset)
    LoadPtrNarrow(bits, signed, offset) =>
      emit_aarch64_load_ptr_narrow(object, inst, bits, signed, offset)
    StorePtr(mem_type, offset) =>
      emit_aarch64_store_ptr(object, inst, mem_type, offset)
    StorePtrNarrow(bits, offset) =>
      emit_aarch64_store_ptr_narrow(object, inst, bits, offset)
    StackAddr(slot_id) => emit_aarch64_stack_addr(object, inst, slot_id, frame)
    Load(slot) => emit_aarch64_stack_load(object, inst, slot, frame)
    Store(slot) => emit_aarch64_stack_store(object, inst, slot, frame)
    Call(_) => {
      emit_aarch64_outgoing_arg_stores(object, inst, frame)
      // TODO(machv_emit): resolve and range-check AArch64 BL relocations during real object linking.
      emit_u32_le(object, 0x94000000)
    }
    CallPtr(_, _) => emit_aarch64_call_ptr(object, inst, frame)
    Jump(_) => emit_aarch64_b(object)
    Return => emit_u32_le(object, 0xd65f03c0)
    Trap(_) =>
      // TODO(machv_emit): encode trap reasons into target-specific debug/trap metadata.
      emit_u32_le(object, 0xd4200000)
    _ => raise UnsupportedOpcode(opcode=opcode_debug_name(inst.opcode))
  }
}

///|
fn write_x64_inst_bytes(
  object : CodeObject,
  inst : @machv.Instruction,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  match inst.opcode {
    IntConst(imm) => emit_x64_int_const(object, inst, imm)
    Move => emit_x64_move(object, inst)
    IntAdd => emit_x64_int_add(object, inst)
    IntSub => emit_x64_int_binop3(object, inst, emit_x64_sub_rr, "sub")
    IntMul => emit_x64_int_binop3(object, inst, emit_x64_imul_rr, "mul")
    IntMulHigh(signed) => emit_x64_int_mul_high(object, inst, signed)
    IntDiv(signed) => emit_x64_int_div(object, inst, signed)
    IntRem(signed) => emit_x64_int_rem(object, inst, signed)
    IntNot => emit_x64_int_not(object, inst)
    IntAnd => emit_x64_int_binop3(object, inst, emit_x64_and_rr, "and")
    IntOr => emit_x64_int_binop3(object, inst, emit_x64_or_rr, "or")
    IntXor => emit_x64_int_binop3(object, inst, emit_x64_xor_rr, "xor")
    IntCmp(cond) => emit_x64_int_cmp(object, inst, cond)
    IntShl => emit_x64_int_shift(object, inst, 4, "shl")
    IntShr(signed) =>
      emit_x64_int_shift(
        object,
        inst,
        if signed {
          7
        } else {
          5
        },
        if signed {
          "sshr"
        } else {
          "ushr"
        },
      )
    IntRotl => emit_x64_int_shift(object, inst, 0, "rotl")
    IntRotr => emit_x64_int_shift(object, inst, 1, "rotr")
    FloatAdd => emit_x64_float_binop3(object, inst, 0x58, "fadd")
    FloatSub => emit_x64_float_binop3(object, inst, 0x5c, "fsub")
    FloatMul => emit_x64_float_binop3(object, inst, 0x59, "fmul")
    FloatDiv => emit_x64_float_binop3(object, inst, 0x5e, "fdiv")
    FloatMin => emit_x64_float_binop3(object, inst, 0x5d, "fmin")
    FloatMax => emit_x64_float_binop3(object, inst, 0x5f, "fmax")
    FloatCmp(cond) => emit_x64_float_cmp(object, inst, cond)
    FloatSqrt => emit_x64_float_unop(object, inst, 0x51, "fsqrt")
    FloatAbs => emit_x64_float_abs_or_neg(object, inst, true, "fabs")
    FloatNeg => emit_x64_float_abs_or_neg(object, inst, false, "fneg")
    FloatCeil => emit_x64_float_round(object, inst, 2, "fceil")
    FloatFloor => emit_x64_float_round(object, inst, 1, "ffloor")
    FloatTrunc => emit_x64_float_round(object, inst, 3, "ftrunc")
    FloatNearest => emit_x64_float_round(object, inst, 0, "fnearest")
    Fpromote => emit_x64_float_width_convert(object, inst, true)
    Fdemote => emit_x64_float_width_convert(object, inst, false)
    Bitcast => emit_x64_bitcast(object, inst)
    Sextend => emit_x64_sign_extend(object, inst, 32)
    Uextend => emit_x64_zero_extend32(object, inst, "uextend")
    Ireduce => emit_x64_zero_extend32(object, inst, "ireduce")
    Sextend8 => emit_x64_sign_extend(object, inst, 8)
    Sextend16 => emit_x64_sign_extend(object, inst, 16)
    Sextend32 => emit_x64_sign_extend(object, inst, 32)
    Select => emit_x64_select(object, inst)
    LoadMemory(mem_type, offset) =>
      emit_x64_load_ptr(object, inst, mem_type, offset)
    StoreMemory(mem_type, offset) =>
      emit_x64_store_ptr(object, inst, mem_type, offset)
    LoadPtr(mem_type, offset) =>
      emit_x64_load_ptr(object, inst, mem_type, offset)
    LoadPtrNarrow(bits, signed, offset) =>
      emit_x64_load_ptr_narrow(object, inst, bits, signed, offset)
    StorePtr(mem_type, offset) =>
      emit_x64_store_ptr(object, inst, mem_type, offset)
    StorePtrNarrow(bits, offset) =>
      emit_x64_store_ptr_narrow(object, inst, bits, offset)
    StackAddr(slot_id) => emit_x64_stack_addr(object, inst, slot_id, frame)
    Load(slot) => emit_x64_stack_load(object, inst, slot, frame)
    Store(slot) => emit_x64_stack_store(object, inst, slot, frame)
    Call(_) => {
      emit_x64_outgoing_arg_stores(object, inst, frame)
      // TODO(machv_emit): patch X64 call rel32 displacement during object linking.
      object.code.push(0xe8)
      emit_u32_le(object, 0)
    }
    CallPtr(_, _) => emit_x64_call_ptr(object, inst, frame)
    Jump(_) =>
      // TODO(machv_emit): patch X64 jump rel32 displacement after block layout.
      emit_x64_jmp_rel32(object)
    Return => object.code.push(0xc3)
    Trap(_) => {
      // TODO(machv_emit): encode trap reasons into target-specific debug/trap metadata.
      object.code.push(0xcc)
      object.code.push(0)
      object.code.push(0)
    }
    _ => raise UnsupportedOpcode(opcode=opcode_debug_name(inst.opcode))
  }
}

///|
fn write_inst_bytes(
  object : CodeObject,
  target : EmitTarget,
  inst : @machv.Instruction,
  frame : StackFrameLayout,
) -> Unit raise EmitError {
  match target {
    AArch64 => write_aarch64_inst_bytes(object, inst, frame)
    X64 => write_x64_inst_bytes(object, inst, frame)
  }
}

///|
fn record_relocations(
  object : CodeObject,
  offset : Int,
  opcode : @machv.Opcode,
) -> Unit {
  match opcode {
    Call(symbol) =>
      object.relocations.push({ offset, kind: ExternalSymbol(symbol) })
    Jump(target) => {
      object.relocations.push({ offset, kind: BlockTarget(target) })
      object.fixups.push({ offset, block_id: target })
    }
    Branch(true_target, false_target) => {
      object.relocations.push({ offset, kind: BlockTarget(true_target) })
      object.relocations.push({
        offset: offset + 1,
        kind: BlockTarget(false_target),
      })
      object.fixups.push({ offset, block_id: true_target })
      object.fixups.push({ offset: offset + 1, block_id: false_target })
    }
    _ => ()
  }
}

///|
fn record_stack_map(
  object : CodeObject,
  offset : Int,
  inst : @machv.Instruction,
) -> Unit {
  if inst.stack_effect != None {
    object.stack_maps.push({ offset, effect: inst.stack_effect })
  }
}

///|
fn record_branch_target(
  object : CodeObject,
  offset : Int,
  target : Int,
) -> Unit {
  object.relocations.push({ offset, kind: BlockTarget(target) })
  object.fixups.push({ offset, block_id: target })
}

///|
fn emit_instruction(
  object : CodeObject,
  target : EmitTarget,
  block_id : Int,
  inst : @machv.Instruction,
  frame : StackFrameLayout,
  emit_abi_frame : Bool,
) -> Unit raise EmitError {
  let offset = object.current_offset()
  if emit_abi_frame && inst.opcode is Return {
    match target {
      AArch64 => emit_aarch64_epilogue(object, frame)
      X64 => emit_x64_epilogue(object, frame)
    }
  }
  write_inst_bytes(object, target, inst, frame)
  record_relocations(object, offset, inst.opcode)
  record_stack_map(object, offset, inst)
  object.debug_entries.push({
    offset,
    block_id,
    inst_id: inst.id,
    opcode: opcode_debug_name(inst.opcode),
  })
}

///|
fn opcode_for_terminator(
  term : @machv.Terminator,
) -> @machv.Opcode raise EmitError {
  match term {
    TermReturn(_) => Return
    TermJump(target, args) => {
      guard args.length() == 0 else {
        raise UnsupportedOperand(
          message="terminator edge arguments require machv_regalloc materialization before emission",
        )
      }
      Jump(target)
    }
    TermTrap(reason) => Trap(reason)
    _ => raise UnsupportedOpcode(opcode=terminator_debug_name(term))
  }
}

///|
fn require_no_edge_args(
  args : Array[@machv.Reg],
  context : String,
) -> Unit raise EmitError {
  guard args.length() == 0 else {
    raise UnsupportedOperand(
      message="\{context} edge arguments require machv_regalloc materialization before emission",
    )
  }
}

///|
fn emit_branch_fallthrough_jump(
  object : CodeObject,
  target : EmitTarget,
) -> Int {
  let jump_offset = object.current_offset()
  match target {
    AArch64 => emit_aarch64_b(object)
    X64 => emit_x64_jmp_rel32(object)
  }
  jump_offset
}

///|
fn require_branch_reg(
  reg : @machv.Reg,
  context : String,
) -> Int raise EmitError {
  match reg {
    Physical(preg) =>
      if preg.class == Int && !preg.is_spilled() {
        preg.index
      } else {
        raise UnsupportedOperand(
          message="\{context} requires an integer physical register",
        )
      }
    Virtual(_) =>
      raise UnsupportedOperand(
        message="\{context} requires register allocation before emission",
      )
  }
}

///|
fn emit_branch_zero(
  object : CodeObject,
  target : EmitTarget,
  reg : @machv.Reg,
  is_nonzero : Bool,
  is_64 : Bool,
  true_target : Int,
  false_target : Int,
) -> Unit raise EmitError {
  let preg = require_branch_reg(reg, "branch-zero")
  let mut branch_offset = object.current_offset()
  match target {
    AArch64 => emit_aarch64_cbz(object, preg, is_nonzero, is_64)
    X64 => {
      emit_x64_test_rr(object, preg)
      branch_offset = object.current_offset()
      emit_x64_jcc_rel32(object, if is_nonzero { Ne } else { Eq })
    }
  }
  record_branch_target(object, branch_offset, true_target)
  let jump_offset = emit_branch_fallthrough_jump(object, target)
  record_branch_target(object, jump_offset, false_target)
}

///|
fn emit_branch_cmp(
  object : CodeObject,
  target : EmitTarget,
  lhs : @machv.Reg,
  rhs : @machv.Reg,
  cond : @machv.Cond,
  is_64 : Bool,
  true_target : Int,
  false_target : Int,
) -> Unit raise EmitError {
  let lhs_reg = require_branch_reg(lhs, "branch-cmp lhs")
  let rhs_reg = require_branch_reg(rhs, "branch-cmp rhs")
  match target {
    AArch64 => emit_aarch64_cmp_rr(object, lhs_reg, rhs_reg, is_64)
    X64 => emit_x64_cmp_rr(object, lhs_reg, rhs_reg)
  }
  let cond_offset = object.current_offset()
  match target {
    AArch64 => emit_aarch64_b_cond(object, cond)
    X64 => emit_x64_jcc_rel32(object, cond)
  }
  record_branch_target(object, cond_offset, true_target)
  let jump_offset = emit_branch_fallthrough_jump(object, target)
  record_branch_target(object, jump_offset, false_target)
}

///|
fn emit_branch_cmp_imm(
  object : CodeObject,
  target : EmitTarget,
  lhs : @machv.Reg,
  imm : Int,
  cond : @machv.Cond,
  is_64 : Bool,
  true_target : Int,
  false_target : Int,
) -> Unit raise EmitError {
  let lhs_reg = require_branch_reg(lhs, "branch-cmp-imm lhs")
  match target {
    AArch64 => emit_aarch64_cmp_imm(object, lhs_reg, imm, is_64)
    X64 => emit_x64_cmp_imm32(object, lhs_reg, imm)
  }
  let cond_offset = object.current_offset()
  match target {
    AArch64 => emit_aarch64_b_cond(object, cond)
    X64 => emit_x64_jcc_rel32(object, cond)
  }
  record_branch_target(object, cond_offset, true_target)
  let jump_offset = emit_branch_fallthrough_jump(object, target)
  record_branch_target(object, jump_offset, false_target)
}

///|
fn emit_conditional_terminator(
  object : CodeObject,
  target : EmitTarget,
  term : @machv.Terminator,
) -> Unit raise EmitError {
  match term {
    TermBranch(cond, true_target, true_args, false_target, false_args) => {
      require_no_edge_args(true_args, "branch true")
      require_no_edge_args(false_args, "branch false")
      emit_branch_zero(
        object, target, cond, true, true, true_target, false_target,
      )
    }
    TermBranchZero(
      reg,
      is_nonzero,
      is_64,
      true_target,
      true_args,
      false_target,
      false_args
    ) => {
      require_no_edge_args(true_args, "branch-zero true")
      require_no_edge_args(false_args, "branch-zero false")
      emit_branch_zero(
        object, target, reg, is_nonzero, is_64, true_target, false_target,
      )
    }
    TermBranchCmp(
      lhs,
      rhs,
      cond,
      is_64,
      true_target,
      true_args,
      false_target,
      false_args
    ) => {
      require_no_edge_args(true_args, "branch-cmp true")
      require_no_edge_args(false_args, "branch-cmp false")
      emit_branch_cmp(
        object, target, lhs, rhs, cond, is_64, true_target, false_target,
      )
    }
    TermBranchCmpImm(
      lhs,
      imm,
      cond,
      is_64,
      true_target,
      true_args,
      false_target,
      false_args
    ) => {
      require_no_edge_args(true_args, "branch-cmp-imm true")
      require_no_edge_args(false_args, "branch-cmp-imm false")
      emit_branch_cmp_imm(
        object, target, lhs, imm, cond, is_64, true_target, false_target,
      )
    }
    _ => raise UnsupportedOpcode(opcode=terminator_debug_name(term))
  }
}

///|
fn emit_terminator(
  object : CodeObject,
  target : EmitTarget,
  block_id : Int,
  term : @machv.Terminator,
  frame : StackFrameLayout,
  emit_abi_frame : Bool,
) -> Unit raise EmitError {
  match term {
    TermBranch(_, _, _, _, _)
    | TermBranchZero(_, _, _, _, _, _, _)
    | TermBranchCmp(_, _, _, _, _, _, _, _)
    | TermBranchCmpImm(_, _, _, _, _, _, _, _) => {
      let offset = object.current_offset()
      emit_conditional_terminator(object, target, term)
      object.debug_entries.push({
        offset,
        block_id,
        inst_id: -1,
        opcode: terminator_debug_name(term),
      })
      return
    }
    _ => ()
  }
  let opcode = opcode_for_terminator(term)
  let inst = @machv.Instruction::new(-1, opcode)
  let offset = object.current_offset()
  if emit_abi_frame && term is TermReturn(_) {
    match target {
      AArch64 => emit_aarch64_epilogue(object, frame)
      X64 => emit_x64_epilogue(object, frame)
    }
  }
  write_inst_bytes(object, target, inst, frame)
  record_relocations(object, offset, opcode)
  object.debug_entries.push({
    offset,
    block_id,
    inst_id: -1,
    opcode: opcode_debug_name(opcode),
  })
}

///|
fn int_array_contains(values : Array[Int], value : Int) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
fn is_callee_saved_gpr(target : EmitTarget, reg : Int) -> Bool {
  match target {
    AArch64 => reg >= 19 && reg <= 28
    X64 =>
      reg == 3 || reg == 5 || reg == 12 || reg == 13 || reg == 14 || reg == 15
  }
}

///|
fn is_callee_saved_fpr(target : EmitTarget, reg : Int) -> Bool {
  match target {
    AArch64 => reg >= 8 && reg <= 15
    X64 => false
  }
}

///|
fn record_saved_reg(
  target : EmitTarget,
  reg : @machv.Reg,
  saved_gprs : Array[Int],
  saved_fprs : Array[Int],
) -> Unit {
  if reg is Physical(preg) && !preg.is_spilled() {
    match preg.class {
      Int =>
        if is_callee_saved_gpr(target, preg.index) &&
          !int_array_contains(saved_gprs, preg.index) {
          saved_gprs.push(preg.index)
        }
      Float32 | Float64 | Vector =>
        if is_callee_saved_fpr(target, preg.index) &&
          !int_array_contains(saved_fprs, preg.index) {
          saved_fprs.push(preg.index)
        }
    }
  }
}

///|
fn collect_terminator_saved_regs(
  target : EmitTarget,
  term : @machv.Terminator,
  saved_gprs : Array[Int],
  saved_fprs : Array[Int],
) -> Unit {
  match term {
    TermJump(_, args) | TermReturn(args) =>
      for arg in args {
        record_saved_reg(target, arg, saved_gprs, saved_fprs)
      }
    TermBranch(cond, _, true_args, _, false_args) => {
      record_saved_reg(target, cond, saved_gprs, saved_fprs)
      for arg in true_args {
        record_saved_reg(target, arg, saved_gprs, saved_fprs)
      }
      for arg in false_args {
        record_saved_reg(target, arg, saved_gprs, saved_fprs)
      }
    }
    TermBranchCmp(lhs, rhs, _, _, _, true_args, _, false_args) => {
      record_saved_reg(target, lhs, saved_gprs, saved_fprs)
      record_saved_reg(target, rhs, saved_gprs, saved_fprs)
      for arg in true_args {
        record_saved_reg(target, arg, saved_gprs, saved_fprs)
      }
      for arg in false_args {
        record_saved_reg(target, arg, saved_gprs, saved_fprs)
      }
    }
    TermBranchZero(value, _, _, _, true_args, _, false_args) => {
      record_saved_reg(target, value, saved_gprs, saved_fprs)
      for arg in true_args {
        record_saved_reg(target, arg, saved_gprs, saved_fprs)
      }
      for arg in false_args {
        record_saved_reg(target, arg, saved_gprs, saved_fprs)
      }
    }
    TermBranchCmpImm(value, _, _, _, _, true_args, _, false_args) => {
      record_saved_reg(target, value, saved_gprs, saved_fprs)
      for arg in true_args {
        record_saved_reg(target, arg, saved_gprs, saved_fprs)
      }
      for arg in false_args {
        record_saved_reg(target, arg, saved_gprs, saved_fprs)
      }
    }
    TermBrTable(value, _, _) =>
      record_saved_reg(target, value, saved_gprs, saved_fprs)
    TermTrap(_) => ()
  }
}

///|
fn collect_saved_regs(
  func : @machv.Function,
  target : EmitTarget,
) -> (Array[Int], Array[Int]) {
  let saved_gprs : Array[Int] = []
  let saved_fprs : Array[Int] = []
  for block in func.blocks {
    for inst in block.instructions {
      for operand in inst.operands {
        record_saved_reg(target, operand.reg, saved_gprs, saved_fprs)
      }
    }
    if block.terminator is Some(term) {
      collect_terminator_saved_regs(target, term, saved_gprs, saved_fprs)
    }
  }
  (saved_gprs, saved_fprs)
}

///|
fn function_has_call(func : @machv.Function) -> Bool {
  for block in func.blocks {
    for inst in block.instructions {
      match inst.opcode {
        Call(_) | CallPtr(_, _) | CallIndirect => return true
        _ => ()
      }
    }
  }
  false
}

///|
fn find_block_offset(block_offsets : Array[(Int, Int)], block_id : Int) -> Int? {
  for entry in block_offsets {
    let (id, offset) = entry
    if id == block_id {
      return Some(offset)
    }
  }
  None
}

///|
fn write_i32_le_at(code : Array[Int], offset : Int, value : Int) -> Unit {
  code[offset] = value & 0xff
  code[offset + 1] = (value >> 8) & 0xff
  code[offset + 2] = (value >> 16) & 0xff
  code[offset + 3] = (value >> 24) & 0xff
}

///|
fn read_u32_le_at(code : Array[Int], offset : Int) -> Int {
  code[offset] |
  (code[offset + 1] << 8) |
  (code[offset + 2] << 16) |
  (code[offset + 3] << 24)
}

///|
fn signed_range_check(
  value : Int,
  bits : Int,
  context : String,
) -> Unit raise EmitError {
  let min = -(1 << (bits - 1))
  let max = (1 << (bits - 1)) - 1
  if value < min || value > max {
    raise BranchFixupError(
      message="\{context} displacement out of signed \{bits}-bit range",
    )
  }
}

///|
fn require_word_aligned_delta(
  delta : Int,
  context : String,
) -> Int raise EmitError {
  if delta % 4 != 0 {
    raise BranchFixupError(message="\{context} target is not 4-byte aligned")
  }
  delta / 4
}

///|
pub fn patch_x64_branch_bytes(
  code : Array[Int],
  branch_offset : Int,
  target_offset : Int,
) -> Unit raise EmitError {
  if branch_offset < 0 || branch_offset >= code.length() {
    raise BranchFixupError(message="X64 branch offset out of code bounds")
  }
  let opcode = code[branch_offset]
  if opcode == 0xe9 {
    let displacement = target_offset - (branch_offset + 5)
    write_i32_le_at(code, branch_offset + 1, displacement)
  } else if opcode == 0x0f && branch_offset + 5 < code.length() {
    let displacement = target_offset - (branch_offset + 6)
    write_i32_le_at(code, branch_offset + 2, displacement)
  } else {
    raise BranchFixupError(message="X64 branch fixup does not point at jmp/jcc")
  }
}

///|
pub fn patch_x64_rel32_disp(
  code : Array[Int],
  disp_offset : Int,
  next_ip_offset : Int,
  target_offset : Int,
) -> Unit raise EmitError {
  if disp_offset < 0 || disp_offset + 3 >= code.length() {
    raise BranchFixupError(message="X64 rel32 displacement out of code bounds")
  }
  write_i32_le_at(code, disp_offset, target_offset - next_ip_offset)
}

///|
pub fn patch_aarch64_branch_bytes(
  code : Array[Int],
  branch_offset : Int,
  target_offset : Int,
) -> Unit raise EmitError {
  if branch_offset < 0 || branch_offset + 3 >= code.length() {
    raise BranchFixupError(message="AArch64 branch offset out of code bounds")
  }
  let word = read_u32_le_at(code, branch_offset)
  let delta = target_offset - branch_offset
  if (word & 0x7c000000) == 0x14000000 {
    let imm26 = require_word_aligned_delta(delta, "AArch64 B/BL")
    signed_range_check(imm26, 26, "AArch64 B/BL")
    let patched = (word & 0xfc000000) | (imm26 & 0x03ffffff)
    write_i32_le_at(code, branch_offset, patched)
  } else if (word & 0xff000010) == 0x54000000 {
    let imm19 = require_word_aligned_delta(delta, "AArch64 B.cond")
    signed_range_check(imm19, 19, "AArch64 B.cond")
    let patched = (word & 0xff00001f) | ((imm19 & 0x7ffff) << 5)
    write_i32_le_at(code, branch_offset, patched)
  } else if (word & 0x7e000000) == 0x34000000 {
    let imm19 = require_word_aligned_delta(delta, "AArch64 CBZ/CBNZ")
    signed_range_check(imm19, 19, "AArch64 CBZ/CBNZ")
    let patched = (word & 0xff00001f) | ((imm19 & 0x7ffff) << 5)
    write_i32_le_at(code, branch_offset, patched)
  } else {
    raise BranchFixupError(
      message="AArch64 branch fixup does not point at branch",
    )
  }
}

///|
fn patch_block_fixups(
  object : CodeObject,
  target : EmitTarget,
  block_offsets : Array[(Int, Int)],
) -> Unit raise EmitError {
  for fixup in object.fixups {
    guard find_block_offset(block_offsets, fixup.block_id)
      is Some(target_offset) else {
      raise BranchFixupError(message="unknown block target \{fixup.block_id}")
    }
    match target {
      AArch64 =>
        patch_aarch64_branch_bytes(object.code, fixup.offset, target_offset)
      X64 => patch_x64_branch_bytes(object.code, fixup.offset, target_offset)
    }
  }
}

///|
pub fn emit_function_for_target(
  func : @machv.Function,
  target : EmitTarget,
) -> CodeObject raise EmitError {
  let object = CodeObject::new()
  let has_call = function_has_call(func)
  let emit_abi_frame = func.params.length() > 0 ||
    func.stack_slots.length() > 0 ||
    func.get_num_spill_slots() > 0 ||
    func.get_max_outgoing_args_size() > 0 ||
    (target == AArch64 && has_call)
  let (saved_gprs, saved_fprs) = if emit_abi_frame {
    collect_saved_regs(func, target)
  } else {
    ([], [])
  }
  if target == AArch64 && has_call && !int_array_contains(saved_gprs, 30) {
    saved_gprs.push(30)
  }
  let frame = if func.stack_slots.length() > 0 {
    StackFrameLayout::build_with_slots(
      saved_gprs,
      saved_fprs,
      func.stack_slots,
      false,
      0,
      outgoing_args_size=func.get_max_outgoing_args_size(),
    )
  } else {
    StackFrameLayout::build(
      saved_gprs,
      saved_fprs,
      func.get_num_spill_slots(),
      false,
      0,
      outgoing_args_size=func.get_max_outgoing_args_size(),
    )
  }
  object.frame_size = frame.frame_size
  let block_offsets : Array[(Int, Int)] = []
  let mut emitted_prologue = false
  for block in func.blocks {
    if !emitted_prologue {
      if emit_abi_frame {
        match target {
          AArch64 => emit_aarch64_prologue(object, frame)
          X64 => emit_x64_prologue(object, frame)
        }
      }
      emitted_prologue = true
    }
    block_offsets.push((block.id, object.current_offset()))
    for inst in block.instructions {
      emit_instruction(object, target, block.id, inst, frame, emit_abi_frame)
    }
    if block.terminator is Some(term) {
      emit_terminator(object, target, block.id, term, frame, emit_abi_frame)
    }
  }
  patch_block_fixups(object, target, block_offsets)
  object
}
