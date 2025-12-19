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
  ParseError(String) // Generic error with message
}

///|
/// Convert int to hex string
fn int_to_hex(n : Int) -> String {
  if n == 0 {
    return "0"
  }
  let digits = "0123456789abcdef"
  let buf = StringBuilder::new()
  let mut val = n
  while val > 0 {
    let digit = val % 16
    buf.write_char(digits.code_unit_at(digit).unsafe_to_char())
    val = val / 16
  }
  // Reverse the string
  let s = buf.to_string()
  let len = s.length()
  let result = StringBuilder::new()
  for i in 0..<len {
    result.write_char(s.code_unit_at(len - 1 - i).unsafe_to_char())
  }
  result.to_string()
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
} derive(Show)

///|
/// Create a new parser from bytes
pub fn Parser::new(data : Bytes) -> Parser {
  { data, pos: 0 }
}

///|
/// Generic error with position info
fn[A] Parser::error(self : Parser, msg : String) -> A raise ParserError {
  raise ParseError("\{msg} at position \{self.pos}")
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

// ============================================================
// Basic Type Parsing
// ============================================================

///|
/// Read a u32
fn Parser::read_u32(self : Parser) -> Int raise ParserError {
  self.read_leb128_u32()
}

///|
/// Read memory argument (align, offset) with validation
/// Alignment values >= 32 are reserved and should be rejected as malformed
fn Parser::read_memarg(self : Parser) -> (Int, Int) raise ParserError {
  let align = self.read_leb128_u32()
  // WebAssembly spec: alignment values >= 32 are reserved
  if align >= 32 {
    raise MalformedMemopFlags
  }
  let offset = self.read_leb128_u32()
  (align, offset)
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
fn Parser::read_value_type(self : Parser) -> @types.ValueType raise ParserError {
  let byte = self.read_byte()
  match byte {
    0x7F => I32
    0x7E => I64
    0x7D => F32
    0x7C => F64
    0x7B => V128
    0x70 => FuncRef
    0x6F => ExternRef
    0x64 => {
      // Non-null reference type: (ref heaptype)
      let heap_type = self.read_heap_type()
      match heap_type {
        0x70 => RefFunc // (ref func)
        0x6F => RefExtern // (ref extern)
        _ => RefFunc // Default to RefFunc for typed references
      }
    }
    0x63 => {
      // Nullable reference type: (ref null heaptype)
      let heap_type = self.read_heap_type()
      match heap_type {
        0x70 => FuncRef // (ref null func) = funcref
        0x6F => ExternRef // (ref null extern) = externref
        _ => FuncRef // Default to FuncRef
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
    0x7F | 0x7E | 0x7D | 0x7C | 0x7B | 0x70 | 0x6F | 0x64 | 0x63 =>
      Value(self.read_value_type())
    _ => TypeIndex(self.read_i32())
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

///|
fn Parser::read_func_type(self : Parser) -> @types.FuncType raise ParserError {
  let tag = self.read_byte()
  if tag != 0x60 {
    self.error("expected function type tag 0x60, got \{tag}")
  }
  let params = self.read_vec(fn() { self.read_value_type() })
  let results = self.read_vec(fn() { self.read_value_type() })
  { params, results }
}

// ============================================================
// Limits Parsing
// ============================================================

///|
fn Parser::read_limits(self : Parser) -> @types.Limits raise ParserError {
  let flags = self.read_byte()
  // Valid flags: 0x00 (no max), 0x01 (has max), 0x03 (shared memory with max)
  if flags != 0x00 && flags != 0x01 && flags != 0x03 {
    raise MalformedLimitsFlags(flags)
  }
  let min = self.read_u32()
  let max = if flags == 0x01 || flags == 0x03 {
    Some(self.read_u32())
  } else {
    None
  }
  { min, max }
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
    let limits = self.read_limits()
    // Read the initialization expression
    let init = self.read_expr()
    { type_: { elem_type, limits }, init: Some(init) }
  } else {
    // Standard encoding: reftype limits
    let elem_type = self.read_value_type()
    let limits = self.read_limits()
    { type_: { elem_type, limits }, init: None }
  }
}

///|
fn Parser::read_table_type(self : Parser) -> @types.TableType raise ParserError {
  // For imports, we just need the table type (no init expression)
  let elem_type = self.read_value_type()
  let limits = self.read_limits()
  { elem_type, limits }
}

///|
fn Parser::read_memory_type(
  self : Parser,
) -> @types.MemoryType raise ParserError {
  let limits = self.read_limits()
  { limits, }
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
    let type_byte = self.read_byte()
    match type_byte {
      0x70 => @types.ValueType::FuncRef
      0x6F => @types.ValueType::ExternRef
      0x64 => {
        // Non-null reference type: (ref heaptype)
        let heap_type = self.read_heap_type()
        match heap_type {
          0x70 => @types.ValueType::RefFunc
          0x6F => @types.ValueType::RefExtern
          _ => @types.ValueType::RefFunc
        }
      }
      0x63 => {
        // Nullable reference type: (ref null heaptype)
        let heap_type = self.read_heap_type()
        match heap_type {
          0x70 => @types.ValueType::FuncRef
          0x6F => @types.ValueType::ExternRef
          _ => @types.ValueType::FuncRef
        }
      }
      _ => raise MalformedReferenceType(type_byte)
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
      let then_body = self.read_expr()
      // Check for else clause using peek
      if self.peek_byte() == 0x05 {
        self.skip(1) // consume else opcode
        let else_body = self.read_expr()
        If(bt, then_body, else_body)
      } else {
        If(bt, then_body, [])
      }
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
    // Parametric instructions
    0x1A => Drop
    0x1B => Select
    // Variable instructions
    0x20 => LocalGet(self.read_u32())
    0x21 => LocalSet(self.read_u32())
    0x22 => LocalTee(self.read_u32())
    0x23 => GlobalGet(self.read_u32())
    0x24 => GlobalSet(self.read_u32())
    // Memory instructions (with alignment validation)
    0x28 => {
      let (align, offset) = self.read_memarg()
      I32Load(align, offset)
    }
    0x29 => {
      let (align, offset) = self.read_memarg()
      I64Load(align, offset)
    }
    0x2A => {
      let (align, offset) = self.read_memarg()
      F32Load(align, offset)
    }
    0x2B => {
      let (align, offset) = self.read_memarg()
      F64Load(align, offset)
    }
    0x2C => {
      let (align, offset) = self.read_memarg()
      I32Load8S(align, offset)
    }
    0x2D => {
      let (align, offset) = self.read_memarg()
      I32Load8U(align, offset)
    }
    0x2E => {
      let (align, offset) = self.read_memarg()
      I32Load16S(align, offset)
    }
    0x2F => {
      let (align, offset) = self.read_memarg()
      I32Load16U(align, offset)
    }
    0x30 => {
      let (align, offset) = self.read_memarg()
      I64Load8S(align, offset)
    }
    0x31 => {
      let (align, offset) = self.read_memarg()
      I64Load8U(align, offset)
    }
    0x32 => {
      let (align, offset) = self.read_memarg()
      I64Load16S(align, offset)
    }
    0x33 => {
      let (align, offset) = self.read_memarg()
      I64Load16U(align, offset)
    }
    0x34 => {
      let (align, offset) = self.read_memarg()
      I64Load32S(align, offset)
    }
    0x35 => {
      let (align, offset) = self.read_memarg()
      I64Load32U(align, offset)
    }
    // Memory store instructions (with alignment validation)
    0x36 => {
      let (align, offset) = self.read_memarg()
      I32Store(align, offset)
    }
    0x37 => {
      let (align, offset) = self.read_memarg()
      I64Store(align, offset)
    }
    0x38 => {
      let (align, offset) = self.read_memarg()
      F32Store(align, offset)
    }
    0x39 => {
      let (align, offset) = self.read_memarg()
      F64Store(align, offset)
    }
    0x3A => {
      let (align, offset) = self.read_memarg()
      I32Store8(align, offset)
    }
    0x3B => {
      let (align, offset) = self.read_memarg()
      I32Store16(align, offset)
    }
    0x3C => {
      let (align, offset) = self.read_memarg()
      I64Store8(align, offset)
    }
    0x3D => {
      let (align, offset) = self.read_memarg()
      I64Store16(align, offset)
    }
    0x3E => {
      let (align, offset) = self.read_memarg()
      I64Store32(align, offset)
    }
    0x3F => {
      self.read_byte() |> ignore // reserved byte
      MemorySize
    }
    0x40 => {
      self.read_byte() |> ignore // reserved byte
      MemoryGrow
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
      // ref.null: read reftype (0x70 = funcref, 0x6F = externref)
      let reftype = self.read_byte()
      match reftype {
        0x70 => RefNull(@types.ValueType::FuncRef)
        0x6F => RefNull(@types.ValueType::ExternRef)
        _ => raise UnknownOpcode(0xD000 + reftype)
      }
    }
    0xD1 => RefIsNull
    0xD2 => {
      // ref.func: read function index
      let func_idx = self.read_u32()
      RefFunc(func_idx)
    }
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
          // memory.init: data_idx, memory_idx (memory_idx must be 0)
          let data_idx = self.read_u32()
          self.read_byte() |> ignore // memory index, must be 0
          MemoryInit(data_idx)
        }
        9 => {
          // data.drop: data_idx
          let data_idx = self.read_u32()
          DataDrop(data_idx)
        }
        10 => {
          // memory.copy: dest_mem, src_mem (both must be 0)
          self.read_byte() |> ignore // dest memory index
          self.read_byte() |> ignore // src memory index
          MemoryCopy
        }
        11 => {
          // memory.fill: memory_idx (must be 0)
          self.read_byte() |> ignore // memory index
          MemoryFill
        }
        13 => {
          // elem.drop: elem_idx
          let elem_idx = self.read_u32()
          ElemDrop(elem_idx)
        }
        _ => raise UnknownOpcode(0xFC00 + subopcode)
      }
    }
    _ => raise UnknownOpcode(opcode)
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
    if section_id != 0 {
      // Custom sections (id=0) can appear anywhere
      if section_id <= last_section_id {
        raise DuplicateSection(section_id)
      }
      last_section_id = section_id
    }
    match section_id {
      1 => {
        // Type section
        let count = parser.read_u32()
        for _ in 0..<count {
          mod.types.push(parser.read_func_type())
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
        // Data section
        let count = parser.read_u32()
        for _ in 0..<count {
          let memory_idx = parser.read_u32()
          let offset = parser.read_expr()
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
      12 =>
        // Data count section (bulk memory)
        data_count = Some(parser.read_u32())
      13 =>
        // Tag section (exception handling) - skip for now
        parser.pos = section_end
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
