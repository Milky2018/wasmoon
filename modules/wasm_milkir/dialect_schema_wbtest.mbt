///|
fn valid_immediates(spec : WasmOpcodeSpec) -> FixedArray[Int] {
  FixedArray::makei(spec.immediate_kinds.length(), i => {
    match spec.immediate_kinds[i] {
      IntegerImmediate => spec.id + i + 1
      BooleanImmediate => 1
      PackedWidthImmediate => 1
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
    for immediate_index, kind in spec.immediate_kinds {
      let invalid_values = match kind {
        BooleanImmediate => [2]
        PackedWidthImmediate => [-1, 0, 3]
        IntegerImmediate => []
      }
      for invalid_value in invalid_values {
        let invalid_immediate = FixedArray::makei(
          spec.immediate_kinds.length(),
          i => if i == immediate_index { invalid_value } else { 1 },
        )
        let malformed = @milkir.ExtOp::ExtOp(
          WASM_DIALECT,
          spec.wire_name,
          invalid_immediate,
        )
        assert_true(decode_error(malformed) is Some(_))
      }
    }
  }
}

///|
test "every schema row enforces its non-contextual minimum shape" {
  let rejected : Array[String] = []
  for spec in wasm_opcode_specs {
    let builder = @milkir.FunctionBuilder::FunctionBuilder(
      "schema_contract_\{spec.wire_name}",
    )
    get_exception_tag(builder) |> ignore
    builder.emit_void_ext_inst(
      ExtOp(WASM_DIALECT, spec.wire_name, valid_immediates(spec)),
      [],
    )
    builder.return_([])
    try builder.finalize() catch {
      _ => rejected.push(spec.wire_name)
    } noraise {
      _ => ()
    }
  }
  debug_inspect(
    rejected,
    content=(
      #|[
      #|  "load_mem_base",
      #|  "call_indirect",
      #|  "call_ref",
      #|  "return_call_indirect",
      #|  "return_call_ref",
      #|  "get_func_ref",
      #|  "struct_new",
      #|  "struct_new_default",
      #|  "struct_get",
      #|  "struct_get_s",
      #|  "struct_get_u",
      #|  "struct_set",
      #|  "array_new",
      #|  "array_new_default",
      #|  "array_new_fixed",
      #|  "array_get",
      #|  "array_get_s",
      #|  "array_get_u",
      #|  "array_set",
      #|  "array_len",
      #|  "array_fill",
      #|  "array_copy",
      #|  "array_new_data",
      #|  "array_new_elem",
      #|  "array_init_data",
      #|  "array_init_elem",
      #|  "i31_new",
      #|  "i31_get_s",
      #|  "i31_get_u",
      #|  "ref_test",
      #|  "ref_cast",
      #|  "any_convert_extern",
      #|  "extern_convert_any",
      #|  "ref_eq",
      #|  "throw_ref",
      #|  "try_table_begin",
      #|  "get_exception_tag",
      #|  "get_exception_value",
      #|  "get_exception_value_count",
      #|  "spill_locals_for_throw",
      #|  "get_spilled_local",
      #|]
    ),
  )
}

///|
test "immediate-dependent operand counts are enforced" {
  let rejected : Array[@milkir.VerifyError] = []
  let fixed = @milkir.FunctionBuilder::FunctionBuilder("array_new_fixed_count")
  get_exception_tag(fixed) |> ignore
  fixed.emit_ext_inst(Ref, encode(ArrayNewFixed(0, 2)), []) |> ignore
  fixed.return_([])
  try fixed.finalize() catch {
    err => rejected.push(err)
  } noraise {
    _ => fail("expected array.new_fixed count mismatch to be rejected")
  }

  let spill = @milkir.FunctionBuilder::FunctionBuilder("spill_local_count")
  get_exception_tag(spill) |> ignore
  spill.emit_void_ext_inst(encode(SpillLocalsForThrow(2)), [])
  spill.return_([])
  try spill.finalize() catch {
    err => rejected.push(err)
  } noraise {
    _ => fail("expected spill-locals count mismatch to be rejected")
  }
  debug_inspect(
    rejected,
    content=(
      #|[
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'array_new_fixed': expected 2 operands, got 0"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'spill_locals_for_throw': expected 2 operands, got 0"),
      #|]
    ),
  )
}
