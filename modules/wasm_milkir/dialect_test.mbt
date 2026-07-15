///|
test "Wasm extension descriptors validate immediate layout" {
  let desc = descriptor(RefTest(3, true))
  inspect(desc.dialect, content="wasm")
  inspect(desc.opcode, content="ref_test")
  inspect(desc.expected_immediate_count(), content="2")
  inspect(encode(RefTest(3, true)).matches_descriptor(desc), content="true")
}

///|
test "Wasm extension decode reports malformed immediates" {
  let ext = @milkir.ExtOp(
    "wasm",
    "struct_get",
    FixedArray::makei(1, fn(_) { 0 }),
  )
  debug_inspect(
    decode_error(ext),
    content=(
      #|Some("malformed Wasm MilkIR extension 'struct_get': expected 2 immediates, got 1")
    ),
  )
}

///|
test "Wasm extension decode reports unknown opcodes" {
  let ext = @milkir.ExtOp(
    "wasm",
    "memroy_size",
    FixedArray::makei(1, fn(_) { 0 }),
  )
  debug_inspect(
    decode_error(ext),
    content=(
      #|Some("unknown Wasm MilkIR extension opcode 'memroy_size'")
    ),
  )
}

///|
test "Wasm adapter validation rejects unknown opcodes" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("unknown_wasm_opcode")
  builder.emit_void_ext_inst(ExtOp("wasm", "typo", []), [])
  builder.return_([])
  try verify_function(builder.get_function()) catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="unknown Wasm MilkIR extension opcode 'typo'")
        ),
      )
  } noraise {
    _ => fail("expected Wasm validation to reject the unknown opcode")
  }
}

///|
test "Wasm adapter validation accepts legal IR without producer metadata" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("legal_wasm_opcode")
  builder.emit_ext_inst(I32, encode(GetExceptionTag), []) |> ignore
  builder.return_([])
  verify_function(builder.get_function())
}

///|
test "Wasm extension decode validates bool immediates" {
  let ext = @milkir.ExtOp(
    "wasm",
    "ref_test",
    FixedArray::makei(2, fn(i) { if i == 0 { 3 } else { 2 } }),
  )
  debug_inspect(
    decode_error(ext),
    content=(
      #|Some("malformed Wasm MilkIR extension 'ref_test': immediate 1 is a bool flag encoded as 0 or 1, got 2")
    ),
  )
}

///|
test "Wasm adapter validation rejects malformed immediates" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "malformed_wasm_opcode",
  )
  builder.emit_void_ext_inst(
    ExtOp(
      "wasm",
      "ref_test",
      FixedArray::makei(2, fn(i) { if i == 0 { 3 } else { 2 } }),
    ),
    [],
  )
  builder.return_([])
  try verify_function(builder.get_function()) catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="malformed Wasm MilkIR extension 'ref_test': immediate 1 is a bool flag encoded as 0 or 1, got 2")
        ),
      )
  } noraise {
    _ => fail("expected Wasm validation to reject malformed immediates")
  }
}

///|
test "Wasm dialect validation rejects missing fixed results" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "missing_wasm_extension_result",
  )
  builder.emit_void_ext_inst(encode(GetExceptionTag), [])
  builder.return_([])
  try verify_function(builder.get_function()) catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="malformed Wasm MilkIR extension 'get_exception_tag': expected results [i32], got []")
        ),
      )
  } noraise {
    _ => fail("expected Wasm validation to reject a missing extension result")
  }
}

///|
test "Wasm dialect validation rejects invalid fixed operand shapes" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "invalid_wasm_extension_operands",
  )
  builder.emit_ext_inst(I32, encode(RefEq), []) |> ignore
  builder.return_([])
  try verify_function(builder.get_function()) catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="malformed Wasm MilkIR extension 'ref_eq': expected operands [ref_like, ref_like], got []")
        ),
      )
  } noraise {
    _ => fail("expected Wasm validation to reject invalid extension operands")
  }
}

///|
test "Wasm dialect validation rejects fixed operand and result types" {
  let rejected : Array[@milkir.VerifyError] = []
  let bad_result = @milkir.FunctionBuilder::FunctionBuilder(
    "invalid_wasm_extension_result_type",
  )
  bad_result.emit_ext_inst(F64, encode(GetExceptionTag), []) |> ignore
  bad_result.return_([])
  try verify_function(bad_result.get_function()) catch {
    err => rejected.push(err)
  } noraise {
    _ => fail("expected Wasm validation to reject the wrong extension result")
  }

  let bad_operands = @milkir.FunctionBuilder::FunctionBuilder(
    "invalid_wasm_extension_operand_types",
  )
  let lhs = bad_operands.add_param(I32)
  let rhs = bad_operands.add_param(I32)
  bad_operands.emit_ext_inst(I32, encode(RefEq), [lhs, rhs]) |> ignore
  bad_operands.return_([])
  try verify_function(bad_operands.get_function()) catch {
    err => rejected.push(err)
  } noraise {
    _ => fail("expected Wasm validation to reject wrong extension operands")
  }
  debug_inspect(
    rejected,
    content=(
      #|[
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'get_exception_tag': expected results [i32], got [f64]"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'ref_eq': expected operands [ref_like, ref_like], got [i32, i32]"),
      #|]
    ),
  )
}

///|
priv enum PackedGetProbe {
  StructGetSigned
  StructGetUnsigned
  ArrayGetSigned
  ArrayGetUnsigned
}

///|
fn PackedGetProbe::wire_name(self : PackedGetProbe) -> String {
  match self {
    StructGetSigned => "struct_get_s"
    StructGetUnsigned => "struct_get_u"
    ArrayGetSigned => "array_get_s"
    ArrayGetUnsigned => "array_get_u"
  }
}

///|
fn packed_get_verify_error(
  probe : PackedGetProbe,
  result_type : @milkir.Type,
  byte_width : Int,
) -> @milkir.VerifyError {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "invalid_\{probe.wire_name()}",
  )
  let ref_value = builder.add_param(Ref)
  let index = builder.add_param(I32)
  let immediates = match probe {
    StructGetSigned | StructGetUnsigned =>
      FixedArray::makei(3, fn(i) { if i == 2 { byte_width } else { 0 } })
    ArrayGetSigned | ArrayGetUnsigned =>
      FixedArray::makei(2, fn(i) { if i == 1 { byte_width } else { 0 } })
  }
  let operands = match probe {
    StructGetSigned | StructGetUnsigned => [ref_value]
    ArrayGetSigned | ArrayGetUnsigned => [ref_value, index]
  }
  builder.emit_ext_inst(
    result_type,
    ExtOp("wasm", probe.wire_name(), immediates),
    operands,
  )
  |> ignore
  builder.return_([])
  try verify_function(builder.get_function()) catch {
    err => err
  } noraise {
    _ => abort("expected \{probe.wire_name()} verification to fail")
  }
}

///|
test "Wasm packed get results are fixed to i32" {
  debug_inspect(
    [
      packed_get_verify_error(StructGetSigned, F64, 1),
      packed_get_verify_error(StructGetUnsigned, F64, 2),
      packed_get_verify_error(ArrayGetSigned, F64, 1),
      packed_get_verify_error(ArrayGetUnsigned, F64, 2),
    ],
    content=(
      #|[
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'struct_get_s': expected results [i32], got [f64]"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'struct_get_u': expected results [i32], got [f64]"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'array_get_s': expected results [i32], got [f64]"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'array_get_u': expected results [i32], got [f64]"),
      #|]
    ),
  )
}

///|
test "Wasm packed get widths are limited to one or two bytes" {
  let errors : Array[@milkir.VerifyError] = []
  for
    probe in [
      StructGetSigned,
      StructGetUnsigned,
      ArrayGetSigned,
      ArrayGetUnsigned,
    ] {
    for byte_width in [-1, 0, 3] {
      errors.push(packed_get_verify_error(probe, I32, byte_width))
    }
  }
  debug_inspect(
    errors,
    content=(
      #|[
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'struct_get_s': immediate 2 is a packed byte width encoded as 1 or 2, got -1"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'struct_get_s': immediate 2 is a packed byte width encoded as 1 or 2, got 0"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'struct_get_s': immediate 2 is a packed byte width encoded as 1 or 2, got 3"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'struct_get_u': immediate 2 is a packed byte width encoded as 1 or 2, got -1"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'struct_get_u': immediate 2 is a packed byte width encoded as 1 or 2, got 0"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'struct_get_u': immediate 2 is a packed byte width encoded as 1 or 2, got 3"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'array_get_s': immediate 1 is a packed byte width encoded as 1 or 2, got -1"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'array_get_s': immediate 1 is a packed byte width encoded as 1 or 2, got 0"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'array_get_s': immediate 1 is a packed byte width encoded as 1 or 2, got 3"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'array_get_u': immediate 1 is a packed byte width encoded as 1 or 2, got -1"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'array_get_u': immediate 1 is a packed byte width encoded as 1 or 2, got 0"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'array_get_u': immediate 1 is a packed byte width encoded as 1 or 2, got 3"),
      #|]
    ),
  )
}

///|
test "Wasm call_indirect accepts a table64 index" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "table64_call_indirect",
  )
  let callee = builder.add_param(I64)
  call_indirect_multi(builder, 0, 0, [], callee, []) |> ignore
  builder.return_([])
  verify_function(builder.get_function())
}

///|
test "Wasm return_call_indirect accepts a table64 index" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "table64_return_call_indirect",
  )
  let callee = builder.add_param(I64)
  return_call_indirect_multi(builder, 0, 0, callee, [])
  builder.trap("unreachable after return_call_indirect")
  verify_function(builder.get_function())
}

///|
test "Wasm indirect calls reject non-integer table indices" {
  let rejected : Array[@milkir.VerifyError] = []
  let call = @milkir.FunctionBuilder::FunctionBuilder(
    "invalid_call_indirect_index",
  )
  let call_callee = call.add_param(F64)
  call_indirect_multi(call, 0, 0, [], call_callee, []) |> ignore
  call.return_([])
  try verify_function(call.get_function()) catch {
    err => rejected.push(err)
  } noraise {
    _ => fail("expected call_indirect to reject an f64 table index")
  }

  let return_call = @milkir.FunctionBuilder::FunctionBuilder(
    "invalid_return_call_indirect_index",
  )
  let return_callee = return_call.add_param(F64)
  return_call_indirect_multi(return_call, 0, 0, return_callee, [])
  return_call.trap("unreachable after return_call_indirect")
  try verify_function(return_call.get_function()) catch {
    err => rejected.push(err)
  } noraise {
    _ => fail("expected return_call_indirect to reject an f64 table index")
  }
  debug_inspect(
    rejected,
    content=(
      #|[
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'call_indirect': expected operands [i32 | i64, ...], got [f64]"),
      #|  UnverifiableInstruction(message="malformed Wasm MilkIR extension 'return_call_indirect': expected operands [i32 | i64, ...], got [f64]"),
      #|]
    ),
  )
}

///|
test "Wasm extension decode rejects runtime-lowered operations" {
  let extensions : Array[@milkir.ExtOp] = [
    ExtOp("wasm", "memory_grow", [0]),
    ExtOp("wasm", "memory_size", [0]),
    ExtOp("wasm", "memory_fill", [0]),
    ExtOp("wasm", "memory_copy", [0, 0]),
    ExtOp("wasm", "memory_init", [0, 0]),
    ExtOp("wasm", "data_drop", [0]),
    ExtOp("wasm", "table_grow", [0]),
    ExtOp("wasm", "table_fill", [0]),
    ExtOp("wasm", "table_copy", [0, 0]),
    ExtOp("wasm", "table_init", [0, 0]),
    ExtOp("wasm", "elem_drop", [0]),
  ]
  for ext in extensions {
    assert_true(decode_error(ext) is Some(_))
    assert_true(decode(ext) is None)
  }
}

///|
test "GC builders preserve reference carriers" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("gc_reference_types")
  let i32 = builder.add_param(I32)
  let any_ref = builder.add_param(Ref)
  let extern_ref = builder.add_param(OpaqueRef)

  inspect(struct_new(builder, 0, []).ty, content="ref")
  inspect(struct_new_default(builder, 0).ty, content="ref")
  inspect(array_new(builder, 0, i32, i32).ty, content="ref")
  inspect(array_new_default(builder, 0, i32).ty, content="ref")
  inspect(array_new_fixed(builder, 0, 1, [i32]).ty, content="ref")
  inspect(array_new_data(builder, 0, 0, i32, i32).ty, content="ref")
  inspect(array_new_elem(builder, 0, 0, i32, i32).ty, content="ref")
  inspect(i31_new(builder, i32).ty, content="ref")
  inspect(ref_cast(builder, 0, false, any_ref, Ref).ty, content="ref")
  inspect(any_convert_extern(builder, extern_ref).ty, content="ref")
  inspect(extern_convert_any(builder, any_ref).ty, content="opaque_ref")
}

///|
test "table grow preserves table index width" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("table_grow_types")
  let vmctx = builder.add_param(I64)
  let delta = builder.add_param(I64)
  let init_value = builder.add_param(CallableRef)
  let symbols = RuntimeSymbols::with_runtime_prefix("wasm.runtime")

  inspect(
    table_grow(builder, symbols, vmctx, 0, delta, init_value).ty,
    content="i32",
  )
  inspect(
    table_grow(builder, symbols, vmctx, 0, delta, init_value, is_table64=true).ty,
    content="i64",
  )
}
