// ============================================================
// Basic Type Parsing
// ============================================================

///|
/// Read a u32
fn Parser::read_u32(self : Parser) -> Int32 raise ParserError {
  self.read_leb128_u32()
}

///|
/// Read a u64
fn Parser::read_u64(self : Parser) -> Int64 raise ParserError {
  self.read_leb128_u64()
}

///|
/// Decode memory arguments; natural alignment is checked by the validator.
/// Bit 6 selects an explicit memory index, and the low six bits encode alignment.
fn Parser::read_memarg(
  self : Parser,
) -> (Int32, Int32, Int64) raise ParserError {
  let flags = self.read_leb128_u32()
  if flags.reinterpret_as_uint() >= 0x80U {
    raise MalformedMemopFlags
  }
  let memidx = if (flags & 0x40) != 0 { self.read_leb128_u32() } else { 0 }
  let align = flags & 0x3F
  // Read offset as u64 to support memory64 64-bit offsets
  let offset = self.read_leb128_u64()
  (memidx, align, offset)
}

///|
/// Read an i32
fn Parser::read_i32(self : Parser) -> Int32 raise ParserError {
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
  let start = self.pos
  self.skip(len)
  @utf8.decode(self.data[start:self.pos], ignore_bom=false) catch {
    _ => raise ParseError("malformed UTF-8 encoding")
  }
}
