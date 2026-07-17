// Machine-code byte and relocation container used by legacy AMD64 emission and
// target-pipeline integration.

// ============ Machine Code Buffer ============

///|
const STACKMAP_I32_MAX : Int = 0x7FFFFFFF

///|
/// A buffer for accumulating machine code bytes
pub struct MachineCode {
  isa : @isa.ISA
  bytes : Array[Int] // Using Int for bytes (0-255)
  mut pos : Int
  // Labels for branch targets
  labels : Map[Int, Int] // block_id -> offset
  // Internal labels are always negative and do not overlap with block ids.
  mut next_internal_label : Int
  // Pending x86_64 rel32 fixups for forward branches (disp32 patched at end).
  x86_rel32_fixups : Array[X86Rel32Fixup]
  // Pending fixups for direct function addresses (offset -> func_idx)
  func_addr_fixups : Array[FuncAddrFixup]
  // Pending fixups for direct function calls (offset -> func_idx)
  call_fixups : Array[CallFixup]
  // Offsets of allocation slow-path GC safepoints.
  gc_safepoint_offsets : Array[Int]
  // Root slot counts for each recorded GC safepoint.
  gc_safepoint_root_counts : Array[Int]
  // Root slot indices for each recorded GC safepoint.
  gc_safepoint_root_indices : Array[Array[Int]]
  // Deduplicated amd64 constant-pool entries (key -> label).
  amd64_const_labels : Map[String, Int]
  // Pending amd64 constant-pool bytes to emit at end of function.
  amd64_const_entries : Array[Amd64ConstEntry]
  // Disassembly annotations (offset -> instruction text)
  disasm : Array[(Int, String)]
  // Whether to record disassembly annotations during emission.
  record_disasm : Bool
  // Stack spill-slot offset (from SP) used to stash caller active function index.
  // -1 means disabled for this function.
  mut debug_prev_func_idx_spill_offset : Int
}

///|
struct Amd64ConstEntry {
  label : Int
  align : Int
  data : Bytes
}

///|
/// x86_64 rel32 fixup for forward branches (jmp/jcc rel32).
///
/// `disp_offset` is the start of the 4-byte displacement field.
/// `next_ip_offset` is the offset of the instruction end (RIP after the branch).
struct X86Rel32Fixup {
  disp_offset : Int
  next_ip_offset : Int
  target_block : Int
}

///|
/// Fixup for direct function address loads
pub(all) struct FuncAddrFixup {
  // Offset in the code buffer where the load starts
  offset : Int
  // Target function or external symbol
  target : @instr.RelocTarget
  // Destination register (physical)
  reg : Int
} derive(Eq, Debug)

///|
/// Fixup for direct function call branches
pub(all) struct CallFixup {
  // Offset in the code buffer where the call instruction starts
  offset : Int
  // Target function or external symbol
  target : @instr.RelocTarget
  // Offset of a local call veneer (load-absolute + br), -1 when absent
  veneer_offset : Int
} derive(Eq, Debug)

///|
pub fn MachineCode::MachineCode(
  isa? : @isa.ISA = AMD64,
  record_disasm? : Bool = true,
) -> MachineCode {
  {
    isa,
    bytes: [],
    pos: 0,
    labels: Map([]),
    next_internal_label: -1,
    x86_rel32_fixups: [],
    func_addr_fixups: [],
    call_fixups: [],
    gc_safepoint_offsets: [],
    gc_safepoint_root_counts: [],
    gc_safepoint_root_indices: [],
    amd64_const_labels: Map([]),
    amd64_const_entries: [],
    disasm: [],
    record_disasm,
    debug_prev_func_idx_spill_offset: -1,
  }
}

///|
pub fn MachineCode::set_debug_prev_func_idx_spill_offset(
  self : MachineCode,
  offset : Int,
) -> Unit {
  self.debug_prev_func_idx_spill_offset = offset
}

///|
pub fn MachineCode::new_internal_label(self : MachineCode) -> Int {
  let l = self.next_internal_label
  self.next_internal_label = self.next_internal_label - 1
  l
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
pub fn MachineCode::current_pos(self : MachineCode) -> Int {
  self.pos
}

///|
/// Add a disassembly annotation at the current position
pub fn MachineCode::annotate(self : MachineCode, text : String) -> Unit {
  if self.record_disasm {
    self.disasm.push((self.pos, text))
  }
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
  let label_map : Map[Int, Array[Int]] = Map([])
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
  let hi = (n >> 4) & 0xF
  let lo = n & 0xF
  let hi_c = if hi < 10 {
    (hi + 48).unsafe_to_char()
  } else {
    (hi - 10 + 97).unsafe_to_char()
  }
  let lo_c = if lo < 10 {
    (lo + 48).unsafe_to_char()
  } else {
    (lo - 10 + 97).unsafe_to_char()
  }
  hi_c.to_string() + lo_c.to_string()
}

///|
fn to_hex_offset(n : Int, width : Int) -> String {
  let hex = int_to_hex(n)
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
/// Add an x86_64 rel32 fixup for a forward branch.
pub fn MachineCode::add_x86_rel32_fixup(
  self : MachineCode,
  target_block : Int,
  disp_offset : Int,
  next_ip_offset : Int,
) -> Unit {
  self.x86_rel32_fixups.push({ disp_offset, next_ip_offset, target_block })
}

///|
/// Add a fixup for an embedding-owned code address load.
pub fn MachineCode::add_code_addr_fixup(
  self : MachineCode,
  offset : Int,
  symbol : @instr.CodeSymbol,
  reg : Int,
) -> Unit {
  self.add_func_addr_target_fixup(offset, Code(symbol), reg)
}

///|
/// Add a fixup for a relocatable function address load.
pub fn MachineCode::add_func_addr_target_fixup(
  self : MachineCode,
  offset : Int,
  target : @instr.RelocTarget,
  reg : Int,
) -> Unit {
  self.func_addr_fixups.push({ offset, target, reg })
}

///|
/// Add a fixup for an external function address load.
pub fn MachineCode::add_external_func_addr_fixup(
  self : MachineCode,
  offset : Int,
  symbol : @instr.ExternalName,
  reg : Int,
) -> Unit {
  self.add_func_addr_target_fixup(offset, External(symbol), reg)
}

///|
/// Add a fixup for a direct call to an embedding-owned code symbol.
pub fn MachineCode::add_call_fixup(
  self : MachineCode,
  offset : Int,
  symbol : @instr.CodeSymbol,
  veneer_offset? : Int = -1,
) -> Unit {
  self.add_call_target_fixup(offset, Code(symbol), veneer_offset~)
}

///|
/// Add a fixup for a relocatable direct call.
pub fn MachineCode::add_call_target_fixup(
  self : MachineCode,
  offset : Int,
  target : @instr.RelocTarget,
  veneer_offset? : Int = -1,
) -> Unit {
  self.call_fixups.push({ offset, target, veneer_offset })
}

///|
/// Add a fixup for a direct call to an external symbol.
pub fn MachineCode::add_external_call_fixup(
  self : MachineCode,
  offset : Int,
  symbol : @instr.ExternalName,
  veneer_offset? : Int = -1,
) -> Unit {
  self.add_call_target_fixup(offset, External(symbol), veneer_offset~)
}

///|
/// Record a GC safepoint at current code offset.
pub fn MachineCode::record_gc_safepoint(
  self : MachineCode,
  offset : Int,
  root_count? : Int = 0,
  root_indices? : Array[Int] = [],
) -> Int {
  let sanitized_indices : Array[Int] = []
  for idx in root_indices {
    if idx >= 0 && idx <= STACKMAP_I32_MAX {
      sanitized_indices.push(idx)
    }
  }
  let resolved_root_count = if root_count > 0 {
    root_count
  } else if sanitized_indices.length() > 0 {
    sanitized_indices.length()
  } else {
    0
  }
  self.gc_safepoint_offsets.push(offset)
  self.gc_safepoint_root_counts.push(resolved_root_count)
  self.gc_safepoint_root_indices.push(sanitized_indices)
  self.gc_safepoint_offsets.length() - 1
}

///|
pub fn MachineCode::resolve_fixups(self : MachineCode) -> Unit {
  // x86_64 rel32 fixups (byte offsets).
  for fixup in self.x86_rel32_fixups {
    if self.labels.get(fixup.target_block) is Some(target_offset) {
      let disp = target_offset - fixup.next_ip_offset
      // Patch little-endian disp32.
      let disp32 = disp & 0xFFFFFFFF
      self.bytes[fixup.disp_offset] = disp32 & 255
      self.bytes[fixup.disp_offset + 1] = (disp32 >> 8) & 255
      self.bytes[fixup.disp_offset + 2] = (disp32 >> 16) & 255
      self.bytes[fixup.disp_offset + 3] = (disp32 >> 24) & 255
    }
  }
}

///|
fn amd64_const_key(bytes : Bytes, align : Int) -> String {
  let mut key = "\{align}:"
  for b in bytes {
    key = key + hex2(b.to_int())
  }
  key
}

///|
pub fn MachineCode::intern_amd64_const(
  self : MachineCode,
  data : Bytes,
  align : Int,
) -> Int {
  let key = amd64_const_key(data, align)
  if self.amd64_const_labels.get(key) is Some(label) {
    return label
  }
  let label = self.new_internal_label()
  self.amd64_const_labels.set(key, label)
  self.amd64_const_entries.push({ label, align, data })
  label
}

///|
pub fn MachineCode::intern_amd64_const_f32(
  self : MachineCode,
  bits : Int,
) -> Int {
  let data = Bytes::from_array([
    (bits & 0xFF).to_byte(),
    ((bits >> 8) & 0xFF).to_byte(),
    ((bits >> 16) & 0xFF).to_byte(),
    ((bits >> 24) & 0xFF).to_byte(),
  ])
  self.intern_amd64_const(data, 4)
}

///|
pub fn MachineCode::intern_amd64_const_f64(
  self : MachineCode,
  bits : Int64,
) -> Int {
  let data = Bytes::makei(8, fn(i) { ((bits >> (i * 8)) & 0xFFL).to_byte() })
  self.intern_amd64_const(data, 8)
}

///|
pub fn MachineCode::emit_amd64_const_pool(self : MachineCode) -> Unit {
  if self.amd64_const_entries.length() == 0 {
    return
  }
  while self.pos % 16 != 0 {
    self.emit_byte(0x90)
  }
  for entry in self.amd64_const_entries {
    guard entry.align > 0 else { continue }
    while self.pos % entry.align != 0 {
      self.emit_byte(0x90)
    }
    self.define_label(entry.label)
    for b in entry.data {
      self.emit_byte(b.to_int())
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
/// Get recorded GC safepoint offsets.
pub fn MachineCode::get_gc_safepoint_offsets(self : MachineCode) -> Array[Int] {
  self.gc_safepoint_offsets
}

///|
/// Get recorded GC safepoint root counts.
pub fn MachineCode::get_gc_safepoint_root_counts(
  self : MachineCode,
) -> Array[Int] {
  self.gc_safepoint_root_counts
}

///|
/// Get recorded GC safepoint root indices.
pub fn MachineCode::get_gc_safepoint_root_indices(
  self : MachineCode,
) -> Array[Array[Int]] {
  self.gc_safepoint_root_indices
}

///|
/// Get size in bytes
pub fn MachineCode::size(self : MachineCode) -> Int {
  self.pos
}

///|
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
