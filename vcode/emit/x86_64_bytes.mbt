///|
/// Minimal x86_64 instruction encoding helpers.
///
/// This is Step 3 scaffolding for the future AMD64 JIT backend. We keep the
/// API surface tiny and build out encodings incrementally as the backend is
/// implemented.

///|
fn emit_u32_le(mc : MachineCode, v : Int) -> Unit {
  mc.emit_byte(v & 255)
  mc.emit_byte((v >> 8) & 255)
  mc.emit_byte((v >> 16) & 255)
  mc.emit_byte((v >> 24) & 255)
}

///|
fn emit_u64_le(mc : MachineCode, v : Int64) -> Unit {
  // Emit in little-endian order.
  let mut x = v
  for _i in 0..<8 {
    mc.emit_byte((x & 0xFFL).to_int())
    x = x >> 8
  }
}

///|
fn emit_rex_w(mc : MachineCode, r : Int, b : Int) -> Unit {
  // REX prefix: 0100WRXB. We only need W=1 and R/B for now.
  let rex = 0x48 | ((r & 1) << 2) | (b & 1)
  mc.emit_byte(rex)
}

///|
fn emit_rex(mc : MachineCode, r : Int, b : Int) -> Unit {
  // REX prefix without W bit (used by some SSE encodings).
  let rex = 0x40 | ((r & 1) << 2) | (b & 1)
  mc.emit_byte(rex)
}

///|
fn emit_modrm(mc : MachineCode, mod_ : Int, reg : Int, rm : Int) -> Unit {
  let b = ((mod_ & 3) << 6) | ((reg & 7) << 3) | (rm & 7)
  mc.emit_byte(b)
}

///|
fn emit_sib(mc : MachineCode, scale : Int, index : Int, base : Int) -> Unit {
  let b = ((scale & 3) << 6) | ((index & 7) << 3) | (base & 7)
  mc.emit_byte(b)
}

///|
fn emit_disp32(mc : MachineCode, disp : Int) -> Unit {
  emit_u32_le(mc, disp)
}

///|
pub fn MachineCode::x86_emit_mov_imm64(
  self : MachineCode,
  dst : Int,
  imm : Int64,
) -> Unit {
  // mov r64, imm64: REX.W + B8+rd, imm64
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xB8 + (dst & 7))
  emit_u64_le(self, imm)
}

///|
pub fn MachineCode::x86_emit_add_rr(
  self : MachineCode,
  dst : Int,
  src : Int,
) -> Unit {
  // add r/m64, r64: REX.W + 01 /r (dst += src)
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x01)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn MachineCode::x86_emit_add_r_imm8(
  self : MachineCode,
  dst : Int,
  imm : Int,
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
pub fn MachineCode::x86_emit_add_rr32(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_sub_rr(
  self : MachineCode,
  dst : Int,
  src : Int,
) -> Unit {
  // sub r/m64, r64: REX.W + 29 /r (dst -= src)
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x29)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn MachineCode::x86_emit_sub_rr32(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_and_rr(
  self : MachineCode,
  dst : Int,
  src : Int,
) -> Unit {
  // and r/m64, r64: REX.W + 21 /r
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x21)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn MachineCode::x86_emit_and_rr32(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_or_rr(
  self : MachineCode,
  dst : Int,
  src : Int,
) -> Unit {
  // or r/m64, r64: REX.W + 09 /r
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x09)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn MachineCode::x86_emit_or_rr32(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_xor_rr(
  self : MachineCode,
  dst : Int,
  src : Int,
) -> Unit {
  // xor r/m64, r64: REX.W + 31 /r
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x31)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn MachineCode::x86_emit_xor_rr32(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_imul_rr(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_imul_rr32(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_not_r64(self : MachineCode, reg : Int) -> Unit {
  // not r/m64: REX.W + F7 /2
  let b = (reg >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 2, reg)
}

///|
pub fn MachineCode::x86_emit_neg_r64(self : MachineCode, reg : Int) -> Unit {
  // neg r/m64: REX.W + F7 /3
  let b = (reg >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 3, reg)
}

///|
pub fn MachineCode::x86_emit_not_r32(self : MachineCode, reg : Int) -> Unit {
  // not r/m32: F7 /2
  let b = (reg >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 2, reg)
}

///|
pub fn MachineCode::x86_emit_shl_r_cl(self : MachineCode, dst : Int) -> Unit {
  // shl r/m64, cl: REX.W + D3 /4
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 4, dst)
}

///|
pub fn MachineCode::x86_emit_shl_r32_cl(self : MachineCode, dst : Int) -> Unit {
  // shl r/m32, cl: D3 /4
  let b = (dst >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 4, dst)
}

///|
pub fn MachineCode::x86_emit_shr_r_cl(self : MachineCode, dst : Int) -> Unit {
  // shr r/m64, cl: REX.W + D3 /5
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 5, dst)
}

///|
pub fn MachineCode::x86_emit_shr_r32_cl(self : MachineCode, dst : Int) -> Unit {
  // shr r/m32, cl: D3 /5
  let b = (dst >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 5, dst)
}

///|
pub fn MachineCode::x86_emit_sar_r_cl(self : MachineCode, dst : Int) -> Unit {
  // sar r/m64, cl: REX.W + D3 /7
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 7, dst)
}

///|
pub fn MachineCode::x86_emit_sar_r32_cl(self : MachineCode, dst : Int) -> Unit {
  // sar r/m32, cl: D3 /7
  let b = (dst >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 7, dst)
}

///|
pub fn MachineCode::x86_emit_ror_r_cl(self : MachineCode, dst : Int) -> Unit {
  // ror r/m64, cl: REX.W + D3 /1
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 1, dst)
}

///|
pub fn MachineCode::x86_emit_ror_r32_cl(self : MachineCode, dst : Int) -> Unit {
  // ror r/m32, cl: D3 /1
  let b = (dst >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xD3)
  emit_modrm(self, 3, 1, dst)
}

///|
pub fn MachineCode::x86_emit_shl_r_imm8(
  self : MachineCode,
  dst : Int,
  imm : Int,
) -> Unit {
  // shl r/m64, imm8: REX.W + C1 /4 ib
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xC1)
  emit_modrm(self, 3, 4, dst)
  self.emit_byte(imm & 255)
}

///|
pub fn MachineCode::x86_emit_shl_r32_imm8(
  self : MachineCode,
  dst : Int,
  imm : Int,
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
pub fn MachineCode::x86_emit_shr_r_imm8(
  self : MachineCode,
  dst : Int,
  imm : Int,
) -> Unit {
  // shr r/m64, imm8: REX.W + C1 /5 ib
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xC1)
  emit_modrm(self, 3, 5, dst)
  self.emit_byte(imm & 255)
}

///|
pub fn MachineCode::x86_emit_shr_r32_imm8(
  self : MachineCode,
  dst : Int,
  imm : Int,
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
pub fn MachineCode::x86_emit_sar_r_imm8(
  self : MachineCode,
  dst : Int,
  imm : Int,
) -> Unit {
  // sar r/m64, imm8: REX.W + C1 /7 ib
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xC1)
  emit_modrm(self, 3, 7, dst)
  self.emit_byte(imm & 255)
}

///|
pub fn MachineCode::x86_emit_sar_r32_imm8(
  self : MachineCode,
  dst : Int,
  imm : Int,
) -> Unit {
  // sar r/m32, imm8: C1 /7 ib
  let b = (dst >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xC1)
  emit_modrm(self, 3, 7, dst)
  self.emit_byte(imm & 255)
}

///|
pub fn MachineCode::x86_emit_ror_r_imm8(
  self : MachineCode,
  dst : Int,
  imm : Int,
) -> Unit {
  // ror r/m64, imm8: REX.W + C1 /1 ib
  let b = (dst >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xC1)
  emit_modrm(self, 3, 1, dst)
  self.emit_byte(imm & 255)
}

///|
pub fn MachineCode::x86_emit_ror_r32_imm8(
  self : MachineCode,
  dst : Int,
  imm : Int,
) -> Unit {
  // ror r/m32, imm8: C1 /1 ib
  let b = (dst >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xC1)
  emit_modrm(self, 3, 1, dst)
  self.emit_byte(imm & 255)
}

///|
pub fn MachineCode::x86_emit_mov_rr(
  self : MachineCode,
  dst : Int,
  src : Int,
) -> Unit {
  // mov r/m64, r64: REX.W + 89 /r
  let r = (src >> 3) & 1
  let b = (dst >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x89)
  emit_modrm(self, 3, src, dst)
}

///|
pub fn MachineCode::x86_emit_mov_rr32(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_movsxd_r64_r32(
  self : MachineCode,
  dst : Int,
  src : Int,
) -> Unit {
  // movsxd r64, r/m32: REX.W + 63 /r
  let r = (dst >> 3) & 1
  let b = (src >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x63)
  emit_modrm(self, 3, dst, src)
}

///|
pub fn MachineCode::x86_emit_movsx_r32_r8(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_movsx_r64_r8(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_movsx_r32_r16(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_movsx_r64_r16(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_movzx_r32_r16(
  self : MachineCode,
  dst : Int,
  src : Int,
) -> Unit {
  // movzx r32, r/m16: 0F B7 /r
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
pub fn MachineCode::x86_emit_push_r64(self : MachineCode, reg : Int) -> Unit {
  // push r64: 50+rd, with optional REX.B for r8-r15.
  let b = (reg >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0x50 + (reg & 7))
}

///|
pub fn MachineCode::x86_emit_pop_r64(self : MachineCode, reg : Int) -> Unit {
  // pop r64: 58+rd, with optional REX.B for r8-r15.
  let b = (reg >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0x58 + (reg & 7))
}

///|
pub fn MachineCode::x86_emit_call_r64(self : MachineCode, reg : Int) -> Unit {
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
pub fn MachineCode::x86_emit_jmp_r64(self : MachineCode, reg : Int) -> Unit {
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
pub fn MachineCode::x86_emit_lea_r64_riprel32(
  self : MachineCode,
  dst : Int,
  target_label : Int,
) -> Unit {
  // lea r64, [rip + disp32]: REX.W + 8D /r with mod=00, rm=101.
  let r = (dst >> 3) & 1
  emit_rex_w(self, r, 0)
  self.emit_byte(0x8D)
  emit_modrm(self, 0, dst, 5)
  let disp_offset = self.current_pos()
  emit_disp32(self, 0)
  let next_ip_offset = self.current_pos()
  self.add_x86_rel32_fixup(target_label, disp_offset, next_ip_offset)
}

///|
pub fn MachineCode::x86_emit_sub_rsp_imm32(
  self : MachineCode,
  imm : Int,
) -> Unit {
  // sub rsp, imm32: 48 81 EC imm32
  self.emit_byte(0x48)
  self.emit_byte(0x81)
  self.emit_byte(0xEC)
  emit_u32_le(self, imm)
}

///|
pub fn MachineCode::x86_emit_add_rsp_imm32(
  self : MachineCode,
  imm : Int,
) -> Unit {
  // add rsp, imm32: 48 81 C4 imm32
  self.emit_byte(0x48)
  self.emit_byte(0x81)
  self.emit_byte(0xC4)
  emit_u32_le(self, imm)
}

///|
pub fn MachineCode::x86_emit_mov_r64_m64(
  self : MachineCode,
  dst : Int,
  base : Int,
  disp : Int,
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
pub fn MachineCode::x86_emit_mov_r32_m32(
  self : MachineCode,
  dst : Int,
  base : Int,
  disp : Int,
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
pub fn MachineCode::x86_emit_mov_m64_r64(
  self : MachineCode,
  base : Int,
  disp : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_mov_m32_r32(
  self : MachineCode,
  base : Int,
  disp : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_mov_m8_r8(
  self : MachineCode,
  base : Int,
  disp : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_mov_m16_r16(
  self : MachineCode,
  base : Int,
  disp : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_movaps_xmm_xmm(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_minps_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_minpd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_maxps_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_maxpd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_subps_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_subpd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_addps_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_addpd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_mulps_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_mulpd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_divps_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_divpd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_sqrtps_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_sqrtpd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pslld_xmm_imm8(
  self : MachineCode,
  dst_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_psllq_xmm_imm8(
  self : MachineCode,
  dst_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_psllw_xmm_imm8(
  self : MachineCode,
  dst_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_psll_xmm_xmm(
  self : MachineCode,
  lane_size : @instr.LaneSize,
  dst_xmm : Int,
  src_xmm : Int,
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
    @instr.H16 => self.emit_byte(0xF1)
    @instr.S32 => self.emit_byte(0xF2)
    @instr.D64 => self.emit_byte(0xF3)
    _ => abort("x86_64 psll: unsupported lane size \{lane_size}")
  }
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_psrl_xmm_xmm(
  self : MachineCode,
  lane_size : @instr.LaneSize,
  dst_xmm : Int,
  src_xmm : Int,
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
    @instr.H16 => self.emit_byte(0xD1)
    @instr.S32 => self.emit_byte(0xD2)
    @instr.D64 => self.emit_byte(0xD3)
    _ => abort("x86_64 psrl: unsupported lane size \{lane_size}")
  }
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_psra_xmm_xmm(
  self : MachineCode,
  lane_size : @instr.LaneSize,
  dst_xmm : Int,
  src_xmm : Int,
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
    @instr.H16 => self.emit_byte(0xE1)
    @instr.S32 => self.emit_byte(0xE2)
    _ => abort("x86_64 psra: unsupported lane size \{lane_size}")
  }
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_psrlw_xmm_imm8(
  self : MachineCode,
  dst_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_psrad_xmm_imm8(
  self : MachineCode,
  dst_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_cmpps_xmm_xmm_imm8(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_cmppd_xmm_xmm_imm8(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_roundps_xmm_xmm_imm8(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_roundpd_xmm_xmm_imm8(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_psrld_xmm_imm8(
  self : MachineCode,
  dst_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_psrlq_xmm_imm8(
  self : MachineCode,
  dst_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_movss_xmm_m32(
  self : MachineCode,
  dst_xmm : Int,
  base : Int,
  disp : Int,
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
pub fn MachineCode::x86_emit_movss_m32_xmm(
  self : MachineCode,
  base : Int,
  disp : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_movsd_m64_xmm(
  self : MachineCode,
  base : Int,
  disp : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_movsd_xmm_m64(
  self : MachineCode,
  dst_xmm : Int,
  base : Int,
  disp : Int,
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
pub fn MachineCode::x86_emit_ucomiss_xmm_xmm(
  self : MachineCode,
  lhs_xmm : Int,
  rhs_xmm : Int,
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
pub fn MachineCode::x86_emit_ucomisd_xmm_xmm(
  self : MachineCode,
  lhs_xmm : Int,
  rhs_xmm : Int,
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
pub fn MachineCode::x86_emit_pcmpeqd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pand_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_por_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pxor_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pandn_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pinsrq_xmm_r64_imm8(
  self : MachineCode,
  dst_xmm : Int,
  src : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_pinsrd_xmm_r32_imm8(
  self : MachineCode,
  dst_xmm : Int,
  src : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_pinsrw_xmm_r32_imm8(
  self : MachineCode,
  dst_xmm : Int,
  src : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_pinsrb_xmm_r32_imm8(
  self : MachineCode,
  dst_xmm : Int,
  src : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_padd_xmm_xmm(
  self : MachineCode,
  lane_size : @instr.LaneSize,
  dst_xmm : Int,
  src_xmm : Int,
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
    @instr.B8 => self.emit_byte(0xFC)
    @instr.H16 => self.emit_byte(0xFD)
    @instr.S32 => self.emit_byte(0xFE)
    @instr.D64 => self.emit_byte(0xD4)
  }
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_psub_xmm_xmm(
  self : MachineCode,
  lane_size : @instr.LaneSize,
  dst_xmm : Int,
  src_xmm : Int,
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
    @instr.B8 => self.emit_byte(0xF8)
    @instr.H16 => self.emit_byte(0xF9)
    @instr.S32 => self.emit_byte(0xFA)
    @instr.D64 => self.emit_byte(0xFB)
  }
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_pmullw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmulld_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pcmpeq_xmm_xmm(
  self : MachineCode,
  lane_size : @instr.LaneSize,
  dst_xmm : Int,
  src_xmm : Int,
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
    @instr.B8 => {
      self.emit_byte(0x74)
      emit_modrm(self, 3, dst_xmm, src_xmm)
    }
    @instr.H16 => {
      self.emit_byte(0x75)
      emit_modrm(self, 3, dst_xmm, src_xmm)
    }
    @instr.S32 => {
      self.emit_byte(0x76)
      emit_modrm(self, 3, dst_xmm, src_xmm)
    }
    @instr.D64 =>
      // pcmpeqq is SSE4.1; avoid relying on it and use an emulation sequence at a higher level.
      abort("x86_64 pcmpeq.i64: use emulation sequence instead")
  }
}

///|
pub fn MachineCode::x86_emit_pcmpgt_xmm_xmm(
  self : MachineCode,
  lane_size : @instr.LaneSize,
  dst_xmm : Int,
  src_xmm : Int,
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
    @instr.B8 => self.emit_byte(0x64)
    @instr.H16 => self.emit_byte(0x65)
    @instr.S32 => self.emit_byte(0x66)
    @instr.D64 => abort("x86_64 pcmpgt.i64: use emulation sequence instead")
  }
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_pshufd_xmm_xmm_imm8(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_paddusb_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_paddsb_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_paddsw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_paddusw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_psubsb_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_psubsw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_psubusb_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_psubusw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pavgb_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pavgw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pminub_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmaxub_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pminsw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmaxsw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pminsb_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmaxsb_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pminuw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmaxuw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pminsd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmaxsd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pminud_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmaxud_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pabsb_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pabsw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pabsd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmovsxbw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmovzxbw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmovsxwd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmovzxwd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmovsxdq_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmovzxdq_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pshufb_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  mask_xmm : Int,
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
pub fn MachineCode::x86_emit_punpcklbw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_punpckhbw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_punpcklwd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
) -> Unit {
  // punpcklwd xmm, xmm/m128: 66 0F 61 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x61)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_punpckhwd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
) -> Unit {
  // punpckhwd xmm, xmm/m128: 66 0F 69 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x69)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_punpckldq_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
) -> Unit {
  // punpckldq xmm, xmm/m128: 66 0F 62 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x62)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_punpckhdq_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
) -> Unit {
  // punpckhdq xmm, xmm/m128: 66 0F 6A /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x6A)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_packsswb_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_packuswb_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_packssdw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_packusdw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_palignr_xmm_xmm_imm8(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_pmulhw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
) -> Unit {
  // pmulhw xmm, xmm/m128: 66 0F E5 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xE5)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_pmulhuw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
) -> Unit {
  // pmulhuw xmm, xmm/m128: 66 0F E4 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xE4)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_pmuldq_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
) -> Unit {
  // pmuldq xmm, xmm/m128 (SSE4.1): 66 0F 38 28 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x38)
  self.emit_byte(0x28)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_pmuludq_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
) -> Unit {
  // pmuludq xmm, xmm/m128: 66 0F F4 /r
  let r = (dst_xmm >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0xF4)
  emit_modrm(self, 3, dst_xmm, src_xmm)
}

///|
pub fn MachineCode::x86_emit_pmaddwd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmaddubsw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pmulhrsw_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_pextrb_r32_xmm_imm8(
  self : MachineCode,
  dst : Int,
  src_xmm : Int,
  imm8 : Int,
) -> Unit {
  // pextrb r32, xmm, imm8 (SSE4.1): 66 0F 3A 14 /r ib
  let r = (dst >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x14)
  emit_modrm(self, 3, dst, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn MachineCode::x86_emit_pextrd_r32_xmm_imm8(
  self : MachineCode,
  dst : Int,
  src_xmm : Int,
  imm8 : Int,
) -> Unit {
  // pextrd r32, xmm, imm8 (SSE4.1): 66 0F 3A 16 /r ib
  let r = (dst >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  if r != 0 || b != 0 {
    emit_rex(self, r, b)
  }
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x16)
  emit_modrm(self, 3, dst, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn MachineCode::x86_emit_pextrq_r64_xmm_imm8(
  self : MachineCode,
  dst : Int,
  src_xmm : Int,
  imm8 : Int,
) -> Unit {
  // pextrq r64, xmm, imm8 (SSE4.1): 66 REX.W 0F 3A 16 /r ib
  let r = (dst >> 3) & 1
  let b = (src_xmm >> 3) & 1
  self.emit_byte(0x66)
  emit_rex_w(self, r, b)
  self.emit_byte(0x0F)
  self.emit_byte(0x3A)
  self.emit_byte(0x16)
  emit_modrm(self, 3, dst, src_xmm)
  self.emit_byte(imm8 & 255)
}

///|
pub fn MachineCode::x86_emit_pextrw_r32_xmm_imm8(
  self : MachineCode,
  dst : Int,
  src_xmm : Int,
  imm8 : Int,
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
pub fn MachineCode::x86_emit_pmovmskb_r32_xmm(
  self : MachineCode,
  dst : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_movmskps_r32_xmm(
  self : MachineCode,
  dst : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_movmskpd_r32_xmm(
  self : MachineCode,
  dst : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_xorpd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_subss_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_subsd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_addss_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_addsd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_cvttss2si_r32_xmm(
  self : MachineCode,
  dst : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_cvttss2si_r64_xmm(
  self : MachineCode,
  dst : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_cvttsd2si_r32_xmm(
  self : MachineCode,
  dst : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_cvttsd2si_r64_xmm(
  self : MachineCode,
  dst : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_cvtsi2ss_xmm_r32(
  self : MachineCode,
  dst_xmm : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_cvtsi2ss_xmm_r64(
  self : MachineCode,
  dst_xmm : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_cvtsi2sd_xmm_r32(
  self : MachineCode,
  dst_xmm : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_cvtsi2sd_xmm_r64(
  self : MachineCode,
  dst_xmm : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_cvtss2sd_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_cvtsd2ss_xmm_xmm(
  self : MachineCode,
  dst_xmm : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_movdqu_m128_xmm(
  self : MachineCode,
  base : Int,
  disp : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_movdqu_xmm_m128(
  self : MachineCode,
  dst_xmm : Int,
  base : Int,
  disp : Int,
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
pub fn MachineCode::x86_emit_movsx_r64_m8(
  self : MachineCode,
  dst : Int,
  base : Int,
  disp : Int,
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
pub fn MachineCode::x86_emit_movzx_r32_m8(
  self : MachineCode,
  dst : Int,
  base : Int,
  disp : Int,
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
pub fn MachineCode::x86_emit_movsx_r64_m16(
  self : MachineCode,
  dst : Int,
  base : Int,
  disp : Int,
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
pub fn MachineCode::x86_emit_movzx_r32_m16(
  self : MachineCode,
  dst : Int,
  base : Int,
  disp : Int,
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
pub fn MachineCode::x86_emit_movsxd_r64_m32(
  self : MachineCode,
  dst : Int,
  base : Int,
  disp : Int,
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
pub fn MachineCode::x86_emit_ret(self : MachineCode) -> Unit {
  self.emit_byte(0xC3)
}

///|
pub fn MachineCode::x86_emit_jmp_rel32(
  self : MachineCode,
  target_block : Int,
) -> Unit {
  // jmp rel32: E9 disp32
  self.emit_byte(0xE9)
  let disp_offset = self.current_pos()
  emit_u32_le(self, 0)
  let next_ip_offset = self.current_pos()
  self.add_x86_rel32_fixup(target_block, disp_offset, next_ip_offset)
}

///|
fn x86_cond_to_jcc_opcode(cond : @instr.Cond) -> Int {
  match cond {
    // Signed/unsigned conditions match the usual interpretation after CMP.
    @instr.Cond::Eq => 0x84 // JE
    @instr.Cond::Ne => 0x85 // JNE
    @instr.Cond::Hs => 0x83 // JAE/JNB
    @instr.Cond::Lo => 0x82 // JB
    @instr.Cond::Mi => 0x88 // JS
    @instr.Cond::Pl => 0x89 // JNS
    @instr.Cond::Vs => 0x80 // JO
    @instr.Cond::Vc => 0x81 // JNO
    // Parity conditions (x86_64-only; used after UCOMIS*).
    @instr.Cond::Ps => 0x8A // JP/JPE (parity set)
    @instr.Cond::Pc => 0x8B // JNP/JPO (parity clear)
    @instr.Cond::Hi => 0x87 // JA
    @instr.Cond::Ls => 0x86 // JBE
    @instr.Cond::Ge => 0x8D // JGE
    @instr.Cond::Lt => 0x8C // JL
    @instr.Cond::Gt => 0x8F // JG
    @instr.Cond::Le => 0x8E // JLE
    @instr.Cond::Al => abort("x86_64 jcc: AL is not a conditional branch")
  }
}

///|
pub fn MachineCode::x86_emit_jcc_rel32(
  self : MachineCode,
  cond : @instr.Cond,
  target_block : Int,
) -> Unit {
  // jcc rel32: 0F 8? disp32
  self.emit_byte(0x0F)
  self.emit_byte(x86_cond_to_jcc_opcode(cond))
  let disp_offset = self.current_pos()
  emit_u32_le(self, 0)
  let next_ip_offset = self.current_pos()
  self.add_x86_rel32_fixup(target_block, disp_offset, next_ip_offset)
}

///|
pub fn MachineCode::x86_emit_setcc_r8(
  self : MachineCode,
  cond : @instr.Cond,
  dst : Int,
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
pub fn MachineCode::x86_emit_movzx_r32_r8(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_cqo(self : MachineCode) -> Unit {
  // cqo: sign-extend rax into rdx:rax (64-bit)
  self.emit_byte(0x48)
  self.emit_byte(0x99)
}

///|
pub fn MachineCode::x86_emit_cdq(self : MachineCode) -> Unit {
  // cdq: sign-extend eax into edx:eax (32-bit)
  self.emit_byte(0x99)
}

///|
pub fn MachineCode::x86_emit_idiv_r64(
  self : MachineCode,
  divisor : Int,
) -> Unit {
  // idiv r/m64: REX.W + F7 /7
  let b = (divisor >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 7, divisor)
}

///|
pub fn MachineCode::x86_emit_idiv_r32(
  self : MachineCode,
  divisor : Int,
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
pub fn MachineCode::x86_emit_div_r64(self : MachineCode, divisor : Int) -> Unit {
  // div r/m64: REX.W + F7 /6
  let b = (divisor >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 6, divisor)
}

///|
pub fn MachineCode::x86_emit_div_r32(self : MachineCode, divisor : Int) -> Unit {
  // div r/m32: F7 /6
  let b = (divisor >> 3) & 1
  if b != 0 {
    emit_rex(self, 0, b)
  }
  self.emit_byte(0xF7)
  emit_modrm(self, 3, 6, divisor)
}

///|
pub fn MachineCode::x86_emit_cmp_r_imm32(
  self : MachineCode,
  reg : Int,
  imm : Int,
) -> Unit {
  // cmp r/m64, imm32: REX.W + 81 /7 id
  let b = (reg >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0x81)
  emit_modrm(self, 3, 7, reg)
  emit_u32_le(self, imm)
}

///|
pub fn MachineCode::x86_emit_cmp_r32_imm32(
  self : MachineCode,
  reg : Int,
  imm : Int,
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
pub fn MachineCode::x86_emit_and_r_imm8_sxb64(
  self : MachineCode,
  reg : Int,
  imm8 : Int,
) -> Unit {
  // and r/m64, imm8: REX.W + 83 /4 ib (imm8 sign-extended)
  let b = (reg >> 3) & 1
  emit_rex_w(self, 0, b)
  self.emit_byte(0x83)
  emit_modrm(self, 3, 4, reg)
  self.emit_byte(imm8 & 255)
}

///|
pub fn MachineCode::x86_emit_cmovcc_rr(
  self : MachineCode,
  cond : @instr.Cond,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_cmovcc_rr32(
  self : MachineCode,
  cond : @instr.Cond,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_movd_r32_xmm(
  self : MachineCode,
  dst : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_movd_xmm_r32(
  self : MachineCode,
  dst_xmm : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_movq_r64_xmm(
  self : MachineCode,
  dst : Int,
  src_xmm : Int,
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
pub fn MachineCode::x86_emit_movq_xmm_r64(
  self : MachineCode,
  dst_xmm : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_cmp_rr(
  self : MachineCode,
  lhs : Int,
  rhs : Int,
) -> Unit {
  // cmp r/m64, r64: REX.W + 39 /r (cmp lhs, rhs)
  let r = (rhs >> 3) & 1
  let b = (lhs >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x39)
  emit_modrm(self, 3, rhs, lhs)
}

///|
pub fn MachineCode::x86_emit_cmp_rr32(
  self : MachineCode,
  lhs : Int,
  rhs : Int,
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
pub fn MachineCode::x86_emit_test_rr(
  self : MachineCode,
  lhs : Int,
  rhs : Int,
) -> Unit {
  // test r/m64, r64: REX.W + 85 /r
  let r = (rhs >> 3) & 1
  let b = (lhs >> 3) & 1
  emit_rex_w(self, r, b)
  self.emit_byte(0x85)
  emit_modrm(self, 3, rhs, lhs)
}

///|
pub fn MachineCode::x86_emit_test_rr32(
  self : MachineCode,
  lhs : Int,
  rhs : Int,
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
pub fn MachineCode::x86_emit_bsr_r32_r32(
  self : MachineCode,
  dst : Int,
  src : Int,
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
pub fn MachineCode::x86_emit_bsr_r64_r64(
  self : MachineCode,
  dst : Int,
  src : Int,
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
/// Encoding: INT3 (0xCC) followed by imm16 (little-endian). The JIT trap signal
/// handler decodes the payload to map to a WebAssembly trap code.
pub fn MachineCode::x86_emit_trap_imm16(
  self : MachineCode,
  imm16 : Int,
) -> Unit {
  self.emit_byte(0xCC)
  self.emit_byte(imm16 & 255)
  self.emit_byte((imm16 >> 8) & 255)
}
