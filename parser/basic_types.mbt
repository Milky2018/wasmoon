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
