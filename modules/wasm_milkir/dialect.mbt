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
const WASM_DIALECT : String = "wasm"

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
fn ext_descriptor(name : String, count : Int) -> @milkir.ExtOpDescriptor {
  ExtOpDescriptor(WASM_DIALECT, name, count)
}

///|
fn ext_descriptor_range(
  name : String,
  min_count : Int,
  max_count : Int,
) -> @milkir.ExtOpDescriptor {
  @milkir.ExtOpDescriptor::with_immediate_range(
    WASM_DIALECT,
    name,
    min_count,
    max_count,
  )
}

///|
pub fn descriptor(opcode : WasmOpcode) -> @milkir.ExtOpDescriptor {
  match opcode {
    LoadMemBase(_) => ext_descriptor("load_mem_base", 1)
    MemoryGrow(_, _) => ext_descriptor_range("memory_grow", 1, 2)
    MemorySize(_) => ext_descriptor("memory_size", 1)
    MemoryFill(_) => ext_descriptor("memory_fill", 1)
    MemoryCopy(_, _) => ext_descriptor("memory_copy", 2)
    MemoryInit(_, _) => ext_descriptor("memory_init", 2)
    DataDrop(_) => ext_descriptor("data_drop", 1)
    TableGrow(_) => ext_descriptor("table_grow", 1)
    TableFill(_) => ext_descriptor("table_fill", 1)
    TableCopy(_, _) => ext_descriptor("table_copy", 2)
    TableInit(_, _) => ext_descriptor("table_init", 2)
    ElemDrop(_) => ext_descriptor("elem_drop", 1)
    WasmCall(_) => ext_descriptor("call", 1)
    WasmCallIndirect(_, _) => ext_descriptor("call_indirect", 2)
    CallRef(_) => ext_descriptor("call_ref", 1)
    ReturnCall(_) => ext_descriptor("return_call", 1)
    ReturnCallIndirect(_, _) => ext_descriptor("return_call_indirect", 2)
    ReturnCallRef(_) => ext_descriptor("return_call_ref", 1)
    GetFuncRef(_) => ext_descriptor("get_func_ref", 1)
    StructNew(_) => ext_descriptor("struct_new", 1)
    StructNewDefault(_) => ext_descriptor("struct_new_default", 1)
    StructGet(_, _) => ext_descriptor("struct_get", 2)
    StructGetS(_, _, _) => ext_descriptor("struct_get_s", 3)
    StructGetU(_, _, _) => ext_descriptor("struct_get_u", 3)
    StructSet(_, _) => ext_descriptor("struct_set", 2)
    ArrayNew(_) => ext_descriptor("array_new", 1)
    ArrayNewDefault(_) => ext_descriptor("array_new_default", 1)
    ArrayNewFixed(_, _) => ext_descriptor("array_new_fixed", 2)
    ArrayGet(_) => ext_descriptor("array_get", 1)
    ArrayGetS(_, _) => ext_descriptor("array_get_s", 2)
    ArrayGetU(_, _) => ext_descriptor("array_get_u", 2)
    ArraySet(_) => ext_descriptor("array_set", 1)
    ArrayLen => ext_descriptor("array_len", 0)
    ArrayFill(_) => ext_descriptor("array_fill", 1)
    ArrayCopy(_, _) => ext_descriptor("array_copy", 2)
    ArrayNewData(_, _) => ext_descriptor("array_new_data", 2)
    ArrayNewElem(_, _) => ext_descriptor("array_new_elem", 2)
    ArrayInitData(_, _) => ext_descriptor("array_init_data", 2)
    ArrayInitElem(_, _) => ext_descriptor("array_init_elem", 2)
    I31New => ext_descriptor("i31_new", 0)
    I31GetS => ext_descriptor("i31_get_s", 0)
    I31GetU => ext_descriptor("i31_get_u", 0)
    RefTest(_, _) => ext_descriptor("ref_test", 2)
    RefCast(_, _) => ext_descriptor("ref_cast", 2)
    AnyConvertExtern => ext_descriptor("any_convert_extern", 0)
    ExternConvertAny => ext_descriptor("extern_convert_any", 0)
    RefEq => ext_descriptor("ref_eq", 0)
    Throw(_) => ext_descriptor("throw", 1)
    ThrowRef => ext_descriptor("throw_ref", 0)
    TryTableBegin(_) => ext_descriptor("try_table_begin", 1)
    TryTableEnd(_) => ext_descriptor("try_table_end", 1)
    GetExceptionTag => ext_descriptor("get_exception_tag", 0)
    GetExceptionValue(_) => ext_descriptor("get_exception_value", 1)
    GetExceptionValueCount => ext_descriptor("get_exception_value_count", 0)
    Delegate(_) => ext_descriptor("delegate", 1)
    SpillLocalsForThrow(_) => ext_descriptor("spill_locals_for_throw", 1)
    GetSpilledLocal(_) => ext_descriptor("get_spilled_local", 1)
  }
}

///|
pub fn descriptor_by_name(name : String) -> @milkir.ExtOpDescriptor? {
  match name {
    "load_mem_base" => Some(ext_descriptor("load_mem_base", 1))
    "memory_grow" => Some(ext_descriptor_range("memory_grow", 1, 2))
    "memory_size" => Some(ext_descriptor("memory_size", 1))
    "memory_fill" => Some(ext_descriptor("memory_fill", 1))
    "memory_copy" => Some(ext_descriptor("memory_copy", 2))
    "memory_init" => Some(ext_descriptor("memory_init", 2))
    "data_drop" => Some(ext_descriptor("data_drop", 1))
    "table_grow" => Some(ext_descriptor("table_grow", 1))
    "table_fill" => Some(ext_descriptor("table_fill", 1))
    "table_copy" => Some(ext_descriptor("table_copy", 2))
    "table_init" => Some(ext_descriptor("table_init", 2))
    "elem_drop" => Some(ext_descriptor("elem_drop", 1))
    "call" => Some(ext_descriptor("call", 1))
    "call_indirect" => Some(ext_descriptor("call_indirect", 2))
    "call_ref" => Some(ext_descriptor("call_ref", 1))
    "return_call" => Some(ext_descriptor("return_call", 1))
    "return_call_indirect" => Some(ext_descriptor("return_call_indirect", 2))
    "return_call_ref" => Some(ext_descriptor("return_call_ref", 1))
    "get_func_ref" => Some(ext_descriptor("get_func_ref", 1))
    "struct_new" => Some(ext_descriptor("struct_new", 1))
    "struct_new_default" => Some(ext_descriptor("struct_new_default", 1))
    "struct_get" => Some(ext_descriptor("struct_get", 2))
    "struct_get_s" => Some(ext_descriptor("struct_get_s", 3))
    "struct_get_u" => Some(ext_descriptor("struct_get_u", 3))
    "struct_set" => Some(ext_descriptor("struct_set", 2))
    "array_new" => Some(ext_descriptor("array_new", 1))
    "array_new_default" => Some(ext_descriptor("array_new_default", 1))
    "array_new_fixed" => Some(ext_descriptor("array_new_fixed", 2))
    "array_get" => Some(ext_descriptor("array_get", 1))
    "array_get_s" => Some(ext_descriptor("array_get_s", 2))
    "array_get_u" => Some(ext_descriptor("array_get_u", 2))
    "array_set" => Some(ext_descriptor("array_set", 1))
    "array_len" => Some(ext_descriptor("array_len", 0))
    "array_fill" => Some(ext_descriptor("array_fill", 1))
    "array_copy" => Some(ext_descriptor("array_copy", 2))
    "array_new_data" => Some(ext_descriptor("array_new_data", 2))
    "array_new_elem" => Some(ext_descriptor("array_new_elem", 2))
    "array_init_data" => Some(ext_descriptor("array_init_data", 2))
    "array_init_elem" => Some(ext_descriptor("array_init_elem", 2))
    "i31_new" => Some(ext_descriptor("i31_new", 0))
    "i31_get_s" => Some(ext_descriptor("i31_get_s", 0))
    "i31_get_u" => Some(ext_descriptor("i31_get_u", 0))
    "ref_test" => Some(ext_descriptor("ref_test", 2))
    "ref_cast" => Some(ext_descriptor("ref_cast", 2))
    "any_convert_extern" => Some(ext_descriptor("any_convert_extern", 0))
    "extern_convert_any" => Some(ext_descriptor("extern_convert_any", 0))
    "ref_eq" => Some(ext_descriptor("ref_eq", 0))
    "throw" => Some(ext_descriptor("throw", 1))
    "throw_ref" => Some(ext_descriptor("throw_ref", 0))
    "try_table_begin" => Some(ext_descriptor("try_table_begin", 1))
    "try_table_end" => Some(ext_descriptor("try_table_end", 1))
    "get_exception_tag" => Some(ext_descriptor("get_exception_tag", 0))
    "get_exception_value" => Some(ext_descriptor("get_exception_value", 1))
    "get_exception_value_count" =>
      Some(ext_descriptor("get_exception_value_count", 0))
    "delegate" => Some(ext_descriptor("delegate", 1))
    "spill_locals_for_throw" =>
      Some(ext_descriptor("spill_locals_for_throw", 1))
    "get_spilled_local" => Some(ext_descriptor("get_spilled_local", 1))
    _ => None
  }
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
  let desc = descriptor(opcode)
  let ext = @milkir.ExtOp::ExtOp(WASM_DIALECT, name, immediates)
  if !ext.matches_descriptor(desc) {
    abort(
      "invalid Wasm MilkIR descriptor for \{name}: expected \{desc.expected_immediate_count()} immediates, got \{immediates.length()}",
    )
  }
  ext
}

///|
pub fn decode(ext : @milkir.ExtOp) -> WasmOpcode? {
  guard ext.dialect == WASM_DIALECT else { return None }
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
fn valid_bool_immediate(value : Int) -> Bool {
  value == 0 || value == 1
}

///|
pub fn decode_error(ext : @milkir.ExtOp) -> String? {
  if ext.dialect != WASM_DIALECT {
    return Some(
      "expected Wasm MilkIR dialect '\{WASM_DIALECT}', got '\{ext.dialect}'",
    )
  }
  let desc = match descriptor_by_name(ext.opcode) {
    Some(desc) => desc
    None => return Some("unknown Wasm MilkIR extension opcode '\{ext.opcode}'")
  }
  if !ext.matches_descriptor(desc) {
    return Some(
      "malformed Wasm MilkIR extension '\{ext.opcode}': expected \{desc.expected_immediate_count()} immediates, got \{ext.immediates.length()}",
    )
  }
  if (ext.opcode == "ref_test" || ext.opcode == "ref_cast") &&
    !valid_bool_immediate(ext.immediates[1]) {
    return Some(
      "malformed Wasm MilkIR extension '\{ext.opcode}': immediate 1 is a bool flag encoded as 0 or 1, got \{ext.immediates[1]}",
    )
  }
  None
}

///|
pub fn decode_or_abort(ext : @milkir.ExtOp) -> WasmOpcode {
  match decode_error(ext) {
    Some(message) => abort(message)
    None =>
      match decode(ext) {
        Some(opcode) => opcode
        None => abort("malformed Wasm MilkIR extension '\{ext.opcode}'")
      }
  }
}

///|
pub fn decode_opcode(opcode : @milkir.Opcode) -> WasmOpcode? {
  match opcode {
    Ext(ext, _) => decode(ext)
    _ => None
  }
}
