// WASM Binary Encoder
// Encodes a Module to WebAssembly binary format (.wasm)
//
// Reference: WebAssembly Core Specification
// https://webassembly.github.io/spec/core/binary/

// ============ Binary Writer ============

///|
/// Binary writer for encoding WASM
priv struct BinaryWriter {
  buf : Array[Int]
}

///|
fn BinaryWriter::new() -> BinaryWriter {
  { buf: [] }
}

///|
fn BinaryWriter::write_byte(self : BinaryWriter, b : Int) -> Unit {
  self.buf.push(b & 0xFF)
}

///|
fn BinaryWriter::write_array(self : BinaryWriter, bytes : Array[Int]) -> Unit {
  for b in bytes {
    self.buf.push(b & 0xFF)
  }
}

///|
/// Write unsigned LEB128
fn BinaryWriter::write_u32(self : BinaryWriter, val : Int) -> Unit {
  let mut v = val & 0x7FFFFFFF // Treat as unsigned
  if val < 0 {
    // For negative values treated as unsigned, we need special handling
    self.write_u64(val.to_int64() & 0xFFFFFFFFL)
    return
  }
  while true {
    let byte = v & 0x7F
    v = v >> 7
    if v == 0 {
      self.buf.push(byte)
      break
    } else {
      self.buf.push(byte | 0x80)
    }
  }
}

///|
/// Write unsigned LEB128 for 64-bit values
fn BinaryWriter::write_u64(self : BinaryWriter, val : Int64) -> Unit {
  let mut v = val
  while true {
    let byte = v.to_int() & 0x7F
    v = (v.reinterpret_as_uint64() >> 7).reinterpret_as_int64()
    if v == 0L {
      self.buf.push(byte)
      break
    } else {
      self.buf.push(byte | 0x80)
    }
  }
}

///|
/// Write signed LEB128 for 32-bit values
fn BinaryWriter::write_s32(self : BinaryWriter, val : Int) -> Unit {
  let mut v = val
  while true {
    let byte = v & 0x7F
    v = v >> 7
    // Check if we can stop
    let sign_bit = (byte & 0x40) != 0
    if (v == 0 && not(sign_bit)) || (v == -1 && sign_bit) {
      self.buf.push(byte)
      break
    } else {
      self.buf.push(byte | 0x80)
    }
  }
}

///|
/// Write signed LEB128 for 64-bit values
fn BinaryWriter::write_s64(self : BinaryWriter, val : Int64) -> Unit {
  let mut v = val
  while true {
    let byte = v.to_int() & 0x7F
    v = v >> 7
    let sign_bit = (byte & 0x40) != 0
    if (v == 0L && not(sign_bit)) || (v == -1L && sign_bit) {
      self.buf.push(byte)
      break
    } else {
      self.buf.push(byte | 0x80)
    }
  }
}

///|
/// Write a UTF-8 string with length prefix
fn BinaryWriter::write_name(self : BinaryWriter, name : String) -> Unit {
  let bytes = string_to_bytes(name)
  self.write_u32(bytes.length())
  self.write_array(bytes)
}

///|
/// Write f32 in little-endian IEEE 754
fn BinaryWriter::write_f32(self : BinaryWriter, val : Float) -> Unit {
  let bits = val.reinterpret_as_int()
  self.buf.push(bits & 0xFF)
  self.buf.push((bits >> 8) & 0xFF)
  self.buf.push((bits >> 16) & 0xFF)
  self.buf.push((bits >> 24) & 0xFF)
}

///|
/// Write f64 in little-endian IEEE 754
fn BinaryWriter::write_f64(self : BinaryWriter, val : Double) -> Unit {
  let bits = val.reinterpret_as_int64()
  self.buf.push(bits.to_int() & 0xFF)
  self.buf.push((bits >> 8).to_int() & 0xFF)
  self.buf.push((bits >> 16).to_int() & 0xFF)
  self.buf.push((bits >> 24).to_int() & 0xFF)
  self.buf.push((bits >> 32).to_int() & 0xFF)
  self.buf.push((bits >> 40).to_int() & 0xFF)
  self.buf.push((bits >> 48).to_int() & 0xFF)
  self.buf.push((bits >> 56).to_int() & 0xFF)
}

///|
fn BinaryWriter::to_bytes(self : BinaryWriter) -> Array[Int] {
  self.buf
}

// ============ Type Encoding ============

///|
/// Encode a value type
fn encode_valtype(w : BinaryWriter, vt : @types.ValueType) -> Unit {
  match vt {
    I32 => w.write_byte(0x7F)
    I64 => w.write_byte(0x7E)
    F32 => w.write_byte(0x7D)
    F64 => w.write_byte(0x7C)
    V128 => w.write_byte(0x7B)
    FuncRef => w.write_byte(0x70)
    ExternRef => w.write_byte(0x6F)
    // GC types
    AnyRef => {
      w.write_byte(0x63) // ref null
      w.write_byte(0x6E) // any
    }
    StructRef => w.write_byte(0x6B)
    ArrayRef => w.write_byte(0x6A)
    RefAny => {
      w.write_byte(0x64) // ref
      w.write_byte(0x6E) // any
    }
    RefEq => {
      w.write_byte(0x64) // ref
      w.write_byte(0x6D) // eq
    }
    RefNullEq => {
      w.write_byte(0x63) // ref null
      w.write_byte(0x6D) // eq
    }
    RefI31 => {
      w.write_byte(0x64) // ref
      w.write_byte(0x6C) // i31
    }
    RefNullI31 => {
      w.write_byte(0x63) // ref null
      w.write_byte(0x6C) // i31
    }
    RefStructAbs => {
      w.write_byte(0x64) // ref
      w.write_byte(0x6B) // struct
    }
    RefArrayAbs => {
      w.write_byte(0x64) // ref
      w.write_byte(0x6A) // array
    }
    RefFunc => {
      w.write_byte(0x64) // ref
      w.write_byte(0x70) // func
    }
    RefExtern => {
      w.write_byte(0x64) // ref
      w.write_byte(0x6F) // extern
    }
    ExnRef => {
      w.write_byte(0x63) // ref null
      w.write_byte(0x69) // exn
    }
    NullRef => {
      w.write_byte(0x63) // ref null
      w.write_byte(0x71) // none
    }
    NullFuncRef => {
      w.write_byte(0x63) // ref null
      w.write_byte(0x73) // nofunc
    }
    NullExnRef => {
      w.write_byte(0x63) // ref null
      w.write_byte(0x74) // noexn
    }
    NullExternRef => {
      w.write_byte(0x63) // ref null
      w.write_byte(0x72) // noextern
    }
    RefNone => {
      w.write_byte(0x64) // ref
      w.write_byte(0x71) // none
    }
    // Typed references
    RefFuncTyped(idx) => {
      w.write_byte(0x64) // ref
      w.write_s32(idx)
    }
    RefNullFuncTyped(idx) => {
      w.write_byte(0x63) // ref null
      w.write_s32(idx)
    }
    RefStruct(idx) => {
      w.write_byte(0x64) // ref
      w.write_s32(idx)
    }
    RefNullStruct(idx) => {
      w.write_byte(0x63) // ref null
      w.write_s32(idx)
    }
    RefArray(idx) => {
      w.write_byte(0x64) // ref
      w.write_s32(idx)
    }
    RefNullArray(idx) => {
      w.write_byte(0x63) // ref null
      w.write_s32(idx)
    }
  }
}

///|
/// Encode a storage type (for GC struct/array fields)
fn encode_storage_type(w : BinaryWriter, st : @types.StorageType) -> Unit {
  match st {
    Val(vt) => encode_valtype(w, vt)
    Packed(pt) =>
      match pt {
        I8 => w.write_byte(0x78)
        I16 => w.write_byte(0x77)
      }
  }
}

///|
/// Encode a field type
fn encode_field_type(w : BinaryWriter, ft : @types.FieldType) -> Unit {
  encode_storage_type(w, ft.storage_type)
  w.write_byte(if ft.mutable { 1 } else { 0 })
}

///|
/// Encode a function type
fn encode_func_type(w : BinaryWriter, ft : @types.FuncType) -> Unit {
  w.write_byte(0x60) // func type marker
  // Params
  w.write_u32(ft.params.length())
  for p in ft.params {
    encode_valtype(w, p)
  }
  // Results
  w.write_u32(ft.results.length())
  for r in ft.results {
    encode_valtype(w, r)
  }
}

///|
/// Encode a struct type
fn encode_struct_type(w : BinaryWriter, st : @types.StructType) -> Unit {
  w.write_byte(0x5F) // struct type marker
  w.write_u32(st.fields.length())
  for field in st.fields {
    encode_field_type(w, field)
  }
}

///|
/// Encode an array type
fn encode_array_type(w : BinaryWriter, at : @types.ArrayType) -> Unit {
  w.write_byte(0x5E) // array type marker
  encode_field_type(w, at.element)
}

///|
/// Encode a composite type
fn encode_composite_type(w : BinaryWriter, ct : @types.CompositeType) -> Unit {
  match ct {
    Func(ft) => encode_func_type(w, ft)
    Struct(st) => encode_struct_type(w, st)
    Array(at) => encode_array_type(w, at)
  }
}

///|
/// Encode a subtype
fn encode_subtype(w : BinaryWriter, st : @types.SubType) -> Unit {
  if st.supertypes.is_empty() && st.final_ {
    // Simple case: no supertypes, final
    encode_composite_type(w, st.composite)
  } else if st.supertypes.is_empty() && not(st.final_) {
    // Non-final, no supertypes
    w.write_byte(0x50) // sub marker
    w.write_u32(0) // no supertypes
    encode_composite_type(w, st.composite)
  } else {
    // Has supertypes
    if st.final_ {
      w.write_byte(0x4F) // sub final marker
    } else {
      w.write_byte(0x50) // sub marker
    }
    w.write_u32(st.supertypes.length())
    for idx in st.supertypes {
      w.write_u32(idx)
    }
    encode_composite_type(w, st.composite)
  }
}

///|
/// Encode limits
fn encode_limits(w : BinaryWriter, limits : @types.Limits) -> Unit {
  match limits.max {
    Some(max) => {
      w.write_byte(0x01) // has max
      w.write_u32(limits.min.to_int())
      w.write_u32(max.to_int())
    }
    None => {
      w.write_byte(0x00) // no max
      w.write_u32(limits.min.to_int())
    }
  }
}

///|
/// Encode a table type
fn encode_table_type(w : BinaryWriter, tt : @types.TableType) -> Unit {
  encode_valtype(w, tt.elem_type)
  encode_limits(w, tt.limits)
}

///|
/// Encode a memory type
fn encode_memory_type(w : BinaryWriter, mt : @types.MemoryType) -> Unit {
  encode_limits(w, mt.limits)
}

///|
/// Encode a global type
fn encode_global_type(w : BinaryWriter, gt : @types.GlobalType) -> Unit {
  encode_valtype(w, gt.value_type)
  w.write_byte(if gt.mutable { 1 } else { 0 })
}

// ============ Instruction Encoding ============

///|
/// Encode a block type
fn encode_block_type(w : BinaryWriter, bt : @types.BlockType) -> Unit {
  match bt {
    Empty => w.write_byte(0x40) // empty block type
    Value(vt) => encode_valtype(w, vt)
    TypeIndex(idx) => w.write_s32(idx)
    MultiValue(_) | InlineType(_, _) =>
      // These should be resolved to TypeIndex before encoding
      w.write_byte(0x40)
  }
}

///|
/// Encode a memory argument (align, offset)
fn encode_memarg(
  w : BinaryWriter,
  _memidx : Int,
  align : Int,
  offset : Int64,
) -> Unit {
  w.write_u32(align)
  w.write_u64(offset & 0xFFFFFFFFL)
}

///|
/// Encode instructions
fn encode_instructions(
  w : BinaryWriter,
  instrs : Array[@types.Instruction],
) -> Unit {
  for instr in instrs {
    encode_instruction(w, instr)
  }
}

///|
/// Encode a single instruction
fn encode_instruction(w : BinaryWriter, instr : @types.Instruction) -> Unit {
  match instr {
    // Control instructions
    Unreachable => w.write_byte(0x00)
    Nop => w.write_byte(0x01)
    Block(bt, body) => {
      w.write_byte(0x02)
      encode_block_type(w, bt)
      encode_instructions(w, body)
      w.write_byte(0x0B) // end
    }
    Loop(bt, body) => {
      w.write_byte(0x03)
      encode_block_type(w, bt)
      encode_instructions(w, body)
      w.write_byte(0x0B) // end
    }
    If(bt, then_body, else_body) => {
      w.write_byte(0x04)
      encode_block_type(w, bt)
      encode_instructions(w, then_body)
      if not(else_body.is_empty()) {
        w.write_byte(0x05) // else
        encode_instructions(w, else_body)
      }
      w.write_byte(0x0B) // end
    }
    Br(label) => {
      w.write_byte(0x0C)
      w.write_u32(label)
    }
    BrIf(label) => {
      w.write_byte(0x0D)
      w.write_u32(label)
    }
    BrTable(labels, default) => {
      w.write_byte(0x0E)
      w.write_u32(labels.length())
      for l in labels {
        w.write_u32(l)
      }
      w.write_u32(default)
    }
    Return => w.write_byte(0x0F)
    Call(idx) => {
      w.write_byte(0x10)
      w.write_u32(idx)
    }
    CallIndirect(type_idx, table_idx) => {
      w.write_byte(0x11)
      w.write_u32(type_idx)
      w.write_u32(table_idx)
    }
    ReturnCall(idx) => {
      w.write_byte(0x12)
      w.write_u32(idx)
    }
    ReturnCallIndirect(type_idx, table_idx) => {
      w.write_byte(0x13)
      w.write_u32(type_idx)
      w.write_u32(table_idx)
    }
    CallRef(type_idx) => {
      w.write_byte(0x14)
      w.write_u32(type_idx)
    }
    ReturnCallRef(type_idx) => {
      w.write_byte(0x15)
      w.write_u32(type_idx)
    }

    // Exception handling
    Throw(tag_idx) => {
      w.write_byte(0x08)
      w.write_u32(tag_idx)
    }
    ThrowRef => w.write_byte(0x0A)
    TryTable(bt, handlers, body) => {
      w.write_byte(0x1F)
      encode_block_type(w, bt)
      w.write_u32(handlers.length())
      for handler in handlers {
        encode_catch_handler(w, handler)
      }
      encode_instructions(w, body)
      w.write_byte(0x0B) // end
    }

    // Parametric instructions
    Drop => w.write_byte(0x1A)
    Select => w.write_byte(0x1B)
    SelectTyped(types) => {
      w.write_byte(0x1C)
      w.write_u32(types.length())
      for t in types {
        encode_valtype(w, t)
      }
    }

    // Variable instructions
    LocalGet(idx) => {
      w.write_byte(0x20)
      w.write_u32(idx)
    }
    LocalSet(idx) => {
      w.write_byte(0x21)
      w.write_u32(idx)
    }
    LocalTee(idx) => {
      w.write_byte(0x22)
      w.write_u32(idx)
    }
    GlobalGet(idx) => {
      w.write_byte(0x23)
      w.write_u32(idx)
    }
    GlobalSet(idx) => {
      w.write_byte(0x24)
      w.write_u32(idx)
    }

    // Table instructions
    TableGet(idx) => {
      w.write_byte(0x25)
      w.write_u32(idx)
    }
    TableSet(idx) => {
      w.write_byte(0x26)
      w.write_u32(idx)
    }
    TableSize(idx) => {
      w.write_byte(0xFC)
      w.write_u32(16)
      w.write_u32(idx)
    }
    TableGrow(idx) => {
      w.write_byte(0xFC)
      w.write_u32(15)
      w.write_u32(idx)
    }
    TableFill(idx) => {
      w.write_byte(0xFC)
      w.write_u32(17)
      w.write_u32(idx)
    }
    TableCopy(dst, src) => {
      w.write_byte(0xFC)
      w.write_u32(14)
      w.write_u32(dst)
      w.write_u32(src)
    }
    TableInit(table_idx, elem_idx) => {
      w.write_byte(0xFC)
      w.write_u32(12)
      w.write_u32(elem_idx)
      w.write_u32(table_idx)
    }

    // Memory instructions
    I32Load(memidx, align, offset) => {
      w.write_byte(0x28)
      encode_memarg(w, memidx, align, offset)
    }
    I64Load(memidx, align, offset) => {
      w.write_byte(0x29)
      encode_memarg(w, memidx, align, offset)
    }
    F32Load(memidx, align, offset) => {
      w.write_byte(0x2A)
      encode_memarg(w, memidx, align, offset)
    }
    F64Load(memidx, align, offset) => {
      w.write_byte(0x2B)
      encode_memarg(w, memidx, align, offset)
    }
    I32Load8S(memidx, align, offset) => {
      w.write_byte(0x2C)
      encode_memarg(w, memidx, align, offset)
    }
    I32Load8U(memidx, align, offset) => {
      w.write_byte(0x2D)
      encode_memarg(w, memidx, align, offset)
    }
    I32Load16S(memidx, align, offset) => {
      w.write_byte(0x2E)
      encode_memarg(w, memidx, align, offset)
    }
    I32Load16U(memidx, align, offset) => {
      w.write_byte(0x2F)
      encode_memarg(w, memidx, align, offset)
    }
    I64Load8S(memidx, align, offset) => {
      w.write_byte(0x30)
      encode_memarg(w, memidx, align, offset)
    }
    I64Load8U(memidx, align, offset) => {
      w.write_byte(0x31)
      encode_memarg(w, memidx, align, offset)
    }
    I64Load16S(memidx, align, offset) => {
      w.write_byte(0x32)
      encode_memarg(w, memidx, align, offset)
    }
    I64Load16U(memidx, align, offset) => {
      w.write_byte(0x33)
      encode_memarg(w, memidx, align, offset)
    }
    I64Load32S(memidx, align, offset) => {
      w.write_byte(0x34)
      encode_memarg(w, memidx, align, offset)
    }
    I64Load32U(memidx, align, offset) => {
      w.write_byte(0x35)
      encode_memarg(w, memidx, align, offset)
    }
    I32Store(memidx, align, offset) => {
      w.write_byte(0x36)
      encode_memarg(w, memidx, align, offset)
    }
    I64Store(memidx, align, offset) => {
      w.write_byte(0x37)
      encode_memarg(w, memidx, align, offset)
    }
    F32Store(memidx, align, offset) => {
      w.write_byte(0x38)
      encode_memarg(w, memidx, align, offset)
    }
    F64Store(memidx, align, offset) => {
      w.write_byte(0x39)
      encode_memarg(w, memidx, align, offset)
    }
    I32Store8(memidx, align, offset) => {
      w.write_byte(0x3A)
      encode_memarg(w, memidx, align, offset)
    }
    I32Store16(memidx, align, offset) => {
      w.write_byte(0x3B)
      encode_memarg(w, memidx, align, offset)
    }
    I64Store8(memidx, align, offset) => {
      w.write_byte(0x3C)
      encode_memarg(w, memidx, align, offset)
    }
    I64Store16(memidx, align, offset) => {
      w.write_byte(0x3D)
      encode_memarg(w, memidx, align, offset)
    }
    I64Store32(memidx, align, offset) => {
      w.write_byte(0x3E)
      encode_memarg(w, memidx, align, offset)
    }
    MemorySize(memidx) => {
      w.write_byte(0x3F)
      w.write_u32(memidx)
    }
    MemoryGrow(memidx) => {
      w.write_byte(0x40)
      w.write_u32(memidx)
    }
    MemoryInit(memidx, data_idx) => {
      w.write_byte(0xFC)
      w.write_u32(8)
      w.write_u32(data_idx)
      w.write_u32(memidx)
    }
    DataDrop(data_idx) => {
      w.write_byte(0xFC)
      w.write_u32(9)
      w.write_u32(data_idx)
    }
    MemoryCopy(dst, src) => {
      w.write_byte(0xFC)
      w.write_u32(10)
      w.write_u32(dst)
      w.write_u32(src)
    }
    MemoryFill(memidx) => {
      w.write_byte(0xFC)
      w.write_u32(11)
      w.write_u32(memidx)
    }
    ElemDrop(elem_idx) => {
      w.write_byte(0xFC)
      w.write_u32(13)
      w.write_u32(elem_idx)
    }

    // Reference instructions
    RefNull(vt) => {
      w.write_byte(0xD0)
      encode_valtype(w, vt)
    }
    RefIsNull => w.write_byte(0xD1)
    RefFunc(idx) => {
      w.write_byte(0xD2)
      w.write_u32(idx)
    }
    RefAsNonNull => w.write_byte(0xD4)
    RefEqInstr => w.write_byte(0xD3)
    BrOnNull(label) => {
      w.write_byte(0xD5)
      w.write_u32(label)
    }
    BrOnNonNull(label) => {
      w.write_byte(0xD6)
      w.write_u32(label)
    }

    // Numeric constants
    I32Const(val) => {
      w.write_byte(0x41)
      w.write_s32(val)
    }
    I64Const(val) => {
      w.write_byte(0x42)
      w.write_s64(val)
    }
    F32Const(val) => {
      w.write_byte(0x43)
      w.write_f32(val)
    }
    F64Const(val) => {
      w.write_byte(0x44)
      w.write_f64(val)
    }

    // i32 operations
    I32Eqz => w.write_byte(0x45)
    I32Eq => w.write_byte(0x46)
    I32Ne => w.write_byte(0x47)
    I32LtS => w.write_byte(0x48)
    I32LtU => w.write_byte(0x49)
    I32GtS => w.write_byte(0x4A)
    I32GtU => w.write_byte(0x4B)
    I32LeS => w.write_byte(0x4C)
    I32LeU => w.write_byte(0x4D)
    I32GeS => w.write_byte(0x4E)
    I32GeU => w.write_byte(0x4F)
    I32Clz => w.write_byte(0x67)
    I32Ctz => w.write_byte(0x68)
    I32Popcnt => w.write_byte(0x69)
    I32Add => w.write_byte(0x6A)
    I32Sub => w.write_byte(0x6B)
    I32Mul => w.write_byte(0x6C)
    I32DivS => w.write_byte(0x6D)
    I32DivU => w.write_byte(0x6E)
    I32RemS => w.write_byte(0x6F)
    I32RemU => w.write_byte(0x70)
    I32And => w.write_byte(0x71)
    I32Or => w.write_byte(0x72)
    I32Xor => w.write_byte(0x73)
    I32Shl => w.write_byte(0x74)
    I32ShrS => w.write_byte(0x75)
    I32ShrU => w.write_byte(0x76)
    I32Rotl => w.write_byte(0x77)
    I32Rotr => w.write_byte(0x78)
    I32Extend8S => w.write_byte(0xC0)
    I32Extend16S => w.write_byte(0xC1)

    // i64 operations
    I64Eqz => w.write_byte(0x50)
    I64Eq => w.write_byte(0x51)
    I64Ne => w.write_byte(0x52)
    I64LtS => w.write_byte(0x53)
    I64LtU => w.write_byte(0x54)
    I64GtS => w.write_byte(0x55)
    I64GtU => w.write_byte(0x56)
    I64LeS => w.write_byte(0x57)
    I64LeU => w.write_byte(0x58)
    I64GeS => w.write_byte(0x59)
    I64GeU => w.write_byte(0x5A)
    I64Clz => w.write_byte(0x79)
    I64Ctz => w.write_byte(0x7A)
    I64Popcnt => w.write_byte(0x7B)
    I64Add => w.write_byte(0x7C)
    I64Sub => w.write_byte(0x7D)
    I64Mul => w.write_byte(0x7E)
    I64DivS => w.write_byte(0x7F)
    I64DivU => w.write_byte(0x80)
    I64RemS => w.write_byte(0x81)
    I64RemU => w.write_byte(0x82)
    I64And => w.write_byte(0x83)
    I64Or => w.write_byte(0x84)
    I64Xor => w.write_byte(0x85)
    I64Shl => w.write_byte(0x86)
    I64ShrS => w.write_byte(0x87)
    I64ShrU => w.write_byte(0x88)
    I64Rotl => w.write_byte(0x89)
    I64Rotr => w.write_byte(0x8A)
    I64Extend8S => w.write_byte(0xC2)
    I64Extend16S => w.write_byte(0xC3)
    I64Extend32S => w.write_byte(0xC4)

    // f32 operations
    F32Eq => w.write_byte(0x5B)
    F32Ne => w.write_byte(0x5C)
    F32Lt => w.write_byte(0x5D)
    F32Gt => w.write_byte(0x5E)
    F32Le => w.write_byte(0x5F)
    F32Ge => w.write_byte(0x60)
    F32Abs => w.write_byte(0x8B)
    F32Neg => w.write_byte(0x8C)
    F32Ceil => w.write_byte(0x8D)
    F32Floor => w.write_byte(0x8E)
    F32Trunc => w.write_byte(0x8F)
    F32Nearest => w.write_byte(0x90)
    F32Sqrt => w.write_byte(0x91)
    F32Add => w.write_byte(0x92)
    F32Sub => w.write_byte(0x93)
    F32Mul => w.write_byte(0x94)
    F32Div => w.write_byte(0x95)
    F32Min => w.write_byte(0x96)
    F32Max => w.write_byte(0x97)
    F32Copysign => w.write_byte(0x98)

    // f64 operations
    F64Eq => w.write_byte(0x61)
    F64Ne => w.write_byte(0x62)
    F64Lt => w.write_byte(0x63)
    F64Gt => w.write_byte(0x64)
    F64Le => w.write_byte(0x65)
    F64Ge => w.write_byte(0x66)
    F64Abs => w.write_byte(0x99)
    F64Neg => w.write_byte(0x9A)
    F64Ceil => w.write_byte(0x9B)
    F64Floor => w.write_byte(0x9C)
    F64Trunc => w.write_byte(0x9D)
    F64Nearest => w.write_byte(0x9E)
    F64Sqrt => w.write_byte(0x9F)
    F64Add => w.write_byte(0xA0)
    F64Sub => w.write_byte(0xA1)
    F64Mul => w.write_byte(0xA2)
    F64Div => w.write_byte(0xA3)
    F64Min => w.write_byte(0xA4)
    F64Max => w.write_byte(0xA5)
    F64Copysign => w.write_byte(0xA6)

    // Conversions
    I32WrapI64 => w.write_byte(0xA7)
    I32TruncF32S => w.write_byte(0xA8)
    I32TruncF32U => w.write_byte(0xA9)
    I32TruncF64S => w.write_byte(0xAA)
    I32TruncF64U => w.write_byte(0xAB)
    I64ExtendI32S => w.write_byte(0xAC)
    I64ExtendI32U => w.write_byte(0xAD)
    I64TruncF32S => w.write_byte(0xAE)
    I64TruncF32U => w.write_byte(0xAF)
    I64TruncF64S => w.write_byte(0xB0)
    I64TruncF64U => w.write_byte(0xB1)
    F32ConvertI32S => w.write_byte(0xB2)
    F32ConvertI32U => w.write_byte(0xB3)
    F32ConvertI64S => w.write_byte(0xB4)
    F32ConvertI64U => w.write_byte(0xB5)
    F32DemoteF64 => w.write_byte(0xB6)
    F64ConvertI32S => w.write_byte(0xB7)
    F64ConvertI32U => w.write_byte(0xB8)
    F64ConvertI64S => w.write_byte(0xB9)
    F64ConvertI64U => w.write_byte(0xBA)
    F64PromoteF32 => w.write_byte(0xBB)
    I32ReinterpretF32 => w.write_byte(0xBC)
    I64ReinterpretF64 => w.write_byte(0xBD)
    F32ReinterpretI32 => w.write_byte(0xBE)
    F64ReinterpretI64 => w.write_byte(0xBF)

    // Saturating truncation
    I32TruncSatF32S => {
      w.write_byte(0xFC)
      w.write_u32(0)
    }
    I32TruncSatF32U => {
      w.write_byte(0xFC)
      w.write_u32(1)
    }
    I32TruncSatF64S => {
      w.write_byte(0xFC)
      w.write_u32(2)
    }
    I32TruncSatF64U => {
      w.write_byte(0xFC)
      w.write_u32(3)
    }
    I64TruncSatF32S => {
      w.write_byte(0xFC)
      w.write_u32(4)
    }
    I64TruncSatF32U => {
      w.write_byte(0xFC)
      w.write_u32(5)
    }
    I64TruncSatF64S => {
      w.write_byte(0xFC)
      w.write_u32(6)
    }
    I64TruncSatF64U => {
      w.write_byte(0xFC)
      w.write_u32(7)
    }

    // GC instructions
    StructNew(type_idx) => {
      w.write_byte(0xFB)
      w.write_u32(0)
      w.write_u32(type_idx)
    }
    StructNewDefault(type_idx) => {
      w.write_byte(0xFB)
      w.write_u32(1)
      w.write_u32(type_idx)
    }
    StructGet(type_idx, field_idx) => {
      w.write_byte(0xFB)
      w.write_u32(2)
      w.write_u32(type_idx)
      w.write_u32(field_idx)
    }
    StructGetS(type_idx, field_idx) => {
      w.write_byte(0xFB)
      w.write_u32(3)
      w.write_u32(type_idx)
      w.write_u32(field_idx)
    }
    StructGetU(type_idx, field_idx) => {
      w.write_byte(0xFB)
      w.write_u32(4)
      w.write_u32(type_idx)
      w.write_u32(field_idx)
    }
    StructSet(type_idx, field_idx) => {
      w.write_byte(0xFB)
      w.write_u32(5)
      w.write_u32(type_idx)
      w.write_u32(field_idx)
    }
    ArrayNew(type_idx) => {
      w.write_byte(0xFB)
      w.write_u32(6)
      w.write_u32(type_idx)
    }
    ArrayNewDefault(type_idx) => {
      w.write_byte(0xFB)
      w.write_u32(7)
      w.write_u32(type_idx)
    }
    ArrayNewFixed(type_idx, len) => {
      w.write_byte(0xFB)
      w.write_u32(8)
      w.write_u32(type_idx)
      w.write_u32(len)
    }
    ArrayNewData(type_idx, data_idx) => {
      w.write_byte(0xFB)
      w.write_u32(9)
      w.write_u32(type_idx)
      w.write_u32(data_idx)
    }
    ArrayNewElem(type_idx, elem_idx) => {
      w.write_byte(0xFB)
      w.write_u32(10)
      w.write_u32(type_idx)
      w.write_u32(elem_idx)
    }
    ArrayGet(type_idx) => {
      w.write_byte(0xFB)
      w.write_u32(11)
      w.write_u32(type_idx)
    }
    ArrayGetS(type_idx) => {
      w.write_byte(0xFB)
      w.write_u32(12)
      w.write_u32(type_idx)
    }
    ArrayGetU(type_idx) => {
      w.write_byte(0xFB)
      w.write_u32(13)
      w.write_u32(type_idx)
    }
    ArraySet(type_idx) => {
      w.write_byte(0xFB)
      w.write_u32(14)
      w.write_u32(type_idx)
    }
    ArrayLen => {
      w.write_byte(0xFB)
      w.write_u32(15)
    }
    ArrayFill(type_idx) => {
      w.write_byte(0xFB)
      w.write_u32(16)
      w.write_u32(type_idx)
    }
    ArrayCopy(dst_type, src_type) => {
      w.write_byte(0xFB)
      w.write_u32(17)
      w.write_u32(dst_type)
      w.write_u32(src_type)
    }
    ArrayInitData(type_idx, data_idx) => {
      w.write_byte(0xFB)
      w.write_u32(18)
      w.write_u32(type_idx)
      w.write_u32(data_idx)
    }
    ArrayInitElem(type_idx, elem_idx) => {
      w.write_byte(0xFB)
      w.write_u32(19)
      w.write_u32(type_idx)
      w.write_u32(elem_idx)
    }
    RefTest(vt) => {
      w.write_byte(0xFB)
      w.write_u32(20)
      encode_valtype(w, vt)
    }
    RefTestNull(vt) => {
      w.write_byte(0xFB)
      w.write_u32(21)
      encode_valtype(w, vt)
    }
    RefCast(vt) => {
      w.write_byte(0xFB)
      w.write_u32(22)
      encode_valtype(w, vt)
    }
    RefCastNull(vt) => {
      w.write_byte(0xFB)
      w.write_u32(23)
      encode_valtype(w, vt)
    }
    BrOnCast(label, from_type, to_type) => {
      w.write_byte(0xFB)
      w.write_u32(24)
      // Cast flags: bit 0 = from nullable, bit 1 = to nullable
      let from_null = if from_type.is_nullable() { 1 } else { 0 }
      let to_null = if to_type.is_nullable() { 2 } else { 0 }
      w.write_byte(from_null | to_null)
      w.write_u32(label)
      encode_valtype(w, from_type)
      encode_valtype(w, to_type)
    }
    BrOnCastFail(label, from_type, to_type) => {
      w.write_byte(0xFB)
      w.write_u32(25)
      let from_null = if from_type.is_nullable() { 1 } else { 0 }
      let to_null = if to_type.is_nullable() { 2 } else { 0 }
      w.write_byte(from_null | to_null)
      w.write_u32(label)
      encode_valtype(w, from_type)
      encode_valtype(w, to_type)
    }
    RefI31 => {
      w.write_byte(0xFB)
      w.write_u32(28)
    }
    I31GetS => {
      w.write_byte(0xFB)
      w.write_u32(29)
    }
    I31GetU => {
      w.write_byte(0xFB)
      w.write_u32(30)
    }
    AnyConvertExtern => {
      w.write_byte(0xFB)
      w.write_u32(26)
    }
    ExternConvertAny => {
      w.write_byte(0xFB)
      w.write_u32(27)
    }

    // SIMD - V128 constant and load/store
    V128Const(bytes) => {
      w.write_byte(0xFD)
      w.write_u32(12)
      for i in 0..<16 {
        w.write_byte(bytes[i].to_int())
      }
    }
    V128Load(memidx, align, offset) => {
      w.write_byte(0xFD)
      w.write_u32(0)
      encode_memarg(w, memidx, align, offset)
    }
    V128Store(memidx, align, offset) => {
      w.write_byte(0xFD)
      w.write_u32(11)
      encode_memarg(w, memidx, align, offset)
    }

    // For unhandled SIMD instructions, use unreachable as placeholder
    _ => w.write_byte(0x00)
  }
}

///|
/// Encode a catch handler
fn encode_catch_handler(
  w : BinaryWriter,
  handler : @types.CatchHandler,
) -> Unit {
  match handler {
    Catch(tag_idx, label) => {
      w.write_byte(0x00)
      w.write_u32(tag_idx)
      w.write_u32(label)
    }
    CatchRef(tag_idx, label) => {
      w.write_byte(0x01)
      w.write_u32(tag_idx)
      w.write_u32(label)
    }
    CatchAll(label) => {
      w.write_byte(0x02)
      w.write_u32(label)
    }
    CatchAllRef(label) => {
      w.write_byte(0x03)
      w.write_u32(label)
    }
  }
}

// ============ Section Encoding ============

///|
/// Write a section with its content
fn write_section(
  w : BinaryWriter,
  section_id : Int,
  content : Array[Int],
) -> Unit {
  w.write_byte(section_id)
  w.write_u32(content.length())
  w.write_array(content)
}

///|
/// Encode the type section
fn encode_type_section(mod : @types.Module) -> Array[Int] {
  if mod.types.is_empty() {
    return []
  }
  let w = BinaryWriter::new()
  w.write_u32(mod.types.length())
  for subtype in mod.types {
    encode_subtype(w, subtype)
  }
  w.to_bytes()
}

///|
/// Encode the import section
fn encode_import_section(mod : @types.Module) -> Array[Int] {
  if mod.imports.is_empty() {
    return []
  }
  let w = BinaryWriter::new()
  w.write_u32(mod.imports.length())
  for imp in mod.imports {
    w.write_name(imp.mod_name)
    w.write_name(imp.name)
    match imp.desc {
      Func(type_idx) => {
        w.write_byte(0x00)
        w.write_u32(type_idx)
      }
      Table(tt) => {
        w.write_byte(0x01)
        encode_table_type(w, tt)
      }
      Memory(mt) => {
        w.write_byte(0x02)
        encode_memory_type(w, mt)
      }
      Global(gt) => {
        w.write_byte(0x03)
        encode_global_type(w, gt)
      }
      Tag(type_idx) => {
        w.write_byte(0x04)
        w.write_byte(0x00) // exception kind
        w.write_u32(type_idx)
      }
    }
  }
  w.to_bytes()
}

///|
/// Encode the function section
fn encode_function_section(mod : @types.Module) -> Array[Int] {
  if mod.funcs.is_empty() {
    return []
  }
  let w = BinaryWriter::new()
  w.write_u32(mod.funcs.length())
  for type_idx in mod.funcs {
    w.write_u32(type_idx)
  }
  w.to_bytes()
}

///|
/// Encode the table section
fn encode_table_section(mod : @types.Module) -> Array[Int] {
  if mod.tables.is_empty() {
    return []
  }
  let w = BinaryWriter::new()
  w.write_u32(mod.tables.length())
  for table in mod.tables {
    match table.init {
      Some(init_expr) => {
        // Table with init expression (0x40 prefix)
        w.write_byte(0x40)
        w.write_byte(0x00) // reserved
        encode_table_type(w, table.type_)
        encode_instructions(w, init_expr)
        w.write_byte(0x0B) // end
      }
      None => encode_table_type(w, table.type_)
    }
  }
  w.to_bytes()
}

///|
/// Encode the memory section
fn encode_memory_section(mod : @types.Module) -> Array[Int] {
  if mod.memories.is_empty() {
    return []
  }
  let w = BinaryWriter::new()
  w.write_u32(mod.memories.length())
  for mem in mod.memories {
    encode_memory_type(w, mem)
  }
  w.to_bytes()
}

///|
/// Encode the global section
fn encode_global_section(mod : @types.Module) -> Array[Int] {
  if mod.globals.is_empty() {
    return []
  }
  let w = BinaryWriter::new()
  w.write_u32(mod.globals.length())
  for global in mod.globals {
    encode_global_type(w, global.type_)
    encode_instructions(w, global.init)
    w.write_byte(0x0B) // end
  }
  w.to_bytes()
}

///|
/// Encode the export section
fn encode_export_section(mod : @types.Module) -> Array[Int] {
  if mod.exports.is_empty() {
    return []
  }
  let w = BinaryWriter::new()
  w.write_u32(mod.exports.length())
  for exp in mod.exports {
    w.write_name(exp.name)
    match exp.desc {
      Func(idx) => {
        w.write_byte(0x00)
        w.write_u32(idx)
      }
      Table(idx) => {
        w.write_byte(0x01)
        w.write_u32(idx)
      }
      Memory(idx) => {
        w.write_byte(0x02)
        w.write_u32(idx)
      }
      Global(idx) => {
        w.write_byte(0x03)
        w.write_u32(idx)
      }
      Tag(idx) => {
        w.write_byte(0x04)
        w.write_u32(idx)
      }
    }
  }
  w.to_bytes()
}

///|
/// Encode the start section
fn encode_start_section(mod : @types.Module) -> Array[Int] {
  match mod.start {
    Some(func_idx) => {
      let w = BinaryWriter::new()
      w.write_u32(func_idx)
      w.to_bytes()
    }
    None => []
  }
}

///|
/// Encode the element section
fn encode_element_section(mod : @types.Module) -> Array[Int] {
  if mod.elems.is_empty() {
    return []
  }
  let w = BinaryWriter::new()
  w.write_u32(mod.elems.length())
  for elem in mod.elems {
    match elem.mode {
      Active(table_idx, offset_expr) =>
        if table_idx == 0 && elem.type_ is @types.FuncRef {
          // Simplified encoding for table 0 with funcref
          w.write_byte(0x00)
          encode_instructions(w, offset_expr)
          w.write_byte(0x0B) // end
          // Write function indices directly
          w.write_u32(elem.init.length())
          for init_expr in elem.init {
            // Extract function index from ref.func instruction
            match init_expr {
              [@types.RefFunc(idx)] => w.write_u32(idx)
              _ => w.write_u32(0) // fallback
            }
          }
        } else {
          // Full encoding
          w.write_byte(0x06) // active with table index, elem type, expr init
          w.write_u32(table_idx)
          encode_instructions(w, offset_expr)
          w.write_byte(0x0B) // end
          encode_valtype(w, elem.type_)
          w.write_u32(elem.init.length())
          for init_expr in elem.init {
            encode_instructions(w, init_expr)
            w.write_byte(0x0B) // end
          }
        }
      Passive => {
        w.write_byte(0x05) // passive with elem type and expr init
        encode_valtype(w, elem.type_)
        w.write_u32(elem.init.length())
        for init_expr in elem.init {
          encode_instructions(w, init_expr)
          w.write_byte(0x0B) // end
        }
      }
      Declarative => {
        w.write_byte(0x07) // declarative with elem type and expr init
        encode_valtype(w, elem.type_)
        w.write_u32(elem.init.length())
        for init_expr in elem.init {
          encode_instructions(w, init_expr)
          w.write_byte(0x0B) // end
        }
      }
    }
  }
  w.to_bytes()
}

///|
/// Encode the code section
fn encode_code_section(mod : @types.Module) -> Array[Int] {
  if mod.codes.is_empty() {
    return []
  }
  let w = BinaryWriter::new()
  w.write_u32(mod.codes.length())
  for code in mod.codes {
    // Encode function body
    let body_writer = BinaryWriter::new()

    // Compress locals: group consecutive same-type locals
    let compressed_locals : Array[(Int, @types.ValueType)] = []
    let mut i = 0
    while i < code.locals.length() {
      let vt = code.locals[i]
      let mut count = 1
      while i + count < code.locals.length() && code.locals[i + count] == vt {
        count += 1
      }
      compressed_locals.push((count, vt))
      i += count
    }

    // Write locals
    body_writer.write_u32(compressed_locals.length())
    for loc in compressed_locals {
      let (count, vt) = loc
      body_writer.write_u32(count)
      encode_valtype(body_writer, vt)
    }

    // Write body
    encode_instructions(body_writer, code.body)
    body_writer.write_byte(0x0B) // end

    // Write function body with size prefix
    let body_bytes = body_writer.to_bytes()
    w.write_u32(body_bytes.length())
    w.write_array(body_bytes)
  }
  w.to_bytes()
}

///|
/// Encode the data section
fn encode_data_section(mod : @types.Module) -> Array[Int] {
  if mod.datas.is_empty() {
    return []
  }
  let w = BinaryWriter::new()
  w.write_u32(mod.datas.length())
  for data in mod.datas {
    if data.memory_idx == 0 && not(data.offset.is_empty()) {
      // Active data segment with memory 0
      w.write_byte(0x00)
      encode_instructions(w, data.offset)
      w.write_byte(0x0B) // end
    } else if data.offset.is_empty() {
      // Passive data segment
      w.write_byte(0x01)
    } else {
      // Active with explicit memory index
      w.write_byte(0x02)
      w.write_u32(data.memory_idx)
      encode_instructions(w, data.offset)
      w.write_byte(0x0B) // end
    }
    // Write data bytes
    w.write_u32(data.init.length())
    for i in 0..<data.init.length() {
      w.write_byte(data.init[i].to_int())
    }
  }
  w.to_bytes()
}

///|
/// Encode the data count section (required for bulk memory)
fn encode_datacount_section(mod : @types.Module) -> Array[Int] {
  if mod.datas.is_empty() {
    return []
  }
  let w = BinaryWriter::new()
  w.write_u32(mod.datas.length())
  w.to_bytes()
}

///|
/// Encode the tag section
fn encode_tag_section(mod : @types.Module) -> Array[Int] {
  if mod.tags.is_empty() {
    return []
  }
  let w = BinaryWriter::new()
  w.write_u32(mod.tags.length())
  for tag in mod.tags {
    w.write_byte(0x00) // exception kind
    w.write_u32(tag.type_idx)
  }
  w.to_bytes()
}

// ============ Main Encoder ============

///|
/// Encode a Module to WebAssembly binary format
pub fn encode(mod : @types.Module) -> Array[Int] {
  let w = BinaryWriter::new()

  // Write magic number: \0asm
  w.write_byte(0x00)
  w.write_byte(0x61)
  w.write_byte(0x73)
  w.write_byte(0x6D)

  // Write version 1
  w.write_byte(0x01)
  w.write_byte(0x00)
  w.write_byte(0x00)
  w.write_byte(0x00)

  // Type section (id=1)
  let type_section = encode_type_section(mod)
  if not(type_section.is_empty()) {
    write_section(w, 1, type_section)
  }

  // Import section (id=2)
  let import_section = encode_import_section(mod)
  if not(import_section.is_empty()) {
    write_section(w, 2, import_section)
  }

  // Function section (id=3)
  let function_section = encode_function_section(mod)
  if not(function_section.is_empty()) {
    write_section(w, 3, function_section)
  }

  // Table section (id=4)
  let table_section = encode_table_section(mod)
  if not(table_section.is_empty()) {
    write_section(w, 4, table_section)
  }

  // Memory section (id=5)
  let memory_section = encode_memory_section(mod)
  if not(memory_section.is_empty()) {
    write_section(w, 5, memory_section)
  }

  // Tag section (id=13)
  let tag_section = encode_tag_section(mod)
  if not(tag_section.is_empty()) {
    write_section(w, 13, tag_section)
  }

  // Global section (id=6)
  let global_section = encode_global_section(mod)
  if not(global_section.is_empty()) {
    write_section(w, 6, global_section)
  }

  // Export section (id=7)
  let export_section = encode_export_section(mod)
  if not(export_section.is_empty()) {
    write_section(w, 7, export_section)
  }

  // Start section (id=8)
  let start_section = encode_start_section(mod)
  if not(start_section.is_empty()) {
    write_section(w, 8, start_section)
  }

  // Element section (id=9)
  let element_section = encode_element_section(mod)
  if not(element_section.is_empty()) {
    write_section(w, 9, element_section)
  }

  // Data count section (id=12)
  let datacount_section = encode_datacount_section(mod)
  if not(datacount_section.is_empty()) {
    write_section(w, 12, datacount_section)
  }

  // Code section (id=10)
  let code_section = encode_code_section(mod)
  if not(code_section.is_empty()) {
    write_section(w, 10, code_section)
  }

  // Data section (id=11)
  let data_section = encode_data_section(mod)
  if not(data_section.is_empty()) {
    write_section(w, 11, data_section)
  }
  w.to_bytes()
}
