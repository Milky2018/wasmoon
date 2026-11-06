// WASM Binary Encoder
// Encodes a Module to WebAssembly binary format (.wasm)
//
// Reference: WebAssembly Core Specification
// https://webassembly.github.io/spec/core/binary/

// ============ Type Encoding ============

///|
/// Encode a value type
fn encode_valtype(w : @binary.Writer, vt : @types.ValueType) -> Unit {
  match vt {
    I32 => w.write_byte(0x7F)
    I64 => w.write_byte(0x7E)
    F32 => w.write_byte(0x7D)
    F64 => w.write_byte(0x7C)
    V128 => w.write_byte(0x7B)
    FuncRef => w.write_byte(0x70)
    ContRef => w.write_byte(0x68)
    NullContRef => w.write_byte(0x75)
    RefCont => {
      w.write_byte(0x64)
      w.write_byte(0x68)
    }
    RefNoCont => {
      w.write_byte(0x64)
      w.write_byte(0x75)
    }
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
    RefFuncTyped(idx) | RefContTyped(idx) => {
      w.write_byte(0x64) // ref
      w.write_s32(idx)
    }
    RefNullFuncTyped(idx) | RefNullContTyped(idx) => {
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
fn encode_storage_type(w : @binary.Writer, st : @types.StorageType) -> Unit {
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
fn encode_field_type(w : @binary.Writer, ft : @types.FieldType) -> Unit {
  encode_storage_type(w, ft.storage_type)
  w.write_byte(if ft.mutable { 1 } else { 0 })
}

///|
/// Encode a function type
fn encode_func_type(w : @binary.Writer, ft : @types.FuncType) -> Unit {
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
fn encode_struct_type(w : @binary.Writer, st : @types.StructType) -> Unit {
  w.write_byte(0x5F) // struct type marker
  w.write_u32(st.fields.length())
  for field in st.fields {
    encode_field_type(w, field)
  }
}

///|
/// Encode an array type
fn encode_array_type(w : @binary.Writer, at : @types.ArrayType) -> Unit {
  w.write_byte(0x5E) // array type marker
  encode_field_type(w, at.element)
}

///|
/// Encode a composite type
fn encode_composite_type(w : @binary.Writer, ct : @types.CompositeType) -> Unit {
  match ct {
    Func(ft) => encode_func_type(w, ft)
    Struct(st) => encode_struct_type(w, st)
    Array(at) => encode_array_type(w, at)
    Cont(index) => {
      w.write_byte(0x5d)
      w.write_u32(index)
    }
  }
}

///|
/// Encode a subtype
fn encode_subtype(w : @binary.Writer, st : @types.SubType) -> Unit {
  if st.supertypes.is_empty() && st.final_ {
    // Simple case: no supertypes, final
    encode_composite_type(w, st.composite)
  } else if st.supertypes.is_empty() && !st.final_ {
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
/// Encode table limits (supports table64 via flag 0x04)
fn encode_table_limits(
  w : @binary.Writer,
  limits : @types.Limits,
  is_table64 : Bool,
) -> Unit {
  let has_max = limits.max is Some(_)
  let mut flags = 0x00
  if has_max {
    flags = flags | 0x01
  }
  if is_table64 {
    flags = flags | 0x04
  }
  w.write_byte(flags)
  // Valid u32 and u64 limits use the same LEB encoding. Preserve the full
  // AST value so decoding rejects an oversized table32 limit instead of wrapping.
  w.write_u64(limits.min)
  if limits.max is Some(max) {
    w.write_u64(max)
  }
}

///|
/// Encode a table type
fn encode_table_type(w : @binary.Writer, tt : @types.TableType) -> Unit {
  encode_valtype(w, tt.elem_type)
  encode_table_limits(w, tt.limits, tt.is_table64)
}

///|
/// Encode memory limits (supports memory64 and custom page sizes)
fn encode_memory_limits(w : @binary.Writer, mt : @types.MemoryType) -> Unit {
  let has_max = mt.limits.max is Some(_)
  let has_custom_page_size = mt.page_size_log2 != 16
  let mut flags = 0x00
  if has_max {
    flags = flags | 0x01
  }
  if mt.is_shared {
    flags = flags | 0x02
  }
  if mt.is_memory64 {
    flags = flags | 0x04
  }
  if has_custom_page_size {
    flags = flags | 0x08
  }
  w.write_byte(flags)
  // Do not narrow unvalidated memory32 limits into a different valid module.
  w.write_u64(mt.limits.min)
  if mt.limits.max is Some(max) {
    w.write_u64(max)
  }
  if has_custom_page_size {
    w.write_u32(mt.page_size_log2)
  }
}

///|
/// Encode a memory type
fn encode_memory_type(w : @binary.Writer, mt : @types.MemoryType) -> Unit {
  encode_memory_limits(w, mt)
}

///|
/// Encode a global type
fn encode_global_type(w : @binary.Writer, gt : @types.GlobalType) -> Unit {
  encode_valtype(w, gt.value_type)
  w.write_byte(if gt.mutable { 1 } else { 0 })
}

// ============ Instruction Encoding ============

///|
/// Encode a block type
fn encode_block_type(w : @binary.Writer, bt : @types.BlockType) -> Unit {
  match bt {
    Empty => w.write_byte(0x40) // empty block type
    Value(vt) => encode_valtype(w, vt)
    TypeIndex(idx) => w.write_s32(idx)
    MultiValue(_) | InlineType(_, _) => abort("unresolved block signature")
  }
}

///|
/// Encode alignment, an optional memory index, and the offset.
fn encode_memarg(
  w : @binary.Writer,
  memidx : Int32,
  align : Int32,
  offset : Int64,
) -> Unit {
  if memidx == 0 {
    w.write_u32(align)
  } else {
    w.write_u32(align | 0x40)
    w.write_u32(memidx)
  }
  w.write_u64(offset)
}

///|
/// Encode instructions
fn encode_instructions(
  w : @binary.Writer,
  instrs : ArrayView[@types.Instruction],
) -> Unit {
  for instr in instrs {
    encode_instruction(w, instr)
  }
}

///|
/// Encode a single instruction
fn encode_instruction(w : @binary.Writer, instr : @types.Instruction) -> Unit {
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
      if !else_body.is_empty() {
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
    ContNew(index) => {
      w.write_byte(0xE0)
      w.write_u32(index)
    }
    ContBind(input, output) => {
      w.write_byte(0xE1)
      w.write_u32(input)
      w.write_u32(output)
    }
    Suspend(tag) => {
      w.write_byte(0xE2)
      w.write_u32(tag)
    }
    Resume(index, handlers) => {
      w.write_byte(0xE3)
      w.write_u32(index)
      encode_resume_handlers(w, handlers)
    }
    ResumeThrow(index, tag, handlers) => {
      w.write_byte(0xE4)
      w.write_u32(index)
      w.write_u32(tag)
      encode_resume_handlers(w, handlers)
    }
    ResumeThrowRef(index, handlers) => {
      w.write_byte(0xE5)
      w.write_u32(index)
      encode_resume_handlers(w, handlers)
    }
    Switch(index, tag) => {
      w.write_byte(0xE6)
      w.write_u32(index)
      w.write_u32(tag)
    }
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
    Atomic(subopcode, memidx, align, offset) => {
      w.write_byte(0xFE)
      w.write_u32(subopcode)
      if subopcode == 3 {
        w.write_byte(0)
      } else {
        encode_memarg(w, memidx, align, offset)
      }
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
      encode_heaptype(w, vt)
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
    I64Add128 | I64Sub128 | I64MulWideS | I64MulWideU => {
      w.write_byte(0xFC)
      w.write_u32(
        match instr {
          I64Add128 => 19
          I64Sub128 => 20
          I64MulWideS => 21
          _ => 22
        },
      )
    }
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
      encode_heaptype(w, vt)
    }
    RefTestNull(vt) => {
      w.write_byte(0xFB)
      w.write_u32(21)
      encode_heaptype(w, vt)
    }
    RefCast(vt) => {
      w.write_byte(0xFB)
      w.write_u32(22)
      encode_heaptype(w, vt)
    }
    RefCastNull(vt) => {
      w.write_byte(0xFB)
      w.write_u32(23)
      encode_heaptype(w, vt)
    }
    BrOnCast(label, from_type, to_type) => {
      w.write_byte(0xFB)
      w.write_u32(24)
      // Cast flags: bit 0 = from nullable, bit 1 = to nullable
      let from_null = if from_type.is_nullable() { 1 } else { 0 }
      let to_null = if to_type.is_nullable() { 2 } else { 0 }
      w.write_byte(from_null | to_null)
      w.write_u32(label)
      encode_heaptype(w, from_type)
      encode_heaptype(w, to_type)
    }
    BrOnCastFail(label, from_type, to_type) => {
      w.write_byte(0xFB)
      w.write_u32(25)
      let from_null = if from_type.is_nullable() { 1 } else { 0 }
      let to_null = if to_type.is_nullable() { 2 } else { 0 }
      w.write_byte(from_null | to_null)
      w.write_u32(label)
      encode_heaptype(w, from_type)
      encode_heaptype(w, to_type)
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
    _ => encode_simd_instruction(w, instr)
  }
}

///|
/// Encode a catch handler
fn encode_catch_handler(
  w : @binary.Writer,
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
  w : @binary.Writer,
  section_id : Int32,
  payload : @binary.Writer,
) -> Unit {
  w.write_byte(section_id)
  w.write_u32(payload.length())
  w.write_buffer(payload)
}

///|
/// Encode the type section
fn encode_type_section(out : @binary.Writer, mod : @types.Module) -> Unit {
  if mod.types.is_empty() {
    return
  }
  let w = @binary.Writer()
  let groups : Array[(Int32, Int32)] = []
  let mut start = 0
  while start < mod.types.length() {
    let mut end = start + 1
    while end < mod.types.length() &&
          mod.type_rec_groups.get(start) is Some(group) &&
          mod.type_rec_groups.get(end) == Some(group) {
      end = end + 1
    }
    groups.push((start, end))
    start = end
  }
  w.write_u32(groups.length())
  for group in groups {
    let (start, end) = group
    // A bare subtype is an implicit singleton group, even with self references.
    if end - start != 1 {
      w.write_byte(0x4E)
      w.write_u32(end - start)
    }
    for index in start..<end {
      encode_subtype(w, mod.types[index])
    }
  }
  write_section(out, 1, w)
}

///|
/// Encode the import section
fn encode_import_section(out : @binary.Writer, mod : @types.Module) -> Unit {
  if mod.imports.is_empty() {
    return
  }
  let w = @binary.Writer()
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
  write_section(out, 2, w)
}

///|
/// Encode the function section
fn encode_function_section(out : @binary.Writer, mod : @types.Module) -> Unit {
  if mod.funcs.is_empty() {
    return
  }
  let w = @binary.Writer()
  w.write_u32(mod.funcs.length())
  for type_idx in mod.funcs {
    w.write_u32(type_idx)
  }
  write_section(out, 3, w)
}

///|
/// Encode the table section
fn encode_table_section(out : @binary.Writer, mod : @types.Module) -> Unit {
  if mod.tables.is_empty() {
    return
  }
  let w = @binary.Writer()
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
  write_section(out, 4, w)
}

///|
/// Encode the memory section
fn encode_memory_section(out : @binary.Writer, mod : @types.Module) -> Unit {
  if mod.memories.is_empty() {
    return
  }
  let w = @binary.Writer()
  w.write_u32(mod.memories.length())
  for mem in mod.memories {
    encode_memory_type(w, mem)
  }
  write_section(out, 5, w)
}

///|
/// Encode the global section
fn encode_global_section(out : @binary.Writer, mod : @types.Module) -> Unit {
  if mod.globals.is_empty() {
    return
  }
  let w = @binary.Writer()
  w.write_u32(mod.globals.length())
  for global in mod.globals {
    encode_global_type(w, global.type_)
    encode_instructions(w, global.init)
    w.write_byte(0x0B) // end
  }
  write_section(out, 6, w)
}

///|
/// Encode the export section
fn encode_export_section(out : @binary.Writer, mod : @types.Module) -> Unit {
  if mod.exports.is_empty() {
    return
  }
  let w = @binary.Writer()
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
  write_section(out, 7, w)
}

///|
/// Encode the start section
fn encode_start_section(out : @binary.Writer, mod : @types.Module) -> Unit {
  match mod.start {
    Some(func_idx) => {
      let w = @binary.Writer()
      w.write_u32(func_idx)
      write_section(out, 8, w)
    }
    None => ()
  }
}

///|
/// Encode the element section
fn encode_element_section(out : @binary.Writer, mod : @types.Module) -> Unit {
  if mod.elems.is_empty() {
    return
  }
  let w = @binary.Writer()
  w.write_u32(mod.elems.length())
  for elem in mod.elems {
    match elem.mode {
      Active(table_idx, offset_expr) => {
        let implicit_funcref = table_idx == 0 && elem.type_ is FuncRef
        if implicit_funcref &&
          elem.init.iter().all(expr => expr is [RefFunc(_)]) {
          w.write_byte(0x00)
          encode_instructions(w, offset_expr)
          w.write_byte(0x0B)
          w.write_u32(elem.init.length())
          for expr in elem.init {
            guard expr is [RefFunc(index)] else {
              abort("compact element encoding requires a function index")
            }
            w.write_u32(index)
          }
        } else {
          if implicit_funcref {
            w.write_byte(0x04)
          } else {
            w.write_byte(0x06)
            w.write_u32(table_idx)
          }
          encode_instructions(w, offset_expr)
          w.write_byte(0x0B)
          if !implicit_funcref {
            encode_valtype(w, elem.type_)
          }
          encode_element_expressions(w, elem.init)
        }
      }
      Passive | Declarative => {
        w.write_byte(if elem.mode is Passive { 0x05 } else { 0x07 })
        encode_valtype(w, elem.type_)
        encode_element_expressions(w, elem.init)
      }
    }
  }
  write_section(out, 9, w)
}

///|
fn encode_element_expressions(
  w : @binary.Writer,
  expressions : ReadOnlyArray[ReadOnlyArray[@types.Instruction]],
) -> Unit {
  w.write_u32(expressions.length())
  for expr in expressions {
    encode_instructions(w, expr)
    w.write_byte(0x0B)
  }
}

///|
/// Encode the code section
fn encode_code_section(out : @binary.Writer, mod : @types.Module) -> Unit {
  if mod.codes.is_empty() {
    return
  }
  let w = @binary.Writer()
  w.write_u32(mod.codes.length())
  for code in mod.codes {
    // Encode function body
    let body_writer = @binary.Writer()

    // Compress locals: group consecutive same-type locals
    let compressed_locals : Array[(Int32, @types.ValueType)] = []
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
    w.write_u32(body_writer.length())
    w.write_buffer(body_writer)
  }
  write_section(out, 10, w)
}

///|
/// Encode the data section
fn encode_data_section(out : @binary.Writer, mod : @types.Module) -> Unit {
  if mod.datas.is_empty() {
    return
  }
  let w = @binary.Writer()
  w.write_u32(mod.datas.length())
  for data in mod.datas {
    if data.memory_idx < 0 {
      // Passive data segment
      w.write_byte(0x01)
    } else if data.memory_idx == 0 && !data.offset.is_empty() {
      // Active data segment with memory 0
      w.write_byte(0x00)
      encode_instructions(w, data.offset)
      w.write_byte(0x0B) // end
    } else {
      // Active with explicit memory index
      w.write_byte(0x02)
      w.write_u32(data.memory_idx)
      encode_instructions(w, data.offset)
      w.write_byte(0x0B) // end
    }
    // Write data bytes
    w.write_u32(data.init.length())
    w.write_bytes(data.init)
  }
  write_section(out, 11, w)
}

///|
/// Encode the data count section (required for bulk memory)
fn encode_datacount_section(out : @binary.Writer, mod : @types.Module) -> Unit {
  if mod.datas.is_empty() {
    return
  }
  let w = @binary.Writer()
  w.write_u32(mod.datas.length())
  write_section(out, 12, w)
}

///|
/// Encode the tag section
fn encode_tag_section(out : @binary.Writer, mod : @types.Module) -> Unit {
  if mod.tags.is_empty() {
    return
  }
  let w = @binary.Writer()
  w.write_u32(mod.tags.length())
  for tag in mod.tags {
    w.write_byte(0x00) // exception kind
    w.write_u32(tag.type_idx)
  }
  write_section(out, 13, w)
}

// ============ Main Encoder ============

///|
/// Encode a module as WebAssembly bytes.
pub fn encode_bytes(mod : @types.Module) -> Bytes {
  let mod = resolve_block_types(mod)
  let w = @binary.Writer()
  w.write_bytes(b"\x00asm\x01\x00\x00\x00")
  encode_type_section(w, mod)
  encode_import_section(w, mod)
  encode_function_section(w, mod)
  encode_table_section(w, mod)
  encode_memory_section(w, mod)
  encode_tag_section(w, mod)
  encode_global_section(w, mod)
  encode_export_section(w, mod)
  encode_start_section(w, mod)
  encode_element_section(w, mod)
  encode_datacount_section(w, mod)
  encode_code_section(w, mod)
  encode_data_section(w, mod)
  encode_function_names(w, mod)
  w.to_bytes()
}

///|
/// Encode a module as an array of unsigned byte values.
pub fn encode(mod : @types.Module) -> Array[Int32] {
  encode_bytes(mod).iter().map(Byte::to_int).collect()
}

///|
fn encode_function_names(out : @binary.Writer, mod : @types.Module) -> Unit {
  let mut count = mod.funcs.length()
  for import_ in mod.imports {
    if import_.desc is Func(_) {
      count += 1
    }
  }
  let indices : Array[Int32] = []
  for index, _ in mod.func_names {
    if index >= 0 && index < count {
      indices.push(index)
    }
  }
  if indices.is_empty() {
    return
  }
  indices.sort()
  let names = @binary.Writer()
  names.write_u32(indices.length())
  for index in indices {
    names.write_u32(index)
    names.write_name(mod.func_names[index])
  }
  let section = @binary.Writer()
  section.write_name("name")
  section.write_byte(1)
  section.write_u32(names.length())
  section.write_buffer(names)
  write_section(out, 0, section)
}

///|
fn encode_resume_handlers(
  w : @binary.Writer,
  handlers : ArrayView[@types.ResumeHandler],
) -> Unit {
  w.write_u32(handlers.length())
  for handler in handlers {
    match handler {
      OnLabel(tag, label) => {
        w.write_byte(0)
        w.write_u32(tag)
        w.write_u32(label)
      }
      OnSwitch(tag) => {
        w.write_byte(1)
        w.write_u32(tag)
      }
    }
  }
}

///|
/// Heap immediates omit the value type's nullability prefix.
fn encode_heaptype(w : @binary.Writer, ty : @types.ValueType) -> Unit {
  let index = match ty {
    RefFuncTyped(i)
    | RefNullFuncTyped(i)
    | RefContTyped(i)
    | RefNullContTyped(i) => i
    RefStruct(i) | RefNullStruct(i) => if i < 0 { -21 } else { i }
    RefArray(i) | RefNullArray(i) => if i < 0 { -22 } else { i }
    FuncRef | RefFunc => -16
    ExternRef | RefExtern => -17
    AnyRef | RefAny => -18
    RefEq | RefNullEq => -19
    RefI31 | RefNullI31 => -20
    StructRef | RefStructAbs => -21
    ArrayRef | RefArrayAbs => -22
    ExnRef => -23
    ContRef | RefCont => -24
    NullRef | RefNone => -15
    NullExternRef => -14
    NullFuncRef => -13
    NullExnRef => -12
    NullContRef | RefNoCont => -11
    I32 | I64 | F32 | F64 | V128 => abort("expected a reference heap type")
  }
  w.write_s32(index)
}
