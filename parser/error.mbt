// Binary parser for WebAssembly modules
// Implements LEB128 decoding and section parsing

// ============================================================
// Parser Errors
// ============================================================

///|
suberror ParserError {
  UnexpectedEndOfInput
  UnexpectedEnd // For custom sections that are truncated
  LengthOutOfBounds // Section size exceeds available data
  InvalidMagicNumber
  UnsupportedVersion
  InvalidValueType(Int)
  LEB128TooLarge
  SectionSizeMismatch
  UnknownOpcode(Int)
  InvalidImportKind(Int)
  InvalidExportKind(Int)
  MalformedMemopFlags // alignment value too large
  TooManyLocals // local count exceeds reasonable limit
  MalformedSectionId(Int) // invalid section id
  MalformedLimitsFlags(Int) // invalid limits flags
  FunctionCodeMismatch // function and code section counts differ
  DataCountMismatch // data count and data section have inconsistent lengths
  UnexpectedContent // unexpected content after last section
  DuplicateSection(Int) // non-custom section appears multiple times or out of order
  MalformedReferenceType(Int) // element segment has non-reference type
  MalformedMutability(Int) // mutability must be 0 or 1
  MalformedDataSegmentFlags(Int) // data segment flags must be 0, 1, or 2
  DataCountRequired // memory.init/data.drop require data count section
  ParseError(String) // Generic error with message
}

// ============================================================
// Limits flags constants
// ============================================================

// Common flags

///|
const LIMITS_NO_MAX : Int = 0x00

///|
const LIMITS_HAS_MAX : Int = 0x01

// Memory-specific flags

///|
const LIMITS_SHARED : Int = 0x03 // shared, has max (memory only)

// 64-bit flags

///|
const LIMITS_64_NO_MAX : Int = 0x04

///|
const LIMITS_64_HAS_MAX : Int = 0x05

///|
const LIMITS_64_SHARED : Int = 0x07 // shared, has max, 64-bit (memory only)

///|
/// Convert int to hex string
fn int_to_hex(n : Int) -> String {
  @types.int_to_hex(n)
}

///|
/// Provide human-readable error messages for parser errors
pub impl Show for ParserError with output(self, logger) {
  let msg = match self {
    UnexpectedEndOfInput => "unexpected end of input"
    UnexpectedEnd => "unexpected end"
    LengthOutOfBounds => "length out of bounds"
    InvalidMagicNumber =>
      "invalid magic number (expected \\00asm, file may not be a valid WebAssembly module)"
    UnsupportedVersion => "unsupported WebAssembly version (expected version 1)"
    InvalidValueType(code) => {
      let type_hint = match code {
        0x7F => " (i32)"
        0x7E => " (i64)"
        0x7D => " (f32)"
        0x7C => " (f64)"
        0x70 => " (funcref)"
        0x6F => " (externref)"
        _ => ""
      }
      "invalid value type 0x\{int_to_hex(code)}\{type_hint}"
    }
    LEB128TooLarge => "LEB128 encoded integer is too large"
    SectionSizeMismatch =>
      "section size mismatch (declared size doesn't match actual content)"
    UnknownOpcode(opcode) =>
      "unknown opcode 0x\{int_to_hex(opcode)} at current position"
    InvalidImportKind(kind) => {
      let kind_hint = match kind {
        0 => " (expected: 0=func, 1=table, 2=memory, 3=global)"
        1 => " (table)"
        2 => " (memory)"
        3 => " (global)"
        4 => " (tag/exception - not yet supported)"
        _ => " (expected: 0=func, 1=table, 2=memory, 3=global)"
      }
      "invalid import kind \{kind}\{kind_hint}"
    }
    InvalidExportKind(kind) => {
      let kind_hint = match kind {
        0 => " (func)"
        1 => " (table)"
        2 => " (memory)"
        3 => " (global)"
        4 => " (tag/exception - not yet supported)"
        _ => " (expected: 0=func, 1=table, 2=memory, 3=global)"
      }
      "invalid export kind \{kind}\{kind_hint}"
    }
    MalformedMemopFlags => "malformed memop flags"
    TooManyLocals => "too many locals"
    MalformedSectionId(id) => "malformed section id: \{id}"
    MalformedLimitsFlags(flags) => "malformed limits flags: \{flags}"
    FunctionCodeMismatch =>
      "function and code section have inconsistent lengths"
    DataCountMismatch => "data count and data section have inconsistent lengths"
    UnexpectedContent => "unexpected content after last section"
    DuplicateSection(_) => "unexpected content after last section"
    MalformedReferenceType(_) => "malformed reference type"
    MalformedMutability(_) => "malformed mutability"
    MalformedDataSegmentFlags(flags) =>
      "malformed data segment flags: \{flags} (expected 0, 1, or 2)"
    DataCountRequired => "data count section required"
    ParseError(msg) => msg
  }
  logger.write_string(msg)
}
