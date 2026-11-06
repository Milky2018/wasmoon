///|
test "x64 Spectre guard emits a branch-free conditional move" {
  let buffer = CodeBuffer::new()
  emit_spectre_guard(
    buffer,
    @vcode.PhysicalReg::new(0, Int),
    @vcode.PhysicalReg::new(1, Int),
    @vcode.PhysicalReg::new(2, Int),
    @vcode.PhysicalReg::new(3, Int),
  )
  debug_inspect(
    buffer.code,
    content="[0x85, 0xc0, 0x48, 0x89, 0xd3, 0x48, 0x0f, 0x45, 0xd9]",
  )
}

///|
test "x64 stack allocation probes every guard-page interval" {
  let buffer = CodeBuffer::new()
  emit_sp_adjust(buffer, true, 8192)
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="4881ec001000004c8b9424000000004881ec001000004c8b942400000000",
  )
}

///|
test "x64 unsigned i32 extension writes the register when coalesced" {
  let buffer = CodeBuffer::new()
  let register = @vcode.PhysicalReg::new(0, Int)
  emit_conversion(buffer, ExtendI32ToI64(Unsigned), register, register)
  debug_inspect(buffer.code, content="[0x89, 0xc0]")
}

///|
test "x64 unsigned i32 to float conversion zero-extends its input" {
  let buffer = CodeBuffer::new()
  try! emit_conversion(
    buffer,
    IntToFloat(I32, F32, Unsigned),
    @vcode.PhysicalReg::new(0, Int),
    @vcode.PhysicalReg::new(0, FpVector),
  )
  debug_inspect(
    buffer.code,
    content=(
      #|[0x41, 0x89, 0xc2, 0xf3, 0x49, 0x0f, 0x2a, 0xc2]
    ),
  )
}

///|
test "x64 unsigned vector compare preserves a coalesced right operand" {
  let buffer = CodeBuffer::new()
  let left = @vcode.PhysicalReg::new(0, FpVector)
  let right_and_destination = @vcode.PhysicalReg::new(1, FpVector)
  try! emit_vector_int_compare(
    buffer,
    I32x4,
    LessThan(Unsigned),
    left,
    right_and_destination,
    right_and_destination,
  )
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="49ba0000008000000080664d0f6ef249ba0000008000000080664d0f3a22f201" +
      "440f28f866410fefce66450feffe66410f66cf",
  )
}

///|
test "x64 i64 vector compare preserves a coalesced input" {
  let buffer = CodeBuffer::new()
  let left_and_destination = @vcode.PhysicalReg::new(0, FpVector)
  let right = @vcode.PhysicalReg::new(1, FpVector)
  try! emit_vector_int_compare(
    buffer,
    I64x2,
    GreaterThan(Signed),
    left_and_destination,
    right,
    left_and_destination,
  )
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="440f28f0664d0f3a16f20066490f3a16cb004d39da410f9fc2450fb6d249f7da" +
      "66490f6ec2664d0f3a16f20166490f3a16cb014d39da410f9fc2450fb6d249f7" +
      "da66490f3a22c201",
  )
}

///|
test "x64 pseudo min preserves a coalesced left operand" {
  let buffer = CodeBuffer::new()
  let left_and_destination = @vcode.PhysicalReg::new(0, FpVector)
  let right = @vcode.PhysicalReg::new(1, FpVector)
  try! emit_vector_float_binary(
    buffer,
    F32x4,
    PseudoMin,
    left_and_destination,
    right,
    left_and_destination,
  )
  debug_inspect(
    buffer.code,
    content=(
      #|[0x44, 0x0f, 0x28, 0xf0, 0x0f, 0x28, 0xc1, 0x41, 0x0f, 0x5d, 0xc6]
    ),
  )
}

///|
test "x64 signed pairwise extension preserves a coalesced input" {
  let buffer = CodeBuffer::new()
  let source_and_destination = @vcode.PhysicalReg::new(0, FpVector)
  try! emit_vector_int_unary(
    buffer,
    I16x8,
    ExtendAddPairwise(Signed),
    source_and_destination,
    source_and_destination,
  )
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="440f28f849ba0101010101010101664d0f6ef249ba0101010101010101664d0f" +
      "3a22f201410f28c666410f3804c7",
  )
}

///|
test "x64 demote preserves a coalesced input" {
  let buffer = CodeBuffer::new()
  let source_and_destination = @vcode.PhysicalReg::new(0, FpVector)
  try! emit_vector_conversion(
    buffer,
    DemoteZeroF64x2,
    source_and_destination,
    source_and_destination,
  )
  inspect(
    @hex.encode(Bytes::from_array(buffer.code)),
    content="440f28f00f57c066410f5ac6",
  )
}

///|
test "x64 vector and-not keeps complement operand order with overlapping outputs" {
  let first = @vcode.PhysicalReg::new(0, FpVector)
  let second = @vcode.PhysicalReg::new(1, FpVector)
  for destination in 0..<3 {
    let buffer = CodeBuffer::new()
    emit_vector_bitwise(
      buffer,
      AndNot,
      first,
      second,
      second,
      @vcode.PhysicalReg::new(destination, FpVector),
    )
    // movaps xmm14, xmm1; pandn xmm14, xmm0; movaps destination, xmm14.
    inspect(
      buffer.code ==
      [
        0x44,
        0x0f,
        0x28,
        0xf1,
        0x66,
        0x44,
        0x0f,
        0xdf,
        0xf0,
        0x41,
        0x0f,
        0x28,
        (0xc6 + 8 * destination).to_byte(),
      ],
      content="true",
    )
  }
}

///|
test "x64_target internal leaf functions establish an unwindable frame record" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new_with_protocol(
    "leaf_frame",
    Internal,
    [Ptr64],
    [],
  )
  builder.set_terminator(
    builder.entry_block(),
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  verify_vcode(function)
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  assert_eq(frame.frame_size(), 8)
  let object = emit(function, allocation, frame)
  assert_true(
    object
    .unwind()
    .any(directive => {
      directive.operation is SetFramePointer(Int, 5, cfa_offset=16)
    }),
  )
}

///|
test "x64 scalar memory uses a signed displacement without address synthesis" {
  let buffer = CodeBuffer::new()
  let base = @vcode.PhysicalReg::new(0, Int)
  let (address, offset) = scalar_memory_address(
    buffer,
    base,
    W64,
    (-240L).reinterpret_as_uint64(),
  )
  assert_true(address == base)
  assert_eq(offset, -240)
  assert_true(buffer.code.is_empty())
}
