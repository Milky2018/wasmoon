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
