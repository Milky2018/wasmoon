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
/// Check if we can read n bytes
fn Parser::can_read(self : Parser, n : Int) -> Bool {
  self.pos + n <= self.data.length()
}

///|
/// Read a single byte
fn Parser::read_byte(self : Parser) -> Int raise ParserError {
  if not(self.can_read(1)) {
    raise UnexpectedEndOfInput
  }
  let byte = self.data[self.pos].to_int()
  self.pos = self.pos + 1
  byte
}

///|
/// Read n bytes
fn Parser::read_bytes(self : Parser, n : Int) -> Bytes raise ParserError {
  if not(self.can_read(n)) {
    raise UnexpectedEndOfInput
  }
  let bytes : Array[Byte] = []
  for i = 0; i < n; i = i + 1 {
    bytes.push(self.data[self.pos + i])
  }
  self.pos = self.pos + n
  Bytes::from_array(bytes)
}

// ============================================================
// LEB128 Decoding
// ============================================================

///|
/// Decode unsigned LEB128
fn Parser::read_leb128_u32(self : Parser) -> Int raise ParserError {
  fn go(result : Int, shift : Int) -> Int raise ParserError {
    if shift > 28 {
      raise LEB128TooLarge
    }
    let byte = self.read_byte()
    let new_result = result | ((byte & 0x7F) << shift)
    if (byte & 0x80) == 0 {
      new_result
    } else {
      go(new_result, shift + 7)
    }
  }

  go(0, 0)
}

///|
/// Decode signed LEB128
fn Parser::read_leb128_i32(self : Parser) -> Int raise ParserError {
  fn go(result : Int, shift : Int) -> Int raise ParserError {
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
      go(new_result, new_shift)
    }
  }

  go(0, 0)
}

///|
/// Decode signed LEB128 i64
fn Parser::read_leb128_i64(self : Parser) -> Int64 raise ParserError {
  fn go(result : Int64, shift : Int) -> Int64 raise ParserError {
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
      go(new_result, new_shift)
    }
  }

  go(0L, 0)
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
/// Read f32
fn Parser::read_f32(self : Parser) -> Float raise ParserError {
  let _bytes = self.read_bytes(4)
  // TODO: Convert bytes to f32 using proper IEEE 754 decoding
  // For now, return a placeholder
  0.0
}

///|
/// Read f64
fn Parser::read_f64(self : Parser) -> Double raise ParserError {
  let _bytes = self.read_bytes(8)
  // TODO: Convert bytes to f64 using proper IEEE 754 decoding
  // For now, return a placeholder
  0.0
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
fn Parser::read_value_type(self : Parser) -> ValueType raise ParserError {
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
/// Read block type
fn Parser::read_block_type(self : Parser) -> BlockType raise ParserError {
  let byte = self.read_byte()
  match byte {
    0x40 => Empty
    0x7F | 0x7E | 0x7D | 0x7C | 0x7B | 0x70 | 0x6F => {
      self.pos = self.pos - 1 // rewind
      let vt = self.read_value_type()
      Value(vt)
    }
    _ => {
      self.pos = self.pos - 1 // rewind
      let idx = self.read_i32()
      TypeIndex(idx)
    }
  }
}

// ============================================================
// Function Type Parsing
// ============================================================

///|
fn Parser::read_func_type(self : Parser) -> FuncType raise ParserError {
  let tag = self.read_byte()
  if tag != 0x60 {
    raise UnexpectedEndOfInput // TODO: better error
  }

  // Read parameter types
  let param_count = self.read_u32()
  let params : Array[ValueType] = []
  for i = 0; i < param_count; i = i + 1 {
    params.push(self.read_value_type())
  }

  // Read result types
  let result_count = self.read_u32()
  let results : Array[ValueType] = []
  for i = 0; i < result_count; i = i + 1 {
    results.push(self.read_value_type())
  }
  { params, results }
}

// ============================================================
// Limits Parsing
// ============================================================

///|
fn Parser::read_limits(self : Parser) -> Limits raise ParserError {
  let flags = self.read_byte()
  let min = self.read_u32()
  let max = if flags == 0x01 { Some(self.read_u32()) } else { None }
  { min, max }
}

// ============================================================
// Table and Memory Type Parsing
// ============================================================

///|
fn Parser::read_table_type(self : Parser) -> TableType raise ParserError {
  let elem_type = self.read_value_type()
  let limits = self.read_limits()
  { elem_type, limits }
}

///|
fn Parser::read_memory_type(self : Parser) -> MemoryType raise ParserError {
  let limits = self.read_limits()
  { limits, }
}

///|
fn Parser::read_global_type(self : Parser) -> GlobalType raise ParserError {
  let value_type = self.read_value_type()
  let mutability = self.read_byte()
  { value_type, mutable: mutability == 0x01 }
}

// ============================================================
// Instruction Parsing
// ============================================================

///|
fn Parser::read_expr(self : Parser) -> Array[Instruction] raise ParserError {
  fn go(
    instructions : Array[Instruction],
  ) -> Array[Instruction] raise ParserError {
    let opcode = self.read_byte()
    if opcode == 0x0B {
      // end
      instructions
    } else {
      instructions.push(self.read_instruction(opcode))
      go(instructions)
    }
  }

  go([])
}

///|
fn Parser::read_instruction(
  self : Parser,
  opcode : Int,
) -> Instruction raise ParserError {
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
      let next = self.read_byte()
      if next == 0x05 {
        // else
        let else_body = self.read_expr()
        If(bt, then_body, else_body)
      } else {
        self.pos = self.pos - 1
        If(bt, then_body, [])
      }
    }
    0x0C => Br(self.read_u32())
    0x0D => BrIf(self.read_u32())
    0x0E => {
      let count = self.read_u32()
      let labels : Array[Int] = []
      for i = 0; i < count; i = i + 1 {
        labels.push(self.read_u32())
      }
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
    _ => raise UnknownOpcode(opcode)
  }
}

// ============================================================
// Section Parsing
// ============================================================

///|
/// Parse WebAssembly module from bytes
pub fn parse_module(data : Bytes) -> Module raise ParserError {
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
  let mod = Module::new()

  // Parse sections
  while parser.can_read(1) {
    let section_id = parser.read_byte()
    let section_size = parser.read_u32()
    let section_end = parser.pos + section_size
    match section_id {
      1 => {
        // Type section
        let count = parser.read_u32()
        for i = 0; i < count; i = i + 1 {
          mod.types.push(parser.read_func_type())
        }
      }
      2 => {
        // Import section
        let count = parser.read_u32()
        for i = 0; i < count; i = i + 1 {
          let mod_name = parser.read_string()
          let name = parser.read_string()
          let kind = parser.read_byte()
          let desc = match kind {
            0x00 => ImportDesc::Func(parser.read_u32())
            0x01 => ImportDesc::Table(parser.read_table_type())
            0x02 => ImportDesc::Memory(parser.read_memory_type())
            0x03 => ImportDesc::Global(parser.read_global_type())
            _ => raise InvalidImportKind(kind)
          }
          mod.imports.push({ mod_name, name, desc })
        }
      }
      3 => {
        // Function section
        let count = parser.read_u32()
        for i = 0; i < count; i = i + 1 {
          mod.funcs.push(parser.read_u32())
        }
      }
      4 => {
        // Table section
        let count = parser.read_u32()
        for i = 0; i < count; i = i + 1 {
          mod.tables.push(parser.read_table_type())
        }
      }
      5 => {
        // Memory section
        let count = parser.read_u32()
        for i = 0; i < count; i = i + 1 {
          mod.memories.push(parser.read_memory_type())
        }
      }
      6 => {
        // Global section
        let count = parser.read_u32()
        for i = 0; i < count; i = i + 1 {
          let type_ = parser.read_global_type()
          let init = parser.read_expr()
          mod.globals.push({ type_, init })
        }
      }
      7 => {
        // Export section
        let count = parser.read_u32()
        for i = 0; i < count; i = i + 1 {
          let name = parser.read_string()
          let kind = parser.read_byte()
          let desc = match kind {
            0x00 => ExportDesc::Func(parser.read_u32())
            0x01 => ExportDesc::Table(parser.read_u32())
            0x02 => ExportDesc::Memory(parser.read_u32())
            0x03 => ExportDesc::Global(parser.read_u32())
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
        for i = 0; i < count; i = i + 1 {
          let table_idx = parser.read_u32()
          let offset = parser.read_expr()
          let elem_count = parser.read_u32()
          let init : Array[Int] = []
          for j = 0; j < elem_count; j = j + 1 {
            init.push(parser.read_u32())
          }
          mod.elems.push({ table_idx, offset, init })
        }
      }
      10 => {
        // Code section
        let count = parser.read_u32()
        for i = 0; i < count; i = i + 1 {
          let _code_size = parser.read_u32()
          let local_count = parser.read_u32()
          let locals : Array[ValueType] = []
          for j = 0; j < local_count; j = j + 1 {
            let n = parser.read_u32()
            let vt = parser.read_value_type()
            for k = 0; k < n; k = k + 1 {
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
        for i = 0; i < count; i = i + 1 {
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
