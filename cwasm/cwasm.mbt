// Compiled WASM (.cwasm) Format
//
// This module provides:
// 1. Serialization of precompiled WASM modules
// 2. Deserialization for fast loading
// 3. Magic number and version validation
//
// Format overview:
// - Magic: 4 bytes (0x63, 0x77, 0x61, 0x73 = "cwas")
// - Version: 4 bytes (little-endian)
// - Target architecture: 1 byte
// - Number of compiled functions: 4 bytes (little-endian)
// - For each function:
//   - Function index: 4 bytes (little-endian)
//   - Name length: 4 bytes (little-endian)
//   - Name: variable bytes (UTF-8)
//   - Code size: 4 bytes (little-endian)
//   - Code bytes: variable
//   - Frame size: 4 bytes (little-endian)
//   - Entry offset: 4 bytes (little-endian)

// ============ Constants ============

///|
/// Magic bytes for .cwasm files: "cwas"
const CWASM_MAGIC_0 : Int = 0x63 // 'c'

///|
const CWASM_MAGIC_1 : Int = 0x77 // 'w'

///|
const CWASM_MAGIC_2 : Int = 0x61 // 'a'

///|
const CWASM_MAGIC_3 : Int = 0x73 // 's'

///|
/// Current format version
/// v1: Initial format
/// v2: Added num_params and num_results to function entries
/// v3: Added import table for WASI/external function support
/// v4: Added memory definitions and data segments
const CWASM_VERSION : Int = 4

// ============ Target Architecture ============

///|
/// Target architecture for compiled code
pub(all) enum TargetArch {
  Unknown
  X86_64
  AArch64
}

///|
fn TargetArch::to_byte(self : TargetArch) -> Int {
  match self {
    Unknown => 0
    X86_64 => 1
    AArch64 => 2
  }
}

///|
fn TargetArch::from_byte(b : Int) -> TargetArch {
  match b {
    1 => X86_64
    2 => AArch64
    _ => Unknown
  }
}

///|
fn TargetArch::to_string(self : TargetArch) -> String {
  match self {
    Unknown => "unknown"
    X86_64 => "x86_64"
    AArch64 => "aarch64"
  }
}

///|
pub impl Show for TargetArch with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Import Entry ============

///|
/// An imported function entry in the .cwasm file
pub(all) struct ImportEntry {
  // Module name (e.g., "wasi_snapshot_preview1")
  module_name : String
  // Function name (e.g., "fd_write")
  func_name : String
  // Number of parameters
  num_params : Int
  // Number of results (0 or 1)
  num_results : Int
}

///|
pub fn ImportEntry::new(
  module_name : String,
  func_name : String,
  num_params : Int,
  num_results : Int,
) -> ImportEntry {
  { module_name, func_name, num_params, num_results }
}

///|
fn ImportEntry::to_string(self : ImportEntry) -> String {
  "\{self.module_name}::\{self.func_name}(\{self.num_params}) -> \{self.num_results}"
}

///|
pub impl Show for ImportEntry with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Compiled Function Entry ============

///|
/// A compiled function entry in the .cwasm file
pub(all) struct CompiledEntry {
  // Function index in original module
  func_idx : Int
  // Function name (for debugging)
  name : String
  // Compiled machine code
  code : Array[Int]
  // Stack frame size
  frame_size : Int
  // Entry point offset within code
  entry_offset : Int
  // Number of parameters
  num_params : Int
  // Number of results (0 or 1 for WASM 1.0)
  num_results : Int
}

///|
pub fn CompiledEntry::new(
  func_idx : Int,
  name : String,
  code : Array[Int],
  frame_size : Int,
  entry_offset : Int,
  num_params : Int,
  num_results : Int,
) -> CompiledEntry {
  { func_idx, name, code, frame_size, entry_offset, num_params, num_results }
}

///|
fn CompiledEntry::to_string(self : CompiledEntry) -> String {
  "CompiledEntry(idx=\{self.func_idx}, name=\"\{self.name}\", code=\{self.code.length()} bytes, frame=\{self.frame_size})"
}

///|
pub impl Show for CompiledEntry with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Memory Definition ============

///|
/// Memory definition (min/max pages)
pub(all) struct MemoryDef {
  min_pages : Int
  max_pages : Int? // None means no maximum
}

///|
pub fn MemoryDef::new(min_pages : Int, max_pages : Int?) -> MemoryDef {
  { min_pages, max_pages }
}

///|
fn MemoryDef::to_string(self : MemoryDef) -> String {
  match self.max_pages {
    Some(max) => "Memory(\{self.min_pages}..\{max} pages)"
    None => "Memory(\{self.min_pages}+ pages)"
  }
}

///|
pub impl Show for MemoryDef with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Data Segment ============

///|
/// A data segment entry (active segments only, with evaluated offset)
pub(all) struct DataEntry {
  // Memory index (usually 0)
  memory_idx : Int
  // Offset in memory (evaluated from const expr)
  offset : Int
  // Data bytes
  data : Array[Int]
}

///|
pub fn DataEntry::new(
  memory_idx : Int,
  offset : Int,
  data : Array[Int],
) -> DataEntry {
  { memory_idx, offset, data }
}

///|
fn DataEntry::to_string(self : DataEntry) -> String {
  "Data(mem=\{self.memory_idx}, offset=\{self.offset}, \{self.data.length()} bytes)"
}

///|
pub impl Show for DataEntry with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Precompiled Module ============

///|
/// A precompiled WASM module
pub(all) struct PrecompiledModule {
  // Format version
  version : Int
  // Target architecture
  target : TargetArch
  // Imported functions
  imports : Array[ImportEntry]
  // Compiled functions
  functions : Array[CompiledEntry]
  // Memory definitions
  memories : Array[MemoryDef]
  // Data segments (with evaluated offsets)
  data_segments : Array[DataEntry]
}

///|
pub fn PrecompiledModule::new(target : TargetArch) -> PrecompiledModule {
  {
    version: CWASM_VERSION,
    target,
    imports: [],
    functions: [],
    memories: [],
    data_segments: [],
  }
}

///|
/// Add an imported function
pub fn PrecompiledModule::add_import(
  self : PrecompiledModule,
  module_name : String,
  func_name : String,
  num_params : Int,
  num_results : Int,
) -> Unit {
  self.imports.push(
    ImportEntry::new(module_name, func_name, num_params, num_results),
  )
}

///|
/// Add a compiled function
pub fn PrecompiledModule::add_function(
  self : PrecompiledModule,
  func_idx : Int,
  name : String,
  compiled : @vcode.CompiledFunction,
  num_params : Int,
  num_results : Int,
) -> Unit {
  let entry = CompiledEntry::new(
    func_idx,
    name,
    compiled.get_code(),
    compiled.frame_size,
    compiled.entry_offset,
    num_params,
    num_results,
  )
  self.functions.push(entry)
}

///|
/// Add a memory definition
pub fn PrecompiledModule::add_memory(
  self : PrecompiledModule,
  min_pages : Int,
  max_pages : Int?,
) -> Unit {
  self.memories.push(MemoryDef::new(min_pages, max_pages))
}

///|
/// Add a data segment
pub fn PrecompiledModule::add_data_segment(
  self : PrecompiledModule,
  memory_idx : Int,
  offset : Int,
  data : Array[Int],
) -> Unit {
  self.data_segments.push(DataEntry::new(memory_idx, offset, data))
}

///|
/// Get number of imports
pub fn PrecompiledModule::import_count(self : PrecompiledModule) -> Int {
  self.imports.length()
}

///|
/// Get number of compiled functions
pub fn PrecompiledModule::function_count(self : PrecompiledModule) -> Int {
  self.functions.length()
}

///|
fn PrecompiledModule::to_string(self : PrecompiledModule) -> String {
  "PrecompiledModule(v\{self.version}, \{self.target}, \{self.imports.length()} imports, \{self.functions.length()} functions, \{self.memories.length()} memories, \{self.data_segments.length()} data segments)"
}

///|
pub impl Show for PrecompiledModule with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Serialization ============

///|
/// Serialize a precompiled module to bytes
pub fn PrecompiledModule::serialize(self : PrecompiledModule) -> Array[Int] {
  let result : Array[Int] = []

  // Write magic number
  result.push(CWASM_MAGIC_0)
  result.push(CWASM_MAGIC_1)
  result.push(CWASM_MAGIC_2)
  result.push(CWASM_MAGIC_3)

  // Write version (little-endian u32)
  write_u32(result, self.version)

  // Write target architecture
  result.push(self.target.to_byte())

  // Write number of imports
  write_u32(result, self.imports.length())

  // Write each import
  for imp in self.imports {
    // Module name
    let module_bytes = string_to_bytes(imp.module_name)
    write_u32(result, module_bytes.length())
    for b in module_bytes {
      result.push(b)
    }

    // Function name
    let func_bytes = string_to_bytes(imp.func_name)
    write_u32(result, func_bytes.length())
    for b in func_bytes {
      result.push(b)
    }

    // Signature
    write_u32(result, imp.num_params)
    write_u32(result, imp.num_results)
  }

  // Write number of functions
  write_u32(result, self.functions.length())

  // Write each function
  for entry in self.functions {
    // Function index
    write_u32(result, entry.func_idx)

    // Name length and bytes
    let name_bytes = string_to_bytes(entry.name)
    write_u32(result, name_bytes.length())
    for b in name_bytes {
      result.push(b)
    }

    // Code size and bytes
    write_u32(result, entry.code.length())
    for b in entry.code {
      result.push(b)
    }

    // Frame size
    write_u32(result, entry.frame_size)

    // Entry offset
    write_u32(result, entry.entry_offset)

    // Function signature: num_params and num_results
    write_u32(result, entry.num_params)
    write_u32(result, entry.num_results)
  }

  // Write number of memories
  write_u32(result, self.memories.length())

  // Write each memory
  for mem in self.memories {
    write_u32(result, mem.min_pages)
    // Write max_pages: -1 for None, otherwise the value
    match mem.max_pages {
      Some(max) => write_u32(result, max)
      None => write_u32(result, -1)
    }
  }

  // Write number of data segments
  write_u32(result, self.data_segments.length())

  // Write each data segment
  for data in self.data_segments {
    write_u32(result, data.memory_idx)
    write_u32(result, data.offset)
    write_u32(result, data.data.length())
    for b in data.data {
      result.push(b)
    }
  }
  result
}

///|
/// Write a u32 in little-endian format
fn write_u32(buf : Array[Int], val : Int) -> Unit {
  buf.push(val & 0xFF)
  buf.push((val >> 8) & 0xFF)
  buf.push((val >> 16) & 0xFF)
  buf.push((val >> 24) & 0xFF)
}

///|
/// Convert string to UTF-8 bytes
fn string_to_bytes(s : String) -> Array[Int] {
  let result : Array[Int] = []
  let len = s.length()
  let mut i = 0
  while i < len {
    let c = s.code_unit_at(i).to_int()
    if c < 0x80 {
      // ASCII
      result.push(c)
      i += 1
    } else if c < 0x800 {
      // 2-byte UTF-8
      result.push(0xC0 | (c >> 6))
      result.push(0x80 | (c & 0x3F))
      i += 1
    } else if c >= 0xD800 && c <= 0xDBFF && i + 1 < len {
      // Surrogate pair - decode to full codepoint
      let c2 = s.code_unit_at(i + 1).to_int()
      if c2 >= 0xDC00 && c2 <= 0xDFFF {
        let codepoint = 0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00)
        result.push(0xF0 | (codepoint >> 18))
        result.push(0x80 | ((codepoint >> 12) & 0x3F))
        result.push(0x80 | ((codepoint >> 6) & 0x3F))
        result.push(0x80 | (codepoint & 0x3F))
        i += 2 // Skip both surrogates
      } else {
        // Invalid surrogate, encode as replacement char
        result.push(0xEF)
        result.push(0xBF)
        result.push(0xBD)
        i += 1
      }
    } else if c >= 0xDC00 && c <= 0xDFFF {
      // Orphan low surrogate, encode as replacement char
      result.push(0xEF)
      result.push(0xBF)
      result.push(0xBD)
      i += 1
    } else {
      // 3-byte UTF-8 (BMP character)
      result.push(0xE0 | (c >> 12))
      result.push(0x80 | ((c >> 6) & 0x3F))
      result.push(0x80 | (c & 0x3F))
      i += 1
    }
  }
  result
}

// ============ Deserialization ============

///|
/// Error during deserialization
pub suberror DeserializeError String

///|
pub impl Show for DeserializeError with output(self, logger) {
  match self {
    DeserializeError(msg) => logger.write_string(msg)
  }
}

///|
/// Deserialize a precompiled module from bytes
pub fn deserialize(
  bytes : Array[Int],
) -> PrecompiledModule raise DeserializeError {
  let reader = ByteReader::new(bytes)

  // Verify magic number
  let magic = [CWASM_MAGIC_0, CWASM_MAGIC_1, CWASM_MAGIC_2, CWASM_MAGIC_3]
  for i in 0..<4 {
    let b = reader.read_byte()
    if b != magic[i] {
      raise DeserializeError("Invalid magic number")
    }
  }

  // Read version
  let version = reader.read_u32()
  if version != CWASM_VERSION {
    raise DeserializeError("Unsupported version: \{version}")
  }

  // Read target architecture
  let target = TargetArch::from_byte(reader.read_byte())

  // Read imports
  let imports : Array[ImportEntry] = []
  let import_count = reader.read_u32()
  for _ in 0..<import_count {
    // Module name
    let module_name_len = reader.read_u32()
    let module_name = reader.read_string(module_name_len)

    // Function name
    let func_name_len = reader.read_u32()
    let func_name = reader.read_string(func_name_len)

    // Signature
    let num_params = reader.read_u32()
    let num_results = reader.read_u32()
    imports.push(
      ImportEntry::new(module_name, func_name, num_params, num_results),
    )
  }

  // Read number of functions
  let func_count = reader.read_u32()

  // Read functions
  let functions : Array[CompiledEntry] = []
  for _ in 0..<func_count {
    // Function index
    let func_idx = reader.read_u32()

    // Name
    let name_len = reader.read_u32()
    let name = reader.read_string(name_len)

    // Code
    let code_size = reader.read_u32()
    let code = reader.read_bytes(code_size)

    // Frame size
    let frame_size = reader.read_u32()

    // Entry offset
    let entry_offset = reader.read_u32()

    // Function signature
    let num_params = reader.read_u32()
    let num_results = reader.read_u32()
    functions.push(
      CompiledEntry::new(
        func_idx, name, code, frame_size, entry_offset, num_params, num_results,
      ),
    )
  }

  // Read memories
  let memories : Array[MemoryDef] = []
  let mem_count = reader.read_u32()
  for _ in 0..<mem_count {
    let min_pages = reader.read_u32()
    let max_raw = reader.read_u32()
    let max_pages : Int? = if max_raw == -1 { None } else { Some(max_raw) }
    memories.push(MemoryDef::new(min_pages, max_pages))
  }

  // Read data segments
  let data_segments : Array[DataEntry] = []
  let data_count = reader.read_u32()
  for _ in 0..<data_count {
    let memory_idx = reader.read_u32()
    let offset = reader.read_u32()
    let data_len = reader.read_u32()
    let data = reader.read_bytes(data_len)
    data_segments.push(DataEntry::new(memory_idx, offset, data))
  }
  {
    version: CWASM_VERSION,
    target,
    imports,
    functions,
    memories,
    data_segments,
  }
}

// ============ Byte Reader ============

///|
/// Helper for reading bytes
priv struct ByteReader {
  bytes : Array[Int]
  mut pos : Int
}

///|
fn ByteReader::new(bytes : Array[Int]) -> ByteReader {
  { bytes, pos: 0 }
}

///|
fn ByteReader::read_byte(self : ByteReader) -> Int {
  if self.pos >= self.bytes.length() {
    0
  } else {
    let b = self.bytes[self.pos]
    self.pos = self.pos + 1
    b
  }
}

///|
fn ByteReader::read_u32(self : ByteReader) -> Int {
  let b0 = self.read_byte()
  let b1 = self.read_byte()
  let b2 = self.read_byte()
  let b3 = self.read_byte()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
fn ByteReader::read_bytes(self : ByteReader, count : Int) -> Array[Int] {
  let result : Array[Int] = []
  for _ in 0..<count {
    result.push(self.read_byte())
  }
  result
}

///|
fn ByteReader::read_string(self : ByteReader, len : Int) -> String {
  let builder = StringBuilder::new()
  let end_pos = self.pos + len
  while self.pos < end_pos {
    let b1 = self.read_byte()
    if b1 < 0x80 {
      // ASCII
      builder.write_char(b1.unsafe_to_char())
    } else if b1 < 0xE0 {
      // 2-byte UTF-8
      let b2 = self.read_byte()
      let codepoint = ((b1 & 0x1F) << 6) | (b2 & 0x3F)
      builder.write_char(codepoint.unsafe_to_char())
    } else if b1 < 0xF0 {
      // 3-byte UTF-8
      let b2 = self.read_byte()
      let b3 = self.read_byte()
      let codepoint = ((b1 & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
      builder.write_char(codepoint.unsafe_to_char())
    } else {
      // 4-byte UTF-8 (supplementary plane)
      let b2 = self.read_byte()
      let b3 = self.read_byte()
      let b4 = self.read_byte()
      let codepoint = ((b1 & 0x07) << 18) |
        ((b2 & 0x3F) << 12) |
        ((b3 & 0x3F) << 6) |
        (b4 & 0x3F)
      // Encode as surrogate pair for JavaScript string
      let adjusted = codepoint - 0x10000
      let high = 0xD800 + (adjusted >> 10)
      let low = 0xDC00 + (adjusted & 0x3FF)
      builder.write_char(high.unsafe_to_char())
      builder.write_char(low.unsafe_to_char())
    }
  }
  builder.to_string()
}

// ============ Conversion to Runtime ============

///|
/// Convert a CompiledEntry to a runtime CompiledFunction
pub fn CompiledEntry::to_compiled_function(
  self : CompiledEntry,
) -> @vcode.CompiledFunction {
  let mc = @emit.MachineCode::new()
  for b in self.code {
    mc.emit_byte(b)
  }
  @vcode.CompiledFunction::new(self.name, mc, self.frame_size)
}
