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
