///|
test "AArch64 pipeline emits an allocated scalar function" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_add",
    Internal,
    [I64, I64],
    [I64],
  )
  let sum = builder.emit(IntBinary(Add), builder.parameters(), [I64])[0]
  builder.return_([sum])
  let function = lower(builder.finish())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe2,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0x41,
      #|    0x00,
      #|    0x00,
      #|    0x8b,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline patches conditional control flow" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_branch",
    Internal,
    [I32],
    [I32],
  )
  let condition = builder.parameters()[0]
  let when_true = builder.create_block([])
  let when_false = builder.create_block([])
  builder.branch(condition, when_true, [], when_false, [])
  builder.switch_to_block(when_true)
  let one = builder.emit(I32Const(1U), [], [I32])[0]
  builder.return_([one])
  builder.switch_to_block(when_false)
  let zero = builder.emit(I32Const(0U), [], [I32])[0]
  builder.return_([zero])
  let function = lower(builder.finish())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe1,
      #|    0x03,
      #|    0x00,
      #|    0x2a,
      #|    0x41,
      #|    0x00,
      #|    0x00,
      #|    0x35,
      #|    0x03,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0x20,
      #|    0x00,
      #|    0x80,
      #|    0x52,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|    0x00,
      #|    0x00,
      #|    0xa0,
      #|    0x52,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}
