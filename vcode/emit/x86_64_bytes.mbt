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
