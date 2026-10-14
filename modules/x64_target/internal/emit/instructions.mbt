///|
/// x86_64 instruction encoding helpers used by the target emitter.

///|
pub fn emit_u32_le(mc : CodeBuffer, v : Int32) -> Unit {
  mc.emit_byte(v & 255)
  mc.emit_byte((v >> 8) & 255)
  mc.emit_byte((v >> 16) & 255)
  mc.emit_byte((v >> 24) & 255)
}

///|
fn emit_u64_le(mc : CodeBuffer, v : Int64) -> Unit {
  // Emit in little-endian order.
  let mut x = v
  for _i in 0..<8 {
    mc.emit_byte((x & 0xFFL).to_int())
    x = x >> 8
  }
}

///|
pub fn emit_rex_w(mc : CodeBuffer, r : Int32, b : Int32) -> Unit {
  // REX prefix: 0100WRXB. We only need W=1 and R/B for now.
  let rex = 0x48 | ((r & 1) << 2) | (b & 1)
  mc.emit_byte(rex)
}

///|
fn emit_rex(mc : CodeBuffer, r : Int32, b : Int32) -> Unit {
  // REX prefix without W bit (used by some SSE encodings).
  let rex = 0x40 | ((r & 1) << 2) | (b & 1)
  mc.emit_byte(rex)
}

///|
fn validate_reg_idx_0_15(kind : String, idx : Int32) -> Unit {
  guard idx >= 0 && idx < 16 else {
    abort("x86_64 encode: invalid \{kind} reg idx \{idx} (expected 0..15)")
  }
}

///|
pub fn emit_modrm(
  mc : CodeBuffer,
  mod_ : Int32,
  reg : Int32,
  rm : Int32,
) -> Unit {
  validate_reg_idx_0_15("modrm.reg", reg)
  validate_reg_idx_0_15("modrm.rm", rm)
  let b = ((mod_ & 3) << 6) | ((reg & 7) << 3) | (rm & 7)
  mc.emit_byte(b)
}

///|
fn emit_sib(
  mc : CodeBuffer,
  scale : Int32,
  index : Int32,
  base : Int32,
) -> Unit {
  validate_reg_idx_0_15("sib.index", index)
  validate_reg_idx_0_15("sib.base", base)
  let b = ((scale & 3) << 6) | ((index & 7) << 3) | (base & 7)
  mc.emit_byte(b)
}

///|
fn emit_disp32(mc : CodeBuffer, disp : Int32) -> Unit {
  emit_u32_le(mc, disp)
}

///|
pub fn CodeBuffer::x86_emit_mov_imm64(
  self : CodeBuffer,
  dst : Int32,
  imm : Int64,
) -> Unit {
  // mov r64, imm64: REX.W + B8+rd, imm64
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xB8 + (dst & 7))
  emit_u64_le(self, imm)
}

///|
pub fn CodeBuffer::x86_emit_add_rr(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // add r/m64, r64: REX.W + 01 /r (dst += src)
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x01)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn CodeBuffer::x86_emit_add_r_imm8(
  self : CodeBuffer,
  dst : Int32,
  imm : Int32,
) -> Unit {
  // add r/m64, imm8: REX.W + 83 /0 ib (sign-extended imm8)
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0x83)
  // /0 in reg field.
  emit_modrm(self, 3, 0, dst)
  self.emit_byte(imm & 255)
}

///|
pub fn CodeBuffer::x86_emit_add_r_imm32(
  self : CodeBuffer,
  dst : Int32,
  imm : Int32,
) -> Unit {
  // add r/m64, imm32: REX.W + 81 /0 id (imm32 sign-extended to 64-bit).
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0x81)
  emit_modrm(self, 3, 0, dst)
  emit_u32_le(self, imm)
}

///|
pub fn CodeBuffer::x86_emit_add_rr32(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // add r/m32, r32: 01 /r (dst += src), zero-extends to 64-bit.
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x01)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn CodeBuffer::x86_emit_sub_rr(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // sub r/m64, r64: REX.W + 29 /r (dst -= src)
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x29)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn CodeBuffer::x86_emit_sub_rr32(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // sub r/m32, r32: 29 /r (dst -= src), zero-extends to 64-bit.
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x29)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn CodeBuffer::x86_emit_and_rr(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // and r/m64, r64: REX.W + 21 /r
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x21)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn CodeBuffer::x86_emit_and_rr32(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // and r/m32, r32: 21 /r
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x21)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn CodeBuffer::x86_emit_or_rr(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // or r/m64, r64: REX.W + 09 /r
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x09)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn CodeBuffer::x86_emit_or_rr32(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // or r/m32, r32: 09 /r
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x09)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn CodeBuffer::x86_emit_xor_rr(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // xor r/m64, r64: REX.W + 31 /r
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x31)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn CodeBuffer::x86_emit_xor_rr32(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // xor r/m32, r32: 31 /r
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x31)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn CodeBuffer::x86_emit_imul_rr(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // imul r64, r/m64: REX.W + 0F AF /r
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0xAF)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn CodeBuffer::x86_emit_imul_rr32(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // imul r32, r/m32: 0F AF /r
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xAF)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn CodeBuffer::x86_emit_not_r64(self : CodeBuffer, reg : Int32) -> Unit {
  // not r/m64: REX.W + F7 /2
  let b = (reg >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 2, reg)
}

///|
pub fn CodeBuffer::x86_emit_neg_r64(self : CodeBuffer, reg : Int32) -> Unit {
  // neg r/m64: REX.W + F7 /3
  let b = (reg >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 3, reg)
}

///|
pub fn CodeBuffer::x86_emit_not_r32(self : CodeBuffer, reg : Int32) -> Unit {
  // not r/m32: F7 /2
  let b = (reg >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 2, reg)
}

///|
pub fn CodeBuffer::x86_emit_neg_r32(self : CodeBuffer, reg : Int32) -> Unit {
  // neg r/m32: F7 /3
  let b = (reg >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 3, reg)
}

///|
pub fn CodeBuffer::x86_emit_shl_r_cl(self : CodeBuffer, dst : Int32) -> Unit {
  // shl r/m64, cl: REX.W + D3 /4
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 4, dst)
}

///|
pub fn CodeBuffer::x86_emit_shl_r32_cl(self : CodeBuffer, dst : Int32) -> Unit {
  // shl r/m32, cl: D3 /4
  let b = (dst >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 4, dst)
}

///|
pub fn CodeBuffer::x86_emit_shr_r_cl(self : CodeBuffer, dst : Int32) -> Unit {
  // shr r/m64, cl: REX.W + D3 /5
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 5, dst)
}

///|
pub fn CodeBuffer::x86_emit_shr_r32_cl(self : CodeBuffer, dst : Int32) -> Unit {
  // shr r/m32, cl: D3 /5
  let b = (dst >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 5, dst)
}

///|
pub fn CodeBuffer::x86_emit_sar_r_cl(self : CodeBuffer, dst : Int32) -> Unit {
  // sar r/m64, cl: REX.W + D3 /7
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 7, dst)
}

///|
pub fn CodeBuffer::x86_emit_sar_r32_cl(self : CodeBuffer, dst : Int32) -> Unit {
  // sar r/m32, cl: D3 /7
  let b = (dst >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 7, dst)
}

///|
pub fn CodeBuffer::x86_emit_ror_r_cl(self : CodeBuffer, dst : Int32) -> Unit {
  // ror r/m64, cl: REX.W + D3 /1
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 1, dst)
}

///|
pub fn CodeBuffer::x86_emit_ror_r32_cl(self : CodeBuffer, dst : Int32) -> Unit {
  // ror r/m32, cl: D3 /1
  let b = (dst >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 1, dst)
}

///|
pub fn CodeBuffer::x86_emit_shl_r_imm8(
  self : CodeBuffer,
  dst : Int32,
  imm : Int32,
) -> Unit {
  // shl r/m64, imm8: REX.W + C1 /4 ib
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xC1)
  emit_modrm(self, 3, 4, dst)
  self.emit_byte(imm & 255)
}

///|
pub fn CodeBuffer::x86_emit_shl_r32_imm8(
  self : CodeBuffer,
  dst : Int32,
  imm : Int32,
) -> Unit {
  // shl r/m32, imm8: C1 /4 ib
  let b = (dst >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xC1)
  emit_modrm(self, 3, 4, dst)
  self.emit_byte(imm & 255)
}

///|
pub fn CodeBuffer::x86_emit_shr_r_imm8(
  self : CodeBuffer,
  dst : Int32,
  imm : Int32,
) -> Unit {
  // shr r/m64, imm8: REX.W + C1 /5 ib
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xC1)
  emit_modrm(self, 3, 5, dst)
  self.emit_byte(imm & 255)
}

///|
pub fn CodeBuffer::x86_emit_shr_r32_imm8(
  self : CodeBuffer,
  dst : Int32,
  imm : Int32,
) -> Unit {
  // shr r/m32, imm8: C1 /5 ib
  let b = (dst >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xC1)
  emit_modrm(self, 3, 5, dst)
  self.emit_byte(imm & 255)
}

///|
pub fn CodeBuffer::x86_emit_mov_rr(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // mov r/m64, r64: REX.W + 89 /r
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x89)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn CodeBuffer::x86_emit_mov_rr32(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // mov r/m32, r32: 89 /r
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x89)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn CodeBuffer::x86_emit_movsxd_r64_r32(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // movsxd r64, r/m32: REX.W + 63 /r
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x63)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn CodeBuffer::x86_emit_movsx_r32_r8(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // movsx r32, r/m8: 0F BE /r
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  if r != 0 || b != 0 || (src & 7) >= 4 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xBE)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn CodeBuffer::x86_emit_movsx_r64_r8(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // movsx r64, r/m8: REX.W + 0F BE /r
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0xBE)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn CodeBuffer::x86_emit_movsx_r32_r16(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // movsx r32, r/m16: 0F BF /r
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xBF)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn CodeBuffer::x86_emit_movsx_r64_r16(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // movsx r64, r/m16: REX.W + 0F BF /r
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0xBF)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn CodeBuffer::x86_emit_push_r64(self : CodeBuffer, reg : Int32) -> Unit {
  // push r64: 50+rd, with optional REX.B for r8-r15.
  let b = (reg >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0x50 + (reg & 7))
}

///|
pub fn CodeBuffer::x86_emit_pop_r64(self : CodeBuffer, reg : Int32) -> Unit {
  // pop r64: 58+rd, with optional REX.B for r8-r15.
  let b = (reg >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0x58 + (reg & 7))
}

///|
pub fn CodeBuffer::x86_emit_call_r64(self : CodeBuffer, reg : Int32) -> Unit {
  // call r/m64: FF /2
  let b = (reg >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xFF)
  // /2 in reg field.
  emit_modrm(self, 3, 2, reg)
}

///|
pub fn CodeBuffer::x86_emit_jmp_r64(self : CodeBuffer, reg : Int32) -> Unit {
  // jmp r/m64: FF /4
  let b = (reg >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xFF)
  // /4 in reg field.
  emit_modrm(self, 3, 4, reg)
}

///|
pub fn CodeBuffer::x86_emit_sub_rsp_imm32(
  self : CodeBuffer,
  imm : Int32,
) -> Unit {
  // sub rsp, imm32: 48 81 EC imm32
  self.emit_byte(0x48)
  self.emit_byte(0x81)
  self.emit_byte(0xEC)
  emit_u32_le(self, imm)
}

///|
pub fn CodeBuffer::x86_emit_add_rsp_imm32(
  self : CodeBuffer,
  imm : Int32,
) -> Unit {
  // add rsp, imm32: 48 81 C4 imm32
  self.emit_byte(0x48)
  self.emit_byte(0x81)
  self.emit_byte(0xC4)
  emit_u32_le(self, imm)
}

///|
pub fn CodeBuffer::x86_emit_mov_r64_m64(
  self : CodeBuffer,
  dst : Int32,
  base : Int32,
  disp : Int32,
) -> Unit {
  // mov r64, [base + disp32]: REX.W + 8B /r, modrm with mod=10 (disp32).
  let r = (dst >> 3) & 1
  let b = (base >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x8B)
  emit_modrm(self, 2, dst, base)
  if (base & 7) == 4 {
    // SIB required for rsp/r12 base.
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_mov_r32_m32(
  self : CodeBuffer,
  dst : Int32,
  base : Int32,
  disp : Int32,
) -> Unit {
  // mov r32, [base + disp32]: 8B /r
  let r = (dst >> 3) & 1
  let b = (base >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x8B)
  emit_modrm(self, 2, dst, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_mov_m64_r64(
  self : CodeBuffer,
  base : Int32,
  disp : Int32,
  src : Int32,
) -> Unit {
  // mov [base + disp32], r64: REX.W + 89 /r, modrm with mod=10 (disp32).
  let r = (src >> 3) & 1
  let b = (base >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x89)
  emit_modrm(self, 2, src, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_mov_m32_r32(
  self : CodeBuffer,
  base : Int32,
  disp : Int32,
  src : Int32,
) -> Unit {
  // mov [base + disp32], r32: 89 /r
  let r = (src >> 3) & 1
  let b = (base >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x89)
  emit_modrm(self, 2, src, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_mov_m8_r8(
  self : CodeBuffer,
  base : Int32,
  disp : Int32,
  src : Int32,
) -> Unit {
  // mov r/m8, r8: 88 /r
  //
  // Low 8-bit register forms SPL/BPL/SIL/DIL require a REX prefix, so we emit
  // a REX prefix whenever the src reg needs it (or when selecting r8b-r15b).
  let r = (src >> 3) & 1
  let b = (base >> 3) & 1
  if r != 0 || b != 0 || (src & 7) >= 4 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x88)
  emit_modrm(self, 2, src, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_mov_m16_r16(
  self : CodeBuffer,
  base : Int32,
  disp : Int32,
  src : Int32,
) -> Unit {
  // mov r/m16, r16: 66 89 /r
  let r = (src >> 3) & 1
  let b = (base >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x89)
  emit_modrm(self, 2, src, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_movaps_xmm_xmm(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // movaps xmm, xmm: 0F 28 /r
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x28)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn CodeBuffer::x86_emit_minps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // minps xmm, xmm/m128: 0F 5D /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5D)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_minpd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // minpd xmm, xmm/m128: 66 0F 5D /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5D)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_maxps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // maxps xmm, xmm/m128: 0F 5F /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5F)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_maxpd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // maxpd xmm, xmm/m128: 66 0F 5F /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5F)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_subps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // subps xmm, xmm/m128: 0F 5C /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5C)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_subpd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // subpd xmm, xmm/m128: 66 0F 5C /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5C)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_addps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // addps xmm, xmm/m128: 0F 58 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x58)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_addpd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // addpd xmm, xmm/m128: 66 0F 58 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x58)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_mulps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // mulps xmm, xmm/m128: 0F 59 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x59)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_mulpd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // mulpd xmm, xmm/m128: 66 0F 59 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x59)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_divps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // divps xmm, xmm/m128: 0F 5E /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5E)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_divpd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // divpd xmm, xmm/m128: 66 0F 5E /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5E)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_sqrtps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // sqrtps xmm, xmm/m128: 0F 51 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x51)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_sqrtpd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // sqrtpd xmm, xmm/m128: 66 0F 51 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x51)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pslld_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // pslld xmm, imm8: 66 0F 72 /6 ib
  let b = (dst_xmm >> 3) & 1
  self.emit_byte(0x66)
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x72)
  emit_modrm(self, 3, 6, dst_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_psllq_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // psllq xmm, imm8: 66 0F 73 /6 ib
  let b = (dst_xmm >> 3) & 1
  self.emit_byte(0x66)
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x73)
  emit_modrm(self, 3, 6, dst_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_psllw_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // psllw xmm, imm8: 66 0F 71 /6 ib
  let b = (dst_xmm >> 3) & 1
  self.emit_byte(0x66)
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x71)
  emit_modrm(self, 3, 6, dst_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_psll_xmm_xmm(
  self : CodeBuffer,
  lane_size : RawLaneSize,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // psll{w,d,q} xmm, xmm/m128: 66 0F F1/F2/F3 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  match lane_size {
    H16 => self.emit_byte(0xF1)
    S32 => self.emit_byte(0xF2)
    D64 => self.emit_byte(0xF3)
    _ => abort("x86_64 psll: unsupported lane size \{lane_size}")
  }
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_psrl_xmm_xmm(
  self : CodeBuffer,
  lane_size : RawLaneSize,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // psrl{w,d,q} xmm, xmm/m128: 66 0F D1/D2/D3 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  match lane_size {
    H16 => self.emit_byte(0xD1)
    S32 => self.emit_byte(0xD2)
    D64 => self.emit_byte(0xD3)
    _ => abort("x86_64 psrl: unsupported lane size \{lane_size}")
  }
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_psra_xmm_xmm(
  self : CodeBuffer,
  lane_size : RawLaneSize,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // psra{w,d} xmm, xmm/m128: 66 0F E1/E2 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  match lane_size {
    H16 => self.emit_byte(0xE1)
    S32 => self.emit_byte(0xE2)
    _ => abort("x86_64 psra: unsupported lane size \{lane_size}")
  }
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_psrlw_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // psrlw xmm, imm8: 66 0F 71 /2 ib
  let b = (dst_xmm >> 3) & 1
  self.emit_byte(0x66)
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x71)
  emit_modrm(self, 3, 2, dst_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_psrad_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // psrad xmm, imm8: 66 0F 72 /4 ib
  let b = (dst_xmm >> 3) & 1
  self.emit_byte(0x66)
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x72)
  emit_modrm(self, 3, 4, dst_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_cmpps_xmm_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // cmpps xmm, xmm/m128, imm8: 0F C2 /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xC2)
  emit_modrm(self, 3, dst_xmm, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_cmppd_xmm_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // cmppd xmm, xmm/m128, imm8: 66 0F C2 /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xC2)
  emit_modrm(self, 3, dst_xmm, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_roundps_xmm_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // roundps xmm, xmm/m128, imm8: 66 0F 3A 08 /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x08)
  emit_modrm(self, 3, dst_xmm, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_roundpd_xmm_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // roundpd xmm, xmm/m128, imm8: 66 0F 3A 09 /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x09)
  emit_modrm(self, 3, dst_xmm, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_roundss_xmm_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // roundss xmm, xmm/m32, imm8: 66 0F 3A 0A /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x0A)
  emit_modrm(self, 3, dst_xmm, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_roundsd_xmm_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // roundsd xmm, xmm/m64, imm8: 66 0F 3A 0B /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x0B)
  emit_modrm(self, 3, dst_xmm, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_psrld_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // psrld xmm, imm8: 66 0F 72 /2 ib
  let b = (dst_xmm >> 3) & 1
  self.emit_byte(0x66)
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x72)
  emit_modrm(self, 3, 2, dst_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_psrlq_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // psrlq xmm, imm8: 66 0F 73 /2 ib
  let b = (dst_xmm >> 3) & 1
  self.emit_byte(0x66)
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x73)
  emit_modrm(self, 3, 2, dst_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_movss_xmm_m32(
  self : CodeBuffer,
  dst_xmm : Int32,
  base : Int32,
  disp : Int32,
) -> Unit {
  // movss xmm, m32: F3 0F 10 /r
  let r = (dst_xmm >> 3) & 1
  let b = (base >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x10)
  emit_modrm(self, 2, dst_xmm, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_movss_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // movss xmm1, xmm2/m32: F3 0F 10 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x10)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_movss_m32_xmm(
  self : CodeBuffer,
  base : Int32,
  disp : Int32,
  src_xmm : Int32,
) -> Unit {
  // movss m32, xmm: F3 0F 11 /r
  let r = (src_xmm >> 3) & 1
  let b = (base >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x11)
  emit_modrm(self, 2, src_xmm, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_movsd_m64_xmm(
  self : CodeBuffer,
  base : Int32,
  disp : Int32,
  src_xmm : Int32,
) -> Unit {
  // movsd m64, xmm: F2 0F 11 /r
  let r = (src_xmm >> 3) & 1
  let b = (base >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x11)
  emit_modrm(self, 2, src_xmm, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_movsd_xmm_m64(
  self : CodeBuffer,
  dst_xmm : Int32,
  base : Int32,
  disp : Int32,
) -> Unit {
  // movsd xmm, m64: F2 0F 10 /r
  let r = (dst_xmm >> 3) & 1
  let b = (base >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x10)
  emit_modrm(self, 2, dst_xmm, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_movsd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // movsd xmm1, xmm2/m64: F2 0F 10 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x10)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_movlhps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // movlhps xmm1, xmm2/m64: 0F 16 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x16)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_unpcklps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // unpcklps xmm1, xmm2/m128: 0F 14 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x14)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_ucomiss_xmm_xmm(
  self : CodeBuffer,
  lhs_xmm : Int32,
  rhs_xmm : Int32,
) -> Unit {
  // ucomiss xmm1, xmm2: 0F 2E /r
  let r = (lhs_xmm >> 3) & 1
  let b = (rhs_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x2E)
  emit_modrm(self, 3, lhs_xmm, rhs_xmm)
}

///|
pub fn CodeBuffer::x86_emit_ucomisd_xmm_xmm(
  self : CodeBuffer,
  lhs_xmm : Int32,
  rhs_xmm : Int32,
) -> Unit {
  // ucomisd xmm1, xmm2: 66 0F 2E /r
  let r = (lhs_xmm >> 3) & 1
  let b = (rhs_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x2E)
  emit_modrm(self, 3, lhs_xmm, rhs_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pcmpeqd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pcmpeqd xmm, xmm/m128: 66 0F 76 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x76)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pand_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pand xmm, xmm/m128: 66 0F DB /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xDB)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_por_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // por xmm, xmm/m128: 66 0F EB /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xEB)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pxor_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pxor xmm, xmm/m128: 66 0F EF /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xEF)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pandn_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pandn xmm, xmm/m128: 66 0F DF /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xDF)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pinsrq_xmm_r64_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src : Int32,
  imm8 : Int32,
) -> Unit {
  // pinsrq xmm, r/m64, imm8: 66 REX.W 0F 3A 22 /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src >> 3) & 1
  self.emit_byte(0x66)
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x22)
  emit_modrm(self, 3, dst_xmm, src)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_pinsrd_xmm_r32_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src : Int32,
  imm8 : Int32,
) -> Unit {
  // pinsrd xmm, r/m32, imm8: 66 0F 3A 22 /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x22)
  emit_modrm(self, 3, dst_xmm, src)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_pinsrw_xmm_r32_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src : Int32,
  imm8 : Int32,
) -> Unit {
  // pinsrw xmm, r/m16, imm8: 66 0F C4 /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xC4)
  emit_modrm(self, 3, dst_xmm, src)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_pinsrb_xmm_r32_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src : Int32,
  imm8 : Int32,
) -> Unit {
  // pinsrb xmm, r/m8, imm8 (SSE4.1): 66 0F 3A 20 /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src >> 3) & 1
  self.emit_byte(0x66)
  // Low 8-bit register forms SPL/BPL/SIL/DIL require a REX prefix.
  if r != 0 || b != 0 || (src & 7) >= 4 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x20)
  emit_modrm(self, 3, dst_xmm, src)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_insertps_xmm_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // insertps xmm1, xmm2/m32, imm8 (SSE4.1): 66 0F 3A 21 /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x21)
  emit_modrm(self, 3, dst_xmm, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_padd_xmm_xmm(
  self : CodeBuffer,
  lane_size : RawLaneSize,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // padd{b,w,d,q}: 66 0F FC/FD/FE/D4 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  match lane_size {
    B8 => self.emit_byte(0xFC)
    H16 => self.emit_byte(0xFD)
    S32 => self.emit_byte(0xFE)
    D64 => self.emit_byte(0xD4)
  }
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_phaddw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // phaddw (SSSE3): 66 0F 38 01 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x01)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_psub_xmm_xmm(
  self : CodeBuffer,
  lane_size : RawLaneSize,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // psub{b,w,d,q}: 66 0F F8/F9/FA/FB /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  match lane_size {
    B8 => self.emit_byte(0xF8)
    H16 => self.emit_byte(0xF9)
    S32 => self.emit_byte(0xFA)
    D64 => self.emit_byte(0xFB)
  }
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmullw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmullw: 66 0F D5 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xD5)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmulld_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmulld (SSE4.1): 66 0F 38 40 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x40)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pcmpeq_xmm_xmm(
  self : CodeBuffer,
  lane_size : RawLaneSize,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pcmpeq{b,w,d,q}: 66 0F 74/75/76/38 29 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  match lane_size {
    B8 => {
      self.emit_byte(0x74)
      emit_modrm(self, 3, dst_xmm, src_xmm)
    }
    H16 => {
      self.emit_byte(0x75)
      emit_modrm(self, 3, dst_xmm, src_xmm)
    }
    S32 => {
      self.emit_byte(0x76)
      emit_modrm(self, 3, dst_xmm, src_xmm)
    }
    D64 =>
      // pcmpeqq is SSE4.1; avoid relying on it and use an emulation sequence at a higher level.
      abort("x86_64 pcmpeq.i64: use emulation sequence instead")
  }
}

///|
pub fn CodeBuffer::x86_emit_pcmpgt_xmm_xmm(
  self : CodeBuffer,
  lane_size : RawLaneSize,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pcmpgt{b,w,d}: 66 0F 64/65/66 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  match lane_size {
    B8 => self.emit_byte(0x64)
    H16 => self.emit_byte(0x65)
    S32 => self.emit_byte(0x66)
    D64 => abort("x86_64 pcmpgt.i64: use emulation sequence instead")
  }
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pshufd_xmm_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // pshufd xmm1, xmm2/m128, imm8: 66 0F 70 /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x70)
  emit_modrm(self, 3, dst_xmm, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_pshuflw_xmm_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // pshuflw xmm1, xmm2/m128, imm8: F2 0F 70 /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x70)
  emit_modrm(self, 3, dst_xmm, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_shufps_xmm_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // shufps xmm1, xmm2/m128, imm8: 0F C6 /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xC6)
  emit_modrm(self, 3, dst_xmm, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_shufpd_xmm_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // shufpd xmm1, xmm2/m128, imm8: 66 0F C6 /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xC6)
  emit_modrm(self, 3, dst_xmm, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_paddusb_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // paddusb xmm, xmm/m128: 66 0F DC /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xDC)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_paddsb_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // paddsb xmm, xmm/m128: 66 0F EC /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xEC)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_paddsw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // paddsw xmm, xmm/m128: 66 0F ED /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xED)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_paddusw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // paddusw xmm, xmm/m128: 66 0F DD /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xDD)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_psubsb_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // psubsb xmm, xmm/m128: 66 0F E8 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xE8)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_psubsw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // psubsw xmm, xmm/m128: 66 0F E9 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xE9)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_psubusb_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // psubusb xmm, xmm/m128: 66 0F D8 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xD8)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_psubusw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // psubusw xmm, xmm/m128: 66 0F D9 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xD9)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pavgb_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pavgb xmm, xmm/m128: 66 0F E0 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xE0)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pavgw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pavgw xmm, xmm/m128: 66 0F E3 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xE3)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pminub_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pminub xmm, xmm/m128: 66 0F DA /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xDA)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmaxub_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmaxub xmm, xmm/m128: 66 0F DE /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xDE)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pminsw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pminsw xmm, xmm/m128: 66 0F EA /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xEA)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmaxsw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmaxsw xmm, xmm/m128: 66 0F EE /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xEE)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pminsb_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pminsb xmm, xmm/m128 (SSE4.1): 66 0F 38 38 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x38)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmaxsb_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmaxsb xmm, xmm/m128 (SSE4.1): 66 0F 38 3C /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x3C)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pminuw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pminuw xmm, xmm/m128 (SSE4.1): 66 0F 38 3A /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x3A)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmaxuw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmaxuw xmm, xmm/m128 (SSE4.1): 66 0F 38 3E /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x3E)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pminsd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pminsd xmm, xmm/m128 (SSE4.1): 66 0F 38 39 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x39)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmaxsd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmaxsd xmm, xmm/m128 (SSE4.1): 66 0F 38 3D /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x3D)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pminud_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pminud xmm, xmm/m128 (SSE4.1): 66 0F 38 3B /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x3B)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmaxud_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmaxud xmm, xmm/m128 (SSE4.1): 66 0F 38 3F /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x3F)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pabsb_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pabsb xmm, xmm/m128 (SSSE3): 66 0F 38 1C /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x1C)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pabsw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pabsw xmm, xmm/m128 (SSSE3): 66 0F 38 1D /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x1D)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pabsd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pabsd xmm, xmm/m128 (SSSE3): 66 0F 38 1E /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x1E)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmovsxbw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmovsxbw xmm, xmm/m64 (SSE4.1): 66 0F 38 20 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x20)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmovzxbw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmovzxbw xmm, xmm/m64 (SSE4.1): 66 0F 38 30 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x30)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmovsxwd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmovsxwd xmm, xmm/m64 (SSE4.1): 66 0F 38 23 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x23)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmovzxwd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmovzxwd xmm, xmm/m64 (SSE4.1): 66 0F 38 33 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x33)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmovsxdq_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmovsxdq xmm, xmm/m64 (SSE4.1): 66 0F 38 25 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x25)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmovzxdq_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmovzxdq xmm, xmm/m64 (SSE4.1): 66 0F 38 35 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x35)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pshufb_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  mask_xmm : Int32,
) -> Unit {
  // pshufb xmm, xmm/m128 (SSSE3): 66 0F 38 00 /r
  let r = (dst_xmm >> 3) & 1
  let b = (mask_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x00)
  emit_modrm(self, 3, dst_xmm, mask_xmm)
}

///|
pub fn CodeBuffer::x86_emit_punpcklbw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // punpcklbw xmm, xmm/m128: 66 0F 60 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x60)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_punpckhbw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // punpckhbw xmm, xmm/m128: 66 0F 68 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x68)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_packsswb_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // packsswb xmm, xmm/m128: 66 0F 63 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x63)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_packuswb_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // packuswb xmm, xmm/m128: 66 0F 67 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x67)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_packssdw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // packssdw xmm, xmm/m128: 66 0F 6B /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x6B)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_packusdw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // packusdw xmm, xmm/m128 (SSE4.1): 66 0F 38 2B /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x2B)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_palignr_xmm_xmm_imm8(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // palignr xmm, xmm/m128, imm8 (SSSE3): 66 0F 3A 0F /r ib
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x0F)
  emit_modrm(self, 3, dst_xmm, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_pmaddwd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmaddwd xmm, xmm/m128: 66 0F F5 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xF5)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmaddubsw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmaddubsw xmm, xmm/m128 (SSSE3): 66 0F 38 04 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x04)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pmulhrsw_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmulhrsw xmm, xmm/m128 (SSSE3): 66 0F 38 0B /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x0B)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_pextrb_r32_xmm_imm8(
  self : CodeBuffer,
  dst : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // pextrb r32, xmm, imm8 (SSE4.1): 66 0F 3A 14 /r ib
  // ModRM.reg encodes the XMM source; ModRM.r/m encodes the GPR destination.
  let r = (src_xmm >> 3) & 1
  let b = (dst >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x14)
  emit_modrm(self, 3, src_xmm, dst)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_pextrd_r32_xmm_imm8(
  self : CodeBuffer,
  dst : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // pextrd r32, xmm, imm8 (SSE4.1): 66 0F 3A 16 /r ib
  // ModRM.reg encodes the XMM source; ModRM.r/m encodes the GPR destination.
  let r = (src_xmm >> 3) & 1
  let b = (dst >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x16)
  emit_modrm(self, 3, src_xmm, dst)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_pextrq_r64_xmm_imm8(
  self : CodeBuffer,
  dst : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // pextrq r64, xmm, imm8 (SSE4.1): 66 REX.W 0F 3A 16 /r ib
  // ModRM.reg encodes the XMM source; ModRM.r/m encodes the GPR destination.
  let r = (src_xmm >> 3) & 1
  let b = (dst >> 3) & 1
  self.emit_byte(0x66)
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x16)
  emit_modrm(self, 3, src_xmm, dst)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_pextrw_r32_xmm_imm8(
  self : CodeBuffer,
  dst : Int32,
  src_xmm : Int32,
  imm8 : Int32,
) -> Unit {
  // pextrw r32, xmm, imm8 (SSE2): 66 0F C5 /r ib
  let r = (dst >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xC5)
  emit_modrm(self, 3, dst, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_pmovmskb_r32_xmm(
  self : CodeBuffer,
  dst : Int32,
  src_xmm : Int32,
) -> Unit {
  // pmovmskb r32, xmm: 66 0F D7 /r
  //
  // Note: Intel manual notes operand-size is 64-bit by default in 64-bit mode
  // but we only need 16 bits. Do not set REX.W.
  let r = (dst >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xD7)
  emit_modrm(self, 3, dst, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_movmskps_r32_xmm(
  self : CodeBuffer,
  dst : Int32,
  src_xmm : Int32,
) -> Unit {
  // movmskps r32, xmm: 0F 50 /r
  let r = (dst >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x50)
  emit_modrm(self, 3, dst, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_movmskpd_r32_xmm(
  self : CodeBuffer,
  dst : Int32,
  src_xmm : Int32,
) -> Unit {
  // movmskpd r32, xmm: 66 0F 50 /r
  let r = (dst >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x50)
  emit_modrm(self, 3, dst, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_xorpd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // xorpd xmm1, xmm2: 66 0F 57 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x57)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_xorps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // xorps xmm1, xmm2: 0F 57 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x57)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_subss_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // subss xmm1, xmm2: F3 0F 5C /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5C)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_subsd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // subsd xmm1, xmm2: F2 0F 5C /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5C)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_addss_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // addss xmm1, xmm2: F3 0F 58 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x58)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_addsd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // addsd xmm1, xmm2: F2 0F 58 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x58)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_minss_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // minss xmm1, xmm2: F3 0F 5D /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5D)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_minsd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // minsd xmm1, xmm2: F2 0F 5D /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5D)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_maxss_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // maxss xmm1, xmm2: F3 0F 5F /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5F)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_maxsd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // maxsd xmm1, xmm2: F2 0F 5F /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5F)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_mulss_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // mulss xmm1, xmm2: F3 0F 59 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x59)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_mulsd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // mulsd xmm1, xmm2: F2 0F 59 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x59)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_divss_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // divss xmm1, xmm2: F3 0F 5E /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5E)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_divsd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // divsd xmm1, xmm2: F2 0F 5E /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5E)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_sqrtss_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // sqrtss xmm1, xmm2: F3 0F 51 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x51)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_sqrtsd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // sqrtsd xmm1, xmm2: F2 0F 51 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x51)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_andps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // andps xmm1, xmm2: 0F 54 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x54)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_andpd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // andpd xmm1, xmm2: 66 0F 54 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x54)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_orps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // orps xmm1, xmm2: 0F 56 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x56)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_orpd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // orpd xmm1, xmm2: 66 0F 56 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x56)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_cvttss2si_r32_xmm(
  self : CodeBuffer,
  dst : Int32,
  src_xmm : Int32,
) -> Unit {
  // cvttss2si r32, xmm: F3 0F 2C /r
  let r = (dst >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x2C)
  emit_modrm(self, 3, dst, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_cvttss2si_r64_xmm(
  self : CodeBuffer,
  dst : Int32,
  src_xmm : Int32,
) -> Unit {
  // cvttss2si r64, xmm: REX.W + F3 0F 2C /r
  let r = (dst >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF3)
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0x2C)
  emit_modrm(self, 3, dst, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_cvttsd2si_r32_xmm(
  self : CodeBuffer,
  dst : Int32,
  src_xmm : Int32,
) -> Unit {
  // cvttsd2si r32, xmm: F2 0F 2C /r
  let r = (dst >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x2C)
  emit_modrm(self, 3, dst, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_cvttsd2si_r64_xmm(
  self : CodeBuffer,
  dst : Int32,
  src_xmm : Int32,
) -> Unit {
  // cvttsd2si r64, xmm: REX.W + F2 0F 2C /r
  let r = (dst >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF2)
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0x2C)
  emit_modrm(self, 3, dst, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_cvtsi2ss_xmm_r32(
  self : CodeBuffer,
  dst_xmm : Int32,
  src : Int32,
) -> Unit {
  // cvtsi2ss xmm, r/m32: F3 0F 2A /r
  let r = (dst_xmm >> 3) & 1
  let b = (src >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x2A)
  emit_modrm(self, 3, dst_xmm, src)
}

///|
pub fn CodeBuffer::x86_emit_cvtsi2ss_xmm_r64(
  self : CodeBuffer,
  dst_xmm : Int32,
  src : Int32,
) -> Unit {
  // cvtsi2ss xmm, r/m64: REX.W + F3 0F 2A /r
  let r = (dst_xmm >> 3) & 1
  let b = (src >> 3) & 1
  self.emit_byte(0xF3)
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0x2A)
  emit_modrm(self, 3, dst_xmm, src)
}

///|
pub fn CodeBuffer::x86_emit_cvtsi2sd_xmm_r32(
  self : CodeBuffer,
  dst_xmm : Int32,
  src : Int32,
) -> Unit {
  // cvtsi2sd xmm, r/m32: F2 0F 2A /r
  let r = (dst_xmm >> 3) & 1
  let b = (src >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x2A)
  emit_modrm(self, 3, dst_xmm, src)
}

///|
pub fn CodeBuffer::x86_emit_cvtsi2sd_xmm_r64(
  self : CodeBuffer,
  dst_xmm : Int32,
  src : Int32,
) -> Unit {
  // cvtsi2sd xmm, r/m64: REX.W + F2 0F 2A /r
  let r = (dst_xmm >> 3) & 1
  let b = (src >> 3) & 1
  self.emit_byte(0xF2)
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0x2A)
  emit_modrm(self, 3, dst_xmm, src)
}

///|
pub fn CodeBuffer::x86_emit_cvtss2sd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // cvtss2sd xmm1, xmm2: F3 0F 5A /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5A)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_cvtsd2ss_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // cvtsd2ss xmm1, xmm2: F2 0F 5A /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF2)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5A)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_cvtdq2ps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // cvtdq2ps xmm1, xmm2/m128: 0F 5B /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5B)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_cvttps2dq_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // cvttps2dq xmm1, xmm2/m128: F3 0F 5B /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5B)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_cvttpd2dq_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // cvttpd2dq xmm1, xmm2/m128: 66 0F E6 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xE6)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_cvtdq2pd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // cvtdq2pd xmm1, xmm2/m64: F3 0F E6 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xE6)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_cvtps2pd_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // cvtps2pd xmm1, xmm2/m64: 0F 5A /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5A)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_cvtpd2ps_xmm_xmm(
  self : CodeBuffer,
  dst_xmm : Int32,
  src_xmm : Int32,
) -> Unit {
  // cvtpd2ps xmm1, xmm2/m128: 66 0F 5A /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x5A)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn CodeBuffer::x86_emit_movdqu_m128_xmm(
  self : CodeBuffer,
  base : Int32,
  disp : Int32,
  src_xmm : Int32,
) -> Unit {
  // movdqu m128, xmm: F3 0F 7F /r
  let r = (src_xmm >> 3) & 1
  let b = (base >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x7F)
  emit_modrm(self, 2, src_xmm, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_movdqu_xmm_m128(
  self : CodeBuffer,
  dst_xmm : Int32,
  base : Int32,
  disp : Int32,
) -> Unit {
  // movdqu xmm, m128: F3 0F 6F /r
  let r = (dst_xmm >> 3) & 1
  let b = (base >> 3) & 1
  self.emit_byte(0xF3)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x6F)
  emit_modrm(self, 2, dst_xmm, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_movsx_r64_m8(
  self : CodeBuffer,
  dst : Int32,
  base : Int32,
  disp : Int32,
) -> Unit {
  // movsx r64, m8: REX.W + 0F BE /r
  let r = (dst >> 3) & 1
  let b = (base >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0xBE)
  emit_modrm(self, 2, dst, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_movzx_r32_m8(
  self : CodeBuffer,
  dst : Int32,
  base : Int32,
  disp : Int32,
) -> Unit {
  // movzx r32, m8: 0F B6 /r
  let r = (dst >> 3) & 1
  let b = (base >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xB6)
  emit_modrm(self, 2, dst, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_movsx_r64_m16(
  self : CodeBuffer,
  dst : Int32,
  base : Int32,
  disp : Int32,
) -> Unit {
  // movsx r64, m16: REX.W + 0F BF /r
  let r = (dst >> 3) & 1
  let b = (base >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0xBF)
  emit_modrm(self, 2, dst, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_movzx_r32_m16(
  self : CodeBuffer,
  dst : Int32,
  base : Int32,
  disp : Int32,
) -> Unit {
  // movzx r32, m16: 0F B7 /r
  let r = (dst >> 3) & 1
  let b = (base >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xB7)
  emit_modrm(self, 2, dst, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_movsxd_r64_m32(
  self : CodeBuffer,
  dst : Int32,
  base : Int32,
  disp : Int32,
) -> Unit {
  // movsxd r64, m32: REX.W + 63 /r
  let r = (dst >> 3) & 1
  let b = (base >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x63)
  emit_modrm(self, 2, dst, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, disp)
}

///|
pub fn CodeBuffer::x86_emit_ret(self : CodeBuffer) -> Unit {
  self.emit_byte(0xC3)
}

///|
pub fn x86_cond_to_jcc_opcode(cond : RawCondition) -> Int32 {
  match cond {
    // Signed/unsigned conditions match the usual interpretation after CMP.
    RawEq => 0x84 // JE
    RawNe => 0x85 // JNE
    RawHs => 0x83 // JAE/JNB
    RawLo => 0x82 // JB
    RawPl => 0x89 // JNS
    RawVs => 0x80 // JO
    // Parity conditions (x86_64-only; used after UCOMIS*).
    RawPs => 0x8A // JP/JPE (parity set)
    RawPc => 0x8B // JNP/JPO (parity clear)
    RawHi => 0x87 // JA
    RawLs => 0x86 // JBE
    RawGe => 0x8D // JGE
    RawLt => 0x8C // JL
    RawGt => 0x8F // JG
    RawLe => 0x8E // JLE
    RawAl => abort("x86_64 jcc: AL is not a conditional branch")
  }
}

///|
pub fn CodeBuffer::x86_emit_setcc_r8(
  self : CodeBuffer,
  cond : RawCondition,
  dst : Int32,
) -> Unit {
  // setcc r/m8: 0F 90+cc /r
  //
  // Note: low 8-bit register forms SPL/BPL/SIL/DIL require a REX prefix. We
  // always emit a REX prefix when needed to select those forms or r8b-r15b.
  let opcode = x86_cond_to_jcc_opcode(cond) + 0x10 // 0x90+cc
  let b = (dst >> 3) & 1
  if b != 0 || (dst & 7) >= 4 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(opcode)
  emit_modrm(self, 3, 0, dst)
}

///|
pub fn CodeBuffer::x86_emit_movzx_r32_r8(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // movzx r32, r/m8: 0F B6 /r (modrm mod=11 for register source)
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  if r != 0 || b != 0 || (src & 7) >= 4 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xB6)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn CodeBuffer::x86_emit_movzx_r32_r16(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xB7)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn CodeBuffer::x86_emit_cqo(self : CodeBuffer) -> Unit {
  // cqo: sign-extend rax into rdx:rax (64-bit)
  self.emit_byte(0x48)
  self.emit_byte(0x99)
}

///|
pub fn CodeBuffer::x86_emit_cdq(self : CodeBuffer) -> Unit {
  // cdq: sign-extend eax into edx:eax (32-bit)
  self.emit_byte(0x99)
}

///|
pub fn CodeBuffer::x86_emit_idiv_r64(
  self : CodeBuffer,
  divisor : Int32,
) -> Unit {
  // idiv r/m64: REX.W + F7 /7
  let b = (divisor >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 7, divisor)
}

///|
pub fn CodeBuffer::x86_emit_idiv_r32(
  self : CodeBuffer,
  divisor : Int32,
) -> Unit {
  // idiv r/m32: F7 /7
  let b = (divisor >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 7, divisor)
}

///|
pub fn CodeBuffer::x86_emit_div_r64(self : CodeBuffer, divisor : Int32) -> Unit {
  // div r/m64: REX.W + F7 /6
  let b = (divisor >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 6, divisor)
}

///|
pub fn CodeBuffer::x86_emit_div_r32(self : CodeBuffer, divisor : Int32) -> Unit {
  // div r/m32: F7 /6
  let b = (divisor >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 6, divisor)
}

///|
pub fn CodeBuffer::x86_emit_mul_r64(self : CodeBuffer, src : Int32) -> Unit {
  // mul r/m64: REX.W + F7 /4
  let b = (src >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 4, src)
}

///|
pub fn CodeBuffer::x86_emit_mul_r32(self : CodeBuffer, src : Int32) -> Unit {
  let b = (src >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 4, src)
}

///|
pub fn CodeBuffer::x86_emit_imul1_r64(self : CodeBuffer, src : Int32) -> Unit {
  // imul r/m64 (one-operand): REX.W + F7 /5
  let b = (src >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 5, src)
}

///|
pub fn CodeBuffer::x86_emit_imul1_r32(self : CodeBuffer, src : Int32) -> Unit {
  let b = (src >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 5, src)
}

///|
pub fn CodeBuffer::x86_emit_cmp_r_imm32(
  self : CodeBuffer,
  reg : Int32,
  imm : Int32,
) -> Unit {
  // cmp r/m64, imm32: REX.W + 81 /7 id
  let b = (reg >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0x81)
  emit_modrm(self, 3, 7, reg)
  emit_u32_le(self, imm)
}

///|
pub fn CodeBuffer::x86_emit_cmp_r32_imm32(
  self : CodeBuffer,
  reg : Int32,
  imm : Int32,
) -> Unit {
  // cmp r/m32, imm32: 81 /7 id
  let b = (reg >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0x81)
  emit_modrm(self, 3, 7, reg)
  emit_u32_le(self, imm)
}

///|
pub fn CodeBuffer::x86_emit_and_r_imm8_sxb64(
  self : CodeBuffer,
  reg : Int32,
  imm8 : Int32,
) -> Unit {
  // and r/m64, imm8: REX.W + 83 /4 ib (imm8 sign-extended)
  let b = (reg >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0x83)
  emit_modrm(self, 3, 4, reg)
  self.emit_byte(imm8 & 255)
}

///|
pub fn CodeBuffer::x86_emit_cmovcc_rr(
  self : CodeBuffer,
  cond : RawCondition,
  dst : Int32,
  src : Int32,
) -> Unit {
  // cmovcc r64, r/m64: REX.W + 0F 40+cc /r
  let cc = x86_cond_to_jcc_opcode(cond) & 15
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0x40 + cc)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn CodeBuffer::x86_emit_cmovcc_rr32(
  self : CodeBuffer,
  cond : RawCondition,
  dst : Int32,
  src : Int32,
) -> Unit {
  // cmovcc r32, r/m32: 0F 40+cc /r
  let cc = x86_cond_to_jcc_opcode(cond) & 15
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x40 + cc)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn CodeBuffer::x86_emit_movd_r32_xmm(
  self : CodeBuffer,
  dst : Int32,
  src_xmm : Int32,
) -> Unit {
  // movd r/m32, xmm: 66 0F 7E /r
  let r = (src_xmm >> 3) & 1
  let b = (dst >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x7E)
  emit_modrm(self, 3, src_xmm, dst)
}

///|
pub fn CodeBuffer::x86_emit_movd_xmm_r32(
  self : CodeBuffer,
  dst_xmm : Int32,
  src : Int32,
) -> Unit {
  // movd xmm, r/m32: 66 0F 6E /r
  let r = (dst_xmm >> 3) & 1
  let b = (src >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x6E)
  emit_modrm(self, 3, dst_xmm, src)
}

///|
pub fn CodeBuffer::x86_emit_movq_r64_xmm(
  self : CodeBuffer,
  dst : Int32,
  src_xmm : Int32,
) -> Unit {
  // movq r/m64, xmm: REX.W + 66 0F 7E /r
  let r = (src_xmm >> 3) & 1
  let b = (dst >> 3) & 1
  self.emit_byte(0x66)
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0x7E)
  emit_modrm(self, 3, src_xmm, dst)
}

///|
pub fn CodeBuffer::x86_emit_movq_xmm_r64(
  self : CodeBuffer,
  dst_xmm : Int32,
  src : Int32,
) -> Unit {
  // movq xmm, r/m64: REX.W + 66 0F 6E /r
  let r = (dst_xmm >> 3) & 1
  let b = (src >> 3) & 1
  self.emit_byte(0x66)
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0x6E)
  emit_modrm(self, 3, dst_xmm, src)
}

///|
pub fn CodeBuffer::x86_emit_cmp_rr(
  self : CodeBuffer,
  lhs : Int32,
  rhs : Int32,
) -> Unit {
  // cmp r/m64, r64: REX.W + 39 /r (cmp lhs, rhs)
  let r = (rhs >> 3) & 1
  let b = (lhs >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x39)
  emit_modrm(self, 3, rhs, lhs)
}

///|
pub fn CodeBuffer::x86_emit_cmp_rr32(
  self : CodeBuffer,
  lhs : Int32,
  rhs : Int32,
) -> Unit {
  // cmp r/m32, r32: 39 /r
  let r = (rhs >> 3) & 1
  let b = (lhs >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x39)
  emit_modrm(self, 3, rhs, lhs)
}

///|
pub fn CodeBuffer::x86_emit_test_rr(
  self : CodeBuffer,
  lhs : Int32,
  rhs : Int32,
) -> Unit {
  // test r/m64, r64: REX.W + 85 /r
  let r = (rhs >> 3) & 1
  let b = (lhs >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x85)
  emit_modrm(self, 3, rhs, lhs)
}

///|
pub fn CodeBuffer::x86_emit_test_rr32(
  self : CodeBuffer,
  lhs : Int32,
  rhs : Int32,
) -> Unit {
  // test r/m32, r32: 85 /r
  let r = (rhs >> 3) & 1
  let b = (lhs >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x85)
  emit_modrm(self, 3, rhs, lhs)
}

///|
pub fn CodeBuffer::x86_emit_bsr_r32_r32(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // bsr r32, r/m32: 0F BD /r
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xBD)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn CodeBuffer::x86_emit_bsr_r64_r64(
  self : CodeBuffer,
  dst : Int32,
  src : Int32,
) -> Unit {
  // bsr r64, r/m64: REX.W 0F BD /r
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0xBD)
  emit_modrm(self, 3, dst, src)
}

///|
/// Emit a trap instruction with a 16-bit payload.
///
/// Encoding: INT3 (0xCC) followed by imm16 (little-endian). The embedding trap
/// handler owns the payload policy.
pub fn CodeBuffer::x86_emit_trap_imm16(
  self : CodeBuffer,
  imm16 : Int32,
) -> Unit {
  self.emit_byte(0xCC)
  self.emit_byte(imm16 & 255)
  self.emit_byte((imm16 >> 8) & 255)
}

///|
fn CodeBuffer::x86_emit_atomic_memory_prefix(
  self : CodeBuffer,
  width : @native.AccessWidth,
  reg : Int32,
  base : Int32,
) -> Unit {
  if width == W16 {
    self.emit_byte(0x66)
  }
  let r = (reg >> 3) & 1
  let b = (base >> 3) & 1
  if width == W64 {
    emit_rex_w(self, r, b)
  } else if r != 0 || b != 0 || (width == W8 && (reg & 7) >= 4) {
    emit_rex(self, r, b)
  }
}

///|
fn CodeBuffer::x86_emit_atomic_modrm(
  self : CodeBuffer,
  reg : Int32,
  base : Int32,
) -> Unit {
  emit_modrm(self, 2, reg, base)
  if (base & 7) == 4 {
    emit_sib(self, 0, 4, base)
  }
  emit_disp32(self, 0)
}

///|
pub fn CodeBuffer::x86_emit_lock_xadd(
  self : CodeBuffer,
  width : @native.AccessWidth,
  base : Int32,
  reg : Int32,
) -> Unit {
  self.emit_byte(0xF0)
  self.x86_emit_atomic_memory_prefix(width, reg, base)
  self.emit_byte(0x0F)
  self.emit_byte(if width == W8 { 0xC0 } else { 0xC1 })
  self.x86_emit_atomic_modrm(reg, base)
}

///|
pub fn CodeBuffer::x86_emit_xchg_memory(
  self : CodeBuffer,
  width : @native.AccessWidth,
  base : Int32,
  reg : Int32,
) -> Unit {
  self.x86_emit_atomic_memory_prefix(width, reg, base)
  self.emit_byte(if width == W8 { 0x86 } else { 0x87 })
  self.x86_emit_atomic_modrm(reg, base)
}

///|
pub fn CodeBuffer::x86_emit_lock_cmpxchg(
  self : CodeBuffer,
  width : @native.AccessWidth,
  base : Int32,
  replacement : Int32,
) -> Unit {
  self.emit_byte(0xF0)
  self.x86_emit_atomic_memory_prefix(width, replacement, base)
  self.emit_byte(0x0F)
  self.emit_byte(if width == W8 { 0xB0 } else { 0xB1 })
  self.x86_emit_atomic_modrm(replacement, base)
}

///|
pub fn CodeBuffer::x86_emit_mfence(self : CodeBuffer) -> Unit {
  self.emit_byte(0x0F)
  self.emit_byte(0xAE)
  self.emit_byte(0xF0)
}
