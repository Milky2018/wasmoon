///|
test "Wasm extension descriptors validate immediate layout" {
  let desc = descriptor(MemoryGrow(0, Some(10)))
  inspect(desc.dialect, content="wasm")
  inspect(desc.opcode, content="memory_grow")
  inspect(desc.expected_immediate_count(), content="1..2")
  inspect(encode(MemoryGrow(0, None)).matches_descriptor(desc), content="true")
  inspect(
    encode(MemoryGrow(0, Some(10))).matches_descriptor(desc),
    content="true",
  )
}

///|
test "Wasm extension decode reports malformed immediates" {
  let ext = @milkir.ExtOp(
    "wasm",
    "memory_size",
    FixedArray::makei(0, fn(_) { 0 }),
  )
  debug_inspect(
    decode_error(ext),
    content=(
      #|Some("malformed Wasm MilkIR extension 'memory_size': expected 1 immediates, got 0")
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
