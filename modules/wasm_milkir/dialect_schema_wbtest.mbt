///|
fn valid_immediates(spec : WasmOpcodeSpec) -> FixedArray[Int] {
  FixedArray::makei(spec.immediate_kinds.length(), i => {
    match spec.immediate_kinds[i] {
      IntegerImmediate => spec.id + i + 1
      BooleanImmediate => 1
    }
  })
}

///|
test "generated Wasm opcode codec round-trips every schema row" {
  inspect(wasm_opcode_specs.length(), content="46")
  let observed_wire_names : Map[String, Unit] = Map([])
  for spec in wasm_opcode_specs {
    let opcode = match opcode_from_payload(spec.id, valid_immediates(spec)) {
      Some(opcode) => opcode
      None => abort("generated codec omitted \{spec.typed_constructor}")
    }
    let (id, encoded_immediates) = opcode_payload(opcode)
    assert_true(id == spec.id)
    assert_true(encoded_immediates == valid_immediates(spec))
    let ext = encode(opcode)
    assert_true(ext.opcode == spec.wire_name)
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
test "every generated schema row decodes to a typed opcode" {
  for spec in wasm_opcode_specs {
    let immediates = valid_immediates(spec)
    let ext = @milkir.ExtOp::ExtOp(WASM_DIALECT, spec.wire_name, immediates)
    assert_true(decode_error(ext) is None)
    assert_true(decode(ext) is Some(_))
  }
}

///|
test "generated schema validates every immediate layout" {
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
