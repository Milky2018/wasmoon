///|
pub(all) enum WasmOpcode {
  LoadMemBase(Int)
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
fn opcode_payload(opcode : WasmOpcode) -> (Int, FixedArray[Int]) {
  match opcode {
    LoadMemBase(memidx) => (0, imm([memidx]))
    WasmCall(func_idx) => (1, imm([func_idx]))
    WasmCallIndirect(type_idx, table_idx) => (2, imm([type_idx, table_idx]))
    CallRef(type_idx) => (3, imm([type_idx]))
    ReturnCall(func_idx) => (4, imm([func_idx]))
    ReturnCallIndirect(type_idx, table_idx) => (5, imm([type_idx, table_idx]))
    ReturnCallRef(type_idx) => (6, imm([type_idx]))
    GetFuncRef(func_idx) => (7, imm([func_idx]))
    StructNew(type_idx) => (8, imm([type_idx]))
    StructNewDefault(type_idx) => (9, imm([type_idx]))
    StructGet(type_idx, field_idx) => (10, imm([type_idx, field_idx]))
    StructGetS(type_idx, field_idx, byte_width) =>
      (11, imm([type_idx, field_idx, byte_width]))
    StructGetU(type_idx, field_idx, byte_width) =>
      (12, imm([type_idx, field_idx, byte_width]))
    StructSet(type_idx, field_idx) => (13, imm([type_idx, field_idx]))
    ArrayNew(type_idx) => (14, imm([type_idx]))
    ArrayNewDefault(type_idx) => (15, imm([type_idx]))
    ArrayNewFixed(type_idx, len) => (16, imm([type_idx, len]))
    ArrayGet(type_idx) => (17, imm([type_idx]))
    ArrayGetS(type_idx, byte_width) => (18, imm([type_idx, byte_width]))
    ArrayGetU(type_idx, byte_width) => (19, imm([type_idx, byte_width]))
    ArraySet(type_idx) => (20, imm([type_idx]))
    ArrayLen => (21, imm([]))
    ArrayFill(type_idx) => (22, imm([type_idx]))
    ArrayCopy(dst_type_idx, src_type_idx) =>
      (23, imm([dst_type_idx, src_type_idx]))
    ArrayNewData(type_idx, data_idx) => (24, imm([type_idx, data_idx]))
    ArrayNewElem(type_idx, elem_idx) => (25, imm([type_idx, elem_idx]))
    ArrayInitData(type_idx, data_idx) => (26, imm([type_idx, data_idx]))
    ArrayInitElem(type_idx, elem_idx) => (27, imm([type_idx, elem_idx]))
    I31New => (28, imm([]))
    I31GetS => (29, imm([]))
    I31GetU => (30, imm([]))
    RefTest(type_idx, nullable) => (31, imm([type_idx, bool_imm(nullable)]))
    RefCast(type_idx, nullable) => (32, imm([type_idx, bool_imm(nullable)]))
    AnyConvertExtern => (33, imm([]))
    ExternConvertAny => (34, imm([]))
    RefEq => (35, imm([]))
    Throw(tag_idx) => (36, imm([tag_idx]))
    ThrowRef => (37, imm([]))
    TryTableBegin(handler_id) => (38, imm([handler_id]))
    TryTableEnd(handler_id) => (39, imm([handler_id]))
    GetExceptionTag => (40, imm([]))
    GetExceptionValue(idx) => (41, imm([idx]))
    GetExceptionValueCount => (42, imm([]))
    Delegate(depth) => (43, imm([depth]))
    SpillLocalsForThrow(count) => (44, imm([count]))
    GetSpilledLocal(idx) => (45, imm([idx]))
  }
}

///|
fn opcode_from_payload(id : Int, imms : FixedArray[Int]) -> WasmOpcode? {
  match id {
    0 => Some(LoadMemBase(imms[0]))
    1 => Some(WasmCall(imms[0]))
    2 => Some(WasmCallIndirect(imms[0], imms[1]))
    3 => Some(CallRef(imms[0]))
    4 => Some(ReturnCall(imms[0]))
    5 => Some(ReturnCallIndirect(imms[0], imms[1]))
    6 => Some(ReturnCallRef(imms[0]))
    7 => Some(GetFuncRef(imms[0]))
    8 => Some(StructNew(imms[0]))
    9 => Some(StructNewDefault(imms[0]))
    10 => Some(StructGet(imms[0], imms[1]))
    11 => Some(StructGetS(imms[0], imms[1], imms[2]))
    12 => Some(StructGetU(imms[0], imms[1], imms[2]))
    13 => Some(StructSet(imms[0], imms[1]))
    14 => Some(ArrayNew(imms[0]))
    15 => Some(ArrayNewDefault(imms[0]))
    16 => Some(ArrayNewFixed(imms[0], imms[1]))
    17 => Some(ArrayGet(imms[0]))
    18 => Some(ArrayGetS(imms[0], imms[1]))
    19 => Some(ArrayGetU(imms[0], imms[1]))
    20 => Some(ArraySet(imms[0]))
    21 => Some(ArrayLen)
    22 => Some(ArrayFill(imms[0]))
    23 => Some(ArrayCopy(imms[0], imms[1]))
    24 => Some(ArrayNewData(imms[0], imms[1]))
    25 => Some(ArrayNewElem(imms[0], imms[1]))
    26 => Some(ArrayInitData(imms[0], imms[1]))
    27 => Some(ArrayInitElem(imms[0], imms[1]))
    28 => Some(I31New)
    29 => Some(I31GetS)
    30 => Some(I31GetU)
    31 => Some(RefTest(imms[0], imm_bool(imms[1])))
    32 => Some(RefCast(imms[0], imm_bool(imms[1])))
    33 => Some(AnyConvertExtern)
    34 => Some(ExternConvertAny)
    35 => Some(RefEq)
    36 => Some(Throw(imms[0]))
    37 => Some(ThrowRef)
    38 => Some(TryTableBegin(imms[0]))
    39 => Some(TryTableEnd(imms[0]))
    40 => Some(GetExceptionTag)
    41 => Some(GetExceptionValue(imms[0]))
    42 => Some(GetExceptionValueCount)
    43 => Some(Delegate(imms[0]))
    44 => Some(SpillLocalsForThrow(imms[0]))
    45 => Some(GetSpilledLocal(imms[0]))
    _ => None
  }
}

///|
fn descriptor_for_spec(spec : WasmOpcodeSpec) -> @milkir.ExtOpDescriptor {
  ExtOpDescriptor(WASM_DIALECT, spec.wire_name, spec.immediate_kinds.length())
}

///|
pub fn descriptor(opcode : WasmOpcode) -> @milkir.ExtOpDescriptor {
  let (id, _) = opcode_payload(opcode)
  descriptor_for_spec(wasm_opcode_spec(id))
}

///|
pub fn descriptor_by_name(name : String) -> @milkir.ExtOpDescriptor? {
  wasm_opcode_spec_by_wire_name(name).map(descriptor_for_spec)
}

///|
pub fn encode(opcode : WasmOpcode) -> @milkir.ExtOp {
  let (id, immediates) = opcode_payload(opcode)
  let spec = wasm_opcode_spec(id)
  if validate_wasm_opcode_immediates(spec, immediates) is Some(message) {
    abort("invalid \{spec.typed_constructor} encoding: \{message}")
  }
  @milkir.ExtOp::ExtOp(WASM_DIALECT, spec.wire_name, immediates)
}

///|
fn decode_result(ext : @milkir.ExtOp) -> Result[WasmOpcode, String] {
  if ext.dialect != WASM_DIALECT {
    return Err(
      "expected Wasm MilkIR dialect '\{WASM_DIALECT}', got '\{ext.dialect}'",
    )
  }
  let spec = match wasm_opcode_spec_by_wire_name(ext.opcode) {
    Some(spec) => spec
    None => return Err("unknown Wasm MilkIR extension opcode '\{ext.opcode}'")
  }
  match validate_wasm_opcode_immediates(spec, ext.immediates) {
    Some(message) => Err(message)
    None =>
      match opcode_from_payload(spec.id, ext.immediates) {
        Some(opcode) => Ok(opcode)
        None => Err("unsupported Wasm MilkIR extension opcode '\{ext.opcode}'")
      }
  }
}

///|
pub fn decode(ext : @milkir.ExtOp) -> WasmOpcode? {
  match decode_result(ext) {
    Ok(opcode) => Some(opcode)
    Err(_) => None
  }
}

///|
pub fn decode_error(ext : @milkir.ExtOp) -> String? {
  match decode_result(ext) {
    Ok(_) => None
    Err(message) => Some(message)
  }
}

///|
pub fn decode_or_abort(ext : @milkir.ExtOp) -> WasmOpcode {
  match decode_result(ext) {
    Ok(opcode) => opcode
    Err(message) => abort(message)
  }
}

///|
pub fn decode_opcode(opcode : @milkir.Opcode) -> WasmOpcode? {
  match opcode {
    Ext(ext, _) => decode(ext)
    _ => None
  }
}
