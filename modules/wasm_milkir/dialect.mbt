///|
pub(all) enum WasmOpcode {
  LoadMemBase(Int)
  MemoryGrow(Int, Int?)
  MemorySize(Int)
  MemoryFill(Int)
  MemoryCopy(Int, Int)
  MemoryInit(Int, Int)
  DataDrop(Int)
  TableGrow(Int)
  TableFill(Int)
  TableCopy(Int, Int)
  TableInit(Int, Int)
  ElemDrop(Int)
  WasmCall(Int)
  WasmCallIndirect(Int, Int)
  CallRef(Int)
  ReturnCall(Int)
  ReturnCallIndirect(Int, Int)
  ReturnCallRef(Int)
  GetFuncRef(Int)
  StructNew(Int)
  StructNewDefault(Int)
  StructGet(Int, Int)
  StructGetS(Int, Int, Int)
  StructGetU(Int, Int, Int)
  StructSet(Int, Int)
  ArrayNew(Int)
  ArrayNewDefault(Int)
  ArrayNewFixed(Int, Int)
  ArrayGet(Int)
  ArrayGetS(Int, Int)
  ArrayGetU(Int, Int)
  ArraySet(Int)
  ArrayLen
  ArrayFill(Int)
  ArrayCopy(Int, Int)
  ArrayNewData(Int, Int)
  ArrayNewElem(Int, Int)
  ArrayInitData(Int, Int)
  ArrayInitElem(Int, Int)
  I31New
  I31GetS
  I31GetU
  RefTest(Int, Bool)
  RefCast(Int, Bool)
  AnyConvertExtern
  ExternConvertAny
  RefEq
  Throw(Int)
  ThrowRef
  TryTableBegin(Int)
  TryTableEnd(Int)
  GetExceptionTag
  GetExceptionValue(Int)
  GetExceptionValueCount
  Delegate(Int)
  SpillLocalsForThrow(Int)
  GetSpilledLocal(Int)
} derive(Debug, Eq, Hash)

///|
fn imm(values : Array[Int]) -> FixedArray[Int] {
  FixedArray::makei(values.length(), fn(i) { values[i] })
}

///|
fn bool_imm(value : Bool) -> Int {
  if value {
    1
  } else {
    0
  }
}

///|
fn imm_bool(value : Int) -> Bool {
  value != 0
}

///|
pub fn encode(opcode : WasmOpcode) -> @milkir.ExtOp {
  let (name, immediates) = match opcode {
    LoadMemBase(memidx) => ("load_mem_base", imm([memidx]))
    MemoryGrow(memidx, max_pages) =>
      (
        "memory_grow",
        match max_pages {
          Some(max) => imm([memidx, max])
          None => imm([memidx])
        },
      )
    MemorySize(memidx) => ("memory_size", imm([memidx]))
    MemoryFill(memidx) => ("memory_fill", imm([memidx]))
    MemoryCopy(dst_memidx, src_memidx) =>
      ("memory_copy", imm([dst_memidx, src_memidx]))
    MemoryInit(memidx, data_idx) => ("memory_init", imm([memidx, data_idx]))
    DataDrop(data_idx) => ("data_drop", imm([data_idx]))
    TableGrow(table_idx) => ("table_grow", imm([table_idx]))
    TableFill(table_idx) => ("table_fill", imm([table_idx]))
    TableCopy(dst_table_idx, src_table_idx) =>
      ("table_copy", imm([dst_table_idx, src_table_idx]))
    TableInit(table_idx, elem_idx) => ("table_init", imm([table_idx, elem_idx]))
    ElemDrop(elem_idx) => ("elem_drop", imm([elem_idx]))
    WasmCall(func_idx) => ("call", imm([func_idx]))
    WasmCallIndirect(type_idx, table_idx) =>
      ("call_indirect", imm([type_idx, table_idx]))
    CallRef(type_idx) => ("call_ref", imm([type_idx]))
    ReturnCall(func_idx) => ("return_call", imm([func_idx]))
    ReturnCallIndirect(type_idx, table_idx) =>
      ("return_call_indirect", imm([type_idx, table_idx]))
    ReturnCallRef(type_idx) => ("return_call_ref", imm([type_idx]))
    GetFuncRef(func_idx) => ("get_func_ref", imm([func_idx]))
    StructNew(type_idx) => ("struct_new", imm([type_idx]))
    StructNewDefault(type_idx) => ("struct_new_default", imm([type_idx]))
    StructGet(type_idx, field_idx) => ("struct_get", imm([type_idx, field_idx]))
    StructGetS(type_idx, field_idx, byte_width) =>
      ("struct_get_s", imm([type_idx, field_idx, byte_width]))
    StructGetU(type_idx, field_idx, byte_width) =>
      ("struct_get_u", imm([type_idx, field_idx, byte_width]))
    StructSet(type_idx, field_idx) => ("struct_set", imm([type_idx, field_idx]))
    ArrayNew(type_idx) => ("array_new", imm([type_idx]))
    ArrayNewDefault(type_idx) => ("array_new_default", imm([type_idx]))
    ArrayNewFixed(type_idx, len) => ("array_new_fixed", imm([type_idx, len]))
    ArrayGet(type_idx) => ("array_get", imm([type_idx]))
    ArrayGetS(type_idx, byte_width) =>
      ("array_get_s", imm([type_idx, byte_width]))
    ArrayGetU(type_idx, byte_width) =>
      ("array_get_u", imm([type_idx, byte_width]))
    ArraySet(type_idx) => ("array_set", imm([type_idx]))
    ArrayLen => ("array_len", imm([]))
    ArrayFill(type_idx) => ("array_fill", imm([type_idx]))
    ArrayCopy(dst_type_idx, src_type_idx) =>
      ("array_copy", imm([dst_type_idx, src_type_idx]))
    ArrayNewData(type_idx, data_idx) =>
      ("array_new_data", imm([type_idx, data_idx]))
    ArrayNewElem(type_idx, elem_idx) =>
      ("array_new_elem", imm([type_idx, elem_idx]))
    ArrayInitData(type_idx, data_idx) =>
      ("array_init_data", imm([type_idx, data_idx]))
    ArrayInitElem(type_idx, elem_idx) =>
      ("array_init_elem", imm([type_idx, elem_idx]))
    I31New => ("i31_new", imm([]))
    I31GetS => ("i31_get_s", imm([]))
    I31GetU => ("i31_get_u", imm([]))
    RefTest(type_idx, nullable) =>
      ("ref_test", imm([type_idx, bool_imm(nullable)]))
    RefCast(type_idx, nullable) =>
      ("ref_cast", imm([type_idx, bool_imm(nullable)]))
    AnyConvertExtern => ("any_convert_extern", imm([]))
    ExternConvertAny => ("extern_convert_any", imm([]))
    RefEq => ("ref_eq", imm([]))
    Throw(tag_idx) => ("throw", imm([tag_idx]))
    ThrowRef => ("throw_ref", imm([]))
    TryTableBegin(handler_id) => ("try_table_begin", imm([handler_id]))
    TryTableEnd(handler_id) => ("try_table_end", imm([handler_id]))
    GetExceptionTag => ("get_exception_tag", imm([]))
    GetExceptionValue(idx) => ("get_exception_value", imm([idx]))
    GetExceptionValueCount => ("get_exception_value_count", imm([]))
    Delegate(depth) => ("delegate", imm([depth]))
    SpillLocalsForThrow(count) => ("spill_locals_for_throw", imm([count]))
    GetSpilledLocal(idx) => ("get_spilled_local", imm([idx]))
  }
  @milkir.ExtOp::new("wasm", name, immediates)
}

///|
pub fn decode(ext : @milkir.ExtOp) -> WasmOpcode? {
  guard ext.dialect == "wasm" else { return None }
  let imms = ext.immediates
  match ext.opcode {
    "load_mem_base" if imms.length() == 1 => Some(LoadMemBase(imms[0]))
    "memory_grow" if imms.length() == 1 => Some(MemoryGrow(imms[0], None))
    "memory_grow" if imms.length() == 2 =>
      Some(MemoryGrow(imms[0], Some(imms[1])))
    "memory_size" if imms.length() == 1 => Some(MemorySize(imms[0]))
    "memory_fill" if imms.length() == 1 => Some(MemoryFill(imms[0]))
    "memory_copy" if imms.length() == 2 => Some(MemoryCopy(imms[0], imms[1]))
    "memory_init" if imms.length() == 2 => Some(MemoryInit(imms[0], imms[1]))
    "data_drop" if imms.length() == 1 => Some(DataDrop(imms[0]))
    "table_grow" if imms.length() == 1 => Some(TableGrow(imms[0]))
    "table_fill" if imms.length() == 1 => Some(TableFill(imms[0]))
    "table_copy" if imms.length() == 2 => Some(TableCopy(imms[0], imms[1]))
    "table_init" if imms.length() == 2 => Some(TableInit(imms[0], imms[1]))
    "elem_drop" if imms.length() == 1 => Some(ElemDrop(imms[0]))
    "call" if imms.length() == 1 => Some(WasmCall(imms[0]))
    "call_indirect" if imms.length() == 2 =>
      Some(WasmCallIndirect(imms[0], imms[1]))
    "call_ref" if imms.length() == 1 => Some(CallRef(imms[0]))
    "return_call" if imms.length() == 1 => Some(ReturnCall(imms[0]))
    "return_call_indirect" if imms.length() == 2 =>
      Some(ReturnCallIndirect(imms[0], imms[1]))
    "return_call_ref" if imms.length() == 1 => Some(ReturnCallRef(imms[0]))
    "get_func_ref" if imms.length() == 1 => Some(GetFuncRef(imms[0]))
    "struct_new" if imms.length() == 1 => Some(StructNew(imms[0]))
    "struct_new_default" if imms.length() == 1 =>
      Some(StructNewDefault(imms[0]))
    "struct_get" if imms.length() == 2 => Some(StructGet(imms[0], imms[1]))
    "struct_get_s" if imms.length() == 3 =>
      Some(StructGetS(imms[0], imms[1], imms[2]))
    "struct_get_u" if imms.length() == 3 =>
      Some(StructGetU(imms[0], imms[1], imms[2]))
    "struct_set" if imms.length() == 2 => Some(StructSet(imms[0], imms[1]))
    "array_new" if imms.length() == 1 => Some(ArrayNew(imms[0]))
    "array_new_default" if imms.length() == 1 => Some(ArrayNewDefault(imms[0]))
    "array_new_fixed" if imms.length() == 2 =>
      Some(ArrayNewFixed(imms[0], imms[1]))
    "array_get" if imms.length() == 1 => Some(ArrayGet(imms[0]))
    "array_get_s" if imms.length() == 2 => Some(ArrayGetS(imms[0], imms[1]))
    "array_get_u" if imms.length() == 2 => Some(ArrayGetU(imms[0], imms[1]))
    "array_set" if imms.length() == 1 => Some(ArraySet(imms[0]))
    "array_len" if imms.length() == 0 => Some(ArrayLen)
    "array_fill" if imms.length() == 1 => Some(ArrayFill(imms[0]))
    "array_copy" if imms.length() == 2 => Some(ArrayCopy(imms[0], imms[1]))
    "array_new_data" if imms.length() == 2 =>
      Some(ArrayNewData(imms[0], imms[1]))
    "array_new_elem" if imms.length() == 2 =>
      Some(ArrayNewElem(imms[0], imms[1]))
    "array_init_data" if imms.length() == 2 =>
      Some(ArrayInitData(imms[0], imms[1]))
    "array_init_elem" if imms.length() == 2 =>
      Some(ArrayInitElem(imms[0], imms[1]))
    "i31_new" if imms.length() == 0 => Some(I31New)
    "i31_get_s" if imms.length() == 0 => Some(I31GetS)
    "i31_get_u" if imms.length() == 0 => Some(I31GetU)
    "ref_test" if imms.length() == 2 =>
      Some(RefTest(imms[0], imm_bool(imms[1])))
    "ref_cast" if imms.length() == 2 =>
      Some(RefCast(imms[0], imm_bool(imms[1])))
    "any_convert_extern" if imms.length() == 0 => Some(AnyConvertExtern)
    "extern_convert_any" if imms.length() == 0 => Some(ExternConvertAny)
    "ref_eq" if imms.length() == 0 => Some(RefEq)
    "throw" if imms.length() == 1 => Some(Throw(imms[0]))
    "throw_ref" if imms.length() == 0 => Some(ThrowRef)
    "try_table_begin" if imms.length() == 1 => Some(TryTableBegin(imms[0]))
    "try_table_end" if imms.length() == 1 => Some(TryTableEnd(imms[0]))
    "get_exception_tag" if imms.length() == 0 => Some(GetExceptionTag)
    "get_exception_value" if imms.length() == 1 =>
      Some(GetExceptionValue(imms[0]))
    "get_exception_value_count" if imms.length() == 0 =>
      Some(GetExceptionValueCount)
    "delegate" if imms.length() == 1 => Some(Delegate(imms[0]))
    "spill_locals_for_throw" if imms.length() == 1 =>
      Some(SpillLocalsForThrow(imms[0]))
    "get_spilled_local" if imms.length() == 1 => Some(GetSpilledLocal(imms[0]))
    _ => None
  }
}

///|
pub fn decode_opcode(opcode : @milkir.Opcode) -> WasmOpcode? {
  match opcode {
    Ext(ext) => decode(ext)
    _ => None
  }
}
