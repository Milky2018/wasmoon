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
pub struct MachineCode {
  bytes : Array[Int] // Using Int for bytes (0-255)
  mut pos : Int
  // Labels for branch targets
  labels : Map[Int, Int] // block_id -> offset
  // Pending fixups for forward branches
  fixups : Array[Fixup]
  // Pending fixups for direct function addresses (offset -> func_idx)
  func_addr_fixups : Array[FuncAddrFixup]
  // Pending fixups for direct function calls (offset -> func_idx)
  call_fixups : Array[CallFixup]
  // Disassembly annotations (offset -> instruction text)
  disasm : Array[(Int, String)]
}

///|
/// A fixup for a forward branch
struct Fixup {
  // Offset in the code buffer where the fixup is needed
  offset : Int
  // Target block id
  target_block : Int
  // Kind of fixup
  kind : FixupKind
}

///|
/// Fixup for direct function address loads
pub(all) struct FuncAddrFixup {
  // Offset in the code buffer where the load starts
  offset : Int
  // Target function index
  func_idx : Int
  // Destination register (physical)
  reg : Int
}

///|
/// Fixup for direct function call branches
pub(all) struct CallFixup {
  // Offset in the code buffer where the call instruction starts
  offset : Int
  // Target function index
  func_idx : Int
}

///|
/// Kind of fixup
pub(all) enum FixupKind {
  Branch26 // 26-bit PC-relative branch (B, BL)
  Branch19 // 19-bit PC-relative branch (B.cond, CBZ, CBNZ)
}

///|
pub fn MachineCode::new() -> MachineCode {
  {
    bytes: [],
    pos: 0,
    labels: {},
    fixups: [],
    func_addr_fixups: [],
    call_fixups: [],
    disasm: [],
  }
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
/// Emit a direct BL with a runtime fixup to a function index.
pub fn MachineCode::emit_bl_func(self : MachineCode, func_idx : Int) -> Unit {
  let offset = self.current_pos()
  self.annotate("bl func_\{func_idx}")
  // BL with imm=0; patched later using CallFixup.
  self.emit_inst(0, 0, 0, 148)
  self.add_call_fixup(offset, func_idx)
}

///|
/// Current position in the buffer
pub fn MachineCode::current_pos(self : MachineCode) -> Int {
  self.pos
}

///|
/// Add a disassembly annotation at the current position
pub fn MachineCode::annotate(self : MachineCode, text : String) -> Unit {
  self.disasm.push((self.pos, text))
}

///|
/// Dump disassembly with hex bytes
pub fn MachineCode::dump_disasm(self : MachineCode) -> String {
  let mut result = ""
  let max_offset = if self.pos > 0 { self.pos - 1 } else { 0 }
  let width = if max_offset <= 0xFFFF {
    4
  } else if max_offset <= 0xFFFFFF {
    6
  } else {
    8
  }
  // Build a map of offset -> labels (multiple blocks can share same offset)
  let label_map : Map[Int, Array[Int]] = {}
  for entry in self.labels {
    let (block_id, offset) = entry
    match label_map.get(offset) {
      Some(ids) => ids.push(block_id)
      None => label_map.set(offset, [block_id])
    }
  }
  // Sort disasm by offset
  let sorted = self.disasm.copy()
  sorted.sort_by(fn(a, b) { a.0.compare(b.0) })
  for entry in sorted {
    let (offset, text) = entry
    // Check if there are labels at this offset
    if label_map.get(offset) is Some(block_ids) {
      for block_id in block_ids {
        result = result + "block\{block_id}:\n"
      }
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
    result = result + "  \{to_hex_offset(offset, width)}: \{hex}  \{text}\n"
  }
  result
}

///|
fn hex2(n : Int) -> String {
  @types.to_hex_byte(n)
}

///|
fn to_hex_offset(n : Int, width : Int) -> String {
  let hex = @types.int_to_hex(n)
  if hex.length() >= width {
    hex
  } else {
    "0".repeat(width - hex.length()) + hex
  }
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
/// Add a fixup for a direct function address load
pub fn MachineCode::add_func_addr_fixup(
  self : MachineCode,
  offset : Int,
  func_idx : Int,
  reg : Int,
) -> Unit {
  self.func_addr_fixups.push({ offset, func_idx, reg })
}

///|
/// Add a fixup for a direct function call
pub fn MachineCode::add_call_fixup(
  self : MachineCode,
  offset : Int,
  func_idx : Int,
) -> Unit {
  self.call_fixups.push({ offset, func_idx })
}

///|
/// Resolve all pending fixups
pub fn MachineCode::resolve_fixups(self : MachineCode) -> Unit {
  for fixup in self.fixups {
    if self.labels.get(fixup.target_block) is Some(target_offset) {
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
      } // imm19 high bits already covered
    }
  }
}

///|
/// Get the generated bytes
pub fn MachineCode::get_bytes(self : MachineCode) -> Array[Int] {
  self.bytes
}

///|
/// Get direct function address fixups
pub fn MachineCode::get_func_addr_fixups(
  self : MachineCode,
) -> Array[FuncAddrFixup] {
  self.func_addr_fixups
}

///|
/// Get direct function call fixups
pub fn MachineCode::get_call_fixups(self : MachineCode) -> Array[CallFixup] {
  self.call_fixups
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
  // Use AlignTo instruction to emit NOPs until aligned
  AlignTo(alignment).emit(self)
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
