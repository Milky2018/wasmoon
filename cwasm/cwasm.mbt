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
const CWASM_VERSION : Int = 1

// ============ Target Architecture ============

///|
/// Target architecture for compiled code
pub enum TargetArch {
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
/// Create AArch64 target
pub fn aarch64_target() -> TargetArch {
  AArch64
}

///|
/// Create x86_64 target
pub fn x86_64_target() -> TargetArch {
  X86_64
}

///|
pub impl Show for TargetArch with output(self, logger) {
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
}

///|
pub fn CompiledEntry::new(
  func_idx : Int,
  name : String,
  code : Array[Int],
  frame_size : Int,
  entry_offset : Int,
) -> CompiledEntry {
  { func_idx, name, code, frame_size, entry_offset }
}

///|
fn CompiledEntry::to_string(self : CompiledEntry) -> String {
  "CompiledEntry(idx=\{self.func_idx}, name=\"\{self.name}\", code=\{self.code.length()} bytes, frame=\{self.frame_size})"
}

///|
pub impl Show for CompiledEntry with output(self, logger) {
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
  // Compiled functions
  functions : Array[CompiledEntry]
}

///|
pub fn PrecompiledModule::new(target : TargetArch) -> PrecompiledModule {
  { version: CWASM_VERSION, target, functions: [] }
}

///|
/// Add a compiled function
pub fn PrecompiledModule::add_function(
  self : PrecompiledModule,
  func_idx : Int,
  name : String,
  compiled : @vcode.CompiledFunction,
) -> Unit {
  let entry = CompiledEntry::new(
    func_idx,
    name,
    compiled.get_code(),
    compiled.frame_size,
    compiled.entry_offset,
  )
  self.functions.push(entry)
}

///|
/// Get number of compiled functions
pub fn PrecompiledModule::function_count(self : PrecompiledModule) -> Int {
  self.functions.length()
}

///|
fn PrecompiledModule::to_string(self : PrecompiledModule) -> String {
  "PrecompiledModule(v\{self.version}, \{self.target}, \{self.functions.length()} functions)"
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
  for i in 0..<s.length() {
    // Simple ASCII encoding (for now)
    result.push(s[i] & 0xFF)
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
    functions.push(
      CompiledEntry::new(func_idx, name, code, frame_size, entry_offset),
    )
  }
  { version, target, functions }
}

// ============ Byte Reader ============

///|
/// Helper for reading bytes
struct ByteReader {
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
  for _ in 0..<len {
    let b = self.read_byte()
    // Simple ASCII decoding
    builder.write_char(b.unsafe_to_char())
  }
  builder.to_string()
}

// ============ Conversion to Runtime ============

///|
/// Convert a CompiledEntry to a runtime CompiledFunction
pub fn CompiledEntry::to_compiled_function(
  self : CompiledEntry,
) -> @vcode.CompiledFunction {
  let mc = @vcode.MachineCode::new()
  for b in self.code {
    mc.emit_byte(b)
  }
  @vcode.CompiledFunction::new(self.name, mc, self.frame_size)
}
