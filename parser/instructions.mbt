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
      let labels = self.read_vec(() => self.read_u32())
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
