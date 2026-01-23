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

// ============================================================
// Parser State
// ============================================================

///|
struct Parser {
  data : Bytes
  mut pos : Int
  mut has_data_count : Bool // true if data count section was seen
  types : Array[@types.SubType]
} derive(Show)

///|
/// Create a new parser from bytes
pub fn Parser::new(data : Bytes) -> Parser {
  { data, pos: 0, has_data_count: false, types: [] }
}

///|
/// Check if at end of input
fn Parser::is_eof(self : Parser) -> Bool {
  self.pos >= self.data.length()
}

///|
/// Peek at the next byte without consuming
fn Parser::peek_byte(self : Parser) -> Int raise ParserError {
  if self.is_eof() {
    raise UnexpectedEndOfInput
  }
  self.data[self.pos].to_int()
}

///|
/// Consume and return the next byte
fn Parser::read_byte(self : Parser) -> Int raise ParserError {
  if self.is_eof() {
    raise UnexpectedEndOfInput
  }
  let byte = self.data[self.pos].to_int()
  self.pos += 1
  byte
}

///|
/// Skip n bytes
fn Parser::skip(self : Parser, n : Int) -> Unit raise ParserError {
  if self.pos + n > self.data.length() {
    raise UnexpectedEndOfInput
  }
  self.pos += n
}

///|
/// Read n bytes
fn Parser::read_bytes(self : Parser, n : Int) -> Bytes raise ParserError {
  if self.pos + n > self.data.length() {
    raise UnexpectedEndOfInput
  }
  let bytes = loop ([], 0) {
    (acc, i) =>
      if i >= n {
        acc
      } else {
        acc.push(self.data[self.pos + i])
        continue (acc, i + 1)
      }
  }
  self.pos += n
  Bytes::from_array(bytes)
}

// ============================================================
// LEB128 Decoding
// ============================================================

///|
/// Decode unsigned LEB128
fn Parser::read_leb128_u32(self : Parser) -> Int raise ParserError {
  loop (0, 0) {
    (result, shift) => {
      if shift > 28 {
        raise LEB128TooLarge
      }
      let byte = self.read_byte()
      // For the 5th byte (shift=28), only lower 4 bits can be used for u32
      // If the value is >= 16 (0x10), it would overflow u32
      if shift == 28 && (byte & 0x7F) > 0x0F {
        raise LEB128TooLarge
      }
      let new_result = result | ((byte & 0x7F) << shift)
      if (byte & 0x80) == 0 {
        new_result
      } else {
        continue (new_result, shift + 7)
      }
    }
  }
}

///|
/// Decode signed LEB128
fn Parser::read_leb128_i32(self : Parser) -> Int raise ParserError {
  loop (0, 0) {
    (result, shift) => {
      if shift > 28 {
        raise LEB128TooLarge
      }
      let byte = self.read_byte()
      // For the 5th byte (shift=28), validate sign extension
      // Bits 4-6 must be sign-extended from bit 3
      if shift == 28 {
        let sign_bit = (byte & 0x08) != 0 // bit 3 is sign
        let upper_bits = byte & 0x70 // bits 4-6 must be sign-extended
        if sign_bit {
          // Negative: bits 4-6 must all be 1 (0x70)
          if upper_bits != 0x70 {
            raise LEB128TooLarge
          }
          // Non-negative: bits 4-6 must all be 0 (0x00)
        } else if upper_bits != 0x00 {
          raise LEB128TooLarge
        }
        // Also, 5th byte cannot have continuation bit
        if (byte & 0x80) != 0 {
          raise LEB128TooLarge
        }
      }
      let new_result = result | ((byte & 0x7F) << shift)
      let new_shift = shift + 7
      if (byte & 0x80) == 0 {
        // Sign extend if needed
        if new_shift < 32 && (byte & 0x40) != 0 {
          new_result | (-1 << new_shift)
        } else {
          new_result
        }
      } else {
        continue (new_result, new_shift)
      }
    }
  }
}

///|
/// Decode signed LEB128 i64
fn Parser::read_leb128_i64(self : Parser) -> Int64 raise ParserError {
  loop (0L, 0) {
    (result, shift) => {
      if shift > 63 {
        raise LEB128TooLarge
      }
      let byte = self.read_byte()
      // For the 10th byte (shift=63), validate sign extension
      // Only bit 0 is used for value (bit 63), bits 1-6 must be sign-extended from bit 0
      if shift == 63 {
        let sign_bit = (byte & 0x01) != 0 // bit 0 is sign (bit 63 of i64)
        let upper_bits = byte & 0x7E // bits 1-6 must be sign-extended
        if sign_bit {
          // Negative: bits 1-6 must all be 1 (0x7E)
          if upper_bits != 0x7E {
            raise LEB128TooLarge
          }
          // Non-negative: bits 1-6 must all be 0 (0x00)
        } else if upper_bits != 0x00 {
          raise LEB128TooLarge
        }
        // Also, 10th byte cannot have continuation bit
        if (byte & 0x80) != 0 {
          raise LEB128TooLarge
        }
      }
      let new_result = result | (byte.land(0x7F).to_int64() << shift)
      let new_shift = shift + 7
      if (byte & 0x80) == 0 {
        // Sign extend if needed
        if new_shift < 64 && (byte & 0x40) != 0 {
          new_result | (-1L << new_shift)
        } else {
          new_result
        }
      } else {
        continue (new_result, new_shift)
      }
    }
  }
}

///|
/// Decode unsigned LEB128 u64
fn Parser::read_leb128_u64(self : Parser) -> Int64 raise ParserError {
  loop (0L, 0) {
    (result, shift) => {
      if shift > 63 {
        raise LEB128TooLarge
      }
      let byte = self.read_byte()
      // For the 10th byte (shift=63), only bit 0 can be used for u64
      // If any other bit is set, it would overflow u64
      if shift == 63 && (byte & 0x7E) != 0 {
        raise LEB128TooLarge
      }
      let new_result = result | (byte.land(0x7F).to_int64() << shift)
      if (byte & 0x80) == 0 {
        new_result
      } else {
        continue (new_result, shift + 7)
      }
    }
  }
}

// ============================================================
// Basic Type Parsing
// ============================================================

///|
/// Read a u32
fn Parser::read_u32(self : Parser) -> Int raise ParserError {
  self.read_leb128_u32()
}

///|
/// Read a u64
fn Parser::read_u64(self : Parser) -> Int64 raise ParserError {
  self.read_leb128_u64()
}

///|
/// Read memory argument (memidx, align, offset) with validation
/// Multi-memory: if bit 6 of flags is set, memory index follows
/// Alignment values >= 32 are reserved and should be rejected as malformed
/// The flags byte must not have continuation bit set (must fit in single byte)
/// offset is read as u64 to support memory64 64-bit offsets
fn Parser::read_memarg(self : Parser) -> (Int, Int, Int64) raise ParserError {
  // Read first byte directly - must not have continuation bit (0x80) set
  let flags_byte = self.read_byte()
  if (flags_byte & 0x80) != 0 {
    // Continuation bit is set - malformed memop flags
    raise MalformedMemopFlags
  }
  let flags = flags_byte
  // Multi-memory proposal: if bit 6 is set, memory index follows
  let memidx = if (flags & 0x40) != 0 { self.read_leb128_u32() } else { 0 }
  let align = flags & 0x3F // Lower 6 bits are alignment
  // WebAssembly spec: alignment values >= 32 are reserved
  if align >= 32 {
    raise MalformedMemopFlags
  }
  // Read offset as u64 to support memory64 64-bit offsets
  let offset = self.read_leb128_u64()
  (memidx, align, offset)
}

///|
/// Read an i32
fn Parser::read_i32(self : Parser) -> Int raise ParserError {
  self.read_leb128_i32()
}

///|
/// Read an i64
fn Parser::read_i64(self : Parser) -> Int64 raise ParserError {
  self.read_leb128_i64()
}

///|
/// Read f32 (IEEE 754, little-endian)
fn Parser::read_f32(self : Parser) -> Float raise ParserError {
  let b0 = self.read_byte()
  let b1 = self.read_byte()
  let b2 = self.read_byte()
  let b3 = self.read_byte()
  let bits = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  Float::reinterpret_from_int(bits)
}

///|
/// Read f64 (IEEE 754, little-endian)
fn Parser::read_f64(self : Parser) -> Double raise ParserError {
  let b0 = self.read_byte().to_int64()
  let b1 = self.read_byte().to_int64()
  let b2 = self.read_byte().to_int64()
  let b3 = self.read_byte().to_int64()
  let b4 = self.read_byte().to_int64()
  let b5 = self.read_byte().to_int64()
  let b6 = self.read_byte().to_int64()
  let b7 = self.read_byte().to_int64()
  let bits = b0 |
    (b1 << 8) |
    (b2 << 16) |
    (b3 << 24) |
    (b4 << 32) |
    (b5 << 40) |
    (b6 << 48) |
    (b7 << 56)
  Int64::reinterpret_as_double(bits)
}

///|
/// Read a UTF-8 string with validation
fn Parser::read_string(self : Parser) -> String raise ParserError {
  let len = self.read_u32()
  let bytes = self.read_bytes(len)
  // Validate and decode UTF-8
  decode_utf8_validated(bytes)
}

///|
/// Decode bytes as UTF-8 with validation, raising error on invalid sequences
fn decode_utf8_validated(bytes : Bytes) -> String raise ParserError {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < bytes.length() {
    let b = bytes[i].to_int()
    if b < 0x80 {
      // ASCII byte
      buf.write_char(b.unsafe_to_char())
      i = i + 1
    } else if b < 0xC0 {
      // Continuation byte without prefix - invalid
      raise ParseError("malformed UTF-8 encoding")
    } else if b < 0xE0 {
      // 2-byte sequence
      if i + 1 >= bytes.length() {
        raise ParseError("malformed UTF-8 encoding")
      }
      let b2 = bytes[i + 1].to_int()
      if (b2 & 0xC0) != 0x80 {
        raise ParseError("malformed UTF-8 encoding")
      }
      let cp = ((b & 0x1F) << 6) | (b2 & 0x3F)
      // Check for overlong encoding
      if cp < 0x80 {
        raise ParseError("malformed UTF-8 encoding")
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 2
    } else if b < 0xF0 {
      // 3-byte sequence
      if i + 2 >= bytes.length() {
        raise ParseError("malformed UTF-8 encoding")
      }
      let b2 = bytes[i + 1].to_int()
      let b3 = bytes[i + 2].to_int()
      if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 {
        raise ParseError("malformed UTF-8 encoding")
      }
      let cp = ((b & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
      // Check for overlong encoding
      if cp < 0x800 {
        raise ParseError("malformed UTF-8 encoding")
      }
      // Check for surrogates (invalid in UTF-8)
      if cp >= 0xD800 && cp <= 0xDFFF {
        raise ParseError("malformed UTF-8 encoding")
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 3
    } else if b < 0xF8 {
      // 4-byte sequence
      if i + 3 >= bytes.length() {
        raise ParseError("malformed UTF-8 encoding")
      }
      let b2 = bytes[i + 1].to_int()
      let b3 = bytes[i + 2].to_int()
      let b4 = bytes[i + 3].to_int()
      if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 || (b4 & 0xC0) != 0x80 {
        raise ParseError("malformed UTF-8 encoding")
      }
      let cp = ((b & 0x07) << 18) |
        ((b2 & 0x3F) << 12) |
        ((b3 & 0x3F) << 6) |
        (b4 & 0x3F)
      // Check for overlong encoding
      if cp < 0x10000 {
        raise ParseError("malformed UTF-8 encoding")
      }
      // Check for out of range (> U+10FFFF)
      if cp > 0x10FFFF {
        raise ParseError("malformed UTF-8 encoding")
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 4
    } else {
      // Invalid leading byte (0xF8-0xFF)
      raise ParseError("malformed UTF-8 encoding")
    }
  }
  buf.to_string()
}

// ============================================================
// Value Type Parsing
// ============================================================

///|
fn Parser::resolve_heap_type_as_ref_value_type(
  self : Parser,
  heap_type : Int,
  nullable : Bool,
) -> @types.ValueType raise ParserError {
  fn resolve_typed_ref(
    type_idx : Int,
    nullable : Bool,
  ) -> @types.ValueType raise ParserError {
    if type_idx < 0 || type_idx >= self.types.length() {
      raise ParseError("invalid heap type")
    }
    match self.types[type_idx].composite {
      Func(_) =>
        if nullable {
          @types.ValueType::RefNullFuncTyped(type_idx)
        } else {
          @types.ValueType::RefFuncTyped(type_idx)
        }
      Struct(_) =>
        if nullable {
          @types.ValueType::RefNullStruct(type_idx)
        } else {
          @types.ValueType::RefStruct(type_idx)
        }
      Array(_) =>
        if nullable {
          @types.ValueType::RefNullArray(type_idx)
        } else {
          @types.ValueType::RefArray(type_idx)
        }
    }
  }

  fn resolve_abstract_heap(
    heap_type : Int,
    nullable : Bool,
  ) -> @types.ValueType raise ParserError {
    match heap_type {
      -16 =>
        if nullable {
          @types.ValueType::FuncRef
        } else {
          @types.ValueType::RefFunc
        }
      -17 =>
        if nullable {
          @types.ValueType::ExternRef
        } else {
          @types.ValueType::RefExtern
        }
      -18 =>
        if nullable {
          @types.ValueType::AnyRef
        } else {
          @types.ValueType::RefAny
        }
      -19 =>
        if nullable {
          @types.ValueType::RefNullEq
        } else {
          @types.ValueType::RefEq
        }
      -20 =>
        if nullable {
          @types.ValueType::RefNullI31
        } else {
          @types.ValueType::RefI31
        }
      -21 =>
        if nullable {
          @types.ValueType::StructRef
        } else {
          @types.ValueType::RefStructAbs
        }
      -22 =>
        if nullable {
          @types.ValueType::ArrayRef
        } else {
          @types.ValueType::RefArrayAbs
        }
      -23 => @types.ValueType::ExnRef
      -15 =>
        if nullable {
          @types.ValueType::NullRef
        } else {
          @types.ValueType::RefNone
        }
      -14 => @types.ValueType::NullExternRef
      -13 => @types.ValueType::NullFuncRef
      -12 => @types.ValueType::NullExnRef
      _ => raise ParseError("invalid heap type")
    }
  }

  if heap_type < 0 {
    resolve_abstract_heap(heap_type, nullable)
  } else {
    resolve_typed_ref(heap_type, nullable)
  }
}

///|
fn Parser::read_value_type(self : Parser) -> @types.ValueType raise ParserError {
  fn resolve_typed_ref(
    type_idx : Int,
    nullable : Bool,
  ) -> @types.ValueType raise ParserError {
    self.resolve_heap_type_as_ref_value_type(type_idx, nullable)
  }

  fn resolve_abstract_heap(
    heap_type : Int,
    nullable : Bool,
  ) -> @types.ValueType raise ParserError {
    self.resolve_heap_type_as_ref_value_type(heap_type, nullable)
  }

  let byte = self.read_byte()
  match byte {
    0x7F => I32
    0x7E => I64
    0x7D => F32
    0x7C => F64
    0x7B => V128

    // Reference shorthands
    0x70 => FuncRef
    0x6F => ExternRef
    0x6E => AnyRef
    0x6D => RefNullEq
    0x6C => RefNullI31
    0x6B => StructRef
    0x6A => ArrayRef
    0x69 => ExnRef
    0x71 => NullRef
    0x72 => NullExternRef
    0x73 => NullFuncRef
    0x74 => NullExnRef

    // ref heaptype
    0x64 => {
      let heap_type = self.read_heap_type()
      if heap_type < 0 {
        resolve_abstract_heap(heap_type, false)
      } else {
        resolve_typed_ref(heap_type, false)
      }
    }

    // ref shared heaptype (shared reference types proposal)
    0x65 => {
      self.read_heap_type() |> ignore
      raise ParseError("shared reference types not supported")
    }

    // ref null shared heaptype (shared reference types proposal)
    0x62 => {
      self.read_heap_type() |> ignore
      raise ParseError("shared reference types not supported")
    }

    // ref null heaptype
    0x63 => {
      let heap_type = self.read_heap_type()
      if heap_type < 0 {
        resolve_abstract_heap(heap_type, true)
      } else {
        resolve_typed_ref(heap_type, true)
      }
    }
    _ => raise InvalidValueType(byte)
  }
}

///|
/// Read a heap type (signed LEB128 type index or abstract heap type)
fn Parser::read_heap_type(self : Parser) -> Int raise ParserError {
  // Heap types are encoded as signed LEB128
  // Negative values represent abstract heap types:
  //   -0x10 (0x70) = func
  //   -0x11 (0x6F) = extern
  // Positive values represent type indices
  self.read_i32()
}

///|
/// Read block type (uses peek to avoid rewind)
fn Parser::read_block_type(self : Parser) -> @types.BlockType raise ParserError {
  let byte = self.peek_byte()
  match byte {
    0x40 => {
      self.skip(1)
      Empty
    }
    0x7F
    | 0x7E
    | 0x7D
    | 0x7C
    | 0x7B
    | 0x70
    | 0x6F
    | 0x6E
    | 0x6D
    | 0x6C
    | 0x6B
    | 0x6A
    | 0x69
    | 0x71
    | 0x72
    | 0x73
    | 0x74
    | 0x64
    | 0x65
    | 0x63
    | 0x62 => Value(self.read_value_type())
    _ => TypeIndex(self.read_i32())
  }
}

// ============================================================
// Recursive Group Type Parsing (WasmGC)
// ============================================================

///|
fn Parser::read_field_type(self : Parser) -> @types.FieldType raise ParserError {
  let storage_type : @types.StorageType = match self.peek_byte() {
    0x78 => {
      self.skip(1)
      @types.StorageType::Packed(@types.PackedType::I8)
    }
    0x77 => {
      self.skip(1)
      @types.StorageType::Packed(@types.PackedType::I16)
    }
    _ => @types.StorageType::Val(self.read_value_type())
  }
  let mutability = self.read_byte()
  if mutability != 0x00 && mutability != 0x01 {
    raise MalformedMutability(mutability)
  }
  { storage_type, mutable: mutability == 0x01 }
}

///|
fn Parser::read_struct_type(
  self : Parser,
) -> @types.StructType raise ParserError {
  let fields = self.read_vec(fn() { self.read_field_type() })
  { fields, }
}

///|
fn Parser::read_array_type(self : Parser) -> @types.ArrayType raise ParserError {
  let element = self.read_field_type()
  { element, }
}

///|
fn Parser::read_composite_type(
  self : Parser,
) -> @types.CompositeType raise ParserError {
  let tag = self.read_byte()
  match tag {
    0x60 => {
      let params = self.read_vec(fn() { self.read_value_type() })
      let results = self.read_vec(fn() { self.read_value_type() })
      @types.CompositeType::Func({ params, results })
    }
    0x5f => @types.CompositeType::Struct(self.read_struct_type())
    0x5e => @types.CompositeType::Array(self.read_array_type())
    _ => raise ParseError("unknown composite type tag: \{tag}")
  }
}

///|
fn Parser::read_subtype(self : Parser) -> @types.SubType raise ParserError {
  // WasmGC binary subtype encoding:
  // - 0x50: subtype header with flags + optional supertype
  // - 0x4f: final subtype header with optional supertype
  // - otherwise: implicit final subtype without supertypes
  let tag = self.peek_byte()
  if tag == 0x50 {
    self.skip(1)
    let flags = self.read_byte()
    let has_supertype = (flags & 0x01) != 0
    let final_ = (flags & 0x02) != 0
    if (flags & 0xFC) != 0 {
      raise ParseError("malformed subtype flags")
    }
    let supertypes : Array[Int] = if has_supertype {
      [self.read_u32()]
    } else {
      []
    }
    let composite = self.read_composite_type()
    { final_, supertypes, composite }
  } else if tag == 0x4f {
    self.skip(1)
    let flags = self.read_byte()
    let has_supertype = (flags & 0x01) != 0
    if (flags & 0xFE) != 0 {
      raise ParseError("malformed subtype flags")
    }
    let supertypes : Array[Int] = if has_supertype {
      [self.read_u32()]
    } else {
      []
    }
    let composite = self.read_composite_type()
    { final_: true, supertypes, composite }
  } else {
    // Implicit final subtype
    let composite = self.read_composite_type()
    { final_: true, supertypes: [], composite }
  }
}

///|
/// Read a rec group entry in the type section.
/// The type section is a vec of rec groups; each entry is either:
/// - 0x4e <vec subtype>  (explicit rec group)
/// - subtype             (implicit singleton group)
fn Parser::read_rec_group(
  self : Parser,
) -> Array[@types.SubType] raise ParserError {
  fn placeholder_subtype_by_composite_tag(
    composite_tag : Int,
  ) -> @types.SubType raise ParserError {
    let composite : @types.CompositeType = match composite_tag {
      0x60 => @types.CompositeType::Func({ params: [], results: [] })
      0x5f => @types.CompositeType::Struct({ fields: [] })
      0x5e => {
        let element : @types.FieldType = {
          storage_type: @types.StorageType::Val(@types.ValueType::I32),
          mutable: false,
        }
        @types.CompositeType::Array({ element, })
      }
      _ => raise ParseError("unknown composite type tag: \{composite_tag}")
    }
    { final_: true, supertypes: [], composite }
  }

  fn skip_value_type_no_resolve(self : Parser) -> Unit raise ParserError {
    let byte = self.read_byte()
    match byte {
      0x7F | 0x7E | 0x7D | 0x7C | 0x7B => ()

      // Reference shorthands
      0x70
      | 0x6F
      | 0x6E
      | 0x6D
      | 0x6C
      | 0x6B
      | 0x6A
      | 0x69
      | 0x71
      | 0x72
      | 0x73
      | 0x74 => ()

      // ref heaptype / ref null heaptype
      0x64 | 0x63 => self.read_heap_type() |> ignore

      // shared reference types proposal
      0x65 | 0x62 => {
        self.read_heap_type() |> ignore
        raise ParseError("shared reference types not supported")
      }
      _ => raise InvalidValueType(byte)
    }
  }

  fn skip_field_type_no_resolve(self : Parser) -> Unit raise ParserError {
    match self.peek_byte() {
      0x78 | 0x77 => self.skip(1)
      _ => skip_value_type_no_resolve(self)
    }
    let mutability = self.read_byte()
    if mutability != 0x00 && mutability != 0x01 {
      raise MalformedMutability(mutability)
    }
  }

  fn skip_composite_type_no_resolve(self : Parser) -> Int raise ParserError {
    let tag = self.read_byte()
    match tag {
      0x60 => {
        // func: vec(valtype) vec(valtype)
        let nparams = self.read_u32()
        for _ in 0..<nparams {
          skip_value_type_no_resolve(self)
        }
        let nresults = self.read_u32()
        for _ in 0..<nresults {
          skip_value_type_no_resolve(self)
        }
        tag
      }
      0x5f => {
        // struct: vec(fieldtype)
        let nfields = self.read_u32()
        for _ in 0..<nfields {
          skip_field_type_no_resolve(self)
        }
        tag
      }
      0x5e => {
        // array: fieldtype
        skip_field_type_no_resolve(self)
        tag
      }
      _ => raise ParseError("unknown composite type tag: \{tag}")
    }
  }

  fn skip_subtype_and_get_composite_tag(
    self : Parser,
  ) -> Int raise ParserError {
    let tag = self.peek_byte()
    if tag == 0x50 {
      self.skip(1)
      let flags = self.read_byte()
      let has_supertype = (flags & 0x01) != 0
      if (flags & 0xFC) != 0 {
        raise ParseError("malformed subtype flags")
      }
      if has_supertype {
        self.read_u32() |> ignore
      }
      skip_composite_type_no_resolve(self)
    } else if tag == 0x4f {
      self.skip(1)
      let flags = self.read_byte()
      let has_supertype = (flags & 0x01) != 0
      if (flags & 0xFE) != 0 {
        raise ParseError("malformed subtype flags")
      }
      if has_supertype {
        self.read_u32() |> ignore
      }
      skip_composite_type_no_resolve(self)
    } else {
      skip_composite_type_no_resolve(self)
    }
  }

  let tag = self.peek_byte()
  if tag == 0x4e {
    self.skip(1)
    let n = self.read_u32()
    let base_idx = self.types.length()

    // WasmGC allows forward references within a `rec` group. Pre-scan the group
    // to learn each entry's composite kind, then pre-allocate placeholders so
    // typed refs can be resolved during the real parse.
    let scan : Parser = {
      data: self.data,
      pos: self.pos,
      has_data_count: self.has_data_count,
      types: [],
    }
    let composite_tags : Array[Int] = []
    for _ in 0..<n {
      composite_tags.push(skip_subtype_and_get_composite_tag(scan))
    }
    for i in 0..<n {
      self.types.push(placeholder_subtype_by_composite_tag(composite_tags[i]))
    }
    let defs : Array[@types.SubType] = []
    for i in 0..<n {
      let subtype = self.read_subtype()
      defs.push(subtype)
      self.types[base_idx + i] = subtype
    }
    defs
  } else {
    let subtype = self.read_subtype()
    self.types.push(subtype)
    [subtype]
  }
}

// ============================================================
// Function Type Parsing
// ============================================================

///|
/// Read a vector of items using a reader function
fn[T] Parser::read_vec(
  self : Parser,
  reader : () -> T raise ParserError,
) -> Array[T] raise ParserError {
  let count = self.read_u32()
  loop ([], 0) {
    (acc, i) =>
      if i >= count {
        acc
      } else {
        acc.push(reader())
        continue (acc, i + 1)
      }
  }
}

// ============================================================
// Table and Memory Type Parsing
// ============================================================

///|
fn Parser::read_table(self : Parser) -> @types.Table raise ParserError {
  // Check for extended table type encoding (typed function references)
  let first_byte = self.peek_byte()
  if first_byte == 0x40 {
    // Extended encoding: 0x40 0x00 reftype limits expr
    self.skip(1) // consume 0x40
    let second_byte = self.read_byte()
    if second_byte != 0x00 {
      raise MalformedReferenceType(second_byte)
    }
    let elem_type = self.read_value_type()
    let (limits, is_table64) = self.read_table_limits()
    // Read the initialization expression
    let init = self.read_expr()
    { type_: { elem_type, limits, is_table64 }, init: Some(init) }
  } else {
    // Standard encoding: reftype limits
    let elem_type = self.read_value_type()
    let (limits, is_table64) = self.read_table_limits()
    { type_: { elem_type, limits, is_table64 }, init: None }
  }
}

///|
fn Parser::read_table_type(self : Parser) -> @types.TableType raise ParserError {
  // For imports, we just need the table type (no init expression)
  let elem_type = self.read_value_type()
  let (limits, is_table64) = self.read_table_limits()
  { elem_type, limits, is_table64 }
}

///|
/// Read table limits with table64 support
/// Returns (limits, is_table64)
fn Parser::read_table_limits(
  self : Parser,
) -> (@types.Limits, Bool) raise ParserError {
  // Table limits flags:
  // Bit 0: has max (0x01)
  // Bit 2: table64 (0x04)
  // Valid combinations: 0x00, 0x01, 0x04, 0x05
  // Tables don't support shared bit (0x02)
  let flags = self.read_byte()
  let valid_table_flags : FixedArray[Int] = [
    LIMITS_NO_MAX,
    LIMITS_HAS_MAX,
    LIMITS_64_NO_MAX,
    LIMITS_64_HAS_MAX,
  ]
  if not(valid_table_flags.contains(flags)) {
    raise MalformedLimitsFlags(flags)
  }
  let has_max = (flags & LIMITS_HAS_MAX) != 0
  let is_table64 = (flags & LIMITS_64_NO_MAX) != 0

  // Read min/max based on table64 flag
  let (min, max) = if is_table64 {
    let min = self.read_leb128_u64()
    let max = if has_max { Some(self.read_leb128_u64()) } else { None }
    (min, max)
  } else {
    let min = self.read_leb128_u32().to_int64()
    let max = if has_max {
      Some(self.read_leb128_u32().to_int64())
    } else {
      None
    }
    (min, max)
  }
  ({ min, max }, is_table64)
}

///|
fn Parser::read_memory_type(
  self : Parser,
) -> @types.MemoryType raise ParserError {
  // Memory type flags:
  // Bit 0: has max (0x01)
  // Bit 1: shared (0x02) - only valid with has max
  // Bit 2: memory64 (0x04)
  // Bit 3: custom-page-sizes (0x08)
  // Valid combinations (wasm-tools/wasmparser):
  // - memory32: 0x00, 0x01, 0x03 and +0x08 variants
  // - memory64: 0x04, 0x05, 0x07 and +0x08 variants
  let flags = self.read_byte()
  let has_max = (flags & LIMITS_HAS_MAX) != 0
  let is_memory64 = (flags & LIMITS_64_NO_MAX) != 0
  let has_custom_page_size = (flags & 0x08) != 0

  // Validate flags
  let valid_memory_flags : FixedArray[Int] = [
    LIMITS_NO_MAX,
    LIMITS_HAS_MAX,
    LIMITS_SHARED,
    LIMITS_64_NO_MAX,
    LIMITS_64_HAS_MAX,
    LIMITS_64_SHARED,
    0x08,
    0x09,
    0x0B,
    0x0C,
    0x0D,
    0x0F,
  ]
  if not(valid_memory_flags.contains(flags)) {
    raise MalformedLimitsFlags(flags)
  }

  // Read limits - for memory64, use u64; for memory32, use u32
  let min = if is_memory64 {
    self.read_u64()
  } else {
    self.read_u32().to_int64()
  }
  let max = if has_max {
    Some(if is_memory64 { self.read_u64() } else { self.read_u32().to_int64() })
  } else {
    None
  }
  let page_size_log2 = if has_custom_page_size {
    // custom-page-sizes proposal encodes a page size log2 after max (or min if no max).
    let l2 = self.read_u32()
    if l2 < 0 || l2 > 30 {
      raise ParseError("invalid memory page size")
    }
    l2
  } else {
    16
  }
  { limits: { min, max }, is_memory64, page_size_log2 }
}

///|
fn Parser::read_global_type(
  self : Parser,
) -> @types.GlobalType raise ParserError {
  let value_type = self.read_value_type()
  let mutability = self.read_byte()
  // Mutability must be 0 (const) or 1 (var)
  if mutability != 0x00 && mutability != 0x01 {
    raise MalformedMutability(mutability)
  }
  { value_type, mutable: mutability == 0x01 }
}

// ============================================================
// Element Segment Parsing
// ============================================================

///|
/// Read element segment based on flags
/// Returns (mode, elem_type, init_exprs)
fn Parser::read_elem_segment(
  self : Parser,
  flags : Int,
) -> (@types.ElemMode, @types.ValueType, Array[Array[@types.Instruction]]) raise ParserError {
  // Flags encoding:
  // bit 0: 0 = active, 1 = passive/declarative
  // bit 1: 0 = implicit table 0, 1 = explicit table index (only if active)
  // bit 2: 0 = func indices, 1 = expressions
  // For passive: bit 1 distinguishes passive (0) from declarative (1)
  let is_passive_or_declarative = (flags & 0x01) != 0
  let has_table_index_or_is_declarative = (flags & 0x02) != 0
  let uses_expressions = (flags & 0x04) != 0
  let mode : @types.ElemMode = if is_passive_or_declarative {
    if has_table_index_or_is_declarative {
      @types.ElemMode::Declarative
    } else {
      @types.ElemMode::Passive
    }
  } else {
    // Active segment
    let table_idx = if has_table_index_or_is_declarative {
      self.read_u32()
    } else {
      0
    }
    let offset = self.read_expr()
    @types.ElemMode::Active(table_idx, offset)
  }

  // Read element type
  // flags encoding for elem type:
  // - flags 0, 4: no elemkind/reftype (implicit funcref)
  // - flags 1, 2, 3: has elemkind byte (0x00 = funcref)
  // - flags 5, 6, 7: has reftype byte (0x70=funcref, 0x6F=externref, etc.)
  // Note: flags 4 uses expressions but has NO reftype byte (implicit funcref)
  let has_elemkind = flags == 1 || flags == 2 || flags == 3
  let has_reftype = flags == 5 || flags == 6 || flags == 7
  let elem_type : @types.ValueType = if has_reftype {
    // flags 5, 6, 7: has explicit reftype
    let vt = self.read_value_type()
    match vt {
      I32 | I64 | F32 | F64 | V128 => raise MalformedReferenceType(0)
      _ => vt
    }
  } else if has_elemkind {
    // flags 1, 2, 3: has elemkind
    let kind = self.read_byte()
    if kind != 0x00 {
      raise ParseError("unsupported element kind: \{kind}")
    }
    @types.ValueType::FuncRef
  } else {
    // flags 0: no elemkind, implicit funcref
    @types.ValueType::FuncRef
  }

  // Read init expressions or function indices
  let elem_count = self.read_u32()
  let init : Array[Array[@types.Instruction]] = []
  for _ in 0..<elem_count {
    if uses_expressions {
      // Read expression
      init.push(self.read_expr())
    } else {
      // Read function index, convert to ref.func expression
      let func_idx = self.read_u32()
      init.push([@types.Instruction::RefFunc(func_idx)])
    }
  }
  (mode, elem_type, init)
}

// ============================================================
// Instruction Parsing
// ============================================================

///|
fn Parser::read_expr(
  self : Parser,
) -> Array[@types.Instruction] raise ParserError {
  loop [] {
    instructions => {
      let opcode = self.read_byte()
      if opcode == 0x0B {
        // end
        instructions
      } else {
        instructions.push(self.read_instruction(opcode))
        continue instructions
      }
    }
  }
}

///|
/// Read if-then body, stopping at either 0x05 (else) or 0x0B (end)
/// Returns (body, has_else) where has_else is true if we stopped at else
fn Parser::read_if_then_body(
  self : Parser,
) -> (Array[@types.Instruction], Bool) raise ParserError {
  loop [] {
    instructions => {
      let opcode = self.read_byte()
      if opcode == 0x0B {
        // end - no else clause
        (instructions, false)
      } else if opcode == 0x05 {
        // else
        (instructions, true)
      } else {
        instructions.push(self.read_instruction(opcode))
        continue instructions
      }
    }
  }
}

///|
fn Parser::read_instruction(
  self : Parser,
  opcode : Int,
) -> @types.Instruction raise ParserError {
  match opcode {
    // Control instructions
    0x00 => Unreachable
    0x01 => Nop
    0x02 => {
      let bt = self.read_block_type()
      let body = self.read_expr()
      Block(bt, body)
    }
    0x03 => {
      let bt = self.read_block_type()
      let body = self.read_expr()
      Loop(bt, body)
    }
    0x04 => {
      let bt = self.read_block_type()
      // Read then body, which ends at either 0x05 (else) or 0x0B (end)
      let (then_body, has_else) = self.read_if_then_body()
      if has_else {
        // Read else body until 0x0B (end)
        let else_body = self.read_expr()
        If(bt, then_body, else_body)
      } else {
        If(bt, then_body, [])
      }
    }
    // Exception handling instructions
    0x08 => Throw(self.read_u32()) // throw tag_idx
    0x0A => ThrowRef // throw_ref
    0x1F => {
      // try_table: blocktype, catch_handlers*, body
      let bt = self.read_block_type()
      let handler_count = self.read_u32()
      let handlers : Array[@types.CatchHandler] = []
      for _ in 0..<handler_count {
        let catch_kind = self.read_byte()
        let handler = match catch_kind {
          0x00 => {
            // catch: tag_idx, label_idx
            let tag_idx = self.read_u32()
            let label_idx = self.read_u32()
            @types.CatchHandler::Catch(tag_idx, label_idx)
          }
          0x01 => {
            // catch_ref: tag_idx, label_idx
            let tag_idx = self.read_u32()
            let label_idx = self.read_u32()
            @types.CatchHandler::CatchRef(tag_idx, label_idx)
          }
          0x02 => {
            // catch_all: label_idx
            let label_idx = self.read_u32()
            @types.CatchHandler::CatchAll(label_idx)
          }
          0x03 => {
            // catch_all_ref: label_idx
            let label_idx = self.read_u32()
            @types.CatchHandler::CatchAllRef(label_idx)
          }
          _ => raise ParseError("invalid catch handler kind: \{catch_kind}")
        }
        handlers.push(handler)
      }
      let body = self.read_expr()
      TryTable(bt, handlers, body)
    }
    0x0C => Br(self.read_u32())
    0x0D => BrIf(self.read_u32())
    0x0E => {
      let labels = self.read_vec(fn() { self.read_u32() })
      let default = self.read_u32()
      BrTable(labels, default)
    }
    0x0F => Return
    0x10 => Call(self.read_u32())
    0x11 => {
      let type_idx = self.read_u32()
      let table_idx = self.read_u32()
      CallIndirect(type_idx, table_idx)
    }
    // Tail-call proposal
    0x12 => ReturnCall(self.read_u32())
    0x13 => {
      let type_idx = self.read_u32()
      let table_idx = self.read_u32()
      ReturnCallIndirect(type_idx, table_idx)
    }
    // WasmGC typed call_ref/return_call_ref
    0x14 => CallRef(self.read_u32())
    0x15 => ReturnCallRef(self.read_u32())
    // Parametric instructions
    0x1A => Drop
    0x1B => Select
    // Variable instructions
    0x20 => LocalGet(self.read_u32())
    0x21 => LocalSet(self.read_u32())
    0x22 => LocalTee(self.read_u32())
    0x23 => GlobalGet(self.read_u32())
    0x24 => GlobalSet(self.read_u32())
    // Table instructions
    0x25 => TableGet(self.read_u32())
    0x26 => TableSet(self.read_u32())
    // Memory instructions (with alignment validation)
    0x28 => {
      let (memidx, align, offset) = self.read_memarg()
      I32Load(memidx, align, offset)
    }
    0x29 => {
      let (memidx, align, offset) = self.read_memarg()
      I64Load(memidx, align, offset)
    }
    0x2A => {
      let (memidx, align, offset) = self.read_memarg()
      F32Load(memidx, align, offset)
    }
    0x2B => {
      let (memidx, align, offset) = self.read_memarg()
      F64Load(memidx, align, offset)
    }
    0x2C => {
      let (memidx, align, offset) = self.read_memarg()
      I32Load8S(memidx, align, offset)
    }
    0x2D => {
      let (memidx, align, offset) = self.read_memarg()
      I32Load8U(memidx, align, offset)
    }
    0x2E => {
      let (memidx, align, offset) = self.read_memarg()
      I32Load16S(memidx, align, offset)
    }
    0x2F => {
      let (memidx, align, offset) = self.read_memarg()
      I32Load16U(memidx, align, offset)
    }
    0x30 => {
      let (memidx, align, offset) = self.read_memarg()
      I64Load8S(memidx, align, offset)
    }
    0x31 => {
      let (memidx, align, offset) = self.read_memarg()
      I64Load8U(memidx, align, offset)
    }
    0x32 => {
      let (memidx, align, offset) = self.read_memarg()
      I64Load16S(memidx, align, offset)
    }
    0x33 => {
      let (memidx, align, offset) = self.read_memarg()
      I64Load16U(memidx, align, offset)
    }
    0x34 => {
      let (memidx, align, offset) = self.read_memarg()
      I64Load32S(memidx, align, offset)
    }
    0x35 => {
      let (memidx, align, offset) = self.read_memarg()
      I64Load32U(memidx, align, offset)
    }
    // Memory store instructions (with alignment validation)
    0x36 => {
      let (memidx, align, offset) = self.read_memarg()
      I32Store(memidx, align, offset)
    }
    0x37 => {
      let (memidx, align, offset) = self.read_memarg()
      I64Store(memidx, align, offset)
    }
    0x38 => {
      let (memidx, align, offset) = self.read_memarg()
      F32Store(memidx, align, offset)
    }
    0x39 => {
      let (memidx, align, offset) = self.read_memarg()
      F64Store(memidx, align, offset)
    }
    0x3A => {
      let (memidx, align, offset) = self.read_memarg()
      I32Store8(memidx, align, offset)
    }
    0x3B => {
      let (memidx, align, offset) = self.read_memarg()
      I32Store16(memidx, align, offset)
    }
    0x3C => {
      let (memidx, align, offset) = self.read_memarg()
      I64Store8(memidx, align, offset)
    }
    0x3D => {
      let (memidx, align, offset) = self.read_memarg()
      I64Store16(memidx, align, offset)
    }
    0x3E => {
      let (memidx, align, offset) = self.read_memarg()
      I64Store32(memidx, align, offset)
    }
    0x3F => {
      let memidx = self.read_leb128_u32() // memory index (0 for single-memory)
      MemorySize(memidx)
    }
    0x40 => {
      let memidx = self.read_leb128_u32() // memory index (0 for single-memory)
      MemoryGrow(memidx)
    }
    // Numeric constant instructions
    0x41 => I32Const(self.read_i32())
    0x42 => I64Const(self.read_i64())
    0x43 => F32Const(self.read_f32())
    0x44 => F64Const(self.read_f64())
    // i32 comparison
    0x45 => I32Eqz
    0x46 => I32Eq
    0x47 => I32Ne
    0x48 => I32LtS
    0x49 => I32LtU
    0x4A => I32GtS
    0x4B => I32GtU
    0x4C => I32LeS
    0x4D => I32LeU
    0x4E => I32GeS
    0x4F => I32GeU
    // i64 comparison
    0x50 => I64Eqz
    0x51 => I64Eq
    0x52 => I64Ne
    0x53 => I64LtS
    0x54 => I64LtU
    0x55 => I64GtS
    0x56 => I64GtU
    0x57 => I64LeS
    0x58 => I64LeU
    0x59 => I64GeS
    0x5A => I64GeU
    // f32 comparison
    0x5B => F32Eq
    0x5C => F32Ne
    0x5D => F32Lt
    0x5E => F32Gt
    0x5F => F32Le
    0x60 => F32Ge
    // f64 comparison
    0x61 => F64Eq
    0x62 => F64Ne
    0x63 => F64Lt
    0x64 => F64Gt
    0x65 => F64Le
    0x66 => F64Ge
    // i32 operations
    0x67 => I32Clz
    0x68 => I32Ctz
    0x69 => I32Popcnt
    0x6A => I32Add
    0x6B => I32Sub
    0x6C => I32Mul
    0x6D => I32DivS
    0x6E => I32DivU
    0x6F => I32RemS
    0x70 => I32RemU
    0x71 => I32And
    0x72 => I32Or
    0x73 => I32Xor
    0x74 => I32Shl
    0x75 => I32ShrS
    0x76 => I32ShrU
    0x77 => I32Rotl
    0x78 => I32Rotr
    // i64 operations
    0x79 => I64Clz
    0x7A => I64Ctz
    0x7B => I64Popcnt
    0x7C => I64Add
    0x7D => I64Sub
    0x7E => I64Mul
    0x7F => I64DivS
    0x80 => I64DivU
    0x81 => I64RemS
    0x82 => I64RemU
    0x83 => I64And
    0x84 => I64Or
    0x85 => I64Xor
    0x86 => I64Shl
    0x87 => I64ShrS
    0x88 => I64ShrU
    0x89 => I64Rotl
    0x8A => I64Rotr
    // f32 operations
    0x8B => F32Abs
    0x8C => F32Neg
    0x8D => F32Ceil
    0x8E => F32Floor
    0x8F => F32Trunc
    0x90 => F32Nearest
    0x91 => F32Sqrt
    0x92 => F32Add
    0x93 => F32Sub
    0x94 => F32Mul
    0x95 => F32Div
    0x96 => F32Min
    0x97 => F32Max
    0x98 => F32Copysign
    // f64 operations
    0x99 => F64Abs
    0x9A => F64Neg
    0x9B => F64Ceil
    0x9C => F64Floor
    0x9D => F64Trunc
    0x9E => F64Nearest
    0x9F => F64Sqrt
    0xA0 => F64Add
    0xA1 => F64Sub
    0xA2 => F64Mul
    0xA3 => F64Div
    0xA4 => F64Min
    0xA5 => F64Max
    0xA6 => F64Copysign
    // Conversion operations
    0xA7 => I32WrapI64
    0xA8 => I32TruncF32S
    0xA9 => I32TruncF32U
    0xAA => I32TruncF64S
    0xAB => I32TruncF64U
    0xAC => I64ExtendI32S
    0xAD => I64ExtendI32U
    0xAE => I64TruncF32S
    0xAF => I64TruncF32U
    0xB0 => I64TruncF64S
    0xB1 => I64TruncF64U
    0xB2 => F32ConvertI32S
    0xB3 => F32ConvertI32U
    0xB4 => F32ConvertI64S
    0xB5 => F32ConvertI64U
    0xB6 => F32DemoteF64
    0xB7 => F64ConvertI32S
    0xB8 => F64ConvertI32U
    0xB9 => F64ConvertI64S
    0xBA => F64ConvertI64U
    0xBB => F64PromoteF32
    0xBC => I32ReinterpretF32
    0xBD => I64ReinterpretF64
    0xBE => F32ReinterpretI32
    0xBF => F64ReinterpretI64
    // Sign-extension operators
    0xC0 => I32Extend8S
    0xC1 => I32Extend16S
    0xC2 => I64Extend8S
    0xC3 => I64Extend16S
    0xC4 => I64Extend32S
    // Reference type instructions
    0xD0 => {
      // ref.null: heaptype immediate (signed LEB)
      let heap_type = self.read_heap_type()
      if heap_type < 0 {
        let nullable_ref_ty = match heap_type {
          -16 => @types.ValueType::FuncRef
          -17 => @types.ValueType::ExternRef
          -18 => @types.ValueType::AnyRef
          -19 => @types.ValueType::RefNullEq
          -20 => @types.ValueType::RefNullI31
          -21 => @types.ValueType::StructRef
          -22 => @types.ValueType::ArrayRef
          -23 => @types.ValueType::ExnRef
          -15 => @types.ValueType::NullRef
          -14 => @types.ValueType::NullExternRef
          -13 => @types.ValueType::NullFuncRef
          -12 => @types.ValueType::NullExnRef
          _ => raise ParseError("invalid heap type")
        }
        RefNull(nullable_ref_ty)
      } else {
        if heap_type >= self.types.length() {
          raise ParseError("invalid heap type")
        }
        let nullable_ref_ty = match self.types[heap_type].composite {
          Func(_) => @types.ValueType::RefNullFuncTyped(heap_type)
          Struct(_) => @types.ValueType::RefNullStruct(heap_type)
          Array(_) => @types.ValueType::RefNullArray(heap_type)
        }
        RefNull(nullable_ref_ty)
      }
    }
    0xD1 => RefIsNull
    0xD2 => {
      // ref.func: read function index
      let func_idx = self.read_u32()
      RefFunc(func_idx)
    }
    0xD3 => RefEqInstr
    0xD4 => RefAsNonNull
    0xD5 => BrOnNull(self.read_u32())
    0xD6 => BrOnNonNull(self.read_u32())
    // Saturating truncation instructions (0xFC prefix)
    0xFC => {
      let subopcode = self.read_u32()
      match subopcode {
        0 => I32TruncSatF32S
        1 => I32TruncSatF32U
        2 => I32TruncSatF64S
        3 => I32TruncSatF64U
        4 => I64TruncSatF32S
        5 => I64TruncSatF32U
        6 => I64TruncSatF64S
        7 => I64TruncSatF64U
        // Bulk memory operations
        8 => {
          // memory.init: data_idx, memory_idx
          // Requires data count section to be present
          if not(self.has_data_count) {
            raise DataCountRequired
          }
          let data_idx = self.read_u32()
          let memidx = self.read_leb128_u32()
          MemoryInit(memidx, data_idx)
        }
        9 => {
          // data.drop: data_idx
          // Requires data count section to be present
          if not(self.has_data_count) {
            raise DataCountRequired
          }
          let data_idx = self.read_u32()
          DataDrop(data_idx)
        }
        10 => {
          // memory.copy: dest_mem, src_mem
          let dst = self.read_leb128_u32()
          let src = self.read_leb128_u32()
          MemoryCopy(dst, src)
        }
        11 => {
          // memory.fill: memory_idx
          let memidx = self.read_leb128_u32()
          MemoryFill(memidx)
        }
        12 => {
          // table.init: elem_idx, table_idx
          let elem_idx = self.read_u32()
          let table_idx = self.read_u32()
          TableInit(table_idx, elem_idx)
        }
        13 => {
          // elem.drop: elem_idx
          let elem_idx = self.read_u32()
          ElemDrop(elem_idx)
        }
        14 => {
          // table.copy: dest_table_idx, src_table_idx
          let dest_idx = self.read_u32()
          let src_idx = self.read_u32()
          TableCopy(dest_idx, src_idx)
        }
        15 => {
          // table.grow: table_idx
          let table_idx = self.read_u32()
          TableGrow(table_idx)
        }
        16 => {
          // table.size: table_idx
          let table_idx = self.read_u32()
          TableSize(table_idx)
        }
        17 => {
          // table.fill: table_idx
          let table_idx = self.read_u32()
          TableFill(table_idx)
        }
        21 => I64MulWideS
        22 => I64MulWideU
        _ => raise UnknownOpcode(0xFC00 + subopcode)
      }
    }
    // GC instructions (0xFB prefix)
    0xFB => {
      let subopcode = self.read_u32()
      self.parse_gc_instruction(subopcode)
    }
    // SIMD instructions (0xFD prefix)
    0xFD => {
      let subopcode = self.read_u32()
      self.parse_simd_instruction(subopcode)
    }
    // Atomics instructions (0xFE prefix)
    0xFE => {
      let subopcode = self.read_u32()
      if subopcode == 3 {
        // atomic.fence has a reserved 0x00 byte
        let reserved = self.read_byte()
        if reserved != 0x00 {
          raise ParseError("malformed atomic.fence")
        }
        Atomic(subopcode, 0, 0, 0L)
      } else {
        let (memidx, align, offset) = self.read_memarg()
        Atomic(subopcode, memidx, align, offset)
      }
    }
    _ => raise UnknownOpcode(opcode)
  }
}

///|
/// Parse GC instruction given the subopcode after 0xFB prefix
fn Parser::parse_gc_instruction(
  self : Parser,
  subopcode : Int,
) -> @types.Instruction raise ParserError {
  match subopcode {
    0 => StructNew(self.read_u32())
    1 => StructNewDefault(self.read_u32())
    2 => {
      let type_idx = self.read_u32()
      let field_idx = self.read_u32()
      StructGet(type_idx, field_idx)
    }
    3 => {
      let type_idx = self.read_u32()
      let field_idx = self.read_u32()
      StructGetS(type_idx, field_idx)
    }
    4 => {
      let type_idx = self.read_u32()
      let field_idx = self.read_u32()
      StructGetU(type_idx, field_idx)
    }
    5 => {
      let type_idx = self.read_u32()
      let field_idx = self.read_u32()
      StructSet(type_idx, field_idx)
    }
    6 => ArrayNew(self.read_u32())
    7 => ArrayNewDefault(self.read_u32())
    8 => {
      let type_idx = self.read_u32()
      let len = self.read_u32()
      ArrayNewFixed(type_idx, len)
    }
    9 => {
      let type_idx = self.read_u32()
      let data_idx = self.read_u32()
      ArrayNewData(type_idx, data_idx)
    }
    10 => {
      let type_idx = self.read_u32()
      let elem_idx = self.read_u32()
      ArrayNewElem(type_idx, elem_idx)
    }
    11 => ArrayGet(self.read_u32())
    12 => ArrayGetS(self.read_u32())
    13 => ArrayGetU(self.read_u32())
    14 => ArraySet(self.read_u32())
    15 => ArrayLen
    16 => ArrayFill(self.read_u32())
    17 => {
      let dst = self.read_u32()
      let src = self.read_u32()
      ArrayCopy(dst, src)
    }
    18 => {
      let type_idx = self.read_u32()
      let data_idx = self.read_u32()
      ArrayInitData(type_idx, data_idx)
    }
    19 => {
      let type_idx = self.read_u32()
      let elem_idx = self.read_u32()
      ArrayInitElem(type_idx, elem_idx)
    }
    20 =>
      RefTest(
        self.resolve_heap_type_as_ref_value_type(self.read_heap_type(), false),
      )
    21 =>
      RefTestNull(
        self.resolve_heap_type_as_ref_value_type(self.read_heap_type(), true),
      )
    22 =>
      RefCast(
        self.resolve_heap_type_as_ref_value_type(self.read_heap_type(), false),
      )
    23 =>
      RefCastNull(
        self.resolve_heap_type_as_ref_value_type(self.read_heap_type(), true),
      )
    24 => {
      let label = self.read_u32()
      let from_t = self.read_value_type()
      let to_t = self.read_value_type()
      BrOnCast(label, from_t, to_t)
    }
    25 => {
      let label = self.read_u32()
      let from_t = self.read_value_type()
      let to_t = self.read_value_type()
      BrOnCastFail(label, from_t, to_t)
    }
    26 => AnyConvertExtern
    27 => ExternConvertAny
    28 => RefI31
    29 => I31GetS
    30 => I31GetU
    _ => raise UnknownOpcode(0xFB00 + subopcode)
  }
}

///|
/// Parse SIMD instruction given the subopcode after 0xFD prefix
fn Parser::parse_simd_instruction(
  self : Parser,
  subopcode : Int,
) -> @types.Instruction raise ParserError {
  match subopcode {
    // Memory operations
    0 => {
      // v128.load memarg
      let (memidx, align, offset) = self.read_memarg()
      V128Load(memidx, align, offset)
    }
    1 => {
      // v128.load8x8_s memarg
      let (memidx, align, offset) = self.read_memarg()
      V128Load8x8S(memidx, align, offset)
    }
    2 => {
      // v128.load8x8_u memarg
      let (memidx, align, offset) = self.read_memarg()
      V128Load8x8U(memidx, align, offset)
    }
    3 => {
      // v128.load16x4_s memarg
      let (memidx, align, offset) = self.read_memarg()
      V128Load16x4S(memidx, align, offset)
    }
    4 => {
      // v128.load16x4_u memarg
      let (memidx, align, offset) = self.read_memarg()
      V128Load16x4U(memidx, align, offset)
    }
    5 => {
      // v128.load32x2_s memarg
      let (memidx, align, offset) = self.read_memarg()
      V128Load32x2S(memidx, align, offset)
    }
    6 => {
      // v128.load32x2_u memarg
      let (memidx, align, offset) = self.read_memarg()
      V128Load32x2U(memidx, align, offset)
    }
    7 => {
      // v128.load8_splat memarg
      let (memidx, align, offset) = self.read_memarg()
      V128Load8Splat(memidx, align, offset)
    }
    8 => {
      // v128.load16_splat memarg
      let (memidx, align, offset) = self.read_memarg()
      V128Load16Splat(memidx, align, offset)
    }
    9 => {
      // v128.load32_splat memarg
      let (memidx, align, offset) = self.read_memarg()
      V128Load32Splat(memidx, align, offset)
    }
    10 => {
      // v128.load64_splat memarg
      let (memidx, align, offset) = self.read_memarg()
      V128Load64Splat(memidx, align, offset)
    }
    11 => {
      // v128.store memarg
      let (memidx, align, offset) = self.read_memarg()
      V128Store(memidx, align, offset)
    }
    12 => {
      // v128.const: read 16 bytes
      let bytes = self.read_bytes(16)
      V128Const(bytes)
    }
    13 => {
      // i8x16.shuffle: read 16 lane indices
      let lanes : FixedArray[Int] = FixedArray::make(16, 0)
      for i in 0..<16 {
        lanes[i] = self.read_byte()
      }
      I8x16Shuffle(lanes)
    }
    14 => I8x16Swizzle
    // Splat operations
    15 => I8x16Splat
    16 => I16x8Splat
    17 => I32x4Splat
    18 => I64x2Splat
    19 => F32x4Splat
    20 => F64x2Splat
    // Lane operations
    21 => {
      let lane = self.read_byte()
      I8x16ExtractLaneS(lane)
    }
    22 => {
      let lane = self.read_byte()
      I8x16ExtractLaneU(lane)
    }
    23 => {
      let lane = self.read_byte()
      I8x16ReplaceLane(lane)
    }
    24 => {
      let lane = self.read_byte()
      I16x8ExtractLaneS(lane)
    }
    25 => {
      let lane = self.read_byte()
      I16x8ExtractLaneU(lane)
    }
    26 => {
      let lane = self.read_byte()
      I16x8ReplaceLane(lane)
    }
    27 => {
      let lane = self.read_byte()
      I32x4ExtractLane(lane)
    }
    28 => {
      let lane = self.read_byte()
      I32x4ReplaceLane(lane)
    }
    29 => {
      let lane = self.read_byte()
      I64x2ExtractLane(lane)
    }
    30 => {
      let lane = self.read_byte()
      I64x2ReplaceLane(lane)
    }
    31 => {
      let lane = self.read_byte()
      F32x4ExtractLane(lane)
    }
    32 => {
      let lane = self.read_byte()
      F32x4ReplaceLane(lane)
    }
    33 => {
      let lane = self.read_byte()
      F64x2ExtractLane(lane)
    }
    34 => {
      let lane = self.read_byte()
      F64x2ReplaceLane(lane)
    }
    // i8x16 comparisons
    35 => I8x16Eq
    36 => I8x16Ne
    37 => I8x16LtS
    38 => I8x16LtU
    39 => I8x16GtS
    40 => I8x16GtU
    41 => I8x16LeS
    42 => I8x16LeU
    43 => I8x16GeS
    44 => I8x16GeU
    // i16x8 comparisons
    45 => I16x8Eq
    46 => I16x8Ne
    47 => I16x8LtS
    48 => I16x8LtU
    49 => I16x8GtS
    50 => I16x8GtU
    51 => I16x8LeS
    52 => I16x8LeU
    53 => I16x8GeS
    54 => I16x8GeU
    // i32x4 comparisons
    55 => I32x4Eq
    56 => I32x4Ne
    57 => I32x4LtS
    58 => I32x4LtU
    59 => I32x4GtS
    60 => I32x4GtU
    61 => I32x4LeS
    62 => I32x4LeU
    63 => I32x4GeS
    64 => I32x4GeU
    // f32x4 comparisons
    65 => F32x4Eq
    66 => F32x4Ne
    67 => F32x4Lt
    68 => F32x4Gt
    69 => F32x4Le
    70 => F32x4Ge
    // f64x2 comparisons
    71 => F64x2Eq
    72 => F64x2Ne
    73 => F64x2Lt
    74 => F64x2Gt
    75 => F64x2Le
    76 => F64x2Ge
    // v128 bitwise
    77 => V128Not
    78 => V128And
    79 => V128AndNot
    80 => V128Or
    81 => V128Xor
    82 => V128Bitselect
    83 => V128AnyTrue
    // Load lane operations
    84 => {
      let (memidx, align, offset) = self.read_memarg()
      let lane = self.read_byte()
      V128Load8Lane(memidx, align, offset, lane)
    }
    85 => {
      let (memidx, align, offset) = self.read_memarg()
      let lane = self.read_byte()
      V128Load16Lane(memidx, align, offset, lane)
    }
    86 => {
      let (memidx, align, offset) = self.read_memarg()
      let lane = self.read_byte()
      V128Load32Lane(memidx, align, offset, lane)
    }
    87 => {
      let (memidx, align, offset) = self.read_memarg()
      let lane = self.read_byte()
      V128Load64Lane(memidx, align, offset, lane)
    }
    // Store lane operations
    88 => {
      let (memidx, align, offset) = self.read_memarg()
      let lane = self.read_byte()
      V128Store8Lane(memidx, align, offset, lane)
    }
    89 => {
      let (memidx, align, offset) = self.read_memarg()
      let lane = self.read_byte()
      V128Store16Lane(memidx, align, offset, lane)
    }
    90 => {
      let (memidx, align, offset) = self.read_memarg()
      let lane = self.read_byte()
      V128Store32Lane(memidx, align, offset, lane)
    }
    91 => {
      let (memidx, align, offset) = self.read_memarg()
      let lane = self.read_byte()
      V128Store64Lane(memidx, align, offset, lane)
    }
    // Load zero operations
    92 => {
      let (memidx, align, offset) = self.read_memarg()
      V128Load32Zero(memidx, align, offset)
    }
    93 => {
      let (memidx, align, offset) = self.read_memarg()
      V128Load64Zero(memidx, align, offset)
    }
    // Floating-point rounding
    94 => F32x4DemoteF64x2Zero
    95 => F64x2PromoteLowF32x4
    // i8x16 operations
    96 => I8x16Abs
    97 => I8x16Neg
    98 => I8x16Popcnt
    99 => I8x16AllTrue
    100 => I8x16Bitmask
    101 => I8x16NarrowI16x8S
    102 => I8x16NarrowI16x8U
    103 => F32x4Ceil
    104 => F32x4Floor
    105 => F32x4Trunc
    106 => F32x4Nearest
    107 => I8x16Shl
    108 => I8x16ShrS
    109 => I8x16ShrU
    110 => I8x16Add
    111 => I8x16AddSatS
    112 => I8x16AddSatU
    113 => I8x16Sub
    114 => I8x16SubSatS
    115 => I8x16SubSatU
    116 => F64x2Ceil
    117 => F64x2Floor
    118 => I8x16MinS
    119 => I8x16MinU
    120 => I8x16MaxS
    121 => I8x16MaxU
    122 => F64x2Trunc
    123 => I8x16AvgrU
    124 => I16x8ExtAddPairwiseI8x16S
    125 => I16x8ExtAddPairwiseI8x16U
    126 => I32x4ExtAddPairwiseI16x8S
    127 => I32x4ExtAddPairwiseI16x8U
    // i16x8 operations
    128 => I16x8Abs
    129 => I16x8Neg
    130 => I16x8Q15MulrSatS
    131 => I16x8AllTrue
    132 => I16x8Bitmask
    133 => I16x8NarrowI32x4S
    134 => I16x8NarrowI32x4U
    135 => I16x8ExtendLowI8x16S
    136 => I16x8ExtendHighI8x16S
    137 => I16x8ExtendLowI8x16U
    138 => I16x8ExtendHighI8x16U
    139 => I16x8Shl
    140 => I16x8ShrS
    141 => I16x8ShrU
    142 => I16x8Add
    143 => I16x8AddSatS
    144 => I16x8AddSatU
    145 => I16x8Sub
    146 => I16x8SubSatS
    147 => I16x8SubSatU
    148 => F64x2Nearest
    149 => I16x8Mul
    150 => I16x8MinS
    151 => I16x8MinU
    152 => I16x8MaxS
    153 => I16x8MaxU
    // 154 is reserved
    155 => I16x8AvgrU
    156 => I16x8ExtMulLowI8x16S
    157 => I16x8ExtMulHighI8x16S
    158 => I16x8ExtMulLowI8x16U
    159 => I16x8ExtMulHighI8x16U
    // i32x4 operations
    160 => I32x4Abs
    161 => I32x4Neg
    // 162 is reserved
    163 => I32x4AllTrue
    164 => I32x4Bitmask
    // 165-166 are reserved
    167 => I32x4ExtendLowI16x8S
    168 => I32x4ExtendHighI16x8S
    169 => I32x4ExtendLowI16x8U
    170 => I32x4ExtendHighI16x8U
    171 => I32x4Shl
    172 => I32x4ShrS
    173 => I32x4ShrU
    174 => I32x4Add
    // 175-176 are reserved
    177 => I32x4Sub
    // 178-180 are reserved
    181 => I32x4Mul
    182 => I32x4MinS
    183 => I32x4MinU
    184 => I32x4MaxS
    185 => I32x4MaxU
    186 => I32x4DotI16x8S
    // 187 is reserved
    188 => I32x4ExtMulLowI16x8S
    189 => I32x4ExtMulHighI16x8S
    190 => I32x4ExtMulLowI16x8U
    191 => I32x4ExtMulHighI16x8U
    // i64x2 operations
    192 => I64x2Abs
    193 => I64x2Neg
    // 194 is reserved
    195 => I64x2AllTrue
    196 => I64x2Bitmask
    // 197-198 are reserved
    199 => I64x2ExtendLowI32x4S
    200 => I64x2ExtendHighI32x4S
    201 => I64x2ExtendLowI32x4U
    202 => I64x2ExtendHighI32x4U
    203 => I64x2Shl
    204 => I64x2ShrS
    205 => I64x2ShrU
    206 => I64x2Add
    // 207-208 are reserved
    209 => I64x2Sub
    // 210-212 are reserved
    213 => I64x2Mul
    214 => I64x2Eq
    215 => I64x2Ne
    216 => I64x2LtS
    217 => I64x2GtS
    218 => I64x2LeS
    219 => I64x2GeS
    220 => I64x2ExtMulLowI32x4S
    221 => I64x2ExtMulHighI32x4S
    222 => I64x2ExtMulLowI32x4U
    223 => I64x2ExtMulHighI32x4U
    // f32x4 operations
    224 => F32x4Abs
    225 => F32x4Neg
    // 226 is reserved
    227 => F32x4Sqrt
    228 => F32x4Add
    229 => F32x4Sub
    230 => F32x4Mul
    231 => F32x4Div
    232 => F32x4Min
    233 => F32x4Max
    234 => F32x4Pmin
    235 => F32x4Pmax
    // f64x2 operations
    236 => F64x2Abs
    237 => F64x2Neg
    // 238 is reserved
    239 => F64x2Sqrt
    240 => F64x2Add
    241 => F64x2Sub
    242 => F64x2Mul
    243 => F64x2Div
    244 => F64x2Min
    245 => F64x2Max
    246 => F64x2Pmin
    247 => F64x2Pmax
    // Conversions
    248 => I32x4TruncSatF32x4S
    249 => I32x4TruncSatF32x4U
    250 => F32x4ConvertI32x4S
    251 => F32x4ConvertI32x4U
    252 => I32x4TruncSatF64x2SZero
    253 => I32x4TruncSatF64x2UZero
    254 => F64x2ConvertLowI32x4S
    255 => F64x2ConvertLowI32x4U
    // Relaxed SIMD instructions (0x100+)
    256 => I8x16RelaxedSwizzle
    257 => I32x4RelaxedTruncF32x4S
    258 => I32x4RelaxedTruncF32x4U
    259 => I32x4RelaxedTruncF64x2SZero
    260 => I32x4RelaxedTruncF64x2UZero
    261 => F32x4RelaxedMadd
    262 => F32x4RelaxedNmadd
    263 => F64x2RelaxedMadd
    264 => F64x2RelaxedNmadd
    265 => I8x16RelaxedLaneselect
    266 => I16x8RelaxedLaneselect
    267 => I32x4RelaxedLaneselect
    268 => I64x2RelaxedLaneselect
    269 => F32x4RelaxedMin
    270 => F32x4RelaxedMax
    271 => F64x2RelaxedMin
    272 => F64x2RelaxedMax
    273 => I16x8RelaxedQ15mulrS
    274 => I16x8RelaxedDotI8x16I7x16S
    275 => I32x4RelaxedDotI8x16I7x16AddS
    _ => raise UnknownOpcode(0xFD00 + subopcode)
  }
}

// ============================================================
// Section Parsing
// ============================================================

///|
/// Parse WebAssembly module from bytes
pub fn parse_module(data : Bytes) -> @types.Module raise ParserError {
  let parser = Parser::new(data)

  // Check magic number
  let magic = parser.read_bytes(4)
  if magic != b"\x00asm" {
    raise InvalidMagicNumber
  }

  // Check version
  let version = parser.read_bytes(4)
  if version != b"\x01\x00\x00\x00" {
    raise UnsupportedVersion
  }
  let mod = @types.Module::new()

  // Track last seen non-custom section id for ordering check
  let mut last_section_id = 0
  // Track data count from section 12 (if present)
  let mut data_count : Int? = None

  // Parse sections
  while !parser.is_eof() {
    let section_id = parser.read_byte()
    let section_size = parser.read_u32()
    let section_end = parser.pos + section_size

    // Validate section_end doesn't exceed data length
    if section_end > parser.data.length() {
      raise LengthOutOfBounds
    }

    // Check section ordering (non-custom sections must be in order, no duplicates)
    // The canonical order is: 1→2→3→4→5→6→13→7→8→9→12→10→11
    // (DataCount=12 appears between Elem=9 and Code=10, Tag=13 after Global=6)
    fn section_order(id : Int) -> Int {
      match id {
        1 => 1 // Type
        2 => 2 // Import
        3 => 3 // Function
        4 => 4 // Table
        5 => 5 // Memory
        6 => 6 // Global
        13 => 7 // Tag (exception handling, after Global)
        7 => 8 // Export
        8 => 9 // Start
        9 => 10 // Elem
        12 => 11 // DataCount (before Code)
        10 => 12 // Code
        11 => 13 // Data
        _ => id // Custom (0) or unknown
      }
    }

    if section_id != 0 {
      // Custom sections (id=0) can appear anywhere
      let current_order = section_order(section_id)
      let last_order = section_order(last_section_id)
      if current_order <= last_order {
        raise DuplicateSection(section_id)
      }
      last_section_id = section_id
    }
    match section_id {
      1 => {
        // Type section
        // The binary type section is a vec of rec groups (WasmGC).
        let group_count = parser.read_u32()
        for group_id in 0..<group_count {
          let group = parser.read_rec_group()
          for subtype in group {
            mod.types.push(subtype)
            mod.type_rec_groups.push(group_id)
          }
        }
      }
      2 => {
        // Import section
        let count = parser.read_u32()
        for _ in 0..<count {
          let mod_name = parser.read_string()
          let name = parser.read_string()
          let kind = parser.read_byte()
          let desc = match kind {
            0x00 => @types.ImportDesc::Func(parser.read_u32())
            0x01 => @types.ImportDesc::Table(parser.read_table_type())
            0x02 => @types.ImportDesc::Memory(parser.read_memory_type())
            0x03 => @types.ImportDesc::Global(parser.read_global_type())
            0x04 => {
              // Tag import: attribute (should be 0 for exception) + type_idx
              let _ = parser.read_byte() // attribute, always 0 for exceptions
              @types.ImportDesc::Tag(parser.read_u32())
            }
            _ => raise InvalidImportKind(kind)
          }
          mod.imports.push({ mod_name, name, desc })
        }
      }
      3 => {
        // Function section
        let count = parser.read_u32()
        for _ in 0..<count {
          mod.funcs.push(parser.read_u32())
        }
      }
      4 => {
        // Table section
        let count = parser.read_u32()
        for _ in 0..<count {
          mod.tables.push(parser.read_table())
        }
      }
      5 => {
        // Memory section
        let count = parser.read_u32()
        for _ in 0..<count {
          mod.memories.push(parser.read_memory_type())
        }
      }
      6 => {
        // Global section
        let count = parser.read_u32()
        for _ in 0..<count {
          let type_ = parser.read_global_type()
          let init = parser.read_expr()
          mod.globals.push({ type_, init })
        }
      }
      7 => {
        // Export section
        let count = parser.read_u32()
        for _ in 0..<count {
          let name = parser.read_string()
          let kind = parser.read_byte()
          let desc = match kind {
            0x00 => @types.ExportDesc::Func(parser.read_u32())
            0x01 => @types.ExportDesc::Table(parser.read_u32())
            0x02 => @types.ExportDesc::Memory(parser.read_u32())
            0x03 => @types.ExportDesc::Global(parser.read_u32())
            0x04 => @types.ExportDesc::Tag(parser.read_u32())
            _ => raise InvalidExportKind(kind)
          }
          mod.exports.push({ name, desc })
        }
      }
      8 =>
        // Start section
        mod.start = Some(parser.read_u32())
      9 => {
        // Element section (supports WebAssembly 1.0+ formats)
        let count = parser.read_u32()
        for _ in 0..<count {
          let flags = parser.read_u32()
          let (mode, elem_type, init) = parser.read_elem_segment(flags)
          mod.elems.push({ mode, type_: elem_type, init })
        }
      }
      10 => {
        // Code section
        let count = parser.read_u32()
        for _ in 0..<count {
          let _code_size = parser.read_u32()
          let local_count = parser.read_u32()
          let locals : Array[@types.ValueType] = []
          let mut total_locals : Int64 = 0L
          for _ in 0..<local_count {
            let n = parser.read_u32()
            let vt = parser.read_value_type()
            // Check for too many locals before accumulating
            // Treat n as unsigned by reinterpreting
            let n_unsigned = n.reinterpret_as_uint().to_int64()
            total_locals = total_locals + n_unsigned
            if total_locals > 1000000L {
              raise TooManyLocals
            }
            for _ in 0..<n {
              locals.push(vt)
            }
          }
          let body = parser.read_expr()
          mod.codes.push({ locals, body })
        }
      }
      11 => {
        // Data section (bulk-memory encoding)
        let count = parser.read_u32()
        for _ in 0..<count {
          let flags = parser.read_u32()
          let (memory_idx, offset) : (Int, Array[@types.Instruction]) = match
            flags {
            0 => {
              // Active segment with implicit memory 0
              let offset = parser.read_expr()
              (0, offset)
            }
            1 =>
              // Passive segment (no memory, no offset)
              (0, [])
            2 => {
              // Active segment with explicit memory index
              let memory_idx = parser.read_u32()
              let offset = parser.read_expr()
              (memory_idx, offset)
            }
            _ => raise MalformedDataSegmentFlags(flags)
          }
          let size = parser.read_u32()
          let init = parser.read_bytes(size)
          mod.datas.push({ memory_idx, offset, init })
        }
      }
      0 => {
        // Custom section - parse and validate name, then skip rest
        // Custom section must have at least a name (which requires at least 1 byte for length)
        if section_size == 0 {
          raise UnexpectedEnd
        }
        // Read and validate the custom section name as UTF-8
        let _ = parser.read_string()
        // Skip any remaining custom section content
        parser.pos = section_end
      }
      12 => {
        // Data count section (bulk memory)
        data_count = Some(parser.read_u32())
        parser.has_data_count = true
      }
      13 => {
        // Tag section (exception handling)
        let count = parser.read_u32()
        for _ in 0..<count {
          let _ = parser.read_byte() // attribute, always 0 for exceptions
          let type_idx = parser.read_u32()
          mod.tags.push(@types.TagType::{ type_idx, })
        }
      }
      _ =>
        // Invalid section id (valid range is 0-13)
        raise MalformedSectionId(section_id)
    }

    // Ensure we're at the expected position
    if parser.pos != section_end {
      raise SectionSizeMismatch
    }
  }

  // Verify function and code section counts match
  if mod.funcs.length() != mod.codes.length() {
    raise FunctionCodeMismatch
  }

  // Verify data count and data section counts match (if data count section present)
  if data_count is Some(count) && count != mod.datas.length() {
    raise DataCountMismatch
  }

  // Check for unexpected content after last section
  if !parser.is_eof() {
    raise UnexpectedContent
  }
  mod
}

// ============================================================
// Parser Tests
// ============================================================

///|
test "LEB128 u32 decoding - single byte" {
  let parser = Parser::new(b"\x7F") // 127
  inspect(parser.read_leb128_u32(), content="127")
}

///|
test "LEB128 u32 decoding - multi byte" {
  let parser = Parser::new(b"\xE5\x8E\x26") // 624485
  inspect(parser.read_leb128_u32(), content="624485")
}

///|
test "LEB128 i32 decoding - negative" {
  let parser = Parser::new(b"\x7E") // -2
  inspect(parser.read_leb128_i32(), content="-2")
}

///|
test "LEB128 i64 decoding" {
  let parser = Parser::new(b"\x80\x80\x80\x80\x80\x01") // 2^32
  inspect(parser.read_leb128_i64(), content="34359738368")
}

///|
test "LEB128 u32 - too long (6 bytes)" {
  // 6 bytes encoding value 3: \x83\x80\x80\x80\x80\x00
  let parser = Parser::new(b"\x83\x80\x80\x80\x80\x00")
  inspect(
    try? parser.read_leb128_u32(),
    content="Err(LEB128 encoded integer is too large)",
  )
}

///|
test "LEB128 u32 - 5th byte with unused bits set" {
  // Value 3 with 5th byte having bit 4 set: \x83\x80\x80\x80\x10
  let parser = Parser::new(b"\x83\x80\x80\x80\x10")
  inspect(
    try? parser.read_leb128_u32(),
    content="Err(LEB128 encoded integer is too large)",
  )
}

///|
test "LEB128 u32 - valid 5 byte encoding" {
  // Maximum u32 (0xFFFFFFFF): \xFF\xFF\xFF\xFF\x0F
  let parser = Parser::new(b"\xFF\xFF\xFF\xFF\x0F")
  inspect(parser.read_leb128_u32(), content="-1") // -1 as signed = 0xFFFFFFFF
}

///|
test "LEB128 i32 - unused bits not sign-extended (positive)" {
  // i32.const 0 with 5th byte = 0x70 (bits 4-6 should be 0 for positive)
  let parser = Parser::new(b"\x80\x80\x80\x80\x70")
  inspect(
    try? parser.read_leb128_i32(),
    content="Err(LEB128 encoded integer is too large)",
  )
}

///|
test "LEB128 i32 - unused bits not sign-extended (negative)" {
  // i32.const -1 with 5th byte = 0x0F (bits 4-6 should be 1 for negative)
  let parser = Parser::new(b"\xFF\xFF\xFF\xFF\x0F")
  inspect(
    try? parser.read_leb128_i32(),
    content="Err(LEB128 encoded integer is too large)",
  )
}

///|
test "LEB128 i32 - valid positive 5 byte" {
  // Maximum positive i32 (0x7FFFFFFF): bits 4-6 = 0 in 5th byte
  let parser = Parser::new(b"\xFF\xFF\xFF\xFF\x07")
  inspect(parser.read_leb128_i32(), content="2147483647")
}

///|
test "LEB128 i32 - valid negative 5 byte" {
  // -1 with proper sign extension: bits 4-6 = 1 in 5th byte
  let parser = Parser::new(b"\xFF\xFF\xFF\xFF\x7F")
  inspect(parser.read_leb128_i32(), content="-1")
}

///|
test "LEB128 i64 - unused bits not sign-extended" {
  // i64.const 0 with 10th byte = 0x7E (bits 1-6 should be 0 for positive)
  let parser = Parser::new(b"\x80\x80\x80\x80\x80\x80\x80\x80\x80\x7E")
  inspect(
    try? parser.read_leb128_i64(),
    content="Err(LEB128 encoded integer is too large)",
  )
}

///|
test "LEB128 i64 - valid maximum positive" {
  // Maximum positive i64: 0x7FFFFFFFFFFFFFFF
  let parser = Parser::new(b"\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x00")
  inspect(parser.read_leb128_i64(), content="9223372036854775807")
}

///|
test "value type parsing" {
  let parser = Parser::new(b"\x7F\x7E\x7D\x7C")
  inspect(parser.read_value_type(), content="I32")
  inspect(parser.read_value_type(), content="I64")
  inspect(parser.read_value_type(), content="F32")
  inspect(parser.read_value_type(), content="F64")
}

///|
test "peek_byte does not consume" {
  let parser = Parser::new(b"\x42")
  let first = parser.peek_byte()
  let second = parser.peek_byte()
  let consumed = parser.read_byte()
  inspect((first, second, consumed), content="(66, 66, 66)")
}

///|
test "f32 parsing - 1.0" {
  // IEEE 754: 1.0f = 0x3F800000, little-endian: 00 00 80 3F
  let parser = Parser::new(b"\x00\x00\x80\x3F")
  inspect(parser.read_f32(), content="1")
}

///|
test "f64 parsing - 1.0" {
  // IEEE 754: 1.0 = 0x3FF0000000000000, little-endian: 00 00 00 00 00 00 F0 3F
  let parser = Parser::new(b"\x00\x00\x00\x00\x00\x00\xF0\x3F")
  inspect(parser.read_f64(), content="1")
}

// ============================================================
// Custom Section Validation Tests (custom.wast regression)
// ============================================================

///|
test "custom section - empty section should fail" {
  // custom.wast line 76: \00asm \01\00\00\00 \00\00
  // section_id=0, section_size=0, but custom section must have a name
  let bytes = b"\x00asm\x01\x00\x00\x00\x00\x00"
  inspect(try? parse_module(bytes), content="Err(unexpected end)")
}

///|
test "custom section - length out of bounds" {
  // custom.wast line 84: section claims 0x26=38 bytes but only 36 available
  // \00asm \01\00\00\00 \00\26\10 "a custom section" "this is the payload"
  let bytes = b"\x00asm\x01\x00\x00\x00\x00\x26\x10a custom sectionthis is the payload"
  inspect(try? parse_module(bytes), content="Err(length out of bounds)")
}

///|
test "custom section - concatenated modules" {
  // custom.wast line 114: two wasm modules concatenated
  // \00asm\01\00\00\00 \00asm\01\00\00\00
  let bytes = b"\x00asm\x01\x00\x00\x00\x00asm\x01\x00\x00\x00"
  inspect(try? parse_module(bytes), content="Err(length out of bounds)")
}
