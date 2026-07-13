///|
fn all_typed_wasm_opcodes() -> Array[WasmOpcode] {
  [
    LoadMemBase(100),
    WasmCall(101),
    WasmCallIndirect(102, 202),
    CallRef(103),
    ReturnCall(104),
    ReturnCallIndirect(105, 205),
    ReturnCallRef(106),
    GetFuncRef(107),
    StructNew(108),
    StructNewDefault(109),
    StructGet(110, 210),
    StructGetS(111, 211, 8),
    StructGetU(112, 212, 16),
    StructSet(113, 213),
    ArrayNew(114),
    ArrayNewDefault(115),
    ArrayNewFixed(116, 216),
    ArrayGet(117),
    ArrayGetS(118, 8),
    ArrayGetU(119, 16),
    ArraySet(120),
    ArrayLen,
    ArrayFill(122),
    ArrayCopy(123, 223),
    ArrayNewData(124, 224),
    ArrayNewElem(125, 225),
    ArrayInitData(126, 226),
    ArrayInitElem(127, 227),
    I31New,
    I31GetS,
    I31GetU,
    RefTest(131, true),
    RefCast(132, false),
    AnyConvertExtern,
    ExternConvertAny,
    RefEq,
    Throw(136),
    ThrowRef,
    TryTableBegin(138),
    TryTableEnd(139),
    GetExceptionTag,
    GetExceptionValue(141),
    GetExceptionValueCount,
    Delegate(143),
    SpillLocalsForThrow(144),
    GetSpilledLocal(145),
  ]
}

///|
fn typed_constructor_name(opcode : WasmOpcode) -> String {
  let repr = "\{to_repr(opcode)}"
  repr.split("(").to_array()[0].to_owned()
}

///|
test "embedded schema covers every typed Wasm opcode" {
  let opcodes = all_typed_wasm_opcodes()
  inspect(wasm_opcode_specs.length(), content="46")
  inspect(opcodes.length(), content="46")
  let observed_wire_names : Map[String, Unit] = Map([])
  for opcode in opcodes {
    let (id, _) = opcode_payload(opcode)
    assert_true(
      wasm_opcode_spec(id).typed_constructor == typed_constructor_name(opcode),
    )
    let ext = encode(opcode)
    assert_true(!observed_wire_names.contains(ext.opcode))
    observed_wire_names[ext.opcode] = ()
    assert_eq(decode(ext), Some(opcode))
    let desc = descriptor(opcode)
    assert_true(desc.opcode == ext.opcode)
    assert_true(desc.accepts_immediate_count(ext.immediates.length()))
    assert_true(descriptor_by_name(ext.opcode) == Some(desc))
  }
}

///|
test "every embedded schema row decodes to a typed opcode" {
  for spec in wasm_opcode_specs {
    let immediates = FixedArray::makei(spec.immediate_kinds.length(), i => {
      match spec.immediate_kinds[i] {
        IntegerImmediate => spec.id + i + 1
        BooleanImmediate => 1
      }
    })
    let ext = @milkir.ExtOp::ExtOp(WASM_DIALECT, spec.wire_name, immediates)
    assert_true(decode_error(ext) is None)
    assert_true(decode(ext) is Some(_))
  }
}

///|
test "embedded schema validates every immediate layout" {
  for spec in wasm_opcode_specs {
    let wrong_count = FixedArray::make(spec.immediate_kinds.length() + 1, 0)
    let malformed_count = @milkir.ExtOp::ExtOp(
      WASM_DIALECT,
      spec.wire_name,
      wrong_count,
    )
    assert_true(decode_error(malformed_count) is Some(_))
    for bool_index, kind in spec.immediate_kinds {
      if kind is BooleanImmediate {
        let invalid_bool = FixedArray::makei(spec.immediate_kinds.length(), i => {
          if i == bool_index {
            2
          } else {
            0
          }
        })
        let malformed_bool = @milkir.ExtOp::ExtOp(
          WASM_DIALECT,
          spec.wire_name,
          invalid_bool,
        )
        assert_true(decode_error(malformed_bool) is Some(_))
      }
    }
  }
}
