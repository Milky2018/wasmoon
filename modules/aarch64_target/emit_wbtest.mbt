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

///|
test "AAPCS64 platform call layout preserves mixed overflow order" {
  let layout = platform_call_layout([
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    F64,
    F64,
    F64,
    F64,
    F64,
    F64,
    F64,
    F64,
    I64,
    V128,
    I32,
    F32,
  ])
  debug_inspect(
    layout,
    content=(
      #|{
      #|  arguments: [
      #|    CallRegister(p0:int),
      #|    CallRegister(p1:int),
      #|    CallRegister(p2:int),
      #|    CallRegister(p3:int),
      #|    CallRegister(p4:int),
      #|    CallRegister(p5:int),
      #|    CallRegister(p6:int),
      #|    CallRegister(p7:int),
      #|    CallRegister(p0:fpvec),
      #|    CallRegister(p1:fpvec),
      #|    CallRegister(p2:fpvec),
      #|    CallRegister(p3:fpvec),
      #|    CallRegister(p4:fpvec),
      #|    CallRegister(p5:fpvec),
      #|    CallRegister(p6:fpvec),
      #|    CallRegister(p7:fpvec),
      #|    CallStack(0),
      #|    CallStack(16),
      #|    CallStack(32),
      #|    CallStack(40),
      #|  ],
      #|  stack_size: 48,
      #|}
    ),
  )
}

///|
test "validated internal ABI derives context, overflow, and result locations" {
  let abi = InternalAbi::new(
    0,
    [1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let layout = abi.call_layout(
    @semantic.Signature::new(
      [
        Ptr64,
        I64,
        I64,
        I64,
        I64,
        I64,
        I64,
        I64,
        I64,
        F64,
        F64,
        F64,
        F64,
        F64,
        F64,
        F64,
        F64,
        V128,
      ],
      [I64, F64],
    ),
  )
  let results = abi.result_registers([I64, F64])
  debug_inspect(
    (layout, results),
    content=(
      #|(
      #|  {
      #|    arguments: [
      #|      CallRegister(p0:int),
      #|      CallRegister(p1:int),
      #|      CallRegister(p2:int),
      #|      CallRegister(p3:int),
      #|      CallRegister(p4:int),
      #|      CallRegister(p5:int),
      #|      CallRegister(p6:int),
      #|      CallRegister(p7:int),
      #|      CallStack(0),
      #|      CallRegister(p0:fpvec),
      #|      CallRegister(p1:fpvec),
      #|      CallRegister(p2:fpvec),
      #|      CallRegister(p3:fpvec),
      #|      CallRegister(p4:fpvec),
      #|      CallRegister(p5:fpvec),
      #|      CallRegister(p6:fpvec),
      #|      CallRegister(p7:fpvec),
      #|      CallStack(16),
      #|    ],
      #|    stack_size: 32,
      #|  },
      #|  [p0:int, p0:fpvec],
      #|)
    ),
  )
}
