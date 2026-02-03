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
fn emit_modrm(mc : MachineCode, mod_ : Int, reg : Int, rm : Int) -> Unit {
  let b = ((mod_ & 3) << 6) | ((reg & 7) << 3) | (rm & 7)
  mc.emit_byte(b)
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
