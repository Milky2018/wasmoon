// Binary parser for WebAssembly modules
// Implements LEB128 decoding and section parsing

// ============================================================
// Parser Errors
// ============================================================

///|
suberror ParserError {
  UnexpectedEndOfInput
  InvalidMagicNumber
  UnsupportedVersion
  InvalidValueType(Int)
  InvalidSectionId(Int)
  LEB128TooLarge
  SectionSizeMismatch
  UnknownOpcode(Int)
  InvalidImportKind(Int)
  InvalidExportKind(Int)
  ParseError(String) // Generic error with message
} derive(Show)

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
  Int::reinterpret_as_float(bits)
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
/// Read a UTF-8 string
fn Parser::read_string(self : Parser) -> String raise ParserError {
  let len = self.read_u32()
  let bytes = self.read_bytes(len)
  // Convert bytes to string
  bytes.to_string()
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
    _ => raise InvalidValueType(byte)
  }
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
    0x7F | 0x7E | 0x7D | 0x7C | 0x7B | 0x70 | 0x6F =>
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
  let min = self.read_u32()
  let max = if flags == 0x01 { Some(self.read_u32()) } else { None }
  { min, max }
}

// ============================================================
// Table and Memory Type Parsing
// ============================================================

///|
fn Parser::read_table_type(self : Parser) -> @types.TableType raise ParserError {
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
  { value_type, mutable: mutability == 0x01 }
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
    // Memory instructions
    0x28 => {
      let align = self.read_u32()
      let offset = self.read_u32()
      I32Load(align, offset)
    }
    0x29 => {
      let align = self.read_u32()
      let offset = self.read_u32()
      I64Load(align, offset)
    }
    0x2A => {
      let align = self.read_u32()
      let offset = self.read_u32()
      F32Load(align, offset)
    }
    0x2B => {
      let align = self.read_u32()
      let offset = self.read_u32()
      F64Load(align, offset)
    }
    // Memory store instructions
    0x36 => {
      let align = self.read_u32()
      let offset = self.read_u32()
      I32Store(align, offset)
    }
    0x37 => {
      let align = self.read_u32()
      let offset = self.read_u32()
      I64Store(align, offset)
    }
    0x38 => {
      let align = self.read_u32()
      let offset = self.read_u32()
      F32Store(align, offset)
    }
    0x39 => {
      let align = self.read_u32()
      let offset = self.read_u32()
      F64Store(align, offset)
    }
    0x3F => {
      let _ = self.read_byte() // reserved byte
      MemorySize
    }
    0x40 => {
      let _ = self.read_byte() // reserved byte
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
          let _ = self.read_byte() // memory index, must be 0
          MemoryInit(data_idx)
        }
        9 => {
          // data.drop: data_idx
          let data_idx = self.read_u32()
          DataDrop(data_idx)
        }
        10 => {
          // memory.copy: dest_mem, src_mem (both must be 0)
          let _ = self.read_byte() // dest memory index
          let _ = self.read_byte() // src memory index
          MemoryCopy
        }
        11 => {
          // memory.fill: memory_idx (must be 0)
          let _ = self.read_byte() // memory index
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

  // Parse sections
  while !parser.is_eof() {
    let section_id = parser.read_byte()
    let section_size = parser.read_u32()
    let section_end = parser.pos + section_size
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
          mod.tables.push(parser.read_table_type())
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
        // Element section
        let count = parser.read_u32()
        for _ in 0..<count {
          let table_idx = parser.read_u32()
          let offset = parser.read_expr()
          let elem_count = parser.read_u32()
          let init : Array[Int] = []
          for _ in 0..<elem_count {
            init.push(parser.read_u32())
          }
          mod.elems.push({ table_idx, offset, init })
        }
      }
      10 => {
        // Code section
        let count = parser.read_u32()
        for _ in 0..<count {
          let _code_size = parser.read_u32()
          let local_count = parser.read_u32()
          let locals : Array[@types.ValueType] = []
          for _ in 0..<local_count {
            let n = parser.read_u32()
            let vt = parser.read_value_type()
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
      0 =>
        // Custom section - skip for now
        parser.pos = section_end
      _ =>
        // Unknown section - skip
        parser.pos = section_end
    }

    // Ensure we're at the expected position
    if parser.pos != section_end {
      raise SectionSizeMismatch
    }
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
