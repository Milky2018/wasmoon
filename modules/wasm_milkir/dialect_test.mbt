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
