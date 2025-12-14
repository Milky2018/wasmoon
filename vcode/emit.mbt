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
  // byte 0: Rd[4:0] | Rn[2:0] << 5
  // byte 1: Rn[4:3] | imm6[5:0] << 2
  // byte 2: Rm[4:0] | shift[1:0] << 6
  // byte 3: 0x8B
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((imm6 & 63) << 2)
  let b2 = (rm & 31) | ((shift_bits & 3) << 6)
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
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((imm6 & 63) << 2)
  let b2 = (rm & 31) | ((shift_bits & 3) << 6)
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
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((imm6 & 63) << 2)
  let b2 = (rm & 31) | ((shift_bits & 3) << 6)
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
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((imm6 & 63) << 2)
  let b2 = (rm & 31) | ((shift_bits & 3) << 6)
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
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((imm6 & 63) << 2)
  let b2 = (rm & 31) | ((shift_bits & 3) << 6)
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
  // byte 0: Rd[4:0] | Rn[2:0] << 5
  // byte 1: Rn[4:3] | Ra[4:0] << 2 | o0 << 7
  // byte 2: Rm[4:0]
  // byte 3: 0x9B
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((ra & 31) << 2)
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
  // byte 0: Rd[4:0] | Rn[2:0] << 5
  // byte 1: Rn[4:3] | Ra[4:0] << 2 | o0 << 7
  // byte 2: Rm[4:0]
  // byte 3: 0x9B
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((ra & 31) << 2) | 128 // o0=1 (bit 7)
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
/// Encoding: sf=1 | 00 | 11011 | 000 | Rm[4:0] | 0 | Ra=11111 | Rn[4:0] | Rd[4:0]
///           31   30-29  28-24  23-21  20-16   15   14-10     9-5      4-0
pub fn emit_mul(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("mul x\{rd}, x\{rn}, x\{rm}")
  // b0: Rd[4:0] | Rn[2:0]<<5
  let b0 = (rd & 0x1f) | ((rn & 0x7) << 5)
  // b1: Rn[4:3] | Ra[4:0]<<2 | o0<<7 = Rn[4:3] | 11111<<2 | 0 = Rn[4:3] | 0x7C
  let b1 = ((rn >> 3) & 0x3) | 0x7C
  // b2: 000 | Rm[4:0] (bits 7-5 are 000 for MUL opcode, bits 4-0 are Rm)
  let b2 = rm & 0x1f
  // b3: 1_00_11011 = 0x9B
  let b3 = 0x9B
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode SDIV: SDIV Xd, Xn, Xm
/// Opcode: 0x9AC00C00
pub fn emit_sdiv(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("sdiv x\{rd}, x\{rn}, x\{rm}")
  // Encoding: sf=1 | 0 | 0 | 11010110 | Rm | 000011 | Rn | Rd
  // byte 0: Rd[4:0] | Rn[2:0] << 5
  // byte 1: Rn[4:3] | opcode[5:0] << 2 (opcode=000011 for SDIV)
  // byte 2: 0xC0 | Rm[4:0]
  // byte 3: 0x9A
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (3 << 2) // opcode 000011 = 3
  let b2 = 0xC0 | (rm & 31)
  let b3 = 0x9A
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode UDIV: UDIV Xd, Xn, Xm
/// Opcode: 0x9AC00800
pub fn emit_udiv(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("udiv x\{rd}, x\{rn}, x\{rm}")
  // Encoding: sf=1 | 0 | 0 | 11010110 | Rm | 000010 | Rn | Rd
  // byte 0: Rd[4:0] | Rn[2:0] << 5
  // byte 1: Rn[4:3] | opcode[5:0] << 2 (opcode=000010 for UDIV)
  // byte 2: 0xC0 | Rm[4:0]
  // byte 3: 0x9A
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (2 << 2) // opcode 000010 = 2
  let b2 = 0xC0 | (rm & 31)
  let b3 = 0x9A
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
  // Encoding: sf=1 | 0 | 0 | 11010110 | Rm | 001000 | Rn | Rd
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (8 << 2) // opcode 001000 = 8
  let b2 = 0xC0 | (rm & 31)
  let b3 = 0x9A
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode ASR (register): ASRV Xd, Xn, Xm
/// Opcode: 0x9AC02800
pub fn emit_asr_reg(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("asr x\{rd}, x\{rn}, x\{rm}")
  // Encoding: sf=1 | 0 | 0 | 11010110 | Rm | 001010 | Rn | Rd
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (10 << 2) // opcode 001010 = 10
  let b2 = 0xC0 | (rm & 31)
  let b3 = 0x9A
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode LSR (register): LSRV Xd, Xn, Xm
/// Opcode: 0x9AC02400
pub fn emit_lsr_reg(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("lsr x\{rd}, x\{rn}, x\{rm}")
  // Encoding: sf=1 | 0 | 0 | 11010110 | Rm | 001001 | Rn | Rd
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (9 << 2) // opcode 001001 = 9
  let b2 = 0xC0 | (rm & 31)
  let b3 = 0x9A
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode ROR (register): ROR Xd, Xn, Xm (rotate right)
/// This is an alias for RORV: Xd = Xn >>> Xm (rotate right by amount in Xm)
/// Opcode: 0x9AC02C00
pub fn emit_ror_reg(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("ror x\{rd}, x\{rn}, x\{rm}")
  // Encoding: sf=1 | 0 | 0 | 11010110 | Rm | 001011 | Rn | Rd
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (11 << 2) // opcode 001011 = 11
  let b2 = 0xC0 | (rm & 31)
  let b3 = 0x9A
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode MVN (register): MVN Xd, Xm (bitwise NOT)
/// This is an alias for ORN Xd, XZR, Xm
/// Opcode: 0xAA2003E0
pub fn emit_mvn(mc : MachineCode, rd : Int, rm : Int) -> Unit {
  mc.annotate("mvn x\{rd}, x\{rm}")
  // ORN Xd, XZR, Xm - bitwise OR NOT with zero register = NOT
  let b0 = (rd & 31) | ((31 & 7) << 5) // rd, XZR low bits
  let b1 = (31 >> 3) & 3 // XZR high bits
  let b2 = (rm & 31) | 32 // rm with N bit set (bit 21 = 1 for ORN)
  let b3 = 170 // 0xAA
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode CLZ: CLZ Xd, Xn (count leading zeros)
/// Opcode: 0xDAC01000
pub fn emit_clz(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("clz x\{rd}, x\{rn}")
  // CLZ encoding: sf=1 | 1 | 0 | 11010110 | 00000 | 00010 | 0 | Rn | Rd
  // [31]: sf = 1 (64-bit)
  // [30]: 1
  // [29]: 0
  // [28:21]: 11010110
  // [20:16]: 00000
  // [15:10]: 000100
  // [9:5]: Rn
  // [4:0]: Rd
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 16 // 0x10 = 000100 << 2
  let b2 = 192 // 0xC0
  let b3 = 218 // 0xDA
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode RBIT: RBIT Xd, Xn (reverse bits)
/// Opcode: 0xDAC00000
pub fn emit_rbit(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("rbit x\{rd}, x\{rn}")
  // RBIT encoding: sf=1 | 1 | 0 | 11010110 | 00000 | 00000 | 0 | Rn | Rd
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3
  let b2 = 192 // 0xC0
  let b3 = 218 // 0xDA
  mc.emit_inst(b0, b1, b2, b3)
}

// ============ Float-Int Conversions ============

///|
/// Encode FCVTZS: convert float to signed int (round toward zero)
/// sf: 0 = 32-bit int (W), 1 = 64-bit int (X)
/// ftype: 0 = single (S), 1 = double (D)
/// FCVTZS Wd, Sn: 0x1E380000 | (Rn << 5) | Rd
/// FCVTZS Wd, Dn: 0x1E780000 | (Rn << 5) | Rd
/// FCVTZS Xd, Sn: 0x9E380000 | (Rn << 5) | Rd
/// FCVTZS Xd, Dn: 0x9E780000 | (Rn << 5) | Rd
pub fn emit_fcvtzs(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  int64~ : Bool,
  double~ : Bool,
) -> Unit {
  let int_name = if int64 { "x" } else { "w" }
  let float_name = if double { "d" } else { "s" }
  mc.annotate("fcvtzs \{int_name}\{rd}, \{float_name}\{rn}")
  // Base: 0x1E380000 for Wd, Sn
  // sf (bit 31) = int64 ? 1 : 0
  // ftype (bit 22) = double ? 1 : 0
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3
  let b2 = if double { 0x78 } else { 0x38 }
  let b3 = if int64 { 0x9E } else { 0x1E }
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FCVTZU: convert float to unsigned int (round toward zero)
/// FCVTZU Wd, Sn: 0x1E390000 | (Rn << 5) | Rd
/// FCVTZU Wd, Dn: 0x1E790000 | (Rn << 5) | Rd
/// FCVTZU Xd, Sn: 0x9E390000 | (Rn << 5) | Rd
/// FCVTZU Xd, Dn: 0x9E790000 | (Rn << 5) | Rd
pub fn emit_fcvtzu(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  int64~ : Bool,
  double~ : Bool,
) -> Unit {
  let int_name = if int64 { "x" } else { "w" }
  let float_name = if double { "d" } else { "s" }
  mc.annotate("fcvtzu \{int_name}\{rd}, \{float_name}\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3
  // Unsigned uses 0x39/0x79 instead of 0x38/0x78 (bit 16 set)
  let b2 = if double { 0x79 } else { 0x39 }
  let b3 = if int64 { 0x9E } else { 0x1E }
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode SCVTF: convert signed int to float
/// SCVTF Sd, Wn: 0x1E220000 | (Rn << 5) | Rd
/// SCVTF Dd, Wn: 0x1E620000 | (Rn << 5) | Rd
/// SCVTF Sd, Xn: 0x9E220000 | (Rn << 5) | Rd
/// SCVTF Dd, Xn: 0x9E620000 | (Rn << 5) | Rd
pub fn emit_scvtf(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  int64~ : Bool,
  double~ : Bool,
) -> Unit {
  let int_name = if int64 { "x" } else { "w" }
  let float_name = if double { "d" } else { "s" }
  mc.annotate("scvtf \{float_name}\{rd}, \{int_name}\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3
  let b2 = if double { 0x62 } else { 0x22 }
  let b3 = if int64 { 0x9E } else { 0x1E }
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode UCVTF: convert unsigned int to float
/// UCVTF Sd, Wn: 0x1E230000 | (Rn << 5) | Rd
/// UCVTF Dd, Wn: 0x1E630000 | (Rn << 5) | Rd
/// UCVTF Sd, Xn: 0x9E230000 | (Rn << 5) | Rd
/// UCVTF Dd, Xn: 0x9E630000 | (Rn << 5) | Rd
pub fn emit_ucvtf(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  int64~ : Bool,
  double~ : Bool,
) -> Unit {
  let int_name = if int64 { "x" } else { "w" }
  let float_name = if double { "d" } else { "s" }
  mc.annotate("ucvtf \{float_name}\{rd}, \{int_name}\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = (rn >> 3) & 3
  // Unsigned uses 0x23/0x63 instead of 0x22/0x62 (bit 16 set)
  let b2 = if double { 0x63 } else { 0x23 }
  let b3 = if int64 { 0x9E } else { 0x1E }
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
/// Encode LDUR (64-bit, unscaled signed offset): LDUR Xt, [Xn, #simm9]
/// Used for negative offsets (-256 to 255)
/// Opcode base: 0xF8400000
pub fn emit_ldr_imm_signed(
  mc : MachineCode,
  rt : Int,
  rn : Int,
  simm9 : Int,
) -> Unit {
  mc.annotate("ldur x\{rt}, [x\{rn}, #\{simm9}]")
  // AArch64 LDUR (unscaled offset) encoding:
  // [31:30] = size = 11 (64-bit)
  // [29:27] = 111 (fixed)
  // [26] = V = 0 (general purpose register)
  // [25:24] = 00 (unscaled)
  // [23:22] = opc = 01 (LDUR)
  // [21] = 0
  // [20:12] = imm9 (signed 9-bit, -256 to 255)
  // [11:10] = 00
  // [9:5] = Rn (base register)
  // [4:0] = Rt (destination register)
  let imm9 = simm9 & 0x1FF // 9-bit mask, preserves sign bits
  let inst = (0b11 << 30) |
    (0b111 << 27) |
    (0 << 26) |
    (0b00 << 24) |
    (0b01 << 22) |
    (0 << 21) |
    (imm9 << 12) |
    (0b00 << 10) |
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

// ============ Sign/Zero Extension Instructions ============

///|
/// Encode SXTB (sign-extend byte to 64-bit): SXTB Xd, Wn
/// This is an alias for SBFM Xd, Xn, #0, #7
/// Opcode: 0x93401C00
pub fn emit_sxtb_x(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("sxtb x\{rd}, w\{rn}")
  // SBFM Xd, Xn, #0, #7: sf=1, opc=00, N=1, immr=0, imms=7
  // Encoding: 1001_0011_0100_0000_0001_1100_nnnn_nddd_d
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (7 << 2) // imms=7
  let b2 = 0x40 // immr=0, N=1
  let b3 = 0x93 // sf=1, opc=00
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode SXTH (sign-extend halfword to 64-bit): SXTH Xd, Wn
/// This is an alias for SBFM Xd, Xn, #0, #15
/// Opcode: 0x93403C00
pub fn emit_sxth_x(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("sxth x\{rd}, w\{rn}")
  // SBFM Xd, Xn, #0, #15: sf=1, opc=00, N=1, immr=0, imms=15
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (15 << 2) // imms=15
  let b2 = 0x40 // immr=0, N=1
  let b3 = 0x93 // sf=1, opc=00
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode SXTW (sign-extend word to 64-bit): SXTW Xd, Wn
/// This is an alias for SBFM Xd, Xn, #0, #31
/// Opcode: 0x93407C00
pub fn emit_sxtw(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("sxtw x\{rd}, w\{rn}")
  // SBFM Xd, Xn, #0, #31: sf=1, opc=00, N=1, immr=0, imms=31
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (31 << 2) // imms=31
  let b2 = 0x40 // immr=0, N=1
  let b3 = 0x93 // sf=1, opc=00
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode SXTB (sign-extend byte to 32-bit): SXTB Wd, Wn
/// This is an alias for SBFM Wd, Wn, #0, #7
pub fn emit_sxtb_w(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("sxtb w\{rd}, w\{rn}")
  // SBFM Wd, Wn, #0, #7: sf=0, opc=00, N=0, immr=0, imms=7
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (7 << 2) // imms=7
  let b2 = 0x00 // immr=0, N=0
  let b3 = 0x13 // sf=0, opc=00
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode SXTH (sign-extend halfword to 32-bit): SXTH Wd, Wn
/// This is an alias for SBFM Wd, Wn, #0, #15
pub fn emit_sxth_w(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("sxth w\{rd}, w\{rn}")
  // SBFM Wd, Wn, #0, #15: sf=0, opc=00, N=0, immr=0, imms=15
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (15 << 2) // imms=15
  let b2 = 0x00 // immr=0, N=0
  let b3 = 0x13 // sf=0, opc=00
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode UXTB (zero-extend byte to 64-bit): UXTB Xd, Wn
/// This is an alias for UBFM Xd, Xn, #0, #7, but since W-register writes
/// automatically zero-extend to X, we can use AND Wd, Wn, #0xFF
pub fn emit_uxtb_x(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("uxtb x\{rd}, w\{rn}")
  // Use AND Wd, Wn, #0xFF which zero-extends to Xd
  // For simplicity, use UBFM Wd, Wn, #0, #7 then rely on zero-extension
  // UBFM Wd, Wn, #0, #7: sf=0, opc=10, N=0, immr=0, imms=7
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (7 << 2) // imms=7
  let b2 = 0x00 // immr=0, N=0
  let b3 = 0x53 // sf=0, opc=10 (UBFM)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode UXTH (zero-extend halfword to 64-bit): UXTH Xd, Wn
/// This is an alias for UBFM Wd, Wn, #0, #15, W-write zero-extends to X
pub fn emit_uxth_x(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("uxth x\{rd}, w\{rn}")
  // UBFM Wd, Wn, #0, #15: sf=0, opc=10, N=0, immr=0, imms=15
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (15 << 2) // imms=15
  let b2 = 0x00 // immr=0, N=0
  let b3 = 0x53 // sf=0, opc=10 (UBFM)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode UXTB (zero-extend byte to 32-bit): UXTB Wd, Wn
pub fn emit_uxtb_w(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("uxtb w\{rd}, w\{rn}")
  // UBFM Wd, Wn, #0, #7: sf=0, opc=10, N=0, immr=0, imms=7
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (7 << 2) // imms=7
  let b2 = 0x00 // immr=0, N=0
  let b3 = 0x53 // sf=0, opc=10 (UBFM)
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode UXTH (zero-extend halfword to 32-bit): UXTH Wd, Wn
pub fn emit_uxth_w(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("uxth w\{rd}, w\{rn}")
  // UBFM Wd, Wn, #0, #15: sf=0, opc=10, N=0, immr=0, imms=15
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | (15 << 2) // imms=15
  let b2 = 0x00 // immr=0, N=0
  let b3 = 0x53 // sf=0, opc=10 (UBFM)
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
/// Encode BR (branch register): BR Xn
/// Opcode: 0xD61F0000 (with Rn in bits [9:5])
pub fn emit_br(mc : MachineCode, rn : Int) -> Unit {
  mc.annotate("br x\{rn}")
  // Rn goes in bits [9:5] of the instruction
  // In little-endian bytes:
  // byte0 bits [7:5] = Rn[2:0]
  // byte1 bits [2:0] = Rn[4:3]
  let b0 = (rn & 7) << 5 // Rn[2:0] in bits [7:5]
  let b1 = (rn >> 3) & 3 // Rn[4:3] in bits [1:0]
  mc.emit_inst(b0, b1, 31, 214) // 0x1F, 0xD6
}

///|
/// Encode ADR: ADR Xd, #offset (PC-relative address with known offset)
/// Opcode: 0x10000000
pub fn emit_adr(mc : MachineCode, rd : Int, offset : Int) -> Unit {
  mc.annotate("adr x\{rd}, .+\{offset}")
  // ADR encoding:
  // | 31 | 30-29 | 28-24 | 23-5   | 4-0 |
  // | op | immlo | 10000 | immhi  | Rd  |
  // op=0 for ADR, immlo in bits [30:29], immhi in bits [23:5]
  // The immediate is a signed 21-bit value split between immlo (2 bits) and immhi (19 bits)
  let immlo = offset & 3
  let immhi = (offset >> 2) & 0x7FFFF
  let b0 = (rd & 31) | ((immhi & 7) << 5)
  let b1 = (immhi >> 3) & 0xFF
  let b2 = (immhi >> 11) & 0xFF
  let b3 = 16 | (immlo << 5) // 0x10 for ADR, immlo in bits [30:29]
  mc.emit_inst(b0, b1, b2, b3)
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

///|
/// Encode DMB ISH (Data Memory Barrier, Inner Shareable)
/// Ensures all earlier memory accesses are visible before later accesses
/// Opcode: 0xD5033BBF
pub fn emit_dmb_ish(mc : MachineCode) -> Unit {
  mc.annotate("dmb ish")
  // DMB ISH encoding: 0xD5033BBF
  // In little-endian: BF 3B 03 D5
  mc.emit_inst(0xBF, 0x3B, 0x03, 0xD5)
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
  // CMP (immediate) = SUBS XZR, Rn, #imm12
  // Encoding: sf=1 | op=1 | S=1 | 100010 | sh=0 | imm12[11:0] | Rn[4:0] | Rd=11111
  // Byte 0: Rd[4:0] | Rn[2:0] << 5
  // Byte 1: Rn[4:3] | imm12[5:0] << 2
  // Byte 2: imm12[11:6] | sh << 6
  // Byte 3: 0xF1
  let b0 = 31 | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((imm & 63) << 2)
  let b2 = (imm >> 6) & 63
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

///|
/// Encode CSEL: CSEL Xd, Xn, Xm, cond
/// If condition is true, Xd = Xn, else Xd = Xm
/// Opcode: 0x9A800000
pub fn emit_csel(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  cond : Int,
) -> Unit {
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
  mc.annotate("csel x\{rd}, x\{rn}, x\{rm}, \{cond_name}")
  // CSEL encoding: sf=1 | op=0 | S=0 | 11010100 | Rm | cond | 0 | 0 | Rn | Rd
  // [31]: sf = 1 (64-bit)
  // [30]: op = 0
  // [29]: S = 0
  // [28:21]: 11010100
  // [20:16]: Rm
  // [15:12]: cond
  // [11]: o2 = 0
  // [10]: 0
  // [9:5]: Rn
  // [4:0]: Rd
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | ((cond & 15) << 4)
  let b2 = (rm & 31) | 128 // 0x80 = bit 7 set for opcode
  let b3 = 154 // 0x9A
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FCSEL (double): FCSEL Dd, Dn, Dm, cond
/// If condition is true, Dd = Dn, else Dd = Dm
/// Opcode: 0x1E600C00
pub fn emit_fcsel_d(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  cond : Int,
) -> Unit {
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
  mc.annotate("fcsel d\{rd}, d\{rn}, d\{rm}, \{cond_name}")
  // FCSEL encoding: M=0 | 0 | S=0 | 11110 | ftype=01 | 1 | Rm | cond | 11 | Rn | Rd
  // [31]: M = 0
  // [30]: 0
  // [29]: S = 0
  // [28:24]: 11110
  // [23:22]: ftype = 01 (double)
  // [21]: 1
  // [20:16]: Rm
  // [15:12]: cond
  // [11:10]: 11
  // [9:5]: Rn
  // [4:0]: Rd
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x0C | ((cond & 15) << 4) // 0x0C = bits 11:10 = 11
  let b2 = 0x60 | (rm & 31) // 0x60 = ftype=01, bit 21=1
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FCSEL (single): FCSEL Sd, Sn, Sm, cond
/// If condition is true, Sd = Sn, else Sd = Sm
/// Opcode: 0x1E200C00
pub fn emit_fcsel_s(
  mc : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  cond : Int,
) -> Unit {
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
  mc.annotate("fcsel s\{rd}, s\{rn}, s\{rm}, \{cond_name}")
  // FCSEL encoding: M=0 | 0 | S=0 | 11110 | ftype=00 | 1 | Rm | cond | 11 | Rn | Rd
  // ftype = 00 (single)
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x0C | ((cond & 15) << 4)
  let b2 = 0x20 | (rm & 31) // 0x20 = ftype=00, bit 21=1
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

// ============ Floating-Point Instructions ============

///|
/// Encode FADD (double): FADD Dd, Dn, Dm
/// Opcode: 0x1E602800
/// Format: 0x1E602800 | (rm << 16) | (rn << 5) | rd
pub fn emit_fadd_d(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fadd d\{rd}, d\{rn}, d\{rm}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x28
  let b2 = 0x60 | (rm & 31)
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FADD (single): FADD Sd, Sn, Sm
/// Opcode: 0x1E202800
/// Format: 0x1E202800 | (rm << 16) | (rn << 5) | rd
pub fn emit_fadd_s(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fadd s\{rd}, s\{rn}, s\{rm}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x28
  let b2 = 0x20 | (rm & 31)
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FSUB (double): FSUB Dd, Dn, Dm
/// Opcode: 0x1E603800
/// Format: 0x1E603800 | (rm << 16) | (rn << 5) | rd
pub fn emit_fsub_d(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fsub d\{rd}, d\{rn}, d\{rm}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x38
  let b2 = 0x60 | (rm & 31)
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FSUB (single): FSUB Sd, Sn, Sm
/// Opcode: 0x1E203800
/// Format: 0x1E203800 | (rm << 16) | (rn << 5) | rd
pub fn emit_fsub_s(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fsub s\{rd}, s\{rn}, s\{rm}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x38
  let b2 = 0x20 | (rm & 31)
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FMUL (double): FMUL Dd, Dn, Dm
/// Opcode: 0x1E600800
/// Format: 0x1E600800 | (rm << 16) | (rn << 5) | rd
pub fn emit_fmul_d(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fmul d\{rd}, d\{rn}, d\{rm}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x08
  let b2 = 0x60 | (rm & 31)
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FMUL (single): FMUL Sd, Sn, Sm
/// Opcode: 0x1E200800
/// Format: 0x1E200800 | (rm << 16) | (rn << 5) | rd
pub fn emit_fmul_s(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fmul s\{rd}, s\{rn}, s\{rm}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x08
  let b2 = 0x20 | (rm & 31)
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FDIV (double): FDIV Dd, Dn, Dm
/// Opcode: 0x1E601800
/// Format: 0x1E601800 | (rm << 16) | (rn << 5) | rd
pub fn emit_fdiv_d(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fdiv d\{rd}, d\{rn}, d\{rm}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x18
  let b2 = 0x60 | (rm & 31)
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FDIV (single): FDIV Sd, Sn, Sm
/// Opcode: 0x1E201800
/// Format: 0x1E201800 | (rm << 16) | (rn << 5) | rd
pub fn emit_fdiv_s(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fdiv s\{rd}, s\{rn}, s\{rm}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x18
  let b2 = 0x20 | (rm & 31)
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FMAX (double): FMAX Dd, Dn, Dm
/// Opcode: 0x1E604800
/// Format: 0x1E604800 | (rm << 16) | (rn << 5) | rd
pub fn emit_fmax_d(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fmax d\{rd}, d\{rn}, d\{rm}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x48
  let b2 = 0x60 | (rm & 31)
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FMAX (single): FMAX Sd, Sn, Sm
/// Opcode: 0x1E204800
/// Format: 0x1E204800 | (rm << 16) | (rn << 5) | rd
pub fn emit_fmax_s(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fmax s\{rd}, s\{rn}, s\{rm}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x48
  let b2 = 0x20 | (rm & 31)
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FMIN (double): FMIN Dd, Dn, Dm
/// Opcode: 0x1E605800
/// Format: 0x1E605800 | (rm << 16) | (rn << 5) | rd
pub fn emit_fmin_d(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fmin d\{rd}, d\{rn}, d\{rm}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x58
  let b2 = 0x60 | (rm & 31)
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FMIN (single): FMIN Sd, Sn, Sm
/// Opcode: 0x1E205800
/// Format: 0x1E205800 | (rm << 16) | (rn << 5) | rd
pub fn emit_fmin_s(mc : MachineCode, rd : Int, rn : Int, rm : Int) -> Unit {
  mc.annotate("fmin s\{rd}, s\{rn}, s\{rm}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 0x58
  let b2 = 0x20 | (rm & 31)
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FSQRT (double): FSQRT Dd, Dn
/// Opcode: 0x1E61C000
pub fn emit_fsqrt_d(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("fsqrt d\{rd}, d\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 192 // 0xC0
  let b2 = 97 // 0x61
  let b3 = 30 // 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FSQRT (single): FSQRT Sd, Sn
/// Opcode: 0x1E21C000
pub fn emit_fsqrt_s(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("fsqrt s\{rd}, s\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 192 // 0xC0
  let b2 = 0x21
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FABS (double): FABS Dd, Dn
/// Opcode: 0x1E60C000
pub fn emit_fabs_d(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("fabs d\{rd}, d\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 192 // 0xC0
  let b2 = 96 // 0x60
  let b3 = 30 // 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FABS (single): FABS Sd, Sn
/// Opcode: 0x1E20C000
pub fn emit_fabs_s(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("fabs s\{rd}, s\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 192 // 0xC0
  let b2 = 0x20
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FNEG (double): FNEG Dd, Dn
/// Opcode: 0x1E614000
pub fn emit_fneg_d(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("fneg d\{rd}, d\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 64 // 0x40
  let b2 = 97 // 0x61
  let b3 = 30 // 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FNEG (single): FNEG Sd, Sn
/// Opcode: 0x1E214000
pub fn emit_fneg_s(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("fneg s\{rd}, s\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 64 // 0x40
  let b2 = 0x21
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FRINTP (double, ceiling): FRINTP Dd, Dn
/// Opcode: 0x1E64C000
pub fn emit_frintp_d(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("frintp d\{rd}, d\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 192 // 0xC0
  let b2 = 100 // 0x64
  let b3 = 30 // 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FRINTP (single, ceiling): FRINTP Sd, Sn
/// Opcode: 0x1E24C000
pub fn emit_frintp_s(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("frintp s\{rd}, s\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 192 // 0xC0
  let b2 = 0x24
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FRINTM (double, floor): FRINTM Dd, Dn
/// Opcode: 0x1E654000
pub fn emit_frintm_d(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("frintm d\{rd}, d\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 64 // 0x40
  let b2 = 101 // 0x65
  let b3 = 30 // 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FRINTM (single, floor): FRINTM Sd, Sn
/// Opcode: 0x1E254000
pub fn emit_frintm_s(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("frintm s\{rd}, s\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 64 // 0x40
  let b2 = 0x25
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FRINTZ (double, truncate towards zero): FRINTZ Dd, Dn
/// Opcode: 0x1E65C000
pub fn emit_frintz_d(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("frintz d\{rd}, d\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 192 // 0xC0
  let b2 = 101 // 0x65
  let b3 = 30 // 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FRINTZ (single, truncate towards zero): FRINTZ Sd, Sn
/// Opcode: 0x1E25C000
pub fn emit_frintz_s(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("frintz s\{rd}, s\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 192 // 0xC0
  let b2 = 0x25
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FRINTN (double, nearest with ties to even): FRINTN Dd, Dn
/// Opcode: 0x1E644000
pub fn emit_frintn_d(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("frintn d\{rd}, d\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 64 // 0x40
  let b2 = 100 // 0x64
  let b3 = 30 // 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FRINTN (single, nearest with ties to even): FRINTN Sd, Sn
/// Opcode: 0x1E244000
pub fn emit_frintn_s(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("frintn s\{rd}, s\{rn}")
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 64 // 0x40
  let b2 = 0x24
  let b3 = 0x1E
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
/// Encode FMOV (single, register): FMOV Sd, Sm
/// Opcode: 0x1E204000
pub fn emit_fmov_s(mc : MachineCode, rd : Int, rm : Int) -> Unit {
  mc.annotate("fmov s\{rd}, s\{rm}")
  let b0 = (rd & 31) | ((rm & 7) << 5)
  let b1 = ((rm >> 3) & 3) | 64 // 0x40
  let b2 = 0x20
  let b3 = 0x1E
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
/// Encode FCVT (double to single): FCVT Sd, Dn
/// Opcode: 0x1E624000
/// Converts double-precision float to single-precision
pub fn emit_fcvt_s_d(mc : MachineCode, rd : Int, rn : Int) -> Unit {
  mc.annotate("fcvt s\{rd}, d\{rn}")
  // Rd in bits [4:0], Rn in bits [9:5]
  // Encoding: 0x1E624000 = 0001 1110 0110 0010 0100 0000 0000 0000
  let b0 = (rd & 31) | ((rn & 7) << 5)
  let b1 = ((rn >> 3) & 3) | 64 // 0x40
  let b2 = 98 // 0x62
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
/// Format: 0x1E602000 | (rm << 16) | (rn << 5)
pub fn emit_fcmp_d(mc : MachineCode, rn : Int, rm : Int) -> Unit {
  mc.annotate("fcmp d\{rn}, d\{rm}")
  let b0 = (rn & 7) << 5
  let b1 = ((rn >> 3) & 3) | 0x20
  let b2 = 0x60 | (rm & 31)
  let b3 = 0x1E
  mc.emit_inst(b0, b1, b2, b3)
}

///|
/// Encode FCMP (single): FCMP Sn, Sm
/// Opcode: 0x1E202000
/// Format: 0x1E202000 | (rm << 16) | (rn << 5)
pub fn emit_fcmp_s(mc : MachineCode, rn : Int, rm : Int) -> Unit {
  mc.annotate("fcmp s\{rn}, s\{rm}")
  let b0 = (rn & 7) << 5
  let b1 = ((rn >> 3) & 3) | 0x20
  let b2 = 0x20 | (rm & 31) // 0x20 for single, 0x60 for double
  let b3 = 0x1E
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
/// Check if a register index is a callee-saved GPR that we use for allocation
fn is_callee_saved_alloc(reg : Int) -> Bool {
  // X19, X23-X28 are callee-saved registers we allocate
  // X20, X21, X22 are reserved for func_table, memory_base, memory_size
  reg == 19 || (reg >= 23 && reg <= 28)
}

///|
/// Check if a FPR index is callee-saved (D8-D15 in AAPCS64)
fn is_callee_saved_fpr(reg : Int) -> Bool {
  reg >= 8 && reg <= 15
}

///|
/// Collect all callee-saved GPRs that are defined in the function
/// Also includes LR (X30) if the function makes any calls
/// When needs_extra_results is true, X23 is excluded because it's reserved for extra_buffer
fn collect_used_callee_saved(
  func : VCodeFunction,
  needs_extra_results : Bool,
) -> Array[Int] {
  let used : @hashset.HashSet[Int] = @hashset.new()
  let mut has_calls = false

  // Check param_pregs: parameters that cross calls are moved to callee-saved registers
  // These are defined in the prologue via `mov xN, x(3+i)`
  for preg in func.param_pregs {
    match preg {
      Some(p) =>
        if is_callee_saved_alloc(p.index) {
          // X23 is reserved for extra_buffer when needs_extra_results
          if needs_extra_results && p.index == 23 {
            continue
          }
          used.add(p.index)
        }
      None => ()
    }
  }
  for block in func.blocks {
    for inst in block.insts {
      // Check if this instruction is a function call
      // MemoryGrow and MemorySize also use BLR internally to call C functions
      if inst.opcode is (CallIndirect(_, _) | MemoryGrow | MemorySize) {
        has_calls = true
      }
      for def in inst.defs {
        match def.reg {
          Physical(preg) =>
            if preg.class is Int && is_callee_saved_alloc(preg.index) {
              // X23 is reserved for extra_buffer when needs_extra_results
              if needs_extra_results && preg.index == 23 {
                continue
              }
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
/// Collect all callee-saved FPRs (D8-D15) that are defined in the function
fn collect_used_callee_saved_fprs(func : VCodeFunction) -> Array[Int] {
  let used : @hashset.HashSet[Int] = @hashset.new()
  for block in func.blocks {
    for inst in block.insts {
      for def in inst.defs {
        match def.reg {
          Physical(preg) =>
            if (preg.class is Float32 || preg.class is Float64) &&
              is_callee_saved_fpr(preg.index) {
              used.add(preg.index)
            }
          Virtual(_) => ()
        }
      }
    }
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
/// JIT ABI: X0 = func_table_ptr, X1 = memory_base, X2 = memory_size
/// User params start from X3 (up to X6)
/// When function has >2 int or >2 float returns: X7 = extra_results_buffer pointer
fn emit_prologue(
  mc : MachineCode,
  clobbered : Array[Int],
  clobbered_fprs : Array[Int],
  params : Array[VReg],
  param_pregs : Array[PReg?],
  needs_extra_results : Bool,
  calls_multi_value : Bool,
  num_spill_slots : Int,
) -> Int {
  // We always clobber X20, X21, X22, X24 for func_table, memory_base, memory_size, indirect_table
  // When needs_extra_results OR calls_multi_value, we also clobber X23
  // - needs_extra_results: X23 stores the incoming buffer pointer from X7
  // - calls_multi_value: X23 points to a local buffer on the stack
  // These are callee-saved registers, so we must save them first!
  // In v2 ABI, X19 is used to save the original context pointer for JIT-to-JIT calls
  let uses_x23 = needs_extra_results || calls_multi_value
  let all_to_save : Array[Int] = if ABI_VERSION == 2 {
    // v2: X19 holds context_ptr, X20 holds func_table after prologue
    if uses_x23 {
      [19, 20, 21, 22, 23, 24]
    } else {
      [19, 20, 21, 22, 24]
    }
    // v1: X20-X22, X24, optionally X23
  } else if uses_x23 {
    [20, 21, 22, 23, 24]
  } else {
    [20, 21, 22, 24]
  }
  for reg in clobbered {
    all_to_save.push(reg)
  }
  // Round up to even number for STP (store pairs)
  let num_regs = all_to_save.length()
  let num_pairs = (num_regs + 1) / 2
  let clobbered_gpr_size = num_pairs * 16 // 16 bytes per pair
  // Calculate FPR save size (D8-D15, 16 bytes per pair)
  let num_fprs = clobbered_fprs.length()
  let num_fpr_pairs = (num_fprs + 1) / 2
  let clobbered_fpr_size = num_fpr_pairs * 16
  // Calculate spill slots size (8 bytes each, aligned to 16)
  // Always allocate at least 16 bytes for scratch space (used by MemoryGrow)
  let spill_size = @cmp.maximum((num_spill_slots * 8 + 15) / 16 * 16, 16)
  // If we call multi-value functions, allocate 64 bytes for receiving extra results
  // This buffer will be pointed to by X23
  let call_results_buffer_size = if calls_multi_value && !needs_extra_results {
    64
  } else {
    0
  }
  let frame_size = clobbered_gpr_size +
    clobbered_fpr_size +
    spill_size +
    call_results_buffer_size
  // Allocate stack frame first using SUB
  emit_sub_imm(mc, 31, 31, frame_size)
  // Save GPRs using STP with signed offset
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
  // Save FPRs (D8-D15) after GPRs
  // Handle pairs first, then single register if odd count
  let mut fi = 0
  let mut fpr_pair_idx = 0
  while fi + 1 < num_fprs {
    // Save pairs
    let reg1 = clobbered_fprs[fi]
    let reg2 = clobbered_fprs[fi + 1]
    let offset = clobbered_gpr_size + fpr_pair_idx * 16
    emit_stp_d_offset(mc, reg1, reg2, 31, offset)
    fi = fi + 2
    fpr_pair_idx = fpr_pair_idx + 1
  }
  // Handle last register if odd count
  if fi < num_fprs {
    let reg = clobbered_fprs[fi]
    let offset = clobbered_gpr_size + fpr_pair_idx * 16
    emit_str_d_imm(mc, reg, 31, offset)
  }
  // Now move parameters to reserved registers (after saving their original values)
  // Different handling based on ABI version:
  // v1 (old): X0=func_table, X1=memory_base, X2=memory_size, params in X3-X10
  // v2 (new): X19=context_ptr (set by caller, callee-saved), params in X0-X7
  if ABI_VERSION == 2 {
    // v2 ABI: X19 = context pointer (set by caller, callee-saved)
    // X19 is callee-saved so it's automatically preserved across calls
    // Load fields from context structure pointed by X19
    // Context layout: [func_table, indirect_table, memory_base, memory_size]
    //                  +0          +8              +16           +24
    emit_ldr_imm(mc, 20, 19, CTX_FUNC_TABLE_OFFSET) // X20 = [X19 + 0]
    emit_ldr_imm(mc, 21, 19, CTX_MEMORY_BASE_OFFSET) // X21 = [X19 + 16]
    emit_ldr_imm(mc, 22, 19, CTX_MEMORY_SIZE_OFFSET) // X22 = [X19 + 24]
    emit_ldr_imm(mc, 24, 19, CTX_INDIRECT_TABLE_OFFSET) // X24 = [X19 + 8]
  } else {
    // v1 ABI (legacy): X0=func_table, X1=memory_base, X2=memory_size
    emit_mov_reg(mc, 20, 0) // MOV X20, X0 (func_table_ptr)
    emit_mov_reg(mc, 21, 1) // MOV X21, X1 (memory_base)
    emit_mov_reg(mc, 22, 2) // MOV X22, X2 (memory_size)
    // Load indirect_table_ptr from func_table[-1] into X24
    // Memory layout: [indirect_table_ptr | func_ptr_0 | func_ptr_1 | ...]
    //                ^                    ^
    //                X20 - 8              X20
    emit_ldr_imm_signed(mc, 24, 20, -8) // LDR X24, [X20, #-8]
  }
  // Set up X23 for extra results buffer
  if needs_extra_results {
    // When we return multi-value, X7 contains the caller-provided buffer pointer
    emit_mov_reg(mc, 23, 7) // MOV X23, X7 (extra_results_buffer)
  } else if calls_multi_value {
    // When we call multi-value functions, allocate local buffer on stack
    // Buffer is at the end of the frame: SP + GPR save + FPR save + spill_size
    let buffer_offset = clobbered_gpr_size + clobbered_fpr_size + spill_size
    emit_add_imm(mc, 23, 31, buffer_offset) // ADD X23, SP, #buffer_offset
  }
  // Move user arguments from X registers to their allocated registers
  // FFI passes all args as Int64 in X registers
  // Float params need special handling:
  //   - For f32: lower 32 bits of X register contain f32 bit pattern
  //     We use FMOV W->S to move bits directly (no conversion)
  //   - For f64: full 64 bits of X register contain f64 bit pattern
  //     We use FMOV X->D to move bits directly
  //
  // ABI v1: X0-X2 reserved, user params in X3-X10
  // ABI v2: user params in X0-X7 (AAPCS64 compatible)
  let actual_param_base = if ABI_VERSION == 2 {
    PARAM_BASE_REG
  } else {
    LEGACY_PARAM_BASE_REG
  }
  let actual_max_reg_params = if ABI_VERSION == 2 {
    MAX_REG_PARAMS
  } else {
    LEGACY_MAX_REG_PARAMS
  }
  for param_idx, param in params {
    // Check if this param needs to be moved to a different register
    let dest_preg = if param_idx < param_pregs.length() {
      param_pregs[param_idx]
    } else {
      None
    }
    if param_idx < actual_max_reg_params {
      // Register param: in X(base+param_idx)
      let x_src = actual_param_base + param_idx
      match param.class {
        Float32 => {
          // Float32 param: extract f32 from lower 32 bits
          // FMOV S(dest), W(x_src) - bit-exact transfer, no conversion
          let s_dest = match dest_preg {
            Some(preg) => preg.index
            None => param_idx
          }
          emit_fmov_w_to_s(mc, s_dest, x_src) // FMOV Sd, Wn (raw bits)
        }
        Float64 => {
          // Float64 param: move full 64 bits from X register to D register
          // FMOV D(dest), X(x_src)
          let d_dest = match dest_preg {
            Some(preg) => preg.index
            None => param_idx
          }
          emit_fmov_x_to_d(mc, d_dest, x_src)
        }
        Int =>
          // Int param: may need to move from X(base+i) to allocated register
          match dest_preg {
            Some(preg) =>
              // Param crosses a call, move to callee-saved register
              emit_mov_reg(mc, preg.index, x_src)
            None =>
              // Int param: already at X(base+i) where regalloc expects it
              // No move needed
              ()
          }
      }
    }
    // Stack params (param_idx >= 8) are now handled by LoadStackParam instruction
    // during function body execution, not in prologue
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
/// Emit STP for FPR pairs (64-bit D registers) with signed offset
fn emit_stp_d_offset(
  mc : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
  mc.annotate("stp d\{rt1}, d\{rt2}, [\{rn_name}, #\{offset}]")
  // STP (FPR, signed offset) encoding for 64-bit:
  // [31:30] = 01 (opc for 64-bit FP)
  // [29:27] = 101
  // [26] = 1 (V = 1 for SIMD/FP)
  // [25:23] = 010 (signed offset)
  // [22] = 0 (store)
  // [21:15] = imm7
  // [14:10] = Rt2
  // [9:5] = Rn
  // [4:0] = Rt1
  let imm7 = (offset / 8) & 0x7F
  let inst = (0b01 << 30) |
    (0b101 << 27) |
    (1 << 26) |
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
/// Emit LDP for FPR pairs (64-bit D registers) with signed offset
fn emit_ldp_d_offset(
  mc : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
  mc.annotate("ldp d\{rt1}, d\{rt2}, [\{rn_name}, #\{offset}]")
  // LDP (FPR, signed offset) encoding for 64-bit:
  // Same as STP but with [22] = 1 (load)
  let imm7 = (offset / 8) & 0x7F
  let inst = (0b01 << 30) |
    (0b101 << 27) |
    (1 << 26) |
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
  clobbered_fprs : Array[Int],
  clobbered_gpr_size : Int,
  frame_size : Int,
  needs_extra_results : Bool,
  calls_multi_value : Bool,
) -> Unit {
  // Build the same list as prologue: (X19 if v2), X20, X21, X22, X24, (X23 if uses_x23) + clobbered
  let uses_x23 = needs_extra_results || calls_multi_value
  let all_to_restore : Array[Int] = if ABI_VERSION == 2 {
    // v2: X19 holds context_ptr
    if uses_x23 {
      [19, 20, 21, 22, 23, 24]
    } else {
      [19, 20, 21, 22, 24]
    }
    // v1: X20-X22, X24, optionally X23
  } else if uses_x23 {
    [20, 21, 22, 23, 24]
  } else {
    [20, 21, 22, 24]
  }
  for reg in clobbered {
    all_to_restore.push(reg)
  }
  let num_regs = all_to_restore.length()
  let num_pairs = (num_regs + 1) / 2
  // Restore FPRs first (before GPRs, since FPRs are saved after GPRs)
  // Handle pairs first, then single register if odd count
  let num_fprs = clobbered_fprs.length()
  let mut fi = 0
  let mut fpr_pair_idx = 0
  while fi + 1 < num_fprs {
    // Restore pairs
    let reg1 = clobbered_fprs[fi]
    let reg2 = clobbered_fprs[fi + 1]
    let offset = clobbered_gpr_size + fpr_pair_idx * 16
    emit_ldp_d_offset(mc, reg1, reg2, 31, offset)
    fi = fi + 2
    fpr_pair_idx = fpr_pair_idx + 1
  }
  // Handle last register if odd count
  if fi < num_fprs {
    let reg = clobbered_fprs[fi]
    let offset = clobbered_gpr_size + fpr_pair_idx * 16
    emit_ldr_d_imm(mc, reg, 31, offset)
  }
  // Restore GPRs using LDP
  let mut i = 0
  let mut pair_idx = 0
  while i < num_regs {
    let reg1 = all_to_restore[i]
    let has_reg2 = i + 1 < num_regs
    let reg2 = if has_reg2 { all_to_restore[i + 1] } else { 31 }
    let offset = pair_idx * 16
    if pair_idx == num_pairs - 1 {
      // Last load
      if !has_reg2 {
        // Odd number of registers: use single LDR for the last one
        // We can't use LDP with X31 as destination - that would corrupt SP!
        emit_ldr_imm(mc, reg1, 31, offset)
        emit_add_imm(mc, 31, 31, frame_size)
      } else if pair_idx == 0 {
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
  // Check if we need extra results buffer (>2 int or >2 float returns)
  let needs_extra_results = func.needs_extra_results_ptr()
  // Check if we call functions that return more than 2 values
  // In that case, we need to allocate a local buffer and use X23 to point to it
  let calls_multi_value = func.calls_multi_value_function()
  // We need X23 if either we return multi-value OR we call multi-value functions
  let uses_x23 = needs_extra_results || calls_multi_value
  // Collect callee-saved GPRs that this function clobbers
  let clobbered = collect_used_callee_saved(func, uses_x23)
  // Collect callee-saved FPRs (D8-D15) that this function clobbers
  let clobbered_fprs = collect_used_callee_saved_fprs(func)
  // Calculate clobbered_gpr_size for spill offset calculation
  // v1: Always save X20-X22, X24; optionally X23
  // v2: Also save X19 (for context_ptr preservation)
  let num_base_regs = if ABI_VERSION == 2 {
    if uses_x23 {
      6
    } else {
      5
    } // X19, X20-X22, X24, (X23)
  } else if uses_x23 {
    5
  } else {
    4
  } // X20-X22, X24, (X23)
  let num_regs = num_base_regs + clobbered.length()
  let num_pairs = (num_regs + 1) / 2
  let clobbered_gpr_size = num_pairs * 16
  // Calculate FPR save size
  let num_fpr_pairs = (clobbered_fprs.length() + 1) / 2
  let clobbered_fpr_size = num_fpr_pairs * 16
  // Emit prologue: save callee-saved registers, set up X20/X21/X22, and move params
  let frame_size = emit_prologue(
    mc,
    clobbered,
    clobbered_fprs,
    func.params,
    func.param_pregs,
    needs_extra_results,
    calls_multi_value,
    func.num_spill_slots,
  )
  // Emit function body
  // Spill slots start after the saved registers area (GPRs + FPRs)
  let spill_base_offset = clobbered_gpr_size + clobbered_fpr_size
  for block in func.blocks {
    mc.define_label(block.id)
    for inst in block.insts {
      emit_instruction(mc, inst, spill_base_offset, frame_size)
    }
    match block.terminator {
      Some(term) =>
        emit_terminator_with_epilogue(
          mc,
          term,
          clobbered,
          clobbered_fprs,
          clobbered_gpr_size,
          frame_size,
          func.result_types,
          needs_extra_results,
          calls_multi_value,
        )
      None => ()
    }
  }
  mc.resolve_fixups()
  mc
}

///|
fn emit_instruction(
  mc : MachineCode,
  inst : VCodeInst,
  spill_base_offset : Int,
  frame_size : Int,
) -> Unit {
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
    Rotr => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      emit_ror_reg(mc, rd, rn, rm)
    }
    Rotl => {
      // Rotate left by n is rotate right by (64 - n)
      // rotl(x, n) = rotr(x, 64 - n)
      // We need to compute 64 - rm, then rotate right
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      // Use scratch register x16 to compute (64 - rm)
      emit_movz(mc, 16, 64, 0) // x16 = 64
      emit_sub_reg(mc, 16, 16, rm) // x16 = 64 - rm
      emit_ror_reg(mc, rd, rn, 16) // rd = rotr(rn, x16)
    }
    Not => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      emit_mvn(mc, rd, rn)
    }
    SRem => {
      // Signed remainder: rem = a - (a / b) * b
      // Using MSUB: rd = ra - rn * rm
      // 1. Compute quotient: x16 = a / b (SDIV)
      // 2. Compute remainder: rd = a - x16 * b (MSUB)
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0]) // dividend (a)
      let rm = reg_num(inst.uses[1]) // divisor (b)
      emit_sdiv(mc, 16, rn, rm) // x16 = a / b
      emit_msub(mc, rd, 16, rm, rn) // rd = a - x16 * b
    }
    URem => {
      // Unsigned remainder: rem = a - (a / b) * b
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0]) // dividend (a)
      let rm = reg_num(inst.uses[1]) // divisor (b)
      emit_udiv(mc, 16, rn, rm) // x16 = a / b (unsigned)
      emit_msub(mc, rd, 16, rm, rn) // rd = a - x16 * b
    }
    Bitcast => {
      // Reinterpret bits between int and float
      // IMPORTANT: For f32 bitcast, we must preserve exact bits (including NaN payloads)
      // We store f32 as raw 32-bit pattern in lower bits of D register, NOT as promoted f64
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Determine direction and size based on register classes
      let dest_class = match inst.defs[0].reg {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      let src_class = match inst.uses[0] {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      match (src_class, dest_class) {
        (Int, Float64) =>
          // i64 -> f64: FMOV Dd, Xn (bit-exact transfer)
          emit_fmov_x_to_d(mc, rd, rn)
        (Float64, Int) =>
          // f64 -> i64: FMOV Xd, Dn (bit-exact transfer)
          emit_fmov_d_to_x(mc, rd, rn)
        (Int, Float32) =>
          // i32 -> f32: Store raw f32 bits in D register
          // Use FMOV S, W which moves bits to lower 32 bits of D register
          // The upper 32 bits are zeroed, which is fine for our purposes
          // This preserves exact bit patterns including signaling NaNs
          emit_fmov_w_to_s(mc, rd, rn) // FMOV Sd, Wn (bit-exact, no conversion)
        (Float32, Int) =>
          // f32 -> i32: Extract raw f32 bits from D register
          // Use FMOV W, S which extracts lower 32 bits
          // This preserves exact bit patterns including signaling NaNs
          emit_fmov_s_to_w(mc, rd, rn) // FMOV Wd, Sn (bit-exact, no conversion)
        _ =>
          // Fallback for other cases (shouldn't happen with valid WASM)
          emit_fmov_x_to_d(mc, rd, rn)
      }
    }
    FAdd(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        // For f32: operate directly on S registers (raw f32 bits)
        emit_fadd_s(mc, rd, rn, rm)
      } else {
        emit_fadd_d(mc, rd, rn, rm)
      }
    }
    FSub(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        emit_fsub_s(mc, rd, rn, rm)
      } else {
        emit_fsub_d(mc, rd, rn, rm)
      }
    }
    FMul(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        emit_fmul_s(mc, rd, rn, rm)
      } else {
        emit_fmul_d(mc, rd, rn, rm)
      }
    }
    FDiv(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        emit_fdiv_s(mc, rd, rn, rm)
      } else {
        emit_fdiv_d(mc, rd, rn, rm)
      }
    }
    FMin(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        emit_fmin_s(mc, rd, rn, rm)
      } else {
        emit_fmin_d(mc, rd, rn, rm)
      }
    }
    FMax(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        emit_fmax_s(mc, rd, rn, rm)
      } else {
        emit_fmax_d(mc, rd, rn, rm)
      }
    }
    // Floating-point unary operations
    FSqrt(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        emit_fsqrt_s(mc, rd, rn)
      } else {
        emit_fsqrt_d(mc, rd, rn)
      }
    }
    FAbs(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        emit_fabs_s(mc, rd, rn)
      } else {
        emit_fabs_d(mc, rd, rn)
      }
    }
    FNeg(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        // For f32: Use FNEG S directly to preserve exact bit patterns
        // Our f32 values are stored as raw bits in S registers (lower 32 bits of D)
        // FNEG S only flips the sign bit without changing NaN payloads
        emit_fneg_s(mc, rd, rn)
      } else {
        emit_fneg_d(mc, rd, rn)
      }
    }
    FCeil(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        emit_frintp_s(mc, rd, rn)
      } else {
        emit_frintp_d(mc, rd, rn)
      }
    }
    FFloor(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        emit_frintm_s(mc, rd, rn)
      } else {
        emit_frintm_d(mc, rd, rn)
      }
    }
    FTrunc(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        emit_frintz_s(mc, rd, rn)
      } else {
        emit_frintz_d(mc, rd, rn)
      }
    }
    FNearest(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        // For f32: operate directly on S registers (raw f32 bits)
        emit_frintn_s(mc, rd, rn)
      } else {
        emit_frintn_d(mc, rd, rn)
      }
    }
    // Floating-point conversions
    FPromote => {
      // f32 -> f64: Convert from S register (raw f32 bits) to D register (f64)
      // This is a real conversion using FCVT
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      emit_fcvt_d_s(mc, rd, rn)
    }
    FDemote => {
      // f64 -> f32: Convert from D register (f64) to S register (raw f32 bits)
      // This is a real conversion using FCVT
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      emit_fcvt_s_d(mc, rd, rn)
    }
    Load(ty, offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // F32 loads directly into S register (raw f32 bits preserved)
      emit_load(mc, ty, rt, rn, offset)
    }
    Store(ty, offset) => {
      // uses[0] = address (Rn), uses[1] = value (Rt)
      let rn = reg_num(inst.uses[0]) // base address
      let rt = reg_num(inst.uses[1]) // value to store
      // F32 stores directly from S register (raw f32 bits preserved)
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
        Float32 => emit_fmov_s(mc, rd, rm)
        Float64 => emit_fmov_d(mc, rd, rm)
        Int => emit_mov_reg(mc, rd, rm)
      }
    }
    LoadConst(v) => {
      let rd = wreg_num(inst.defs[0])
      emit_load_imm64(mc, rd, v)
    }
    LoadConstF32(bits) => {
      // Load 32-bit float constant as raw bits into S register
      // 1. Load the 32-bit representation into a scratch W register (W16)
      // 2. FMOV from W16 to destination S register (bit-exact, no conversion)
      let rd = wreg_num(inst.defs[0])
      // Use X16 as scratch register, load the 32-bit value as unsigned
      emit_movz(mc, 16, bits & 0xFFFF, 0)
      let high = (bits >> 16) & 0xFFFF
      if high != 0 {
        emit_movk(mc, 16, high, 16)
      }
      // FMOV Sd, W16 (move 32-bit value to S register - bit-exact)
      emit_fmov_w_to_s(mc, rd, 16)
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
      // Check register class to use appropriate compare instruction
      let reg_class = match inst.uses[0] {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      match reg_class {
        Float32 => emit_fcmp_s(mc, rn, rm)
        _ => emit_fcmp_d(mc, rn, rm)
      }
      let rd = wreg_num(inst.defs[0])
      let cond = fcmp_kind_to_cond(kind)
      emit_cset(mc, rd, cond)
    }
    Select => {
      // Select: dst = cond != 0 ? true_val : false_val
      // Uses: [cond, true_val, false_val]
      let rd = wreg_num(inst.defs[0])
      let cond_reg = reg_num(inst.uses[0])
      let true_val = reg_num(inst.uses[1])
      let false_val = reg_num(inst.uses[2])
      // Compare cond with 0: CMP cond, #0
      emit_cmp_imm(mc, cond_reg, 0)
      // Check register class to use appropriate select instruction
      let reg_class = match inst.defs[0].reg {
        Physical(preg) => preg.class
        Virtual(_) => Int // Should not happen at emit time
      }
      match reg_class {
        Float32 =>
          // Use FCSEL S for single-precision
          emit_fcsel_s(mc, rd, true_val, false_val, NE.to_int())
        Float64 =>
          // Use FCSEL D for double-precision
          emit_fcsel_d(mc, rd, true_val, false_val, NE.to_int())
        Int =>
          // Use CSEL for integer registers
          emit_csel(mc, rd, true_val, false_val, NE.to_int())
      }
    }
    Clz => {
      // Count leading zeros
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      emit_clz(mc, rd, rn)
    }
    Ctz => {
      // Count trailing zeros: CTZ(x) = CLZ(RBIT(x))
      // First reverse the bits, then count leading zeros
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Use X16 as scratch register
      emit_rbit(mc, 16, rn) // X16 = RBIT(rn)
      emit_clz(mc, rd, 16) // rd = CLZ(X16)
    }
    Popcnt => {
      // Population count (count number of 1 bits)
      // AArch64 doesn't have a direct POPCNT for GPRs, we use SIMD:
      // 1. FMOV D16, Xn (move to vector register)
      // 2. CNT V16.8B, V16.8B (count bits in each byte)
      // 3. ADDV B17, V16.8B (sum all byte counts)
      // 4. FMOV Xd, D17 (move back to GPR)
      // For simplicity, we'll use a software fallback sequence
      // TODO: Implement proper SIMD version for better performance
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // For now, emit NOP and move the input to output (placeholder)
      // This needs proper implementation
      emit_mov_reg(mc, rd, rn)
      emit_nop(mc)
    }
    Extend(kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match kind {
        Signed8To32 => emit_sxtb_w(mc, rd, rn)
        Signed8To64 => emit_sxtb_x(mc, rd, rn)
        Signed16To32 => emit_sxth_w(mc, rd, rn)
        Signed16To64 => emit_sxth_x(mc, rd, rn)
        Signed32To64 => emit_sxtw(mc, rd, rn)
        Unsigned8To32 => emit_uxtb_w(mc, rd, rn)
        Unsigned8To64 => emit_uxtb_x(mc, rd, rn)
        Unsigned16To32 => emit_uxth_w(mc, rd, rn)
        Unsigned16To64 => emit_uxth_x(mc, rd, rn)
        Unsigned32To64 =>
          // Zero-extend 32-bit to 64-bit: MOV Wd, Wn (W-write zero-extends to X)
          emit_mov_reg32(mc, rd, rn)
      }
    }
    Truncate => {
      // Truncate from 64-bit to 32-bit: just use MOV Wd, Wn
      // The upper 32 bits are automatically zeroed
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      emit_mov_reg32(mc, rd, rn)
    }
    FloatToInt(kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // f32 values are stored as raw bits in S registers
      // f64 values are stored in D registers
      match kind {
        F32ToI32S =>
          // S register contains f32, convert directly
          emit_fcvtzs(mc, rd, rn, int64=false, double=false) // FCVTZS Wd, Sn
        F32ToI32U => emit_fcvtzu(mc, rd, rn, int64=false, double=false)
        F32ToI64S => emit_fcvtzs(mc, rd, rn, int64=true, double=false)
        F32ToI64U => emit_fcvtzu(mc, rd, rn, int64=true, double=false)
        F64ToI32S => emit_fcvtzs(mc, rd, rn, int64=false, double=true)
        F64ToI32U => emit_fcvtzu(mc, rd, rn, int64=false, double=true)
        F64ToI64S => emit_fcvtzs(mc, rd, rn, int64=true, double=true)
        F64ToI64U => emit_fcvtzu(mc, rd, rn, int64=true, double=true)
      }
    }
    IntToFloat(kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // f32 results go directly to S registers
      // f64 results go directly to D registers
      match kind {
        I32SToF32 =>
          // Convert to S register directly
          emit_scvtf(mc, rd, rn, int64=false, double=false) // SCVTF Sd, Wn
        I32UToF32 => emit_ucvtf(mc, rd, rn, int64=false, double=false)
        I64SToF32 => emit_scvtf(mc, rd, rn, int64=true, double=false)
        I64UToF32 => emit_ucvtf(mc, rd, rn, int64=true, double=false)
        I32SToF64 => emit_scvtf(mc, rd, rn, int64=false, double=true)
        I32UToF64 => emit_ucvtf(mc, rd, rn, int64=false, double=true)
        I64SToF64 => emit_scvtf(mc, rd, rn, int64=true, double=true)
        I64UToF64 => emit_ucvtf(mc, rd, rn, int64=true, double=true)
      }
    }
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
    CallIndirect(num_args, num_results) => {
      // Call through a function pointer in a register
      // ABI v1: X0=func_table, X1=memory_base, X2=memory_size, args in X3-X10
      // ABI v2: args in X0-X7 (AAPCS64 compatible), context via X20 (callee-saved)
      // Return values: X0, X1 for first two int results, extra results via buffer pointed by X7/X23
      // Uses: [func_ptr, arg0, arg1, ...]
      let func_ptr = reg_num(inst.uses[0])
      // Save function pointer to X17 (intra-procedure call scratch register)
      // Note: X18 is reserved on Apple platforms, must NOT use it
      emit_mov_reg(mc, 17, func_ptr) // MOV X17, func_ptr
      // Calculate how many args go on stack (args beyond the first 8)
      let actual_param_base_call = if ABI_VERSION == 2 {
        PARAM_BASE_REG
      } else {
        LEGACY_PARAM_BASE_REG
      }
      let call_max_reg_args = 8
      let stack_args = if num_args > call_max_reg_args {
        num_args - call_max_reg_args
      } else {
        0
      }
      let reg_args_count = @cmp.minimum(num_args, call_max_reg_args)
      // Allocate stack space for:
      // 1. Overflow args (args 8+)
      // 2. Temp space for register args (to avoid register clobbering during parallel copy)
      let overflow_space = stack_args * 8
      let temp_space = reg_args_count * 8
      let total_stack_space = (overflow_space + temp_space + 15) / 16 * 16
      if total_stack_space > 0 {
        emit_sub_imm(mc, 31, 31, total_stack_space) // SUB SP, SP, #total_stack_space
      }
      // Move arguments using stack-based parallel copy to avoid register conflicts
      // This approach doesn't require reserving any GPRs (like X11-X15)
      //
      // Layout on stack after SUB SP:
      // [SP + 0 ... overflow_space-1]: overflow args (args 8+)
      // [SP + overflow_space ... overflow_space + temp_space - 1]: temp space for register args
      if num_args > 0 {
        // Phase 1: Store all register args to temp space on stack
        // This saves their values before we load to destination registers
        for i in 0..<reg_args_count {
          let src = reg_num(inst.uses[i + 1])
          let temp_offset = overflow_space + i * 8
          let arg_class = match inst.uses[i + 1] {
            Physical(preg) => preg.class
            Virtual(vreg) => vreg.class
          }
          if src >= spill_slot_base {
            // Already spilled - we'll load directly from spill slot in Phase 3
            // Store a marker value (we won't actually read this)
            ()
          } else {
            match arg_class {
              Int => emit_str_imm(mc, src, 31, temp_offset)
              Float32 => {
                emit_fmov_s_to_w(mc, 16, src)
                emit_str_imm(mc, 16, 31, temp_offset)
              }
              Float64 => {
                emit_fmov_d_to_x(mc, 16, src)
                emit_str_imm(mc, 16, 31, temp_offset)
              }
            }
          }
        }
        // Phase 2: Store overflow args (args 8+) to call stack area
        for i in call_max_reg_args..<num_args {
          let src = reg_num(inst.uses[i + 1])
          let stack_offset = (i - call_max_reg_args) * 8
          let arg_class = match inst.uses[i + 1] {
            Physical(preg) => preg.class
            Virtual(vreg) => vreg.class
          }
          if src >= spill_slot_base {
            // Spilled: load from spill slot to X16, then store to call stack
            let spill_slot = src - spill_slot_base
            let spill_offset = spill_base_offset +
              total_stack_space +
              spill_slot * 8
            match arg_class {
              Int => {
                emit_ldr_imm(mc, 16, 31, spill_offset)
                emit_str_imm(mc, 16, 31, stack_offset)
              }
              Float32 => {
                emit_ldr_d_imm(mc, 16, 31, spill_offset)
                emit_fmov_s_to_w(mc, 16, 16)
                emit_str_imm(mc, 16, 31, stack_offset)
              }
              Float64 => {
                emit_ldr_d_imm(mc, 16, 31, spill_offset)
                emit_fmov_d_to_x(mc, 16, 16)
                emit_str_imm(mc, 16, 31, stack_offset)
              }
            }
          } else {
            match arg_class {
              Int => emit_str_imm(mc, src, 31, stack_offset)
              Float32 => {
                emit_fmov_s_to_w(mc, 16, src)
                emit_str_imm(mc, 16, 31, stack_offset)
              }
              Float64 => {
                emit_fmov_d_to_x(mc, 16, src)
                emit_str_imm(mc, 16, 31, stack_offset)
              }
            }
          }
        }
        // Phase 3: Load from temp space (or spill slot) to destination registers
        for i in 0..<reg_args_count {
          let src = reg_num(inst.uses[i + 1])
          let dst = i + actual_param_base_call
          let temp_offset = overflow_space + i * 8
          let arg_class = match inst.uses[i + 1] {
            Physical(preg) => preg.class
            Virtual(vreg) => vreg.class
          }
          if src >= spill_slot_base {
            // Spilled: load directly from spill slot
            let spill_slot = src - spill_slot_base
            let spill_offset = spill_base_offset +
              total_stack_space +
              spill_slot * 8
            match arg_class {
              Int => emit_ldr_imm(mc, dst, 31, spill_offset)
              Float32 => {
                emit_ldr_d_imm(mc, 16, 31, spill_offset)
                emit_fmov_s_to_w(mc, dst, 16)
              }
              Float64 => {
                emit_ldr_d_imm(mc, 16, 31, spill_offset)
                emit_fmov_d_to_x(mc, dst, 16)
              }
            }
          } else {
            // Load from temp space on stack
            emit_ldr_imm(mc, dst, 31, temp_offset)
          }
        }
      }
      // If callee returns more than 2 values, it needs a buffer pointer in X7
      // Note: This overwrites arg4 if it was set, so multi-return functions
      // can only have up to 4 user args when using the buffer
      if num_results > 2 {
        emit_mov_reg(mc, 7, 23) // MOV X7, X23
      }
      // Set up context for callee
      if ABI_VERSION == 2 {
        // v2: X19 already contains context_ptr (callee-saved)
        // The callee's prologue will load from X19, no setup needed
        ()
      } else {
        // v1: Set up X0 = func_table (X20), X1 = memory_base (X21), X2 = memory_size (X22)
        emit_mov_reg(mc, 0, 20) // MOV X0, X20
        emit_mov_reg(mc, 1, 21) // MOV X1, X21
        emit_mov_reg(mc, 2, 22) // MOV X2, X22
      }
      // Call the function (from saved X17)
      emit_blr(mc, 17)
      // Restore X20 (func_table) after call for v2 ABI
      // X19 is callee-saved, so it still contains our context_ptr
      // We need to reload func_table from X19
      if ABI_VERSION == 2 {
        emit_ldr_imm(mc, 20, 19, CTX_FUNC_TABLE_OFFSET) // X20 = [X19 + 0]
      }
      // Move results to destination registers
      // JIT ABI: integer returns in X0, X1; float returns in D0/S0, D1/S1
      // Two-phase is only needed when there's potential conflict:
      // - For ints: if dest is X0/X1 and we have multiple int results
      // - For floats: if mixing f32 and f64 types

      // Collect result info
      let int_results : Array[(Int, Int)] = [] // (dest_reg, abi_idx)
      let float_results : Array[(RegClass, Int, Int)] = [] // (class, dest_reg, abi_idx)
      let mut int_abi_idx = 0
      let mut float_abi_idx = 0
      for i in 0..<num_results {
        if i >= inst.defs.length() {
          break
        }
        let rd = wreg_num(inst.defs[i])
        let def_class = match inst.defs[i].reg {
          Physical(preg) => preg.class
          Virtual(vreg) => vreg.class
        }
        match def_class {
          Int => {
            int_results.push((rd, int_abi_idx))
            int_abi_idx = int_abi_idx + 1
          }
          Float32 | Float64 => {
            float_results.push((def_class, rd, float_abi_idx))
            float_abi_idx = float_abi_idx + 1
          }
        }
      }

      // Handle integer results
      // Need two-phase if: multiple results AND any dest is X0 or X1 (would conflict)
      let int_need_two_phase = int_results.length() >= 2 &&
        {
          let mut has_conflict = false
          for entry in int_results {
            let (rd, _) = entry
            if rd == 0 || rd == 1 {
              has_conflict = true
              break
            }
          }
          has_conflict
        }
      if int_need_two_phase {
        // Two-phase: save to temps first
        let temp_int_base = 10
        for entry in int_results {
          let (_, abi_idx) = entry
          if abi_idx < 2 {
            emit_mov_reg(mc, temp_int_base + abi_idx, abi_idx)
          }
        }
        for entry in int_results {
          let (rd, abi_idx) = entry
          if abi_idx < 2 {
            let temp = temp_int_base + abi_idx
            if rd != temp {
              emit_mov_reg(mc, rd, temp)
            }
          } else {
            let offset = (abi_idx - 2) * 8
            emit_ldr_imm(mc, rd, 23, offset)
          }
        }
      } else {
        // Direct move: no conflict
        for entry in int_results {
          let (rd, abi_idx) = entry
          if abi_idx < 2 {
            if rd != abi_idx {
              emit_mov_reg(mc, rd, abi_idx)
            }
          } else {
            let offset = (abi_idx - 2) * 8
            emit_ldr_imm(mc, rd, 23, offset)
          }
        }
      }

      // Handle float results
      // Need two-phase only when mixing f32 and f64 (D/S register aliasing)
      let mut has_f32 = false
      let mut has_f64 = false
      for entry in float_results {
        let (class, _, _) = entry
        match class {
          Float32 => has_f32 = true
          _ => has_f64 = true
        }
      }
      let float_need_two_phase = has_f32 &&
        has_f64 &&
        float_results.length() >= 2
      if float_need_two_phase {
        // Two-phase: save to temps first
        let temp_float_base = 24
        for entry in float_results {
          let (_, _, abi_idx) = entry
          if abi_idx < 2 {
            emit_fmov_d(mc, temp_float_base + abi_idx, abi_idx)
          }
        }
        for entry in float_results {
          let (class, rd, abi_idx) = entry
          if abi_idx < 2 {
            let temp = temp_float_base + abi_idx
            if rd != temp {
              match class {
                Float32 => emit_fmov_s(mc, rd, temp)
                _ => emit_fmov_d(mc, rd, temp)
              }
            }
          } else {
            let offset = (abi_idx - 2) * 8
            match class {
              Float32 => emit_ldr_s_imm(mc, rd, 23, offset)
              _ => emit_ldr_d_imm(mc, rd, 23, offset)
            }
          }
        }
      } else {
        // Direct move: no conflict
        for entry in float_results {
          let (class, rd, abi_idx) = entry
          if abi_idx < 2 {
            if rd != abi_idx {
              match class {
                Float32 => emit_fmov_s(mc, rd, abi_idx)
                _ => emit_fmov_d(mc, rd, abi_idx)
              }
            }
          } else {
            let offset = (abi_idx - 2) * 8
            match class {
              Float32 => emit_ldr_s_imm(mc, rd, 23, offset)
              _ => emit_ldr_d_imm(mc, rd, 23, offset)
            }
          }
        }
      }
      // Restore stack pointer if we allocated space for stack args
      if total_stack_space > 0 {
        emit_add_imm(mc, 31, 31, total_stack_space) // ADD SP, SP, #total_stack_space
      }
    }
    StackLoad(offset) => {
      // Load from [SP + spill_base_offset + offset] into the def register
      // Uses SP (X31) as base
      // spill_base_offset accounts for saved registers area
      let rd = wreg_num(inst.defs[0])
      // Check if this is a float or int register
      let def_class = match inst.defs[0].reg {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      match def_class {
        Int => emit_ldr_imm(mc, rd, 31, spill_base_offset + offset) // LDR Xd, [SP, #offset]
        // Always use 64-bit load for floats to avoid S/D register aliasing issues
        Float32 | Float64 =>
          emit_ldr_d_imm(mc, rd, 31, spill_base_offset + offset) // LDR Dd, [SP, #offset]
      }
    }
    StackStore(offset) => {
      // Store the use register to [SP + spill_base_offset + offset]
      // Uses SP (X31) as base
      // spill_base_offset accounts for saved registers area
      let rt = reg_num(inst.uses[0])
      // Check if this is a float or int register
      let use_class = match inst.uses[0] {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      match use_class {
        Int => emit_str_imm(mc, rt, 31, spill_base_offset + offset) // STR Xt, [SP, #offset]
        // Always use 64-bit store for floats to avoid S/D register aliasing issues
        Float32 | Float64 =>
          emit_str_d_imm(mc, rt, 31, spill_base_offset + offset) // STR Dt, [SP, #offset]
      }
    }
    LoadStackParam(param_idx, class) => {
      // Load stack parameter from [SP + frame_size + (param_idx - 8) * 8]
      // Stack parameters are located above the current frame
      let max_reg_params = 8
      let stack_offset = frame_size + (param_idx - max_reg_params) * 8
      let rd = wreg_num(inst.defs[0])
      match class {
        Int => emit_ldr_imm(mc, rd, 31, stack_offset) // LDR Xd, [SP, #offset]
        Float32 => {
          // Load 32-bit value to scratch, then move to S register
          emit_ldr_w_imm(mc, 16, 31, stack_offset) // LDR W16, [SP, #offset]
          emit_fmov_w_to_s(mc, rd, 16) // FMOV Sd, W16
        }
        Float64 => {
          // Load 64-bit value to scratch, then move to D register
          emit_ldr_imm(mc, 16, 31, stack_offset) // LDR X16, [SP, #offset]
          emit_fmov_x_to_d(mc, rd, 16) // FMOV Dd, X16
        }
      }
    }
    MemoryGrow => {
      // Call wasmoon_jit_memory_grow(delta, max_pages)
      // Uses: [delta], Defs: [result]
      // Get the delta from the use register
      let delta_reg = reg_num(inst.uses[0])
      let result_reg = wreg_num(inst.defs[0])

      // Move delta to X0 (first argument)
      emit_mov_reg(mc, 0, delta_reg) // MOV X0, delta

      // Set X1 = 0 (max_pages = 0 means no limit)
      emit_movz(mc, 1, 0, 0) // MOVZ X1, #0

      // Load memory_grow function pointer into X16
      let grow_ptr = @jit_ffi.c_jit_get_memory_grow_v2_ptr()
      emit_load_imm64(mc, 16, grow_ptr)

      // Call the function
      mc.annotate("blr x16  // memory_grow")
      emit_blr(mc, 16)

      // Save result to stack temporarily (at spill_base_offset, which is scratch space)
      // The subsequent BLR calls will clobber X0-X17, so we save to stack
      // We use spill_base_offset which points to the spill slot area
      emit_str_imm(mc, 0, 31, spill_base_offset) // STR X0, [SP, #spill_base_offset]

      // After memory.grow, reload memory base and size into X21/X22
      // since realloc may have moved the memory

      // Call get_memory_base() and store to X21
      let base_ptr = @jit_ffi.c_jit_get_memory_base_v2_ptr()
      emit_load_imm64(mc, 16, base_ptr)
      mc.annotate("blr x16  // get_memory_base")
      emit_blr(mc, 16)
      emit_mov_reg(mc, 21, 0) // MOV X21, X0

      // Call get_memory_size_bytes() and store to X22
      let size_ptr = @jit_ffi.c_jit_get_memory_size_bytes_v2_ptr()
      emit_load_imm64(mc, 16, size_ptr)
      mc.annotate("blr x16  // get_memory_size_bytes")
      emit_blr(mc, 16)
      emit_mov_reg(mc, 22, 0) // MOV X22, X0

      // Load result from stack to the destination register
      emit_ldr_imm(mc, result_reg, 31, spill_base_offset) // LDR Xd, [SP, #spill_base_offset]
    }
    MemorySize => {
      // Call wasmoon_jit_memory_size()
      // Uses: [], Defs: [result]
      let result_reg = wreg_num(inst.defs[0])

      // Load memory_size function pointer into X16
      let size_ptr = @jit_ffi.c_jit_get_memory_size_v2_ptr()
      emit_load_imm64(mc, 16, size_ptr)

      // Call the function
      mc.annotate("blr x16  // memory_size")
      emit_blr(mc, 16)

      // Move result from X0 to destination
      if result_reg != 0 {
        emit_mov_reg(mc, result_reg, 0) // MOV result, X0
      }
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
/// Map floating-point comparison kind to AArch64 condition code.
///
/// For floating-point comparisons, we need "ordered" semantics where
/// any comparison involving NaN returns false (0).
///
/// After FCMP, the NZCV flags are set as:
/// - Ordered less than:    N=1, Z=0, C=0, V=0
/// - Ordered equal:        N=0, Z=1, C=1, V=0
/// - Ordered greater than: N=0, Z=0, C=1, V=0
/// - Unordered (NaN):      N=0, Z=0, C=1, V=1
///
/// Condition codes for ordered floating-point comparisons:
/// - Lt: MI (N=1) - true only when N is set (ordered less than)
/// - Le: LS (C=0|Z=1) - true when C is clear OR Z is set
/// - Gt: GT (Z=0 & N=V) - works correctly for floats
/// - Ge: GE (N=V) - works correctly for floats
/// - Eq: EQ (Z=1) - works correctly
/// - Ne: NE (Z=0) - but need VC for ordered ne, using NE gives unordered ne
///
/// Note: For NaN, NZCV=0011, so:
/// - MI: N=0, false ✓
/// - LS: C=1, Z=0, so C=0|Z=1 = false ✓
/// - GT: Z=0 & N=V = 0 & (0=1) = false ✓
/// - GE: N=V = 0=1 = false ✓
fn fcmp_kind_to_cond(kind : FCmpKind) -> Int {
  match kind {
    FCmpKind::Eq => EQ.to_int()
    FCmpKind::Ne => NE.to_int()
    FCmpKind::Lt => MI.to_int() // Use MI for ordered less-than
    FCmpKind::Le => LS.to_int() // Use LS for ordered less-or-equal
    FCmpKind::Gt => GT.to_int()
    FCmpKind::Ge => GE.to_int()
  }
}

///|
/// Emit terminator with epilogue for Return
/// Handles multi-value returns:
/// - First 2 integer returns → X0, X1
/// - First 2 float returns → D0, D1
/// - Extra returns → written to buffer pointed by X23 (which was passed in X7)
fn emit_terminator_with_epilogue(
  mc : MachineCode,
  term : VCodeTerminator,
  clobbered : Array[Int],
  clobbered_fprs : Array[Int],
  clobbered_gpr_size : Int,
  frame_size : Int,
  result_types : Array[@ir.Type],
  needs_extra_results : Bool,
  calls_multi_value : Bool,
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
      // Two-phase approach is ONLY needed when there's potential for D/S clobbering:
      // - D_n and S_n share the same V_n register
      // - So mixing f32 and f64 returns can cause issues if source overlaps dest

      // First pass: collect sources for each return type
      let int_sources : Array[(Int, Int)] = [] // (src_reg, value_index)
      let float_sources : Array[(@ir.Type, Int, Int)] = [] // (type, src_reg, value_index)
      for i, value in values {
        let src = reg_num(value)
        let ty = if i < result_types.length() {
          result_types[i]
        } else {
          @ir.Type::I64
        }
        match ty {
          F32 | F64 => float_sources.push((ty, src, i))
          _ => int_sources.push((src, i))
        }
      }

      // Handle integer returns - need two-phase if sources conflict with destinations
      // Conflict occurs when source of return[i] is destination of return[j] for j < i
      // Example: swap(x0, x1) needs two-phase because ret[0]=x1, ret[1]=x0
      let int_need_two_phase = {
        let mut need = false
        for idx, entry in int_sources {
          let (src, _) = entry
          if idx < 2 {
            // Check if src will be overwritten by an earlier return
            for j in 0..<idx {
              if j == src {
                need = true
                break
              }
            }
          }
          if need {
            break
          }
        }
        need
      }
      let mut extra_offset = 0
      if int_need_two_phase {
        // Two-phase: save sources to temp registers first
        let temp_int_base = 10 // X10, X11 as temps
        for idx, entry in int_sources {
          let (src, _) = entry
          if idx < 2 {
            emit_mov_reg(mc, temp_int_base + idx, src)
          }
        }
        // Then move from temps to destinations
        for idx, entry in int_sources {
          let (_, _) = entry
          if idx < 2 {
            emit_mov_reg(mc, idx, temp_int_base + idx)
          } else {
            // For extra results, load from the temp if it was a register return
            let src = int_sources[idx].0
            emit_str_offset(mc, src, 23, extra_offset)
            extra_offset = extra_offset + 8
          }
        }
      } else {
        // Direct move: no conflict
        for idx, entry in int_sources {
          let (src, _) = entry
          if idx < 2 {
            if src != idx {
              emit_mov_reg(mc, idx, src)
            }
          } else {
            emit_str_offset(mc, src, 23, extra_offset)
            extra_offset = extra_offset + 8
          }
        }
      }

      // Check if we need two-phase for floats (only when mixing f32 and f64)
      let mut has_f32 = false
      let mut has_f64 = false
      for entry in float_sources {
        let (ty, _, _) = entry
        match ty {
          F32 => has_f32 = true
          _ => has_f64 = true
        }
      }
      let need_two_phase = has_f32 && has_f64 && float_sources.length() >= 2
      if need_two_phase {
        // Two-phase: copy to temps first, then to final registers
        let temp_float_base = 28
        for idx, entry in float_sources {
          let (ty, src, _) = entry
          let temp = temp_float_base + idx
          if src != temp {
            match ty {
              F32 => emit_fmov_s(mc, temp, src)
              _ => emit_fmov_d(mc, temp, src)
            }
          }
        }
        for idx, entry in float_sources {
          let (ty, _, _) = entry
          let temp = temp_float_base + idx
          if idx < 2 {
            if temp != idx {
              match ty {
                F32 => emit_fmov_s(mc, idx, temp)
                _ => emit_fmov_d(mc, idx, temp)
              }
            }
          } else {
            emit_str_d_offset(mc, temp, 23, extra_offset)
            extra_offset = extra_offset + 8
          }
        }
      } else {
        // Direct move: no conflict possible
        for idx, entry in float_sources {
          let (ty, src, _) = entry
          if idx < 2 {
            if src != idx {
              match ty {
                F32 => emit_fmov_s(mc, idx, src)
                _ => emit_fmov_d(mc, idx, src)
              }
            }
          } else {
            emit_str_d_offset(mc, src, 23, extra_offset)
            extra_offset = extra_offset + 8
          }
        }
      }
      // Emit epilogue to restore callee-saved registers before return
      emit_epilogue(
        mc, clobbered, clobbered_fprs, clobbered_gpr_size, frame_size, needs_extra_results,
        calls_multi_value,
      )
      emit_ret(mc, 30)
    }
    Trap(_) => mc.emit_inst(0, 0, 32, 212) // BRK #0 = 0xD4200000
    BrTable(index, targets, default) => {
      // Jump table implementation for br_table
      // 1. Check bounds: if index >= num_targets, branch to default
      // 2. Compute jump table entry address: base + index * 4
      // 3. Branch indirectly to that entry
      // 4. Jump table: sequence of B instructions
      let index_reg = reg_num(index)
      let num_targets = targets.length()
      // Use x16 and x17 as scratch registers (IP0 and IP1)
      // First, bounds check: CMP index, num_targets
      // Note: CMP immediate only supports 12-bit immediate (0-4095)
      // For larger values, we must load into a register and use CMP register
      if num_targets <= 4095 {
        emit_cmp_imm(mc, index_reg, num_targets)
      } else {
        // Load num_targets into x17 and compare
        emit_load_imm64(mc, 17, num_targets.to_int64())
        emit_cmp_reg(mc, index_reg, 17)
      }
      // B.HS default (condition code 2 = HS/CS = unsigned >=)
      emit_b_cond(mc, 2, default)
      // Layout after this point:
      //   ADR  at offset X    -> x16 = X + 12 (pointing to jump table)
      //   ADD  at offset X+4
      //   BR   at offset X+8
      //   B target[0] at offset X+12  <- jump table starts here
      emit_adr(mc, 16, 12)
      // ADD x16, x16, index, LSL #2 (each entry is 4 bytes)
      emit_add_shifted(mc, 16, 16, index_reg, Lsl, 2)
      // BR x16
      emit_br(mc, 16)
      // Emit jump table: sequence of B instructions
      for target in targets {
        emit_b(mc, target)
      }
    }
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
