///|
test "AArch64 stack access encodings preserve width and scaled offset" {
  let buffer = CodeBuffer::new()
  emit_stack_access(buffer, false, I64, @vcode.PhysicalReg::new(19, Int), 16)
  emit_stack_access(buffer, true, I64, @vcode.PhysicalReg::new(20, Int), 16)
  emit_stack_access(buffer, false, I32, @vcode.PhysicalReg::new(0, Int), 12)
  emit_stack_access(buffer, true, I32, @vcode.PhysicalReg::new(1, Int), 12)
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0xf3,
      #|  0x0b,
      #|  0x00,
      #|  0xf9,
      #|  0xf4,
      #|  0x0b,
      #|  0x40,
      #|  0xf9,
      #|  0xe0,
      #|  0x0f,
      #|  0x00,
      #|  0xb9,
      #|  0xe1,
      #|  0x0f,
      #|  0x40,
      #|  0xb9,
      #|]
    ),
  )
}

///|
test "AArch64 integer unary encodings place source in the correct field" {
  let source = @vcode.PhysicalReg::new(3, Int)
  let destination = @vcode.PhysicalReg::new(5, Int)
  let buffer = CodeBuffer::new()
  buffer.emit_word(encode_int_unary(W32, Mvn, destination, source))
  buffer.emit_word(encode_int_unary(W64, Mvn, destination, source))
  buffer.emit_word(encode_int_unary(W32, Clz, destination, source))
  buffer.emit_word(encode_int_unary(W64, Clz, destination, source))
  debug_inspect(
    buffer.code,
    content=(
      #|[
      #|  0xe5,
      #|  0x03,
      #|  0x23,
      #|  0x2a,
      #|  0xe5,
      #|  0x03,
      #|  0x23,
      #|  0xaa,
      #|  0x65,
      #|  0x10,
      #|  0xc0,
      #|  0x5a,
      #|  0x65,
      #|  0x10,
      #|  0xc0,
      #|  0xda,
      #|]
    ),
  )
}
