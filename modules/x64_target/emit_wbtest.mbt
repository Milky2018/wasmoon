///|
test "x64 pairwise i16 add uses horizontal lane semantics" {
  let buffer = CodeBuffer::new()
  buffer.x86_emit_phaddw_xmm_xmm(2, 1)
  debug_inspect(
    buffer.code,
    content=(
      #|[0x66, 0x0f, 0x38, 0x01, 0xd1]
    ),
  )
}

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
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0x48,
      #|  0x81,
      #|  0xec,
      #|  0x00,
      #|  0x10,
      #|  0x00,
      #|  0x00,
      #|  0x4c,
      #|  0x8b,
      #|  0x94,
      #|  0x24,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x48,
      #|  0x81,
      #|  0xec,
      #|  0x00,
      #|  0x10,
      #|  0x00,
      #|  0x00,
      #|  0x4c,
      #|  0x8b,
      #|  0x94,
      #|  0x24,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|]
    ),
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
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0x49,
      #|  0xba,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x80,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x80,
      #|  0x66,
      #|  0x4d,
      #|  0x0f,
      #|  0x6e,
      #|  0xf2,
      #|  0x49,
      #|  0xba,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x80,
      #|  0x00,
      #|  0x00,
      #|  0x00,
      #|  0x80,
      #|  0x66,
      #|  0x4d,
      #|  0x0f,
      #|  0x3a,
      #|  0x22,
      #|  0xf2,
      #|  0x01,
      #|  0x44,
      #|  0x0f,
      #|  0x28,
      #|  0xf8,
      #|  0x66,
      #|  0x41,
      #|  0x0f,
      #|  0xef,
      #|  0xce,
      #|  0x66,
      #|  0x45,
      #|  0x0f,
      #|  0xef,
      #|  0xfe,
      #|  0x66,
      #|  0x41,
      #|  0x0f,
      #|  0x66,
      #|  0xcf,
      #|]
    ),
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
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0x44,
      #|  0x0f,
      #|  0x28,
      #|  0xf0,
      #|  0x66,
      #|  0x4d,
      #|  0x0f,
      #|  0x3a,
      #|  0x16,
      #|  0xf2,
      #|  0x00,
      #|  0x66,
      #|  0x49,
      #|  0x0f,
      #|  0x3a,
      #|  0x16,
      #|  0xcb,
      #|  0x00,
      #|  0x4d,
      #|  0x39,
      #|  0xda,
      #|  0x41,
      #|  0x0f,
      #|  0x9f,
      #|  0xc2,
      #|  0x45,
      #|  0x0f,
      #|  0xb6,
      #|  0xd2,
      #|  0x49,
      #|  0xf7,
      #|  0xda,
      #|  0x66,
      #|  0x49,
      #|  0x0f,
      #|  0x6e,
      #|  0xc2,
      #|  0x66,
      #|  0x4d,
      #|  0x0f,
      #|  0x3a,
      #|  0x16,
      #|  0xf2,
      #|  0x01,
      #|  0x66,
      #|  0x49,
      #|  0x0f,
      #|  0x3a,
      #|  0x16,
      #|  0xcb,
      #|  0x01,
      #|  0x4d,
      #|  0x39,
      #|  0xda,
      #|  0x41,
      #|  0x0f,
      #|  0x9f,
      #|  0xc2,
      #|  0x45,
      #|  0x0f,
      #|  0xb6,
      #|  0xd2,
      #|  0x49,
      #|  0xf7,
      #|  0xda,
      #|  0x66,
      #|  0x49,
      #|  0x0f,
      #|  0x3a,
      #|  0x22,
      #|  0xc2,
      #|  0x01,
      #|]
    ),
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
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0x44,
      #|  0x0f,
      #|  0x28,
      #|  0xf8,
      #|  0x49,
      #|  0xba,
      #|  0x01,
      #|  0x01,
      #|  0x01,
      #|  0x01,
      #|  0x01,
      #|  0x01,
      #|  0x01,
      #|  0x01,
      #|  0x66,
      #|  0x4d,
      #|  0x0f,
      #|  0x6e,
      #|  0xf2,
      #|  0x49,
      #|  0xba,
      #|  0x01,
      #|  0x01,
      #|  0x01,
      #|  0x01,
      #|  0x01,
      #|  0x01,
      #|  0x01,
      #|  0x01,
      #|  0x66,
      #|  0x4d,
      #|  0x0f,
      #|  0x3a,
      #|  0x22,
      #|  0xf2,
      #|  0x01,
      #|  0x41,
      #|  0x0f,
      #|  0x28,
      #|  0xc6,
      #|  0x66,
      #|  0x41,
      #|  0x0f,
      #|  0x38,
      #|  0x04,
      #|  0xc7,
      #|]
    ),
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
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0x44,
      #|  0x0f,
      #|  0x28,
      #|  0xf0,
      #|  0x0f,
      #|  0x57,
      #|  0xc0,
      #|  0x66,
      #|  0x41,
      #|  0x0f,
      #|  0x5a,
      #|  0xc6,
      #|]
    ),
  )
}
