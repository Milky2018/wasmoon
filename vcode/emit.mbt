// Code Emission
// Generates machine code from VCode representation
//
// This module provides:
// 1. Machine code buffer for accumulating bytes
// 2. AArch64 instruction encoding
// 3. VCode to machine code translation

// ============ Machine Code Buffer ============

///|
/// A buffer for accumulating machine code bytes
pub(all) struct MachineCode {
  bytes : Array[Int] // Using Int for bytes (0-255)
  mut pos : Int
  // Labels for branch targets
  labels : Map[Int, Int] // block_id -> offset
  // Pending fixups for forward branches
  fixups : Array[Fixup]
  // Disassembly annotations (offset -> instruction text)
  disasm : Array[(Int, String)]
}

///|
/// A fixup for a forward branch
pub(all) struct Fixup {
  // Offset in the code buffer where the fixup is needed
  offset : Int
  // Target block id
  target_block : Int
  // Kind of fixup
  kind : FixupKind
}

///|
/// Kind of fixup
pub enum FixupKind {
  Branch26 // 26-bit PC-relative branch (B, BL)
  Branch19 // 19-bit PC-relative branch (B.cond, CBZ, CBNZ)
}

///|
pub fn MachineCode::new() -> MachineCode {
  { bytes: [], pos: 0, labels: {}, fixups: [], disasm: [] }
}

///|
/// Emit a single byte
pub fn MachineCode::emit_byte(self : MachineCode, b : Int) -> Unit {
  self.bytes.push(b & 255)
  self.pos = self.pos + 1
}

///|
/// Emit 4 bytes (instruction) as 4 separate bytes
pub fn MachineCode::emit_inst(
  self : MachineCode,
  b0 : Int,
  b1 : Int,
  b2 : Int,
  b3 : Int,
) -> Unit {
  self.emit_byte(b0)
  self.emit_byte(b1)
  self.emit_byte(b2)
  self.emit_byte(b3)
}

///|
/// Current position in the buffer
pub fn MachineCode::current_pos(self : MachineCode) -> Int {
  self.pos
}

///|
/// Add a disassembly annotation at the current position
fn MachineCode::annotate(self : MachineCode, text : String) -> Unit {
  self.disasm.push((self.pos, text))
}

///|
/// Dump disassembly with hex bytes
pub fn MachineCode::dump_disasm(self : MachineCode) -> String {
  let mut result = ""
  // Build a map of offset -> label for block labels
  let label_map : Map[Int, Int] = {}
  for entry in self.labels {
    label_map.set(entry.1, entry.0)
  }
  // Sort disasm by offset
  let sorted = self.disasm.copy()
  sorted.sort_by(fn(a, b) { a.0.compare(b.0) })
  for entry in sorted {
    let (offset, text) = entry
    // Check if there's a label at this offset
    if label_map.get(offset) is Some(block_id) {
      result = result + "block\{block_id}:\n"
    }
    // Get the 4 bytes at this offset
    let b0 = if offset < self.bytes.length() { self.bytes[offset] } else { 0 }
    let b1 = if offset + 1 < self.bytes.length() {
      self.bytes[offset + 1]
    } else {
      0
    }
    let b2 = if offset + 2 < self.bytes.length() {
      self.bytes[offset + 2]
    } else {
      0
    }
    let b3 = if offset + 3 < self.bytes.length() {
      self.bytes[offset + 3]
    } else {
      0
    }
    let hex = hex2(b0) + hex2(b1) + hex2(b2) + hex2(b3)
    result = result + "  \{to_hex4(offset)}: \{hex}  \{text}\n"
  }
  result
}

///|
fn hex2(n : Int) -> String {
  let hi = (n >> 4) & 0xF
  let lo = n & 0xF
  let hi_c = if hi < 10 {
    (hi + 48).unsafe_to_char().to_string()
  } else {
    (hi - 10 + 97).unsafe_to_char().to_string()
  }
  let lo_c = if lo < 10 {
    (lo + 48).unsafe_to_char().to_string()
  } else {
    (lo - 10 + 97).unsafe_to_char().to_string()
  }
  hi_c + lo_c
}

///|
fn to_hex4(n : Int) -> String {
  hex2((n >> 8) & 0xFF) + hex2(n & 0xFF)
}

///|
/// Define a label at the current position
pub fn MachineCode::define_label(self : MachineCode, block_id : Int) -> Unit {
  self.labels.set(block_id, self.pos)
}

///|
/// Add a fixup for a forward branch
pub fn MachineCode::add_fixup(
  self : MachineCode,
  target_block : Int,
  kind : FixupKind,
) -> Unit {
  // Fixup is at current position - 4 (since we already emitted the instruction)
  self.fixups.push({ offset: self.pos - 4, target_block, kind })
}

///|
/// Resolve all pending fixups
pub fn MachineCode::resolve_fixups(self : MachineCode) -> Unit {
  for fixup in self.fixups {
    match self.labels.get(fixup.target_block) {
      Some(target_offset) => {
        let pc_offset = (target_offset - fixup.offset) / 4 // Instructions are 4 bytes
        match fixup.kind {
          Branch26 => {
            // Patch bits [25:0] with the 26-bit offset
            // Keep opcode bits in byte 3
            let imm26 = pc_offset & 0x3FFFFFF
            self.bytes[fixup.offset] = imm26 & 255
            self.bytes[fixup.offset + 1] = (imm26 >> 8) & 255
            self.bytes[fixup.offset + 2] = (imm26 >> 16) & 255
            // Keep upper bits of byte 3 (opcode)
            let old_b3 = self.bytes[fixup.offset + 3]
            self.bytes[fixup.offset + 3] = (old_b3 & 252) | ((imm26 >> 24) & 3)
          }
          Branch19 => {
            // Patch bits [23:5] with the 19-bit offset
            let imm19 = pc_offset & 0x7FFFF
            // imm19 goes into bits [23:5], so bytes 0-2 primarily
            // Byte 0: bits [7:5] from imm19 bits [2:0], keep bits [4:0] (Rt)
            let old_b0 = self.bytes[fixup.offset]
            self.bytes[fixup.offset] = (old_b0 & 31) | ((imm19 << 5) & 224)
            self.bytes[fixup.offset + 1] = (imm19 >> 3) & 255
            self.bytes[fixup.offset + 2] = (imm19 >> 11) & 255
            // Byte 3: keep opcode, add top bits of imm19
            let old_b3 = self.bytes[fixup.offset + 3]
            self.bytes[fixup.offset + 3] = (old_b3 & 255) | 0
          }
        }
      } // imm19 high bits already covered
      None => () // Label not found, skip (should not happen in valid code)
    }
  }
}

///|
/// Get the generated bytes
pub fn MachineCode::get_bytes(self : MachineCode) -> Array[Int] {
  self.bytes
}

///|
/// Get size in bytes
pub fn MachineCode::size(self : MachineCode) -> Int {
  self.pos
}

///|
/// Align the code buffer to a given boundary
/// Pads with NOP instructions (AArch64 NOP = 0xD503201F)
pub fn MachineCode::align(self : MachineCode, alignment : Int) -> Unit {
  // alignment must be a power of 2
  guard alignment > 0 && (alignment & (alignment - 1)) == 0 else { return }
  // Pad until aligned
  while self.pos % alignment != 0 {
    emit_nop(self)
  }
}

///|
/// Align to function boundary (typically 16 bytes on AArch64)
pub fn MachineCode::align_function(self : MachineCode) -> Unit {
  self.align(16)
}

///|
/// Align to basic block boundary (typically 4 bytes for AArch64 instructions)
pub fn MachineCode::align_block(self : MachineCode) -> Unit {
  self.align(4)
}

// ============ AArch64 Instruction Encoding ============

// Helper to build instruction from fields

///|
#warnings("-unused_value")
fn build_inst(
  b3 : Int,
  b2 : Int,
  b1 : Int,
  b0 : Int,
  rd : Int,
  rn : Int,
  rm : Int,
) -> (Int, Int, Int, Int) {
  // Most AArch64 instructions have:
  // - Rd in bits [4:0]
  // - Rn in bits [9:5]
  // - Rm in bits [20:16] (for register operations)
  let byte0 = b0 | (rd & 31) | ((rn & 7) << 5)
  let byte1 = b1 | ((rn >> 3) & 3) | ((rm & 15) << 4)
  let byte2 = b2 | ((rm >> 4) & 1)
  let byte3 = b3
  (byte0, byte1, byte2, byte3)
}

// Register encoding helper

///|
fn reg_num(reg : Reg) -> Int {
  match reg {
    Physical(preg) => preg.index
    Virtual(_) => abort("Virtual register in code emission")
  }
}

// Writable register encoding helper

///|
fn wreg_num(wreg : Writable) -> Int {
  reg_num(wreg.reg)
}

///|
/// Encode ADD (shifted register): ADD Xd, Xn, Xm
/// Opcode: 0x8B000000 = 10001011 00000000 00000000 00000000
pub fn emit_add_reg(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("add x\{rd}, x\{rn}, x\{rm}")
  // AArch64 ADD (shifted register) encoding:
  // | 31 | 30-29 | 28 | 27-24 | 23-22 | 21 | 20-16 | 15-10 | 9-5 | 4-0 |
  // | sf |  op   | S  | 01011 | shift | 0  |  Rm   | imm6  | Rn  | Rd  |
  // With sf=1, op=00, S=0, shift=00 (LSL), imm6=0:
  // Byte 0 (bits 7-0): Rd[4:0] | Rn[2:0] << 5
  // Byte 1 (bits 15-8): Rn[4:3] | imm6[5:0] << 2
  // Byte 2 (bits 23-16): Rm[4:0] | 0 << 5 | shift[1:0] << 6
  // Byte 3 (bits 31-24): 0x8B
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3 // imm6 = 0
  let b2 = rm & 31 // shift = 0, bit 21 = 0
  let b3 = 139 // 0x8B
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode ADD (shifted register with shift amount): ADD Xd, Xn, Xm, shift #amount
/// Opcode: 0x8B000000 (with shift bits)
/// shift: 00=LSL, 01=LSR, 10=ASR
pub fn emit_add_shifted(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  shift : ShiftType,
  amount : Int,
) -> Unit {
  let shift_bits = match shift {
    Lsl => 0
    Lsr => 1
    Asr => 2
  }
  let shift_name = match shift {
    Lsl => "lsl"
    Lsr => "lsr"
    Asr => "asr"
  }
  mc.annotate("add x\{rd}, x\{rn}, x\{rm}, \{shift_name} #\{amount}")
  let imm6 = amount & 63
  // Encoding: sf=1 | op=0 | S=0 | 01011 | shift[1:0] | 0 | Rm | imm6 | Rn | Rd
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | ((imm6 & 7) << 3) | ((rm & 1) << 6)
  let b2 = ((rm >> 1) & 15) | ((shift_bits & 3) << 6)
  let b3 = 139 // 0x8B
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode SUB (shifted register with shift amount): SUB Xd, Xn, Xm, shift #amount
pub fn emit_sub_shifted(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  shift : ShiftType,
  amount : Int,
) -> Unit {
  let shift_bits = match shift {
    Lsl => 0
    Lsr => 1
    Asr => 2
  }
  let shift_name = match shift {
    Lsl => "lsl"
    Lsr => "lsr"
    Asr => "asr"
  }
  mc.annotate("sub x\{rd}, x\{rn}, x\{rm}, \{shift_name} #\{amount}")
  let imm6 = amount & 63
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | ((imm6 & 7) << 3) | ((rm & 1) << 6)
  let b2 = ((rm >> 1) & 15) | ((shift_bits & 3) << 6)
  let b3 = 203 // 0xCB
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode AND (shifted register with shift amount): AND Xd, Xn, Xm, shift #amount
pub fn emit_and_shifted(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  shift : ShiftType,
  amount : Int,
) -> Unit {
  let shift_bits = match shift {
    Lsl => 0
    Lsr => 1
    Asr => 2
  }
  let shift_name = match shift {
    Lsl => "lsl"
    Lsr => "lsr"
    Asr => "asr"
  }
  mc.annotate("and x\{rd}, x\{rn}, x\{rm}, \{shift_name} #\{amount}")
  let imm6 = amount & 63
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | ((imm6 & 7) << 3) | ((rm & 1) << 6)
  let b2 = ((rm >> 1) & 15) | ((shift_bits & 3) << 6)
  let b3 = 138 // 0x8A
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode ORR (shifted register with shift amount): ORR Xd, Xn, Xm, shift #amount
pub fn emit_orr_shifted(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  shift : ShiftType,
  amount : Int,
) -> Unit {
  let shift_bits = match shift {
    Lsl => 0
    Lsr => 1
    Asr => 2
  }
  let shift_name = match shift {
    Lsl => "lsl"
    Lsr => "lsr"
    Asr => "asr"
  }
  mc.annotate("orr x\{rd}, x\{rn}, x\{rm}, \{shift_name} #\{amount}")
  let imm6 = amount & 63
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | ((imm6 & 7) << 3) | ((rm & 1) << 6)
  let b2 = ((rm >> 1) & 15) | ((shift_bits & 3) << 6)
  let b3 = 170 // 0xAA
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode EOR (shifted register with shift amount): EOR Xd, Xn, Xm, shift #amount
pub fn emit_eor_shifted(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  shift : ShiftType,
  amount : Int,
) -> Unit {
  let shift_bits = match shift {
    Lsl => 0
    Lsr => 1
    Asr => 2
  }
  let shift_name = match shift {
    Lsl => "lsl"
    Lsr => "lsr"
    Asr => "asr"
  }
  mc.annotate("eor x\{rd}, x\{rn}, x\{rm}, \{shift_name} #\{amount}")
  let imm6 = amount & 63
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | ((imm6 & 7) << 3) | ((rm & 1) << 6)
  let b2 = ((rm >> 1) & 15) | ((shift_bits & 3) << 6)
  let b3 = 202 // 0xCA
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode MADD: MADD Xd, Xn, Xm, Xa (Xd = Xa + Xn * Xm)
/// Opcode: 0x9B000000
pub fn emit_madd(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  ra : Int,
) -> Unit {
  mc.annotate("madd x\{rd}, x\{rn}, x\{rm}, x\{ra}")
  // Encoding: sf=1 | 00 | 11011 | 000 | Rm | o0=0 | Ra | Rn | Rd
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | ((ra & 31) << 3)
  let b2 = rm & 31
  let b3 = 155 // 0x9B
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode MSUB: MSUB Xd, Xn, Xm, Xa (Xd = Xa - Xn * Xm)
/// Opcode: 0x9B008000
pub fn emit_msub(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  ra : Int,
) -> Unit {
  mc.annotate("msub x\{rd}, x\{rn}, x\{rm}, x\{ra}")
  // Encoding: sf=1 | 00 | 11011 | 000 | Rm | o0=1 | Ra | Rn | Rd
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | ((ra & 31) << 3) | 128 // o0=1 (bit 7)
  let b2 = rm & 31
  let b3 = 155 // 0x9B
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode MNEG: MNEG Xd, Xn, Xm (Xd = -(Xn * Xm)) = MSUB Xd, Xn, Xm, XZR
/// Opcode: 0x9B00FC00
pub fn emit_mneg(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("mneg x\{rd}, x\{rn}, x\{rm}")
  emit_msub(mc, rd, rn, rm, 31) // XZR = register 31
}

///|
/// Encode ADD (immediate): ADD Xd, Xn, #imm12
/// Opcode: 0x91000000
pub fn emit_add_imm(mc : MachineCode, rd : Int, rn : Int, imm12 : Int) -> Unit {
  let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
  let rd_name = if rd == 31 { "sp" } else { "x\{rd}" }
  mc.annotate("add \{rd_name}, \{rn_name}, #\{imm12}")
  // sf=1 | op=0 | S=0 | 100010 | sh=0 | imm12[11:0] | Rn[4:0] | Rd[4:0]
  // Build as 32-bit instruction
  let imm = imm12 & 0xFFF
  let inst = (0b1 << 31) |
    (0 << 30) |
    (0 << 29) |
    (0b100010 << 23) |
    (0 << 22) |
    (imm << 10) |
    ((rn & 31) << 5) |
    (rd & 31)
  mc.emit_inst(
    inst & 255,
    (inst >> 8) & 255,
    (inst >> 16) & 255,
    (inst >> 24) & 255,
  )
}

///|
/// Encode SUB (shifted register): SUB Xd, Xn, Xm
/// Opcode: 0xCB000000
pub fn emit_sub_reg(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("sub x\{rd}, x\{rn}, x\{rm}")
  // Same encoding as ADD but with opcode 0xCB
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3 // imm6 = 0
  let b2 = rm & 31 // shift = 0, bit 21 = 0
  let b3 = 203 // 0xCB
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode SUB (immediate): SUB Xd, Xn, #imm12
/// Opcode: 0xD1000000
pub fn emit_sub_imm(mc : MachineCode, rd : Int, rn : Int, imm12 : Int) -> Unit {
  let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
  let rd_name = if rd == 31 { "sp" } else { "x\{rd}" }
  mc.annotate("sub \{rd_name}, \{rn_name}, #\{imm12}")
  // sf=1 | op=1 | S=0 | 100010 | sh=0 | imm12[11:0] | Rn[4:0] | Rd[4:0]
  // Build as 32-bit instruction
  let imm = imm12 & 0xFFF
  let inst = (0b1 << 31) |
    (1 << 30) |
    (0 << 29) |
    (0b100010 << 23) |
    (0 << 22) |
    (imm << 10) |
    ((rn & 31) << 5) |
    (rd & 31)
  mc.emit_inst(
    inst & 255,
    (inst >> 8) & 255,
    (inst >> 16) & 255,
    (inst >> 24) & 255,
  )
}

///|
/// Encode MUL: MUL Xd, Xn, Xm (MADD Xd, Xn, Xm, XZR)
/// Opcode: 0x9B007C00
pub fn emit_mul(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("mul x\{rd}, x\{rn}, x\{rm}")
  // sf=1 | 00 | 11011 | 000 | Rm | 0 | Ra=11111 | Rn | Rd
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | 248 // Ra=11111, bit pattern 0xF8
  let mul_124 = 124 // 0x7C
  let b2 = (mul_124 | ((rm & 15) << 4)) & 255
  let b3 = 155 // 0x9B
  let mul_155 = 155
  mc.emit_inst(b0, b1, b2, (((rm >> 4) | (b3 & 240)) & 255) | mul_155)
}

///|
/// Encode SDIV: SDIV Xd, Xn, Xm
/// Opcode: 0x9AC00C00
pub fn emit_sdiv(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("sdiv x\{rd}, x\{rn}, x\{rm}")
  // Encoding: sf=1 | 0 | 0 | 11010110 | Rm | 00001 | 1 | Rn | Rd
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | 24 // 00001 | 1 pattern = 0x18
  let c0 = 192 // 0xC0
  let b2 = (c0 | (rm & 15)) & 255
  let x9a = 154 // 0x9A
  let b3 = x9a | ((rm >> 4) & 1)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode UDIV: UDIV Xd, Xn, Xm
/// Opcode: 0x9AC00800
pub fn emit_udiv(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("udiv x\{rd}, x\{rn}, x\{rm}")
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | 16 // 00001 | 0 pattern = 0x10
  let c0 = 192 // 0xC0
  let b2 = (c0 | (rm & 15)) & 255
  let x9a = 154 // 0x9A
  let b3 = x9a | ((rm >> 4) & 1)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode AND (shifted register): AND Xd, Xn, Xm
/// Opcode: 0x8A000000
pub fn emit_and_reg(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("and x\{rd}, x\{rn}, x\{rm}")
  // Same encoding format as ADD/SUB but with opcode 0x8A
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3 // imm6 = 0
  let b2 = rm & 31 // shift = 0, bit 21 = 0
  let b3 = 138 // 0x8A
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode ORR (shifted register): ORR Xd, Xn, Xm
/// Opcode: 0xAA000000
pub fn emit_orr_reg(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("orr x\{rd}, x\{rn}, x\{rm}")
  // Same encoding format as ADD/SUB but with opcode 0xAA
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3 // imm6 = 0
  let b2 = rm & 31 // shift = 0, bit 21 = 0
  let b3 = 170 // 0xAA
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode EOR (shifted register): EOR Xd, Xn, Xm
/// Opcode: 0xCA000000
pub fn emit_eor_reg(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("eor x\{rd}, x\{rn}, x\{rm}")
  // Same encoding format as ADD/SUB but with opcode 0xCA
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3 // imm6 = 0
  let b2 = rm & 31 // shift = 0, bit 21 = 0
  let b3 = 202 // 0xCA
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode LSL (register): LSLV Xd, Xn, Xm
/// Opcode: 0x9AC02000
pub fn emit_lsl_reg(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("lsl x\{rd}, x\{rn}, x\{rm}")
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | 64 // 0010 | 00 = 0x40
  let c0 = 192 // 0xC0
  let b2 = (c0 | (rm & 15)) & 255
  let x9a = 154 // 0x9A
  let b3 = x9a | ((rm >> 4) & 1)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode ASR (register): ASRV Xd, Xn, Xm
/// Opcode: 0x9AC02800
pub fn emit_asr_reg(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("asr x\{rd}, x\{rn}, x\{rm}")
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | 80 // 0010 | 10 = 0x50
  let c0 = 192 // 0xC0
  let b2 = (c0 | (rm & 15)) & 255
  let x9a = 154 // 0x9A
  let b3 = x9a | ((rm >> 4) & 1)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode LSR (register): LSRV Xd, Xn, Xm
/// Opcode: 0x9AC02400
pub fn emit_lsr_reg(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("lsr x\{rd}, x\{rn}, x\{rm}")
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | 72 // 0010 | 01 = 0x48
  let c0 = 192 // 0xC0
  let b2 = (c0 | (rm & 15)) & 255
  let x9a = 154 // 0x9A
  let b3 = x9a | ((rm >> 4) & 1)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode MOV (register): MOV Xd, Xm (ORR Xd, XZR, Xm)
pub fn emit_mov_reg(mc : MachineCode, rd : Int, rm : Int) -> Unit {
  mc.annotate("mov x\{rd}, x\{rm}")
  // Inline ORR encoding to avoid double annotation
  let b0 = (rd & 31) | ((31 & 7) << 5)
  let b1 = (31 >> 3) & 3 // imm6 = 0
  let b2 = rm & 31 // shift = 0, bit 21 = 0
  let b3 = 170 // 0xAA
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode 32-bit MOV (register): MOV Wd, Wm (ORR Wd, WZR, Wm)
/// This zero-extends the result to 64-bit in Xd
pub fn emit_mov_reg32(mc : MachineCode, rd : Int, rm : Int) -> Unit {
  mc.annotate("mov w\{rd}, w\{rm}")
  // ORR Wd, WZR, Wm - 32-bit OR with zero register
  // Same as emit_orr_reg but with sf=0 (byte 3 = 0x2A instead of 0xAA)
  let b0 = (rd & 31) | ((31 & 7) << 5) // rd, WZR low bits
  let b1 = (31 >> 3) & 3 // WZR high bits, imm6 = 0
  let b2 = rm & 31 // shift = 0, bit 21 = 0
  let b3 = 0x2A // 32-bit ORR opcode
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode MOVZ: MOVZ Xd, #imm16, LSL #shift
/// Opcode: 0xD2800000
pub fn emit_movz(mc : MachineCode, rd : Int, imm16 : Int, shift : Int) -> Unit {
  mc.annotate("movz x\{rd}, #\{imm16}, lsl #\{shift}")
  let hw = shift / 16
  let imm = imm16 & 0xFFFF
  let b0 = (rd & 31) | ((imm & 7) << 5)
  let b1 = (imm >> 3) & 255
  let b2 = ((imm >> 11) & 31) | ((hw & 3) << 5) | 128 // 0x80 is part of the opcode
  let xd2 = 210 // 0xD2
  let b3 = xd2 | ((hw >> 2) & 1)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode MOVK: MOVK Xd, #imm16, LSL #shift
/// Opcode: 0xF2800000
pub fn emit_movk(mc : MachineCode, rd : Int, imm16 : Int, shift : Int) -> Unit {
  mc.annotate("movk x\{rd}, #\{imm16}, lsl #\{shift}")
  let hw = shift / 16
  let imm = imm16 & 0xFFFF
  let b0 = (rd & 31) | ((imm & 7) << 5)
  let b1 = (imm >> 3) & 255
  let b2 = ((imm >> 11) & 31) | ((hw & 3) << 5) | 128 // 0x80 is part of the opcode
  let xf2 = 242 // 0xF2
  let b3 = xf2 | ((hw >> 2) & 1)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Load a 64-bit immediate using MOVZ/MOVK sequence
pub fn emit_load_imm64(mc : MachineCode, rd : Int, imm : Int64) -> Unit {
  // Work with Int64 to avoid issues with shifts on narrower types
  let v0 = (imm & 0xFFFFL).to_int()
  let v1 = ((imm >> 16) & 0xFFFFL).to_int()
  let v2 = ((imm >> 32) & 0xFFFFL).to_int()
  let v3 = ((imm >> 48) & 0xFFFFL).to_int()
  let mut started = false
  if v0 != 0 || (v1 == 0 && v2 == 0 && v3 == 0) {
    emit_movz(mc, rd, v0, 0)
    started = true
  }
  if v1 != 0 {
    if started {
      emit_movk(mc, rd, v1, 16)
    } else {
      emit_movz(mc, rd, v1, 16)
      started = true
    }
  }
  if v2 != 0 {
    if started {
      emit_movk(mc, rd, v2, 32)
    } else {
      emit_movz(mc, rd, v2, 32)
      started = true
    }
  }
  if v3 != 0 {
    if started {
      emit_movk(mc, rd, v3, 48)
    } else {
      emit_movz(mc, rd, v3, 48)
    }
  }
}

// ============ Load/Store Instructions ============

///|
/// Encode LDR (64-bit, unsigned offset): LDR Xt, [Xn, #imm]
/// Opcode: 0xF9400000
pub fn emit_ldr_imm(mc : MachineCode, rt : Int, rn : Int, imm12 : Int) -> Unit {
  mc.annotate("ldr x\{rt}, [x\{rn}, #\{imm12}]")
  // AArch64 LDR (immediate, unsigned offset) encoding:
  // [31:30] = size = 11 (64-bit)
  // [29:27] = 111 (fixed)
  // [26] = V = 0 (general purpose register)
  // [25:24] = 01 (fixed for unsigned offset)
  // [23:22] = opc = 01 (LDR)
  // [21:10] = imm12 (scaled offset, divided by 8 for 64-bit)
  // [9:5] = Rn (base register)
  // [4:0] = Rt (destination register)
  let scaled = (imm12 / 8) & 0xFFF
  // Build instruction as 32-bit value then extract bytes
  let inst = (0b11 << 30) |
    (0b111 << 27) |
    (0 << 26) |
    (0b01 << 24) |
    (0b01 << 22) |
    (scaled << 10) |
    ((rn & 31) << 5) |
    (rt & 31)
  mc.emit_inst(
    inst & 255,
    (inst >> 8) & 255,
    (inst >> 16) & 255,
    (inst >> 24) & 255,
  )
}

///|
/// Encode STR (64-bit, unsigned offset): STR Xt, [Xn, #imm]
/// Opcode: 0xF9000000
pub fn emit_str_imm(mc : MachineCode, rt : Int, rn : Int, imm12 : Int) -> Unit {
  mc.annotate("str x\{rt}, [x\{rn}, #\{imm12}]")
  // AArch64 STR (immediate, unsigned offset) encoding:
  // Same as LDR but opc = 00 instead of 01
  let scaled = (imm12 / 8) & 0xFFF
  let inst = (0b11 << 30) |
    (0b111 << 27) |
    (0 << 26) |
    (0b01 << 24) |
    (0b00 << 22) |
    (scaled << 10) |
    ((rn & 31) << 5) |
    (rt & 31)
  mc.emit_inst(
    inst & 255,
    (inst >> 8) & 255,
    (inst >> 16) & 255,
    (inst >> 24) & 255,
  )
}

///|
/// Encode LDRB (unsigned offset): LDRB Wt, [Xn, #imm]
/// Opcode: 0x39400000
pub fn emit_ldrb_imm(mc : MachineCode, rt : Int, rn : Int, imm12 : Int) -> Unit {
  mc.annotate("ldrb w\{rt}, [x\{rn}, #\{imm12}]")
  let imm = imm12 & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((imm & 63) << 2)
  let b2 = ((imm >> 6) & 63) | 64 // bit pattern for LDR = 0x40
  let b3 = 57 // 0x39
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode LDRH (unsigned offset): LDRH Wt, [Xn, #imm]
/// Opcode: 0x79400000
pub fn emit_ldrh_imm(mc : MachineCode, rt : Int, rn : Int, imm12 : Int) -> Unit {
  mc.annotate("ldrh w\{rt}, [x\{rn}, #\{imm12}]")
  let scaled = (imm12 / 2) & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
  let b2 = ((scaled >> 6) & 63) | 64 // 0x40
  let b3 = 121 // 0x79
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode LDR (32-bit, unsigned offset): LDR Wt, [Xn, #imm]
/// Opcode: 0xB9400000
pub fn emit_ldr_w_imm(
  mc : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  mc.annotate("ldr w\{rt}, [x\{rn}, #\{imm12}]")
  let scaled = (imm12 / 4) & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
  let b2 = ((scaled >> 6) & 63) | 64 // 0x40
  let b3 = 185 // 0xB9
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode STRB (unsigned offset): STRB Wt, [Xn, #imm]
/// Opcode: 0x39000000
pub fn emit_strb_imm(mc : MachineCode, rt : Int, rn : Int, imm12 : Int) -> Unit {
  mc.annotate("strb w\{rt}, [x\{rn}, #\{imm12}]")
  let imm = imm12 & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((imm & 63) << 2)
  let b2 = (imm >> 6) & 63
  let b3 = 57 // 0x39
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode STRH (unsigned offset): STRH Wt, [Xn, #imm]
/// Opcode: 0x79000000
pub fn emit_strh_imm(mc : MachineCode, rt : Int, rn : Int, imm12 : Int) -> Unit {
  mc.annotate("strh w\{rt}, [x\{rn}, #\{imm12}]")
  let scaled = (imm12 / 2) & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
  let b2 = (scaled >> 6) & 63
  let b3 = 121 // 0x79
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode STR (32-bit, unsigned offset): STR Wt, [Xn, #imm]
/// Opcode: 0xB9000000
pub fn emit_str_w_imm(
  mc : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  mc.annotate("str w\{rt}, [x\{rn}, #\{imm12}]")
  let scaled = (imm12 / 4) & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
  let b2 = (scaled >> 6) & 63
  let b3 = 185 // 0xB9
  mc.emit_inst(b0, b1, b2, b3)
}

// ============ Stack Pair Instructions (for prologue/epilogue) ============

///|
/// Encode STP (Store Pair, pre-indexed): STP Xt1, Xt2, [SP, #imm]!
/// Used in function prologue to save callee-saved registers
/// Opcode: 0xA9800000 base + pre-index flag
/// imm7 is signed, scaled by 8 (range: -512 to 504)
pub fn emit_stp_pre(
  mc : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  imm : Int,
) -> Unit {
  let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
  mc.annotate("stp x\{rt1}, x\{rt2}, [\{rn_name}, #\{imm}]!")
  // STP (pre-indexed) encoding for 64-bit:
  // Instruction format: 1 0 1 0 1 0 0 1 1 | imm7 | Rt2 | Rn | Rt1
  // [31:30] = 10 (opc for 64-bit)
  // [29:27] = 101
  // [26] = 0 (integer, not SIMD)
  // [25:23] = 011 (pre-indexed)
  // [22] = 0 (store, not load)
  // [21:15] = imm7
  // [14:10] = Rt2
  // [9:5] = Rn
  // [4:0] = Rt1
  // So opcode base is 0xA9800000 for pre-indexed STP
  let imm7 = (imm / 8) & 0x7F
  // Build 32-bit instruction
  let inst = (0b10 << 30) |
    (0b101 << 27) |
    (0 << 26) |
    (0b011 << 23) |
    (0 << 22) |
    (imm7 << 15) |
    ((rt2 & 31) << 10) |
    ((rn & 31) << 5) |
    (rt1 & 31)
  mc.emit_inst(
    inst & 255,
    (inst >> 8) & 255,
    (inst >> 16) & 255,
    (inst >> 24) & 255,
  )
}

///|
/// Encode LDP (Load Pair, post-indexed): LDP Xt1, Xt2, [SP], #imm
/// Used in function epilogue to restore callee-saved registers
/// Opcode: 0xA8C00000 base
pub fn emit_ldp_post(
  mc : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  imm : Int,
) -> Unit {
  let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
  mc.annotate("ldp x\{rt1}, x\{rt2}, [\{rn_name}], #\{imm}")
  // LDP (post-indexed) encoding for 64-bit:
  // [31:30] = 10 (opc for 64-bit)
  // [29:27] = 101
  // [26] = 0 (integer)
  // [25:23] = 001 (post-indexed)
  // [22] = 1 (load)
  // [21:15] = imm7
  // [14:10] = Rt2
  // [9:5] = Rn
  // [4:0] = Rt1
  let imm7 = (imm / 8) & 0x7F
  let inst = (0b10 << 30) |
    (0b101 << 27) |
    (0 << 26) |
    (0b001 << 23) |
    (1 << 22) |
    (imm7 << 15) |
    ((rt2 & 31) << 10) |
    ((rn & 31) << 5) |
    (rt1 & 31)
  mc.emit_inst(
    inst & 255,
    (inst >> 8) & 255,
    (inst >> 16) & 255,
    (inst >> 24) & 255,
  )
}

// ============ Sign-Extending Load Instructions ============

///|
/// Encode LDRSB (64-bit result, unsigned offset): LDRSB Xt, [Xn, #imm]
/// Opcode: 0x39800000
pub fn emit_ldrsb_x_imm(
  mc : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  mc.annotate("ldrsb x\{rt}, [x\{rn}, #\{imm12}]")
  let imm = imm12 & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((imm & 63) << 2)
  let b2 = ((imm >> 6) & 63) | 128 // bit 7 = 1 for signed + 64-bit
  let b3 = 57 // 0x39
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode LDRSB (32-bit result, unsigned offset): LDRSB Wt, [Xn, #imm]
/// Opcode: 0x39C00000
pub fn emit_ldrsb_w_imm(
  mc : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  mc.annotate("ldrsb w\{rt}, [x\{rn}, #\{imm12}]")
  let imm = imm12 & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((imm & 63) << 2)
  let b2 = ((imm >> 6) & 63) | 192 // bit 7,6 = 11 for signed + 32-bit
  let b3 = 57 // 0x39
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode LDRSH (64-bit result, unsigned offset): LDRSH Xt, [Xn, #imm]
/// Opcode: 0x79800000
pub fn emit_ldrsh_x_imm(
  mc : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  mc.annotate("ldrsh x\{rt}, [x\{rn}, #\{imm12}]")
  let scaled = (imm12 / 2) & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
  let b2 = ((scaled >> 6) & 63) | 128 // bit 7 = 1 for signed + 64-bit
  let b3 = 121 // 0x79
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode LDRSH (32-bit result, unsigned offset): LDRSH Wt, [Xn, #imm]
/// Opcode: 0x79C00000
pub fn emit_ldrsh_w_imm(
  mc : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  mc.annotate("ldrsh w\{rt}, [x\{rn}, #\{imm12}]")
  let scaled = (imm12 / 2) & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
  let b2 = ((scaled >> 6) & 63) | 192 // bit 7,6 = 11 for signed + 32-bit
  let b3 = 121 // 0x79
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode LDRSW (unsigned offset): LDRSW Xt, [Xn, #imm]
/// Opcode: 0xB9800000
pub fn emit_ldrsw_imm(
  mc : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  mc.annotate("ldrsw x\{rt}, [x\{rn}, #\{imm12}]")
  let scaled = (imm12 / 4) & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
  let b2 = ((scaled >> 6) & 63) | 128 // bit 7 = 1 for signed
  let b3 = 185 // 0xB9
  mc.emit_inst(b0, b1, b2, b3)
}

// ============ Branch Instructions ============

///|
/// Encode B (unconditional branch): B label
/// Opcode: 0x14000000
pub fn emit_b(mc : MachineCode, target_block : Int) -> Unit {
  mc.annotate("b block\{target_block}")
  mc.emit_inst(0, 0, 0, 20) // 0x14
  mc.add_fixup(target_block, Branch26)
}

///|
/// Encode B.cond (conditional branch): B.cond label
/// Opcode: 0x54000000
pub fn emit_b_cond(mc : MachineCode, cond : Int, target_block : Int) -> Unit {
  let cond_name = match cond {
    0 => "eq"
    1 => "ne"
    2 => "hs"
    3 => "lo"
    10 => "ge"
    11 => "lt"
    12 => "gt"
    13 => "le"
    _ => "?\{cond}"
  }
  mc.annotate("b.\{cond_name} block\{target_block}")
  mc.emit_inst(cond & 15, 0, 0, 84) // 0x54
  mc.add_fixup(target_block, Branch19)
}

///|
/// Encode CBZ: CBZ Xt, label
/// Opcode: 0xB4000000
pub fn emit_cbz(mc : MachineCode, rt : Int, target_block : Int) -> Unit {
  mc.annotate("cbz x\{rt}, block\{target_block}")
  mc.emit_inst(rt & 31, 0, 0, 180) // 0xB4
  mc.add_fixup(target_block, Branch19)
}

///|
/// Encode CBNZ: CBNZ Xt, label
/// Opcode: 0xB5000000
pub fn emit_cbnz(mc : MachineCode, rt : Int, target_block : Int) -> Unit {
  mc.annotate("cbnz x\{rt}, block\{target_block}")
  mc.emit_inst(rt & 31, 0, 0, 181) // 0xB5
  mc.add_fixup(target_block, Branch19)
}

///|
/// Encode RET: RET Xn
/// Opcode: 0xD65F0000 (with Rn in bits [9:5])
pub fn emit_ret(mc : MachineCode, rn : Int) -> Unit {
  mc.annotate("ret")
  // Rn goes in bits [9:5] of the instruction
  // In little-endian bytes:
  // byte0 bits [7:5] = Rn[2:0]
  // byte1 bits [2:0] = Rn[4:3]
  let b0 = (rn & 7) << 5 // Rn[2:0] in bits [7:5]
  let b1 = (rn >> 3) & 3 // Rn[4:3] in bits [1:0]
  mc.emit_inst(b0, b1, 95, 214) // 0x5F, 0xD6
}

///|
/// Encode BL (branch with link): BL label
/// Opcode: 0x94000000
pub fn emit_bl(mc : MachineCode, target_block : Int) -> Unit {
  mc.annotate("bl block\{target_block}")
  mc.emit_inst(0, 0, 0, 148) // 0x94
  mc.add_fixup(target_block, Branch26)
}

///|
/// Encode BLR (branch with link to register): BLR Xn
/// Opcode: 0xD63F0000
/// The register goes in bits [9:5]
pub fn emit_blr(mc : MachineCode, rn : Int) -> Unit {
  mc.annotate("blr x\{rn}")
  // BLR Xn encoding: 0xD63F0000 with Rn in bits [9:5]
  // In little-endian bytes:
  // byte0 bits [7:5] = Rn[2:0], bits [4:0] = 0
  // byte1 bits [1:0] = Rn[4:3], rest is opcode
  let b0 = (rn & 7) << 5 // Rn[2:0] in bits [7:5]
  let b1 = (rn >> 3) & 3 // Rn[4:3] in bits [1:0]
  mc.emit_inst(b0, b1, 63, 214) // 0x3F, 0xD6
}

// ============ Comparison Instructions ============

///|
/// Encode CMP (register): CMP Xn, Xm (SUBS XZR, Xn, Xm)
/// Opcode: 0xEB00001F
pub fn emit_cmp_reg(mc : MachineCode, rn : Int, rm : Int) -> Unit {
  mc.annotate("cmp x\{rn}, x\{rm}")
  // SUBS with Rd=31 (XZR)
  // Same encoding as SUB (shifted register) but with S=1 (opcode 0xEB instead of 0xCB)
  let b0 = 31 | ((rn & 7) << 5) // Rd=31 (XZR)
  let b1 = (rn >> 3) & 3 // imm6 = 0
  let b2 = rm & 31 // shift = 0
  let b3 = 235 // 0xEB
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode CMP (immediate): CMP Xn, #imm12 (SUBS XZR, Xn, #imm12)
/// Opcode: 0xF100001F
pub fn emit_cmp_imm(mc : MachineCode, rn : Int, imm12 : Int) -> Unit {
  mc.annotate("cmp x\{rn}, #\{imm12}")
  let imm = imm12 & 0xFFF
  let x1f = 31 // 0x1F
  let b0 = x1f | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | ((imm & 31) << 3)
  let b2 = (imm >> 5) & 127
  let b3 = 241 // 0xF1
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode CSET: CSET Xd, cond (CSINC Xd, XZR, XZR, invert(cond))
/// Opcode: 0x9A9F0400
pub fn emit_cset(mc : MachineCode, rd : Int, cond : Int) -> Unit {
  let cond_name = match cond {
    0 => "eq"
    1 => "ne"
    2 => "hs"
    3 => "lo"
    10 => "ge"
    11 => "lt"
    12 => "gt"
    13 => "le"
    _ => "?\{cond}"
  }
  mc.annotate("cset x\{rd}, \{cond_name}")
  let inv_cond = cond ^ 1
  // CSINC Xd, XZR, XZR, inv_cond
  // Encoding: sf=1 | 00 | 11010100 | Rm=11111 | cond | 0 | 1 | Rn=11111 | Rd
  let xe0 = 224 // Rn=11111 bits [1:0] shifted = 0xE0
  let b0 = (rd & 31) | xe0
  let x07 = 7
  let x04 = 4 // cond and opcode bits
  let b1 = x07 | ((inv_cond & 15) << 4) | x04
  let b2 = 159 // Rm=11111 = 0x9F
  let b3 = 154 // 0x9A
  mc.emit_inst(b0, b1, b2, b3)
}

// ============ Floating-Point Instructions ============

///|
/// Encode FADD (double): FADD Dd, Dn, Dm
/// Opcode: 0x1E602800
pub fn emit_fadd_d(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fadd d\{rd}, d\{rn}, d\{rm}")
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | 40 // 0x28
  let x60 = 96 // 0x60
  let x6f = 111 // 0x6F
  let b2 = (x60 | (rm & 15)) & x6f
  let x1e = 30 // 0x1E
  let b3 = x1e | ((rm >> 4) & 1)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FSUB (double): FSUB Dd, Dn, Dm
/// Opcode: 0x1E603800
pub fn emit_fsub_d(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fsub d\{rd}, d\{rn}, d\{rm}")
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | 56 // 0x38
  let x60 = 96 // 0x60
  let x6f = 111 // 0x6F
  let b2 = (x60 | (rm & 15)) & x6f
  let x1e = 30 // 0x1E
  let b3 = x1e | ((rm >> 4) & 1)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FMUL (double): FMUL Dd, Dn, Dm
/// Opcode: 0x1E600800
pub fn emit_fmul_d(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fmul d\{rd}, d\{rn}, d\{rm}")
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | 8 // 0x08
  let x60 = 96 // 0x60
  let x6f = 111 // 0x6F
  let b2 = (x60 | (rm & 15)) & x6f
  let x1e = 30 // 0x1E
  let b3 = x1e | ((rm >> 4) & 1)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FDIV (double): FDIV Dd, Dn, Dm
/// Opcode: 0x1E601800
pub fn emit_fdiv_d(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fdiv d\{rd}, d\{rn}, d\{rm}")
  let b0 = (rd & 31) | ((rn & 3) << 5)
  let b1 = ((rn >> 2) & 7) | 24 // 0x18
  let x60 = 96 // 0x60
  let x6f = 111 // 0x6F
  let b2 = (x60 | (rm & 15)) & x6f
  let x1e = 30 // 0x1E
  let b3 = x1e | ((rm >> 4) & 1)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FMOV (double, register): FMOV Dd, Dm
/// Opcode: 0x1E604000
pub fn emit_fmov_d(mc : MachineCode, rd : Int, rm : Int) -> Unit {
  mc.annotate("fmov d\{rd}, d\{rm}")
  // Encoding: Rd in bits [4:0], Rn in bits [9:5]
  let b0 = (rd & 31) | ((rm & 7) << 5)
  let b1 = ((rm >> 3) & 3) | 64 // 0x40
  let b2 = 96 // 0x60
  let b3 = 30 // 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FMOV (double to general): FMOV Xd, Dn
/// Opcode: 0x9E660000
/// Moves 64-bit FP register to 64-bit GPR
pub fn emit_fmov_d_to_x(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("fmov x\{rd}, d\{rn}")
  // Rd in bits [4:0], Rn in bits [9:5]
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3
  let b2 = 102 // 0x66
  let b3 = 158 // 0x9E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FMOV (single to general): FMOV Wd, Sn
/// Opcode: 0x1E260000
/// Moves 32-bit FP register to 32-bit GPR
pub fn emit_fmov_s_to_w(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("fmov w\{rd}, s\{rn}")
  // Rd in bits [4:0], Rn in bits [9:5]
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3
  let b2 = 38 // 0x26
  let b3 = 30 // 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FMOV (general to double): FMOV Dd, Xn
/// Opcode: 0x9E670000
/// Moves 64-bit GPR to 64-bit FP register
pub fn emit_fmov_x_to_d(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("fmov d\{rd}, x\{rn}")
  // Rd in bits [4:0], Rn in bits [9:5]
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3
  let b2 = 103 // 0x67
  let b3 = 158 // 0x9E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FMOV (general to single): FMOV Sd, Wn
/// Opcode: 0x1E270000
/// Moves 32-bit GPR to 32-bit FP register
pub fn emit_fmov_w_to_s(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("fmov s\{rd}, w\{rn}")
  // Rd in bits [4:0], Rn in bits [9:5]
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3
  let b2 = 39 // 0x27
  let b3 = 30 // 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FCVT (single to double): FCVT Dd, Sn
/// Opcode: 0x1E22C000
/// Converts single-precision float to double-precision
pub fn emit_fcvt_d_s(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("fcvt d\{rd}, s\{rn}")
  // Rd in bits [4:0], Rn in bits [9:5]
  // Encoding: 0 0 0 1 1 1 1 0 0 0 1 0 0 0 1 0 1 1 0 0 0 0 0 0 Rn Rd
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 192 // 0xC0
  let b2 = 34 // 0x22
  let b3 = 30 // 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode LDR (single, unsigned offset): LDR St, [Xn, #imm]
/// Opcode: 0xBD400000
pub fn emit_ldr_s_imm(
  mc : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  mc.annotate("ldr s\{rt}, [x\{rn}, #\{imm12}]")
  let scaled = (imm12 / 4) & 0xFFF
  // Encoding: Rt in bits [4:0], Rn in bits [9:5], imm12 in bits [21:10]
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
  let b2 = ((scaled >> 6) & 63) | 64 // 0x40 for LDR
  let b3 = 189 // 0xBD
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode STR (single, unsigned offset): STR St, [Xn, #imm]
/// Opcode: 0xBD000000
pub fn emit_str_s_imm(
  mc : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  mc.annotate("str s\{rt}, [x\{rn}, #\{imm12}]")
  let scaled = (imm12 / 4) & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
  let b2 = (scaled >> 6) & 63
  let b3 = 189 // 0xBD
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode LDR (double, unsigned offset): LDR Dt, [Xn, #imm]
/// Opcode: 0xFD400000
pub fn emit_ldr_d_imm(
  mc : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  mc.annotate("ldr d\{rt}, [x\{rn}, #\{imm12}]")
  let scaled = (imm12 / 8) & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
  let b2 = ((scaled >> 6) & 63) | 64 // 0x40 for LDR
  let b3 = 253 // 0xFD
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode STR (double, unsigned offset): STR Dt, [Xn, #imm]
/// Opcode: 0xFD000000
pub fn emit_str_d_imm(
  mc : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  mc.annotate("str d\{rt}, [x\{rn}, #\{imm12}]")
  let scaled = (imm12 / 8) & 0xFFF
  let b0 = (rt & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
  let b2 = (scaled >> 6) & 63
  let b3 = 253 // 0xFD
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Store 64-bit integer to memory with offset
/// STR Xt, [Xn, #offset]
fn emit_str_offset(mc : MachineCode, rt : Int, rn : Int, offset : Int) -> Unit {
  emit_str_imm(mc, rt, rn, offset)
}

///|
/// Store double to memory with offset
/// STR Dt, [Xn, #offset]
fn emit_str_d_offset(
  mc : MachineCode,
  rt : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  emit_str_d_imm(mc, rt, rn, offset)
}

///|
/// Encode FCMP (double): FCMP Dn, Dm
/// Opcode: 0x1E602000
pub fn emit_fcmp_d(mc : MachineCode, rn : Int, rm : Int) -> Unit {
  mc.annotate("fcmp d\{rn}, d\{rm}")
  let b0 = (rn & 3) << 5
  let b1 = ((rn >> 2) & 7) | 32 // 0x20
  let x60 = 96 // 0x60
  let x6f = 111 // 0x6F
  let b2 = (x60 | (rm & 15)) & x6f
  let x1e = 30 // 0x1E
  let b3 = x1e | ((rm >> 4) & 1)
  mc.emit_inst(b0, b1, b2, b3)
}

// ============ NOP ============

///|
/// Encode NOP
/// Opcode: 0xD503201F
pub fn emit_nop(mc : MachineCode) -> Unit {
  mc.annotate("nop")
  mc.emit_inst(31, 32, 3, 213) // 0x1F, 0x20, 0x03, 0xD5
}

// ============ Condition Codes ============

///|
/// AArch64 condition codes
pub(all) enum CondCode {
  EQ // Equal (Z=1)
  NE // Not equal (Z=0)
  HS // Unsigned higher or same (C=1), also CS
  LO // Unsigned lower (C=0), also CC
  MI // Minus/negative (N=1)
  PL // Plus/positive or zero (N=0)
  VS // Overflow (V=1)
  VC // No overflow (V=0)
  HI // Unsigned higher (C=1 & Z=0)
  LS // Unsigned lower or same (C=0 | Z=1)
  GE // Signed greater or equal (N=V)
  LT // Signed less than (N!=V)
  GT // Signed greater than (Z=0 & N=V)
  LE // Signed less or equal (Z=1 | N!=V)
  AL // Always
}

///|
pub fn CondCode::to_int(self : CondCode) -> Int {
  match self {
    EQ => 0
    NE => 1
    HS => 2
    LO => 3
    MI => 4
    PL => 5
    VS => 6
    VC => 7
    HI => 8
    LS => 9
    GE => 10
    LT => 11
    GT => 12
    LE => 13
    AL => 14
  }
}

// ============ VCode to Machine Code ============

///|
/// Check if a register index is a callee-saved register that we use for allocation
fn is_callee_saved_alloc(reg : Int) -> Bool {
  // X19, X23-X28 are callee-saved registers we allocate
  // X20, X21, X22 are reserved for func_table, memory_base, memory_size
  reg == 19 || (reg >= 23 && reg <= 28)
}

///|
/// Collect all callee-saved registers that are defined in the function
/// Also includes LR (X30) if the function makes any calls
fn collect_used_callee_saved(func : VCodeFunction) -> Array[Int] {
  let used : @hashset.HashSet[Int] = @hashset.new()
  let mut has_calls = false
  for block in func.blocks {
    for inst in block.insts {
      // Check if this instruction is a function call
      if inst.opcode is CallIndirect(_, _) {
        has_calls = true
      }
      for def in inst.defs {
        match def.reg {
          Physical(preg) =>
            if is_callee_saved_alloc(preg.index) {
              used.add(preg.index)
            }
          Virtual(_) => ()
        }
      }
    }
  }
  // If the function makes any calls, we must save LR (X30)
  if has_calls {
    used.add(30)
  }
  // Sort the registers for consistent ordering
  let result : Array[Int] = []
  for reg in used {
    result.push(reg)
  }
  result.sort()
  result
}

///|
/// Emit prologue to save callee-saved registers and set up parameters
/// Returns the stack frame size used
/// When needs_extra_ptr is true:
///   - X0 contains the extra results buffer pointer (saved to X23)
///   - X1 = func_table_ptr, X2 = memory_base, X3 = memory_size
///   - User params start from X4
/// When needs_extra_ptr is false:
///   - X0 = func_table_ptr, X1 = memory_base, X2 = memory_size
///   - User params start from X3
fn emit_prologue(
  mc : MachineCode,
  clobbered : Array[Int],
  params : Array[VReg],
  needs_extra_ptr : Bool,
) -> Int {
  // We always clobber X20, X21, X22 for func_table, memory_base, memory_size
  // When needs_extra_ptr, we also clobber X23 for the extra results pointer
  // These are callee-saved registers, so we must save them first!
  let all_to_save : Array[Int] = if needs_extra_ptr {
    [20, 21, 22, 23]
  } else {
    [20, 21, 22]
  }
  for reg in clobbered {
    all_to_save.push(reg)
  }
  // Round up to even number for STP (store pairs)
  let num_regs = all_to_save.length()
  let num_pairs = (num_regs + 1) / 2
  let frame_size = num_pairs * 16 // 16 bytes per pair
  // Allocate stack frame first using SUB
  emit_sub_imm(mc, 31, 31, frame_size)
  // Save registers using STP with signed offset
  let mut i = 0
  let mut pair_idx = 0
  while i < num_regs {
    let reg1 = all_to_save[i]
    let reg2 = if i + 1 < num_regs { all_to_save[i + 1] } else { 31 } // XZR as padding
    let offset = pair_idx * 16
    emit_stp_offset(mc, reg1, reg2, 31, offset)
    i = i + 2
    pair_idx = pair_idx + 1
  }
  // Now move parameters to reserved registers (after saving their original values)
  if needs_extra_ptr {
    // X0 = extra_results_ptr, X1 = func_table, X2 = memory_base, X3 = memory_size
    emit_mov_reg(mc, 23, 0) // MOV X23, X0 (extra_results_ptr)
    emit_mov_reg(mc, 20, 1) // MOV X20, X1 (func_table_ptr)
    emit_mov_reg(mc, 21, 2) // MOV X21, X2 (memory_base)
    emit_mov_reg(mc, 22, 3) // MOV X22, X3 (memory_size)
  } else {
    // X0 = func_table, X1 = memory_base, X2 = memory_size
    emit_mov_reg(mc, 20, 0) // MOV X20, X0 (func_table_ptr)
    emit_mov_reg(mc, 21, 1) // MOV X21, X1 (memory_base)
    emit_mov_reg(mc, 22, 2) // MOV X22, X2 (memory_size)
  }
  // Move user arguments from X registers to their allocated registers
  // FFI passes all args as Int64 in X registers
  // Float params need special handling:
  //   - For f32: lower 32 bits of X register contain f32 bit pattern
  //     We need to extract to S register, then FCVT to D register
  //   - For f64: full 64 bits of X register contain f64 bit pattern
  //     We need to FMOV from X register to D register
  // Regalloc assigns: Int param i → X(base+i), Float param i → D(i)
  let param_base = if needs_extra_ptr { 4 } else { 3 } // User params start at X4 or X3
  for param_idx, param in params {
    let x_src = param_base + param_idx
    match param.class {
      Float32 => {
        // Float32 param: extract f32 from lower 32 bits and convert to f64
        // 1. FMOV S16, W(x_src) - move lower 32 bits to S register
        // 2. FCVT D(param_idx), S16 - convert f32 to f64
        emit_fmov_w_to_s(mc, 16, x_src) // FMOV S16, W(base+i)
        emit_fcvt_d_s(mc, param_idx, 16) // FCVT D(i), S16
      }
      Float64 =>
        // Float64 param: move full 64 bits from X register to D register
        // FMOV D(param_idx), X(x_src)
        emit_fmov_x_to_d(mc, param_idx, x_src)
      Int =>
        // Int param: already in X(base+i) where regalloc expects it
        // No move needed
        ()
    }
  }
  frame_size
}

///|
/// Emit STP with signed offset (not pre/post indexed)
fn emit_stp_offset(
  mc : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
  mc.annotate("stp x\{rt1}, x\{rt2}, [\{rn_name}, #\{offset}]")
  // STP (signed offset) encoding for 64-bit:
  // [31:30] = 10 (opc for 64-bit)
  // [29:27] = 101
  // [26] = 0 (integer)
  // [25:23] = 010 (signed offset)
  // [22] = 0 (store)
  // [21:15] = imm7
  // [14:10] = Rt2
  // [9:5] = Rn
  // [4:0] = Rt1
  let imm7 = (offset / 8) & 0x7F
  let inst = (0b10 << 30) |
    (0b101 << 27) |
    (0 << 26) |
    (0b010 << 23) |
    (0 << 22) |
    (imm7 << 15) |
    ((rt2 & 31) << 10) |
    ((rn & 31) << 5) |
    (rt1 & 31)
  mc.emit_inst(
    inst & 255,
    (inst >> 8) & 255,
    (inst >> 16) & 255,
    (inst >> 24) & 255,
  )
}

///|
/// Emit LDP with signed offset (not pre/post indexed)
fn emit_ldp_offset(
  mc : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
  mc.annotate("ldp x\{rt1}, x\{rt2}, [\{rn_name}, #\{offset}]")
  let imm7 = (offset / 8) & 0x7F
  let inst = (0b10 << 30) |
    (0b101 << 27) |
    (0 << 26) |
    (0b010 << 23) |
    (1 << 22) |
    (imm7 << 15) |
    ((rt2 & 31) << 10) |
    ((rn & 31) << 5) |
    (rt1 & 31)
  mc.emit_inst(
    inst & 255,
    (inst >> 8) & 255,
    (inst >> 16) & 255,
    (inst >> 24) & 255,
  )
}

///|
/// Emit epilogue to restore callee-saved registers
fn emit_epilogue(
  mc : MachineCode,
  clobbered : Array[Int],
  frame_size : Int,
  needs_extra_ptr : Bool,
) -> Unit {
  // Build the same list as prologue: X20, X21, X22, (X23 if needed) + clobbered
  let all_to_restore : Array[Int] = if needs_extra_ptr {
    [20, 21, 22, 23]
  } else {
    [20, 21, 22]
  }
  for reg in clobbered {
    all_to_restore.push(reg)
  }
  let num_regs = all_to_restore.length()
  let num_pairs = (num_regs + 1) / 2
  // Restore registers using LDP
  let mut i = 0
  let mut pair_idx = 0
  while i < num_regs {
    let reg1 = all_to_restore[i]
    let reg2 = if i + 1 < num_regs { all_to_restore[i + 1] } else { 31 }
    let offset = pair_idx * 16
    if pair_idx == num_pairs - 1 {
      // Last LDP with post-indexed to deallocate stack
      // But we still need to load from the correct offset first
      if pair_idx == 0 {
        // Only one pair, use post-indexed directly
        emit_ldp_post(mc, reg1, reg2, 31, frame_size)
      } else {
        // Multiple pairs: load from offset, then add to SP
        emit_ldp_offset(mc, reg1, reg2, 31, offset)
        // Add frame_size to SP
        emit_add_imm(mc, 31, 31, frame_size)
      }
    } else {
      emit_ldp_offset(mc, reg1, reg2, 31, offset)
    }
    i = i + 2
    pair_idx = pair_idx + 1
  }
}

///|
/// Emit machine code for a VCode function
pub fn emit_function(func : VCodeFunction) -> MachineCode {
  let mc = MachineCode::new()
  // Check if we need extra results pointer
  let needs_extra_ptr = func.needs_extra_results_ptr()
  // Collect callee-saved registers that this function clobbers
  let clobbered = collect_used_callee_saved(func)
  // Emit prologue: save callee-saved registers, set up X20/X21/X22, and move params
  let frame_size = emit_prologue(mc, clobbered, func.params, needs_extra_ptr)
  // Emit function body
  for block in func.blocks {
    mc.define_label(block.id)
    for inst in block.insts {
      emit_instruction(mc, inst)
    }
    match block.terminator {
      Some(term) =>
        emit_terminator_with_epilogue(
          mc,
          term,
          clobbered,
          frame_size,
          func.result_types,
          needs_extra_ptr,
        )
      None => ()
    }
  }
  mc.resolve_fixups()
  mc
}

///|
fn emit_instruction(mc : MachineCode, inst : VCodeInst) -> Unit {
  match inst.opcode {
    Add => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_add_reg(mc, rd, rn, rm)
    }
    AddImm(imm) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      emit_add_imm(mc, rd, rn, imm)
    }
    Sub => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_sub_reg(mc, rd, rn, rm)
    }
    Mul => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_mul(mc, rd, rn, rm)
    }
    SDiv => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_sdiv(mc, rd, rn, rm)
    }
    UDiv => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_udiv(mc, rd, rn, rm)
    }
    And => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_and_reg(mc, rd, rn, rm)
    }
    Or => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_orr_reg(mc, rd, rn, rm)
    }
    Xor => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_eor_reg(mc, rd, rn, rm)
    }
    Shl => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_lsl_reg(mc, rd, rn, rm)
    }
    AShr => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_asr_reg(mc, rd, rn, rm)
    }
    LShr => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_lsr_reg(mc, rd, rn, rm)
    }
    FAdd => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_fadd_d(mc, rd, rn, rm)
    }
    FSub => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_fsub_d(mc, rd, rn, rm)
    }
    FMul => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_fmul_d(mc, rd, rn, rm)
    }
    FDiv => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_fdiv_d(mc, rd, rn, rm)
    }
    Load(ty, offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      emit_load(mc, ty, rt, rn, offset)
    }
    Store(ty, offset) => {
      // uses[0] = address (Rn), uses[1] = value (Rt)
      let rn = reg_num(inst.uses[0]) // base address
      let rt = reg_num(inst.uses[1]) // value to store
      emit_store(mc, ty, rt, rn, offset)
    }
    // Narrow load operations (8/16/32-bit with sign/zero extension)
    Load8S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Sign-extend to 64-bit (use LDRSB Xt form)
      emit_ldrsb_x_imm(mc, rt, rn, offset)
    }
    Load8U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Zero-extend (LDRB already zero-extends)
      emit_ldrb_imm(mc, rt, rn, offset)
    }
    Load16S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Sign-extend to 64-bit (use LDRSH Xt form)
      emit_ldrsh_x_imm(mc, rt, rn, offset)
    }
    Load16U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Zero-extend (LDRH already zero-extends)
      emit_ldrh_imm(mc, rt, rn, offset)
    }
    Load32S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Sign-extend 32-bit to 64-bit
      emit_ldrsw_imm(mc, rt, rn, offset)
    }
    Load32U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Zero-extend (LDR W already zero-extends to 64-bit)
      emit_ldr_w_imm(mc, rt, rn, offset)
    }
    Move => {
      let rd = wreg_num(inst.defs[0])
      let rm = reg_num(inst.uses[0])
      // Check register class to use appropriate move instruction
      let reg_class = match inst.defs[0].reg {
        Physical(preg) => preg.class
        Virtual(_) => Int // Should not happen at emit time
      }
      match reg_class {
        Float32 | Float64 => emit_fmov_d(mc, rd, rm)
        Int => emit_mov_reg(mc, rd, rm)
      }
    }
    LoadConst(v) => {
      let rd = wreg_num(inst.defs[0])
      emit_load_imm64(mc, rd, v)
    }
    LoadConstF32(bits) => {
      // Load 32-bit float constant and convert to double:
      // 1. Load the 32-bit representation into a scratch W register (X16/W16)
      // 2. FMOV from W16 to scratch S register (S16)
      // 3. FCVT to convert f32 to f64 in destination D register
      // This ensures the f32 value is properly represented as f64 for our
      // double-precision arithmetic operations
      let rd = wreg_num(inst.defs[0])
      // Use X16 as scratch register, load the 32-bit value as unsigned
      emit_movz(mc, 16, bits & 0xFFFF, 0)
      let high = (bits >> 16) & 0xFFFF
      if high != 0 {
        emit_movk(mc, 16, high, 16)
      }
      // FMOV S16, W16 (move 32-bit value to S register)
      emit_fmov_w_to_s(mc, 16, 16)
      // FCVT Dd, S16 (convert single to double)
      emit_fcvt_d_s(mc, rd, 16)
    }
    LoadConstF64(bits) => {
      // Load 64-bit float constant:
      // 1. Load the 64-bit representation into a scratch X register (X16)
      // 2. FMOV from X16 to the destination D register
      let rd = wreg_num(inst.defs[0])
      // Use X16 as scratch register
      emit_load_imm64(mc, 16, bits)
      // FMOV Dd, Xn
      emit_fmov_x_to_d(mc, rd, 16)
    }
    Cmp(kind) => {
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_cmp_reg(mc, rn, rm)
      let rd = wreg_num(inst.defs[0])
      let cond = cmp_kind_to_cond(kind)
      emit_cset(mc, rd, cond)
    }
    FCmp(kind) => {
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_fcmp_d(mc, rn, rm)
      let rd = wreg_num(inst.defs[0])
      let cond = fcmp_kind_to_cond(kind)
      emit_cset(mc, rd, cond)
    }
    Extend(_) | Truncate | IntToFloat | FloatToInt => emit_nop(mc)
    Nop => emit_nop(mc)
    BoundsCheck(offset, access_size) => {
      // Memory bounds check: trap if wasm_addr + offset + access_size > memory_size
      // Uses: [wasm_addr]
      // X22 = memory_size (stored in prologue)
      // We use X16 as a temporary register for calculation (platform scratch, not allocatable)
      //
      // IMPORTANT: WASM addresses are 32-bit unsigned. We must zero-extend to 64-bit
      // to avoid overflow issues when the 32-bit value is negative (like 0xFFFFFFFF).
      let wasm_addr = reg_num(inst.uses[0])
      // First zero-extend the 32-bit wasm_addr to X16 (clear upper 32 bits)
      emit_mov_reg32(mc, 16, wasm_addr)
      // Compute end_addr = X16 + offset + access_size
      // Handle offset as unsigned 32-bit, then add access_size
      let offset_u64 = offset
        .reinterpret_as_uint()
        .to_uint64()
        .reinterpret_as_int64()
      let end_offset = offset_u64 + access_size.to_int64()
      if end_offset > 0L {
        // Compute end_addr = X16 + (offset + access_size)
        if end_offset <= 4095L {
          // Use ADD immediate for small offsets: X16 = X16 + end_offset
          emit_add_imm(mc, 16, 16, end_offset.to_int())
        } else {
          // For large offsets, load the offset into X17 first, then ADD register
          emit_load_imm64(mc, 17, end_offset)
          // ADD X16, X16, X17
          emit_add_reg(mc, 16, 16, 17)
        }
      }
      // CMP X16, X22 (compare end_addr with memory_size)
      emit_cmp_reg(mc, 16, 22)
      // B.HI trap (branch if unsigned higher, meaning out of bounds)
      // We need to emit: B.HI +8 (skip the BRK if in bounds)
      // B.LS is condition code 9 (LS = lower or same, unsigned <=)
      // So we use B.LS to skip the trap
      // B.cond encoding: imm19 in bits [23:5], cond in bits [3:0]
      // We want to jump +2 instructions (8 bytes) to skip the BRK
      let skip_imm19 = 2 // Skip 2 instructions = 8 bytes
      let b_ls_cond = 9 // LS condition
      let b0 = b_ls_cond | ((skip_imm19 & 7) << 5)
      let b1 = (skip_imm19 >> 3) & 0xFF
      let b2 = (skip_imm19 >> 11) & 0xFF
      let b3 = 0x54 // B.cond opcode
      mc.emit_inst(b0, b1, b2, b3)
      // BRK #1 - trap with code 1 for out of bounds memory access
      // BRK encoding: 0xD4200000 + (imm16 << 5)
      // BRK #1 = 0xD4200020
      mc.emit_inst(0x20, 0x00, 0x20, 0xD4)
    }
    // AArch64-specific: shifted operand instructions
    AddShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_add_shifted(mc, rd, rn, rm, shift, amount)
    }
    SubShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_sub_shifted(mc, rd, rn, rm, shift, amount)
    }
    AndShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_and_shifted(mc, rd, rn, rm, shift, amount)
    }
    OrShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_orr_shifted(mc, rd, rn, rm, shift, amount)
    }
    XorShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_eor_shifted(mc, rd, rn, rm, shift, amount)
    }
    // AArch64-specific: multiply-accumulate instructions
    Madd => {
      // Xd = Xa + Xn * Xm, uses: [acc, src1, src2]
      let rd = wreg_num(inst.defs[0])
      let ra = reg_num(inst.uses[0]) // accumulator
      let rn = reg_num(inst.uses[1]) // multiplicand
      let rm = reg_num(inst.uses[2]) // multiplier
      emit_madd(mc, rd, rn, rm, ra)
    }
    Msub => {
      // Xd = Xa - Xn * Xm, uses: [acc, src1, src2]
      let rd = wreg_num(inst.defs[0])
      let ra = reg_num(inst.uses[0]) // accumulator
      let rn = reg_num(inst.uses[1]) // multiplicand
      let rm = reg_num(inst.uses[2]) // multiplier
      emit_msub(mc, rd, rn, rm, ra)
    }
    Mneg => {
      // Xd = -(Xn * Xm), uses: [src1, src2]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_mneg(mc, rd, rn, rm)
    }
    CallIndirect(num_args, has_result) => {
      // Call through a function pointer in a register
      // Our JIT ABI: X0 = func_table_ptr, X1 = memory_base, X2 = memory_size, args in X3-X7, return in X0
      // Uses: [func_ptr, arg0, arg1, ...]
      let func_ptr = reg_num(inst.uses[0])
      // First, save function pointer to a safe temp register (X9)
      // This is necessary because the arg moving below may overwrite the func_ptr register
      emit_mov_reg(mc, 9, func_ptr) // MOV X9, func_ptr
      // Move arguments to ABI registers (starting at X3, since X0/X1/X2 are reserved)
      // We need to handle parallel moves carefully to avoid overwriting source values.
      // Strategy: first copy all args to temp registers (X10-X17), then to final destinations
      // This avoids the problem of e.g. MOV X3, X4; MOV X4, X5 where X4 gets clobbered.
      if num_args > 0 {
        // Step 1: Copy all args to temp registers X10, X11, ...
        for i in 0..<num_args {
          let src = reg_num(inst.uses[i + 1])
          let temp = 10 + i // X10, X11, X12, ...
          emit_mov_reg(mc, temp, src)
        }
        // Step 2: Copy from temp registers to final ABI registers X3, X4, ...
        for i in 0..<num_args {
          let temp = 10 + i
          let dst = i + 3 // X3, X4, X5, ... (shifted by 1 for memory_size)
          emit_mov_reg(mc, dst, temp)
        }
      }
      // Set up context: X0 = func_table (X20), X1 = memory_base (X21), X2 = memory_size (X22)
      emit_mov_reg(mc, 0, 20) // MOV X0, X20
      emit_mov_reg(mc, 1, 21) // MOV X1, X21
      emit_mov_reg(mc, 2, 22) // MOV X2, X22
      // Call the function (from saved X9)
      emit_blr(mc, 9)
      // Move result to destination if needed
      if has_result && inst.defs.length() > 0 {
        let rd = wreg_num(inst.defs[0])
        if rd != 0 {
          emit_mov_reg(mc, rd, 0) // Move X0 to result
        }
      }
    }
    StackLoad(offset) => {
      // Load from [SP + offset] into the def register
      // Uses SP (X31) as base, loads 64-bit value
      let rd = wreg_num(inst.defs[0])
      emit_ldr_imm(mc, rd, 31, offset) // LDR Xd, [SP, #offset]
    }
    StackStore(offset) => {
      // Store the use register to [SP + offset]
      // Uses SP (X31) as base, stores 64-bit value
      let rt = reg_num(inst.uses[0])
      emit_str_imm(mc, rt, 31, offset) // STR Xt, [SP, #offset]
    }
  }
}

///|
fn emit_load(
  mc : MachineCode,
  ty : MemType,
  rt : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  match ty {
    I8 => emit_ldrb_imm(mc, rt, rn, offset)
    I16 => emit_ldrh_imm(mc, rt, rn, offset)
    I32 => emit_ldr_w_imm(mc, rt, rn, offset)
    I64 => emit_ldr_imm(mc, rt, rn, offset)
    F32 => emit_ldr_s_imm(mc, rt, rn, offset)
    F64 => emit_ldr_d_imm(mc, rt, rn, offset)
  }
}

///|
fn emit_store(
  mc : MachineCode,
  ty : MemType,
  rt : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  match ty {
    I8 => emit_strb_imm(mc, rt, rn, offset)
    I16 => emit_strh_imm(mc, rt, rn, offset)
    I32 => emit_str_w_imm(mc, rt, rn, offset)
    I64 => emit_str_imm(mc, rt, rn, offset)
    F32 => emit_str_s_imm(mc, rt, rn, offset)
    F64 => emit_str_d_imm(mc, rt, rn, offset)
  }
}

///|
fn cmp_kind_to_cond(kind : CmpKind) -> Int {
  match kind {
    Eq => EQ.to_int()
    Ne => NE.to_int()
    Slt => LT.to_int()
    Sle => LE.to_int()
    Sgt => GT.to_int()
    Sge => GE.to_int()
    Ult => LO.to_int()
    Ule => LS.to_int()
    Ugt => HI.to_int()
    Uge => HS.to_int()
  }
}

///|
fn fcmp_kind_to_cond(kind : FCmpKind) -> Int {
  match kind {
    FCmpKind::Eq => EQ.to_int()
    FCmpKind::Ne => NE.to_int()
    FCmpKind::Lt => LT.to_int()
    FCmpKind::Le => LE.to_int()
    FCmpKind::Gt => GT.to_int()
    FCmpKind::Ge => GE.to_int()
  }
}

///|
/// Emit terminator with epilogue for Return
/// Handles multi-value returns:
/// - First 2 integer returns → X0, X1
/// - First 2 float returns → D0, D1
/// - Extra returns → written to buffer pointed by X23
fn emit_terminator_with_epilogue(
  mc : MachineCode,
  term : VCodeTerminator,
  clobbered : Array[Int],
  frame_size : Int,
  result_types : Array[@ir.Type],
  needs_extra_ptr : Bool,
) -> Unit {
  match term {
    Jump(target) => emit_b(mc, target)
    Branch(cond, then_b, else_b) => {
      let rt = reg_num(cond)
      emit_cbnz(mc, rt, then_b)
      emit_b(mc, else_b)
    }
    Return(values) => {
      // For multi-value returns, we need to carefully place each value
      // Track how many int/float values we've placed in registers
      let mut int_reg_idx = 0 // Next X register to use (0 or 1)
      let mut float_reg_idx = 0 // Next D register to use (0 or 1)
      let mut extra_offset = 0 // Offset in extra results buffer
      for i, value in values {
        let src = reg_num(value)
        let ty = if i < result_types.length() {
          result_types[i]
        } else {
          @ir.Type::I64 // Fallback
        }
        match ty {
          F32 | F64 =>
            if float_reg_idx < 2 {
              // Place in D0 or D1
              if src != float_reg_idx {
                emit_fmov_d(mc, float_reg_idx, src)
              }
              float_reg_idx = float_reg_idx + 1
            } else {
              // Spill to extra results buffer
              // STR D(src), [X23, #extra_offset]
              emit_str_d_offset(mc, src, 23, extra_offset)
              extra_offset = extra_offset + 8
            }
          _ =>
            // I32, I64, or other integer types
            if int_reg_idx < 2 {
              // Place in X0 or X1
              if src != int_reg_idx {
                emit_mov_reg(mc, int_reg_idx, src)
              }
              int_reg_idx = int_reg_idx + 1
            } else {
              // Spill to extra results buffer
              // STR X(src), [X23, #extra_offset]
              emit_str_offset(mc, src, 23, extra_offset)
              extra_offset = extra_offset + 8
            }
        }
      }
      // Emit epilogue to restore callee-saved registers before return
      emit_epilogue(mc, clobbered, frame_size, needs_extra_ptr)
      emit_ret(mc, 30)
    }
    Trap(_) => mc.emit_inst(0, 0, 32, 212) // BRK #0 = 0xD4200000
  }
}

///|
/// Print machine code as hex dump
pub fn MachineCode::hex_dump(self : MachineCode) -> String {
  let mut result = ""
  for i, b in self.bytes {
    if i > 0 && i % 4 == 0 {
      result = result + " "
    }
    if i > 0 && i % 16 == 0 {
      result = result + "\n"
    }
    let hi = b / 16
    let lo = b % 16
    let hi_char = if hi < 10 {
      (hi + 48).unsafe_to_char().to_string()
    } else {
      (hi - 10 + 97).unsafe_to_char().to_string()
    }
    let lo_char = if lo < 10 {
      (lo + 48).unsafe_to_char().to_string()
    } else {
      (lo - 10 + 97).unsafe_to_char().to_string()
    }
    result = result + hi_char + lo_char
  }
  result
}
