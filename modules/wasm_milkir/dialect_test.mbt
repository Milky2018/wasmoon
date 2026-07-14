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
test "Wasm dialect validation rejects unknown opcodes during finalize" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("unknown_wasm_opcode")
  get_exception_tag(builder) |> ignore
  builder.emit_void_ext_inst(ExtOp("wasm", "typo", []), [])
  builder.return_([])
  try builder.finalize() catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="unknown Wasm MilkIR extension opcode 'typo'")
        ),
      )
  } noraise {
    _ => fail("expected finalize to reject the unknown Wasm opcode")
  }
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
test "Wasm dialect validation rejects malformed immediates during finalize" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "malformed_wasm_opcode",
  )
  get_exception_tag(builder) |> ignore
  builder.emit_void_ext_inst(
    ExtOp(
      "wasm",
      "ref_test",
      FixedArray::makei(2, fn(i) { if i == 0 { 3 } else { 2 } }),
    ),
    [],
  )
  builder.return_([])
  try builder.finalize() catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="malformed Wasm MilkIR extension 'ref_test': immediate 1 is a bool flag encoded as 0 or 1, got 2")
        ),
      )
  } noraise {
    _ => fail("expected finalize to reject malformed Wasm immediates")
  }
}

///|
test "Wasm dialect validation rejects missing fixed results" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "missing_wasm_extension_result",
  )
  get_exception_tag(builder) |> ignore
  builder.emit_void_ext_inst(encode(GetExceptionTag), [])
  builder.return_([])
  try builder.finalize() catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="malformed Wasm MilkIR extension 'get_exception_tag': expected results [i32], got []")
        ),
      )
  } noraise {
    _ => fail("expected finalize to reject a missing Wasm extension result")
  }
}

///|
test "Wasm dialect validation rejects invalid fixed operand shapes" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "invalid_wasm_extension_operands",
  )
  get_exception_tag(builder) |> ignore
  builder.emit_ext_inst(I32, encode(RefEq), []) |> ignore
  builder.return_([])
  try builder.finalize() catch {
    err =>
      inspect(
        err,
        content=(
          #|UnverifiableInstruction(message="malformed Wasm MilkIR extension 'ref_eq': expected operands [ref_like, ref_like], got []")
        ),
      )
  } noraise {
    _ => fail("expected finalize to reject invalid Wasm extension operands")
  }
}

///|
test "Wasm dialect validation rejects fixed operand and result types" {
  let rejected : Array[@milkir.VerifyError] = []
  let bad_result = @milkir.FunctionBuilder::FunctionBuilder(
    "invalid_wasm_extension_result_type",
  )
  get_exception_tag(bad_result) |> ignore
  bad_result.emit_ext_inst(F64, encode(GetExceptionTag), []) |> ignore
  bad_result.return_([])
  try bad_result.finalize() catch {
    err => rejected.push(err)
  } noraise {
    _ => fail("expected finalize to reject a wrong Wasm extension result type")
  }

  let bad_operands = @milkir.FunctionBuilder::FunctionBuilder(
    "invalid_wasm_extension_operand_types",
  )
  let lhs = bad_operands.add_param(I32)
  let rhs = bad_operands.add_param(I32)
  get_exception_tag(bad_operands) |> ignore
  bad_operands.emit_ext_inst(I32, encode(RefEq), [lhs, rhs]) |> ignore
  bad_operands.return_([])
  try bad_operands.finalize() catch {
    err => rejected.push(err)
  } noraise {
    _ => fail("expected finalize to reject wrong Wasm extension operand types")
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
test "Wasm call_indirect accepts a table64 index" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "table64_call_indirect",
  )
  let callee = builder.add_param(I64)
  call_indirect_multi(builder, 0, 0, [], callee, []) |> ignore
  builder.return_([])
  builder.finalize() |> ignore
}

///|
test "Wasm return_call_indirect accepts a table64 index" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "table64_return_call_indirect",
  )
  let callee = builder.add_param(I64)
  return_call_indirect_multi(builder, 0, 0, callee, [])
  builder.trap("unreachable after return_call_indirect")
  builder.finalize() |> ignore
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
  try call.finalize() catch {
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
  try return_call.finalize() catch {
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
