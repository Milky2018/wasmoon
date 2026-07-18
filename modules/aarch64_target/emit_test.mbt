///|
test "AArch64 pipeline emits an allocated scalar function" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_add",
    Platform,
    [I64, I64],
    [I64],
  )
  let sum = builder.emit(IntBinary(Add), builder.parameters(), [I64])[0]
  builder.return_([sum])
  let function = lower(builder.finish(), test_lowering_context())
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
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits multi-result overflow arithmetic" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_overflow_multiply",
    Platform,
    [I64, I64],
    [I64],
  )
  let results = builder.emit(
    IntWithOverflow(Mul(Signed)),
    builder.parameters(),
    [I64, I32],
  )
  builder.return_([results[0]])
  let function = lower(builder.finish(), test_lowering_context())
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
      #|    0x7c,
      #|    0x00,
      #|    0x9b,
      #|    0x50,
      #|    0x7c,
      #|    0x40,
      #|    0x9b,
      #|    0x1f,
      #|    0xfe,
      #|    0x81,
      #|    0xeb,
      #|    0xe3,
      #|    0x07,
      #|    0x9f,
      #|    0x9a,
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
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits allocated vector foundation operations" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_foundation",
    Platform,
    [I32, V128, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let constant = builder.emit(
      V128Const(0x0706050403020100UL, 0x0F0E0D0C0B0A0908UL),
      [],
      [V128],
    )[0]
  let selected_bits = builder.emit(
      Vector(Bitwise(BitSelect)),
      [parameters[1], parameters[2], constant],
      [V128],
    )[0]
  let selected = builder.emit(
      Select,
      [parameters[0], selected_bits, parameters[3]],
      [V128],
    )[0]
  builder.return_([selected])
  let function = lower(builder.finish(), test_lowering_context())
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
      #|    0x03,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0x02,
      #|    0xe4,
      #|    0x00,
      #|    0x6f,
      #|    0x10,
      #|    0x20,
      #|    0x80,
      #|    0xd2,
      #|    0x50,
      #|    0x60,
      #|    0xa0,
      #|    0xf2,
      #|    0x90,
      #|    0xa0,
      #|    0xc0,
      #|    0xf2,
      #|    0xd0,
      #|    0xe0,
      #|    0xe0,
      #|    0xf2,
      #|    0x02,
      #|    0x1e,
      #|    0x08,
      #|    0x4e,
      #|    0x10,
      #|    0x21,
      #|    0x81,
      #|    0xd2,
      #|    0x50,
      #|    0x61,
      #|    0xa1,
      #|    0xf2,
      #|    0x90,
      #|    0xa1,
      #|    0xc1,
      #|    0xf2,
      #|    0xd0,
      #|    0xe1,
      #|    0xe1,
      #|    0xf2,
      #|    0x02,
      #|    0x1e,
      #|    0x18,
      #|    0x4e,
      #|    0x64,
      #|    0x1c,
      #|    0x20,
      #|    0x6e,
      #|    0x84,
      #|    0x1c,
      #|    0x22,
      #|    0x4e,
      #|    0x84,
      #|    0x1c,
      #|    0x20,
      #|    0x6e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x00,
      #|    0x00,
      #|    0x34,
      #|    0x80,
      #|    0x1c,
      #|    0xa4,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline preserves vector lane replacement ties" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_lane_movement",
    Platform,
    [V128],
    [V128],
  )
  let vector = builder.parameters()[0]
  let scalar = builder.emit(
      Vector(ExtractLane(I8x16, 15, Some(Signed))),
      [vector],
      [I32],
    )[0]
  let replaced = builder.emit(Vector(ReplaceLane(I16x8, 7)), [vector, scalar], [
      V128,
    ])[0]
  builder.return_([replaced])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  inspect(
    allocation.summary(),
    content=(
      #|allocation emitted_vector_lane_movement
      #|  v0:v128 -> p0:fpvec
      #|  v1:v128 -> p1:fpvec
      #|  v2:i32 -> p0:int
      #|  v3:v128 -> p1:fpvec
      #|  i0 operand0 -> p0:fpvec
      #|  i0 operand1 -> p1:fpvec
      #|  i1 operand0 -> p1:fpvec
      #|  i1 operand1 -> p0:int
      #|  i2 operand0 -> p1:fpvec
      #|  i2 operand1 -> p0:int
      #|  i2 operand2 -> p1:fpvec
      #|  i3 operand0 -> p1:fpvec
      #|
    ),
  )
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x2c,
      #|    0x1f,
      #|    0x0e,
      #|    0x01,
      #|    0x1c,
      #|    0x1e,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits vector permutation operations" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_permute",
    Platform,
    [V128, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let mask : FixedArray[Int] = [
    0, 17, 2, 19, 4, 21, 6, 23, 8, 25, 10, 27, 12, 29, 14, 31,
  ]
  let shuffled = builder.emit(
      Vector(Shuffle(mask)),
      [parameters[0], parameters[1]],
      [V128],
    )[0]
  let swizzled = builder.emit(Vector(Swizzle), [shuffled, parameters[2]], [V128])[0]
  builder.return_([swizzled])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x03,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0x10,
      #|    0xe4,
      #|    0x00,
      #|    0x6f,
      #|    0x10,
      #|    0x00,
      #|    0x90,
      #|    0xd2,
      #|    0x50,
      #|    0x00,
      #|    0xb0,
      #|    0xf2,
      #|    0x90,
      #|    0x00,
      #|    0xd0,
      #|    0xf2,
      #|    0xd0,
      #|    0x00,
      #|    0xf0,
      #|    0xf2,
      #|    0x10,
      #|    0x1e,
      #|    0x08,
      #|    0x4e,
      #|    0x10,
      #|    0x01,
      #|    0x90,
      #|    0xd2,
      #|    0x50,
      #|    0x01,
      #|    0xb0,
      #|    0xf2,
      #|    0x90,
      #|    0x01,
      #|    0xd0,
      #|    0xf2,
      #|    0xd0,
      #|    0x01,
      #|    0xf0,
      #|    0xf2,
      #|    0x10,
      #|    0x1e,
      #|    0x18,
      #|    0x4e,
      #|    0x70,
      #|    0x00,
      #|    0x10,
      #|    0x4e,
      #|    0x11,
      #|    0xe4,
      #|    0x00,
      #|    0x6f,
      #|    0x10,
      #|    0x30,
      #|    0x80,
      #|    0xd2,
      #|    0x10,
      #|    0x70,
      #|    0xa0,
      #|    0xf2,
      #|    0x10,
      #|    0xb0,
      #|    0xc0,
      #|    0xf2,
      #|    0x10,
      #|    0xf0,
      #|    0xe0,
      #|    0xf2,
      #|    0x11,
      #|    0x1e,
      #|    0x08,
      #|    0x4e,
      #|    0x10,
      #|    0x30,
      #|    0x81,
      #|    0xd2,
      #|    0x10,
      #|    0x70,
      #|    0xa1,
      #|    0xf2,
      #|    0x10,
      #|    0xb0,
      #|    0xc1,
      #|    0xf2,
      #|    0x10,
      #|    0xf0,
      #|    0xe1,
      #|    0xf2,
      #|    0x11,
      #|    0x1e,
      #|    0x18,
      #|    0x4e,
      #|    0x11,
      #|    0x00,
      #|    0x11,
      #|    0x4e,
      #|    0x02,
      #|    0x1e,
      #|    0xb1,
      #|    0x4e,
      #|    0x40,
      #|    0x00,
      #|    0x01,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits basic vector integer arithmetic" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_integer_arithmetic",
    Platform,
    [V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let absolute = builder.emit(
      Vector(IntUnary(I8x16, Absolute)),
      [parameters[0]],
      [V128],
    )[0]
  let negated = builder.emit(Vector(IntUnary(I64x2, Negate)), [absolute], [V128])[0]
  let added = builder.emit(
      Vector(IntBinary(I16x8, Add)),
      [negated, parameters[1]],
      [V128],
    )[0]
  let subtracted = builder.emit(
      Vector(IntBinary(I32x4, Sub)),
      [added, parameters[1]],
      [V128],
    )[0]
  let multiplied_bytes = builder.emit(
      Vector(IntBinary(I8x16, Mul)),
      [subtracted, parameters[1]],
      [V128],
    )[0]
  let multiplied_words = builder.emit(
      Vector(IntBinary(I64x2, Mul)),
      [multiplied_bytes, parameters[1]],
      [V128],
    )[0]
  builder.return_([multiplied_words])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x02,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0xb8,
      #|    0x20,
      #|    0x4e,
      #|    0x22,
      #|    0xb8,
      #|    0xe0,
      #|    0x6e,
      #|    0x41,
      #|    0x84,
      #|    0x60,
      #|    0x4e,
      #|    0x22,
      #|    0x84,
      #|    0xa0,
      #|    0x6e,
      #|    0x41,
      #|    0x9c,
      #|    0x20,
      #|    0x4e,
      #|    0x30,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x11,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x10,
      #|    0x3e,
      #|    0x08,
      #|    0x4e,
      #|    0x31,
      #|    0x3e,
      #|    0x08,
      #|    0x4e,
      #|    0x10,
      #|    0x7e,
      #|    0x11,
      #|    0x9b,
      #|    0x02,
      #|    0x1e,
      #|    0x08,
      #|    0x4e,
      #|    0x10,
      #|    0x3e,
      #|    0x18,
      #|    0x4e,
      #|    0x31,
      #|    0x3e,
      #|    0x18,
      #|    0x4e,
      #|    0x10,
      #|    0x7e,
      #|    0x11,
      #|    0x9b,
      #|    0x02,
      #|    0x1e,
      #|    0x18,
      #|    0x4e,
      #|    0x40,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits vector integer shifts" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_integer_shifts",
    Platform,
    [V128, I32],
    [V128],
  )
  let parameters = builder.parameters()
  let shifted_left = builder.emit(Vector(IntShift(I8x16, Left)), parameters, [
      V128,
    ])[0]
  let shifted_signed = builder.emit(
      Vector(IntShift(I32x4, Right(Signed))),
      [shifted_left, parameters[1]],
      [V128],
    )[0]
  let shifted_unsigned = builder.emit(
      Vector(IntShift(I64x2, Right(Unsigned))),
      [shifted_signed, parameters[1]],
      [V128],
    )[0]
  builder.return_([shifted_unsigned])
  let function = lower(builder.finish(), test_lowering_context())
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
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x30,
      #|    0x08,
      #|    0x40,
      #|    0xd3,
      #|    0x10,
      #|    0x0e,
      #|    0x01,
      #|    0x4e,
      #|    0x20,
      #|    0x44,
      #|    0x30,
      #|    0x4e,
      #|    0x30,
      #|    0x10,
      #|    0x40,
      #|    0xd3,
      #|    0xf0,
      #|    0x03,
      #|    0x10,
      #|    0xcb,
      #|    0x10,
      #|    0x0e,
      #|    0x04,
      #|    0x4e,
      #|    0x01,
      #|    0x44,
      #|    0xb0,
      #|    0x4e,
      #|    0x30,
      #|    0x14,
      #|    0x40,
      #|    0xd3,
      #|    0xf0,
      #|    0x03,
      #|    0x10,
      #|    0xcb,
      #|    0x10,
      #|    0x0e,
      #|    0x08,
      #|    0x4e,
      #|    0x20,
      #|    0x44,
      #|    0xf0,
      #|    0x6e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits vector integer comparisons" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_integer_comparisons",
    Platform,
    [V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let not_equal = builder.emit(
      Vector(IntCompare(I8x16, NotEqual)),
      parameters,
      [V128],
    )[0]
  let less_unsigned = builder.emit(
      Vector(IntCompare(I16x8, LessThan(Unsigned))),
      [not_equal, parameters[1]],
      [V128],
    )[0]
  let greater_or_equal = builder.emit(
      Vector(IntCompare(I64x2, GreaterOrEqual(Signed))),
      [less_unsigned, parameters[1]],
      [V128],
    )[0]
  builder.return_([greater_or_equal])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x02,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x8c,
      #|    0x20,
      #|    0x6e,
      #|    0x21,
      #|    0x58,
      #|    0x20,
      #|    0x6e,
      #|    0x02,
      #|    0x34,
      #|    0x61,
      #|    0x6e,
      #|    0x41,
      #|    0x3c,
      #|    0xe0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits saturating vector integer arithmetic" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_saturating_arithmetic",
    Platform,
    [V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let signed_add = builder.emit(
      Vector(IntBinary(I8x16, SaturatingAdd(Signed))),
      parameters,
      [V128],
    )[0]
  let unsigned_add = builder.emit(
      Vector(IntBinary(I16x8, SaturatingAdd(Unsigned))),
      [signed_add, parameters[1]],
      [V128],
    )[0]
  let signed_sub = builder.emit(
      Vector(IntBinary(I32x4, SaturatingSub(Signed))),
      [unsigned_add, parameters[1]],
      [V128],
    )[0]
  let unsigned_sub = builder.emit(
      Vector(IntBinary(I64x2, SaturatingSub(Unsigned))),
      [signed_sub, parameters[1]],
      [V128],
    )[0]
  builder.return_([unsigned_sub])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x02,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x0c,
      #|    0x20,
      #|    0x4e,
      #|    0x22,
      #|    0x0c,
      #|    0x60,
      #|    0x6e,
      #|    0x41,
      #|    0x2c,
      #|    0xa0,
      #|    0x4e,
      #|    0x22,
      #|    0x2c,
      #|    0xe0,
      #|    0x6e,
      #|    0x40,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits vector integer min and max" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_integer_min_max",
    Platform,
    [V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let signed_min = builder.emit(
      Vector(IntBinary(I8x16, Min(Signed))),
      parameters,
      [V128],
    )[0]
  let unsigned_max = builder.emit(
      Vector(IntBinary(I32x4, Max(Unsigned))),
      [signed_min, parameters[1]],
      [V128],
    )[0]
  let signed_min_i64 = builder.emit(
      Vector(IntBinary(I64x2, Min(Signed))),
      [unsigned_max, parameters[1]],
      [V128],
    )[0]
  let unsigned_max_i64 = builder.emit(
      Vector(IntBinary(I64x2, Max(Unsigned))),
      [signed_min_i64, parameters[1]],
      [V128],
    )[0]
  builder.return_([unsigned_max_i64])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x02,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x6c,
      #|    0x20,
      #|    0x4e,
      #|    0x22,
      #|    0x64,
      #|    0xa0,
      #|    0x6e,
      #|    0x50,
      #|    0x34,
      #|    0xe0,
      #|    0x4e,
      #|    0x01,
      #|    0x1c,
      #|    0x22,
      #|    0x6e,
      #|    0x21,
      #|    0x1c,
      #|    0x30,
      #|    0x4e,
      #|    0x21,
      #|    0x1c,
      #|    0x22,
      #|    0x6e,
      #|    0x30,
      #|    0x34,
      #|    0xe0,
      #|    0x6e,
      #|    0x22,
      #|    0x1c,
      #|    0x20,
      #|    0x6e,
      #|    0x42,
      #|    0x1c,
      #|    0x30,
      #|    0x4e,
      #|    0x42,
      #|    0x1c,
      #|    0x20,
      #|    0x6e,
      #|    0x40,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits vector unsigned averages" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_unsigned_average",
    Platform,
    [V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let bytes = builder.emit(
      Vector(IntBinary(I8x16, AverageUnsigned)),
      parameters,
      [V128],
    )[0]
  let halfwords = builder.emit(
      Vector(IntBinary(I16x8, AverageUnsigned)),
      [bytes, parameters[1]],
      [V128],
    )[0]
  builder.return_([halfwords])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x02,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x14,
      #|    0x20,
      #|    0x6e,
      #|    0x22,
      #|    0x14,
      #|    0x60,
      #|    0x6e,
      #|    0x40,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits vector byte population count" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_population_count",
    Platform,
    [V128],
    [V128],
  )
  let result = builder.emit(
      Vector(IntUnary(I8x16, PopulationCount)),
      builder.parameters(),
      [V128],
    )[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x58,
      #|    0x20,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits widening vector integer arithmetic" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_widening_arithmetic",
    Platform,
    [V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let pairwise = builder.emit(
      Vector(IntUnary(I64x2, ExtendAddPairwise(Unsigned))),
      [parameters[0]],
      [V128],
    )[0]
  let multiplied = builder.emit(
      Vector(IntBinary(I64x2, ExtendMultiply(High, Signed))),
      [pairwise, parameters[1]],
      [V128],
    )[0]
  let dotted = builder.emit(
      Vector(IntBinary(I32x4, Dot16To32Signed)),
      [multiplied, parameters[1]],
      [V128],
    )[0]
  let q15 = builder.emit(
      Vector(IntBinary(I16x8, Q15MultiplyRoundedSaturating)),
      [dotted, parameters[1]],
      [V128],
    )[0]
  builder.return_([q15])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x02,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x28,
      #|    0xa0,
      #|    0x6e,
      #|    0x22,
      #|    0xc0,
      #|    0xa0,
      #|    0x4e,
      #|    0x50,
      #|    0xc0,
      #|    0x60,
      #|    0x0e,
      #|    0x51,
      #|    0xc0,
      #|    0x60,
      #|    0x4e,
      #|    0x01,
      #|    0xbe,
      #|    0xb1,
      #|    0x4e,
      #|    0x22,
      #|    0xb4,
      #|    0x60,
      #|    0x6e,
      #|    0x40,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits vector integer extension" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_integer_extension",
    Platform,
    [V128],
    [V128],
  )
  let result = builder.emit(
      Vector(Convert(ExtendHigh(I64x2, Unsigned))),
      builder.parameters(),
      [V128],
    )[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0xa4,
      #|    0x20,
      #|    0x6f,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits saturating vector narrowing" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_narrowing",
    Platform,
    [V128, V128],
    [V128],
  )
  let result = builder.emit(
      Vector(Convert(Narrow(I8x16, Unsigned))),
      builder.parameters(),
      [V128],
    )[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x02,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x28,
      #|    0x21,
      #|    0x2e,
      #|    0x01,
      #|    0x28,
      #|    0x21,
      #|    0x6e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits vector truth predicates" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_truth_predicates",
    Platform,
    [V128],
    [I32],
  )
  let source = builder.parameters()[0]
  let any = builder.emit(Vector(Predicate(AnyTrue)), [source], [I32])[0]
  let all = builder.emit(Vector(Predicate(AllTrue(I64x2))), [source], [I32])[0]
  let result = builder.emit(IntBinary(Add), [any, all], [I32])[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x30,
      #|    0xa8,
      #|    0x30,
      #|    0x6e,
      #|    0x10,
      #|    0x02,
      #|    0x66,
      #|    0x9e,
      #|    0x1f,
      #|    0x02,
      #|    0x00,
      #|    0xf1,
      #|    0xe0,
      #|    0x07,
      #|    0x9f,
      #|    0x9a,
      #|    0x30,
      #|    0x3c,
      #|    0x08,
      #|    0x4e,
      #|    0x31,
      #|    0x3c,
      #|    0x18,
      #|    0x4e,
      #|    0x1f,
      #|    0x02,
      #|    0x00,
      #|    0xf1,
      #|    0x24,
      #|    0x1a,
      #|    0x40,
      #|    0xfa,
      #|    0xe1,
      #|    0x07,
      #|    0x9f,
      #|    0x9a,
      #|    0x02,
      #|    0x00,
      #|    0x01,
      #|    0x0b,
      #|    0xe0,
      #|    0x03,
      #|    0x02,
      #|    0x2a,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits vector integer bitmasks" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_integer_bitmasks",
    Platform,
    [V128],
    [I32],
  )
  let source = builder.parameters()[0]
  let bytes = builder.emit(Vector(Predicate(BitMask(I8x16))), [source], [I32])[0]
  let doubles = builder.emit(Vector(Predicate(BitMask(I64x2))), [source], [I32])[0]
  let result = builder.emit(IntBinary(Add), [bytes, doubles], [I32])[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x31,
      #|    0x04,
      #|    0x09,
      #|    0x6f,
      #|    0x30,
      #|    0x40,
      #|    0x80,
      #|    0xd2,
      #|    0x90,
      #|    0x00,
      #|    0xa1,
      #|    0xf2,
      #|    0x10,
      #|    0x02,
      #|    0xc4,
      #|    0xf2,
      #|    0x10,
      #|    0x08,
      #|    0xf0,
      #|    0xf2,
      #|    0x10,
      #|    0x02,
      #|    0x67,
      #|    0x9e,
      #|    0x10,
      #|    0x06,
      #|    0x08,
      #|    0x4e,
      #|    0x31,
      #|    0x9e,
      #|    0x30,
      #|    0x4e,
      #|    0x31,
      #|    0x2a,
      #|    0x20,
      #|    0x6e,
      #|    0x31,
      #|    0x2a,
      #|    0x60,
      #|    0x6e,
      #|    0x31,
      #|    0x2a,
      #|    0xa0,
      #|    0x6e,
      #|    0x30,
      #|    0x3e,
      #|    0x08,
      #|    0x4e,
      #|    0x31,
      #|    0x3e,
      #|    0x18,
      #|    0x4e,
      #|    0x00,
      #|    0x22,
      #|    0x11,
      #|    0x2a,
      #|    0x21,
      #|    0x3c,
      #|    0x08,
      #|    0x4e,
      #|    0x21,
      #|    0xfc,
      #|    0x7f,
      #|    0xd3,
      #|    0x30,
      #|    0x3c,
      #|    0x18,
      #|    0x4e,
      #|    0x10,
      #|    0xfe,
      #|    0x7f,
      #|    0xd3,
      #|    0x21,
      #|    0x04,
      #|    0x10,
      #|    0x2a,
      #|    0x02,
      #|    0x00,
      #|    0x01,
      #|    0x0b,
      #|    0xe0,
      #|    0x03,
      #|    0x02,
      #|    0x2a,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits representative vector float operations" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_float_operations",
    Platform,
    [V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let rounded = builder.emit(
      Vector(FloatUnary(F32x4, Nearest)),
      [parameters[0]],
      [V128],
    )[0]
  let pseudo_min = builder.emit(
      Vector(FloatBinary(F64x2, PseudoMin)),
      [rounded, parameters[1]],
      [V128],
    )[0]
  let not_equal = builder.emit(
      Vector(FloatCompare(F32x4, NotEqual)),
      [pseudo_min, parameters[0]],
      [V128],
    )[0]
  builder.return_([not_equal])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x02,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x88,
      #|    0x21,
      #|    0x4e,
      #|    0x30,
      #|    0xe4,
      #|    0xe0,
      #|    0x6e,
      #|    0x10,
      #|    0x1c,
      #|    0x61,
      #|    0x6e,
      #|    0x03,
      #|    0x1e,
      #|    0xb0,
      #|    0x4e,
      #|    0x60,
      #|    0xe4,
      #|    0x22,
      #|    0x4e,
      #|    0x00,
      #|    0x58,
      #|    0x20,
      #|    0x6e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits vector fused operations without tied operands" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_float_fused",
    Platform,
    [V128, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let result = builder.emit(
      Vector(FloatTernary(F64x2, FusedNegatedMultiplySubtract)),
      parameters,
      [V128],
    )[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x03,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0x70,
      #|    0x1c,
      #|    0xa3,
      #|    0x4e,
      #|    0x11,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x22,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x42,
      #|    0xf8,
      #|    0xe0,
      #|    0x6e,
      #|    0x02,
      #|    0xce,
      #|    0xf1,
      #|    0x4e,
      #|    0x40,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits representative vector numeric conversions" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_conversions",
    Platform,
    [V128],
    [V128],
  )
  let source = builder.parameters()[0]
  let integer = builder.emit(
      Vector(Convert(FloatToInt(F64x2, I32x4, Unsigned, Saturating))),
      [source],
      [V128],
    )[0]
  let float = builder.emit(
      Vector(Convert(IntToFloat(I32x4, F64x2, Signed))),
      [integer],
      [V128],
    )[0]
  let result = builder.emit(Vector(Convert(DemoteZeroF64x2)), [float], [V128])[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x30,
      #|    0xb8,
      #|    0xe1,
      #|    0x6e,
      #|    0x00,
      #|    0x4a,
      #|    0xa1,
      #|    0x2e,
      #|    0x10,
      #|    0xa4,
      #|    0x20,
      #|    0x0f,
      #|    0x01,
      #|    0xda,
      #|    0x61,
      #|    0x4e,
      #|    0x20,
      #|    0x68,
      #|    0x61,
      #|    0x0e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits relaxed dot8-to16 across allocation aliases" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_relaxed_dot8_to16",
    Platform,
    [V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let result = builder.emit(
      Vector(Relaxed(Dot8To16Signed)),
      [parameters[0], parameters[1]],
      [V128],
    )[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x02,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x50,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0x11,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x01,
      #|    0xc2,
      #|    0x31,
      #|    0x0e,
      #|    0x10,
      #|    0xc2,
      #|    0x31,
      #|    0x4e,
      #|    0x21,
      #|    0xbc,
      #|    0x70,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits relaxed dot8-to32-add with allocated temporaries" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_relaxed_dot8_to32_add",
    Platform,
    [V128, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let result = builder.emit(
      Vector(Relaxed(Dot8To32AddSigned)),
      [parameters[0], parameters[1], parameters[2]],
      [V128],
    )[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0x03,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0x62,
      #|    0xc0,
      #|    0x20,
      #|    0x0e,
      #|    0x64,
      #|    0xc0,
      #|    0x20,
      #|    0x4e,
      #|    0x40,
      #|    0xbc,
      #|    0x64,
      #|    0x4e,
      #|    0x02,
      #|    0x28,
      #|    0x60,
      #|    0x4e,
      #|    0x40,
      #|    0x84,
      #|    0xa1,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits vector memory at the faulting instruction" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_vector_memory",
    Platform,
    [Ptr64, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let loaded = builder.emit(
      Load(
        @semantic.LoadSpec::new(
          W128,
          None,
          V128,
          16UL,
          Little,
          Some(MemoryOutOfBounds),
        ),
      ),
      [parameters[0]],
      [V128],
    )[0]
  builder.emit(
    Store(
      @semantic.StoreSpec::new(
        W128,
        V128,
        32UL,
        Little,
        Some(MemoryOutOfBounds),
      ),
    ),
    [parameters[0], loaded],
    [],
  )
  |> ignore
  builder.emit(
    VectorLoad(
      @semantic.VectorLoadSpec::new(
        Splat(I16x8),
        4UL,
        Little,
        Some(MemoryOutOfBounds),
      ),
    ),
    [parameters[0]],
    [V128],
  )
  |> ignore
  builder.emit(
    VectorLoad(
      @semantic.VectorLoadSpec::new(
        Extend(I32x4, Signed),
        8UL,
        Little,
        Some(MemoryOutOfBounds),
      ),
    ),
    [parameters[0]],
    [V128],
  )
  |> ignore
  builder.emit(
    VectorLoad(
      @semantic.VectorLoadSpec::new(
        Zero(W64),
        24UL,
        Little,
        Some(MemoryOutOfBounds),
      ),
    ),
    [parameters[0]],
    [V128],
  )
  |> ignore
  let lane = builder.emit(
      VectorLoad(
        @semantic.VectorLoadSpec::new(
          Lane(I32x4, 2),
          7UL,
          Little,
          Some(MemoryOutOfBounds),
        ),
      ),
      [parameters[0], loaded],
      [V128],
    )[0]
  builder.emit(
    VectorStoreLane(
      @semantic.VectorStoreLaneSpec::new(
        I64x2,
        1,
        9UL,
        Little,
        Some(MemoryOutOfBounds),
      ),
    ),
    [parameters[0], lane],
    [],
  )
  |> ignore
  builder.return_([lane])
  let function = lower(builder.finish(), test_lowering_context())
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
      #|    0xaa,
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x04,
      #|    0xc0,
      #|    0x3d,
      #|    0x20,
      #|    0x08,
      #|    0x80,
      #|    0x3d,
      #|    0x90,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0x30,
      #|    0x00,
      #|    0x10,
      #|    0x8b,
      #|    0x01,
      #|    0xc6,
      #|    0x40,
      #|    0x4d,
      #|    0x21,
      #|    0x04,
      #|    0x40,
      #|    0xfd,
      #|    0x21,
      #|    0xa4,
      #|    0x10,
      #|    0x0f,
      #|    0x21,
      #|    0x0c,
      #|    0x40,
      #|    0xfd,
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0xf0,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0x30,
      #|    0x00,
      #|    0x10,
      #|    0x8b,
      #|    0x01,
      #|    0x82,
      #|    0x40,
      #|    0x4d,
      #|    0x30,
      #|    0x01,
      #|    0x80,
      #|    0xd2,
      #|    0x30,
      #|    0x00,
      #|    0x10,
      #|    0x8b,
      #|    0x01,
      #|    0x86,
      #|    0x00,
      #|    0x4d,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [
      #|    { offset: 8, reason: MemoryOutOfBounds, source: None },
      #|    { offset: 12, reason: MemoryOutOfBounds, source: None },
      #|    { offset: 24, reason: MemoryOutOfBounds, source: None },
      #|    { offset: 28, reason: MemoryOutOfBounds, source: None },
      #|    { offset: 36, reason: MemoryOutOfBounds, source: None },
      #|    { offset: 52, reason: MemoryOutOfBounds, source: None },
      #|    { offset: 64, reason: MemoryOutOfBounds, source: None },
      #|  ],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits sequentially consistent atomic loops" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_atomics",
    Platform,
    [Ptr64, I32],
    [I32],
  )
  let parameters = builder.parameters()
  builder.emit(
    AtomicLoad(
      @semantic.AtomicSpec::new(W32, I32, 0UL, Little, Some(MemoryOutOfBounds)),
    ),
    [parameters[0]],
    [I32],
  )
  |> ignore
  builder.emit(
    AtomicStore(
      @semantic.AtomicSpec::new(W16, I32, 2UL, Little, Some(MemoryOutOfBounds)),
    ),
    parameters,
    [],
  )
  |> ignore
  let old = builder.emit(
      AtomicRmw(
        @semantic.AtomicSpec::new(
          W32,
          I32,
          4UL,
          Little,
          Some(MemoryOutOfBounds),
        ),
        Add,
      ),
      parameters,
      [I32],
    )[0]
  let exchanged = builder.emit(
      AtomicCompareExchange(
        @semantic.AtomicSpec::new(W8, I32, 8UL, Little, Some(MemoryOutOfBounds)),
      ),
      [parameters[0], old, parameters[1]],
      [I32],
    )[0]
  builder.emit(AtomicFence, [], []) |> ignore
  builder.return_([exchanged])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  inspect(
    allocation.summary(),
    content=(
      #|allocation emitted_atomics
      #|  v0:ptr64 -> p0:int
      #|  v1:i32 -> p1:int
      #|  v2:ptr64 -> p2:int
      #|  v3:i32 -> p0:int
      #|  v4:i32 -> p1:int
      #|  v5:i64 -> p1:int
      #|  v6:ptr64 -> p3:int
      #|  v7:i64 -> p1:int
      #|  v8:ptr64 -> p3:int
      #|  v9:i32 -> p1:int
      #|  v10:i64 -> p3:int
      #|  v11:ptr64 -> p4:int
      #|  v12:i32 -> p2:int
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p2:int
      #|  i1 operand0 -> p1:int
      #|  i1 operand1 -> p0:int
      #|  i2 operand0 -> p2:int
      #|  i2 operand1 -> p1:int
      #|  i3 operand0 -> p1:int
      #|  i4 operand0 -> p2:int
      #|  i4 operand1 -> p1:int
      #|  i4 operand2 -> p3:int
      #|  i5 operand0 -> p3:int
      #|  i5 operand1 -> p0:int
      #|  i6 operand0 -> p1:int
      #|  i7 operand0 -> p2:int
      #|  i7 operand1 -> p1:int
      #|  i7 operand2 -> p3:int
      #|  i8 operand0 -> p3:int
      #|  i8 operand1 -> p0:int
      #|  i8 operand2 -> p1:int
      #|  i9 operand0 -> p3:int
      #|  i10 operand0 -> p2:int
      #|  i10 operand1 -> p3:int
      #|  i10 operand2 -> p4:int
      #|  i11 operand0 -> p4:int
      #|  i11 operand1 -> p1:int
      #|  i11 operand2 -> p0:int
      #|  i11 operand3 -> p2:int
      #|  i13 operand0 -> p2:int
      #|
    ),
  )
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
      #|    0x2a,
      #|    0x41,
      #|    0xfc,
      #|    0xdf,
      #|    0x88,
      #|    0x41,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0x43,
      #|    0x00,
      #|    0x01,
      #|    0x8b,
      #|    0x60,
      #|    0xfc,
      #|    0x9f,
      #|    0x48,
      #|    0x81,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0x43,
      #|    0x00,
      #|    0x01,
      #|    0x8b,
      #|    0x61,
      #|    0xfc,
      #|    0x5f,
      #|    0x88,
      #|    0x30,
      #|    0x00,
      #|    0x00,
      #|    0x0b,
      #|    0x70,
      #|    0xfc,
      #|    0x11,
      #|    0x88,
      #|    0xb1,
      #|    0xff,
      #|    0xff,
      #|    0x35,
      #|    0x03,
      #|    0x01,
      #|    0x80,
      #|    0xd2,
      #|    0x44,
      #|    0x00,
      #|    0x03,
      #|    0x8b,
      #|    0x30,
      #|    0x1c,
      #|    0x00,
      #|    0x53,
      #|    0x82,
      #|    0xfc,
      #|    0x5f,
      #|    0x08,
      #|    0x5f,
      #|    0x00,
      #|    0x10,
      #|    0x6b,
      #|    0x60,
      #|    0x00,
      #|    0x00,
      #|    0x54,
      #|    0x5f,
      #|    0x3f,
      #|    0x03,
      #|    0xd5,
      #|    0x03,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0x80,
      #|    0xfc,
      #|    0x11,
      #|    0x08,
      #|    0x51,
      #|    0xff,
      #|    0xff,
      #|    0x35,
      #|    0xbf,
      #|    0x3b,
      #|    0x03,
      #|    0xd5,
      #|    0xe0,
      #|    0x03,
      #|    0x02,
      #|    0x2a,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [
      #|    { offset: 8, reason: MemoryOutOfBounds, source: None },
      #|    { offset: 20, reason: MemoryOutOfBounds, source: None },
      #|    { offset: 32, reason: MemoryOutOfBounds, source: None },
      #|    { offset: 60, reason: MemoryOutOfBounds, source: None },
      #|  ],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits standalone safepoint roots at a NOP marker" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_safepoint_marker",
    Platform,
    [GcRef64],
    [],
  )
  let root = builder.parameters()[0]
  builder.emit_with_metadata(
    Safepoint(GcAndCancellation),
    [],
    [],
    @semantic.InstructionMetadata::new(None, [root]),
  )
  |> ignore
  builder.return_([])
  let function = lower(builder.finish(), test_lowering_context())
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
      #|    0xaa,
      #|    0x1f,
      #|    0x20,
      #|    0x03,
      #|    0xd5,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [
      #|    {
      #|      offset: 4,
      #|      kind: GcAndCancellation,
      #|      roots: [Register(Int, 1)],
      #|      source: None,
      #|      stack_map: None,
      #|    },
      #|  ],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline emits addresses inside the semantic stack-object area" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_stack_addresses",
    Platform,
    [],
    [Ptr64],
  )
  let first = builder.create_stack_object(3, 1)
  builder.create_stack_object(16, 16) |> ignore
  let last = builder.create_stack_object(24, 8)
  let first_address = builder.emit(StackAddress(first), [], [Ptr64])[0]
  let last_address = builder.emit(StackAddress(last), [], [Ptr64])[0]
  ignore(first_address)
  builder.return_([last_address])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xff,
      #|    0x03,
      #|    0x01,
      #|    0xd1,
      #|    0xe0,
      #|    0x83,
      #|    0x00,
      #|    0x91,
      #|    0xff,
      #|    0x03,
      #|    0x01,
      #|    0x91,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline materializes a large semantic stack-object offset" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_large_stack_address",
    Platform,
    [],
    [Ptr64],
  )
  builder.create_stack_object(5000, 1) |> ignore
  let object = builder.create_stack_object(8, 8)
  let address = builder.emit(StackAddress(object), [], [Ptr64])[0]
  builder.return_([address])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xff,
      #|    0x07,
      #|    0x40,
      #|    0xd1,
      #|    0xf0,
      #|    0x03,
      #|    0x40,
      #|    0xf9,
      #|    0xff,
      #|    0x43,
      #|    0x0e,
      #|    0xd1,
      #|    0xe0,
      #|    0x03,
      #|    0x00,
      #|    0x91,
      #|    0x10,
      #|    0x71,
      #|    0x82,
      #|    0xd2,
      #|    0x00,
      #|    0x00,
      #|    0x10,
      #|    0x8b,
      #|    0xff,
      #|    0x07,
      #|    0x40,
      #|    0x91,
      #|    0xff,
      #|    0x43,
      #|    0x0e,
      #|    0x91,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
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
    Platform,
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
  let function = lower(builder.finish(), test_lowering_context())
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
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 pipeline materializes block arguments on their selected edges" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_phi",
    Platform,
    [I32, I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let when_true = builder.create_block([])
  let when_false = builder.create_block([])
  let merge = builder.create_block([I64])
  builder.branch(parameters[0], when_true, [], when_false, [])
  builder.switch_to_block(when_true)
  builder.jump(merge, [parameters[1]])
  builder.switch_to_block(when_false)
  builder.jump(merge, [parameters[2]])
  builder.switch_to_block(merge)
  builder.return_([builder.block_parameters(merge)[0]])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  inspect(
    allocation.summary(),
    content=(
      #|allocation emitted_phi
      #|  v0:i32 -> p0:int
      #|  v1:i64 -> p1:int
      #|  v2:i64 -> p2:int
      #|  v3:i32 -> p3:int
      #|  v4:i64 -> p0:int
      #|  v5:i64 -> p1:int
      #|  v6:i64 -> p4:int
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p3:int
      #|  i1 operand0 -> p1:int
      #|  i1 operand1 -> p0:int
      #|  i2 operand0 -> p2:int
      #|  i2 operand1 -> p1:int
      #|  i3 operand0 -> p3:int
      #|  i6 operand0 -> p4:int
      #|  edge(block1, 0): move v4 p0:int -> p4:int
      #|  edge(block2, 0): move v5 p1:int -> p4:int
      #|
    ),
  )
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe3,
      #|    0x03,
      #|    0x00,
      #|    0x2a,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0x43,
      #|    0x00,
      #|    0x00,
      #|    0x35,
      #|    0x03,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0xe4,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0x03,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0xe4,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0x01,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0xe0,
      #|    0x03,
      #|    0x04,
      #|    0xaa,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 conditional edges isolate their parallel copies" {
  let builder = @semantic.FunctionBuilder::new(
    "conditional_phi",
    Platform,
    [I32, I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let merge = builder.create_block([I64])
  builder.branch(parameters[0], merge, [parameters[1]], merge, [parameters[2]])
  builder.switch_to_block(merge)
  builder.return_([builder.block_parameters(merge)[0]])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  inspect(
    allocation.summary(),
    content=(
      #|allocation conditional_phi
      #|  v0:i32 -> p0:int
      #|  v1:i64 -> p1:int
      #|  v2:i64 -> p2:int
      #|  v3:i32 -> p3:int
      #|  v4:i64 -> p0:int
      #|  v5:i64 -> p1:int
      #|  v6:i64 -> p4:int
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p3:int
      #|  i1 operand0 -> p1:int
      #|  i1 operand1 -> p0:int
      #|  i2 operand0 -> p2:int
      #|  i2 operand1 -> p1:int
      #|  i3 operand0 -> p3:int
      #|  i4 operand0 -> p4:int
      #|  edge(block0, 0): move v4 p0:int -> p4:int
      #|  edge(block0, 1): move v5 p1:int -> p4:int
      #|
    ),
  )
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe3,
      #|    0x03,
      #|    0x00,
      #|    0x2a,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0x63,
      #|    0x00,
      #|    0x00,
      #|    0x35,
      #|    0xe4,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0x03,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0xe4,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0x01,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0xe0,
      #|    0x03,
      #|    0x04,
      #|    0xaa,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 code objects retain safepoints and allocated GC roots" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
    "metadata_root",
    [GcRef64],
  )
  let entry = builder.entry_block()
  let root = builder.parameter(0)
  builder.append_body(
    entry,
    Move(GcRef64),
    [@vcode.Input::any(root)],
    [@vcode.Output::any(GcRef64)],
    [],
    @vcode.InstructionMetadata::new(
      source=@semantic.SourceLocation::new("metadata.wat", 4, 12),
      safepoint=Gc,
      live_gc_roots=[root],
    ),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [0xe1, 0x03, 0x00, 0xaa, 0xc0, 0x03, 0x5f, 0xd6],
      #|  relocations: [],
      #|  sources: [{ offset: 0, source: { file: "metadata.wat", line: 4, column: 12 } }],
      #|  traps: [],
      #|  safepoints: [
      #|    {
      #|      offset: 0,
      #|      kind: Gc,
      #|      roots: [Register(Int, 0)],
      #|      source: Some({ file: "metadata.wat", line: 4, column: 12 }),
      #|      stack_map: None,
      #|    },
      #|  ],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 direct calls preserve LR and emit typed call relocations" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_direct_call",
    Platform,
    [GcRef64],
    [],
  )
  let call = @semantic.SemanticCall::new(
    External(@semantic.ExternalSymbol::new("runtime.poll")),
    @semantic.Signature::new([], []),
    Platform,
    @semantic.CallBehavior::new(ReadWrite, true, true, true, true),
  )
  builder.emit_with_metadata(
    Call(call),
    [],
    [],
    @semantic.InstructionMetadata::new(
      Some(@semantic.SourceLocation::new("poll.wat", 5, 2)),
      [builder.parameters()[0]],
      stack_map=@semantic.StackMapMetadata::new(0, argument_root_count=1),
    ),
  )
  |> ignore
  builder.return_([])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  inspect(
    frame.summary(),
    content=(
      #|aarch64 frame size=16 align=16
      #|  save p19:int at sp+0
      #|  save p30:int at sp+8
      #|
    ),
  )
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xff,
      #|    0x43,
      #|    0x00,
      #|    0xd1,
      #|    0xf3,
      #|    0x03,
      #|    0x00,
      #|    0xf9,
      #|    0xfe,
      #|    0x07,
      #|    0x00,
      #|    0xf9,
      #|    0xf3,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x94,
      #|    0xfe,
      #|    0x07,
      #|    0x40,
      #|    0xf9,
      #|    0xf3,
      #|    0x03,
      #|    0x40,
      #|    0xf9,
      #|    0xff,
      #|    0x43,
      #|    0x00,
      #|    0x91,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [
      #|    {
      #|      offset: 16,
      #|      kind: AArch64Call26,
      #|      target: External({ name: "runtime.poll" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [{ offset: 16, source: { file: "poll.wat", line: 5, column: 2 } }],
      #|  traps: [],
      #|  safepoints: [
      #|    {
      #|      offset: 16,
      #|      kind: GcAndCancellation,
      #|      roots: [Register(Int, 19)],
      #|      source: Some({ file: "poll.wat", line: 5, column: 2 }),
      #|      stack_map: Some({ id: 0, argument_root_count: 1 }),
      #|    },
      #|  ],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 emits the internal result-area ABI" {
  let types : Array[@semantic.ValueType] = [I64, I64, F32, V128]
  let builder = @semantic.FunctionBuilder::new(
    "emitted_internal_result_area",
    Internal,
    [Ptr64, ..types],
    types,
  )
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.result_area")),
    @semantic.Signature::new([Ptr64, ..types], types),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  let results = builder.emit(Call(call), builder.parameters(), types)
  builder.return_(results)
  let function = lower(builder.finish(), compact_result_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  inspect(
    frame.summary(),
    content=(
      #|aarch64 frame size=48 align=16
      #|  call-results 32 bytes at sp+0
      #|  save p19:int at sp+32
      #|  save p30:int at sp+40
      #|
    ),
  )
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xff,
      #|    0xc3,
      #|    0x00,
      #|    0xd1,
      #|    0xf3,
      #|    0x13,
      #|    0x00,
      #|    0xf9,
      #|    0xfe,
      #|    0x17,
      #|    0x00,
      #|    0xf9,
      #|    0xe3,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0xf3,
      #|    0x03,
      #|    0x08,
      #|    0xaa,
      #|    0x02,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0xe2,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x03,
      #|    0xaa,
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x40,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0xe8,
      #|    0x03,
      #|    0x00,
      #|    0x91,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x94,
      #|    0xe1,
      #|    0x03,
      #|    0x40,
      #|    0xf9,
      #|    0xe1,
      #|    0x07,
      #|    0xc0,
      #|    0x3d,
      #|    0x61,
      #|    0x02,
      #|    0x00,
      #|    0xf9,
      #|    0x61,
      #|    0x06,
      #|    0x80,
      #|    0x3d,
      #|    0xfe,
      #|    0x17,
      #|    0x40,
      #|    0xf9,
      #|    0xf3,
      #|    0x13,
      #|    0x40,
      #|    0xf9,
      #|    0xff,
      #|    0xc3,
      #|    0x00,
      #|    0x91,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [
      #|    {
      #|      offset: 60,
      #|      kind: AArch64Call26,
      #|      target: Code({ name: "wasm.func.result_area" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 emits result-area forwarding for internal tail calls" {
  let types : Array[@semantic.ValueType] = [I64, I64, F32, V128]
  let builder = @semantic.FunctionBuilder::new(
    "emitted_internal_result_area_tail",
    Internal,
    [Ptr64, ..types],
    types,
  )
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.result_area_tail")),
    @semantic.Signature::new([Ptr64, ..types], types),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.tail_call(call, builder.parameters())
  let function = lower(builder.finish(), compact_result_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  inspect(
    frame.summary(),
    content=(
      #|aarch64 frame size=0 align=16
      #|
    ),
  )
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe3,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0xe2,
      #|    0x03,
      #|    0x08,
      #|    0xaa,
      #|    0x02,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0xe8,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0xe2,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x03,
      #|    0xaa,
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x40,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|  ],
      #|  relocations: [
      #|    {
      #|      offset: 48,
      #|      kind: AArch64Jump26,
      #|      target: Code({ name: "wasm.func.result_area_tail" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 emits jump-table and sparse switches" {
  let dense = @semantic.FunctionBuilder::new(
    "emitted_dense_switch",
    Internal,
    [Ptr64, I32],
    [],
  )
  let dense_zero = dense.create_block([])
  let dense_one = dense.create_block([])
  let dense_default = dense.create_block([])
  dense.switch(
    dense.parameters()[1],
    [(1UL, dense_one, []), (0UL, dense_zero, [])],
    dense_default,
    [],
  )
  for target in [dense_zero, dense_one, dense_default] {
    dense.switch_to_block(target)
    dense.return_([])
  }
  let dense_function = lower(dense.finish(), test_lowering_context())
  let dense_allocation = allocate(dense_function)
  debug_inspect(
    emit(
      dense_function,
      dense_allocation,
      plan_frame(dense_function, dense_allocation),
    ),
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
      #|    0x2a,
      #|    0x1f,
      #|    0x08,
      #|    0x00,
      #|    0x71,
      #|    0x02,
      #|    0x01,
      #|    0x00,
      #|    0x54,
      #|    0x70,
      #|    0x00,
      #|    0x00,
      #|    0x10,
      #|    0x10,
      #|    0x4a,
      #|    0x20,
      #|    0x8b,
      #|    0x00,
      #|    0x02,
      #|    0x1f,
      #|    0xd6,
      #|    0x02,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0x02,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
  let sparse = @semantic.FunctionBuilder::new(
    "emitted_sparse_switch",
    Internal,
    [Ptr64, I64],
    [],
  )
  let sparse_low = sparse.create_block([])
  let sparse_high = sparse.create_block([])
  let sparse_default = sparse.create_block([])
  sparse.switch(
    sparse.parameters()[1],
    [(7UL, sparse_low, []), (0x10000UL, sparse_high, [])],
    sparse_default,
    [],
  )
  for target in [sparse_low, sparse_high, sparse_default] {
    sparse.switch_to_block(target)
    sparse.return_([])
  }
  let sparse_function = lower(sparse.finish(), test_lowering_context())
  let sparse_allocation = allocate(sparse_function)
  debug_inspect(
    emit(
      sparse_function,
      sparse_allocation,
      plan_frame(sparse_function, sparse_allocation),
    ),
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
      #|    0x1f,
      #|    0x1c,
      #|    0x00,
      #|    0xf1,
      #|    0xa0,
      #|    0x00,
      #|    0x00,
      #|    0x54,
      #|    0x31,
      #|    0x00,
      #|    0xa0,
      #|    0xd2,
      #|    0x1f,
      #|    0x00,
      #|    0x11,
      #|    0xeb,
      #|    0x60,
      #|    0x00,
      #|    0x00,
      #|    0x54,
      #|    0x03,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
  let edge_switch = @semantic.FunctionBuilder::new(
    "emitted_switch_edges",
    Internal,
    [Ptr64, I32],
    [I32],
  )
  let edge_zero = edge_switch.create_block([I32])
  let edge_one = edge_switch.create_block([I32])
  let edge_default = edge_switch.create_block([I32])
  let edge_value = edge_switch.parameters()[1]
  edge_switch.switch(
    edge_value,
    [(0UL, edge_zero, [edge_value]), (1UL, edge_one, [edge_value])],
    edge_default,
    [edge_value],
  )
  for target in [edge_zero, edge_one, edge_default] {
    edge_switch.switch_to_block(target)
    edge_switch.return_(edge_switch.block_parameters(target))
  }
  let edge_function = lower(edge_switch.finish(), test_lowering_context())
  let edge_allocation = allocate(edge_function)
  debug_inspect(
    emit(
      edge_function,
      edge_allocation,
      plan_frame(edge_function, edge_allocation),
    ),
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
      #|    0x2a,
      #|    0x1f,
      #|    0x08,
      #|    0x00,
      #|    0x71,
      #|    0x42,
      #|    0x01,
      #|    0x00,
      #|    0x54,
      #|    0x70,
      #|    0x00,
      #|    0x00,
      #|    0x10,
      #|    0x10,
      #|    0x4a,
      #|    0x20,
      #|    0x8b,
      #|    0x00,
      #|    0x02,
      #|    0x1f,
      #|    0xd6,
      #|    0x02,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0x03,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0xe3,
      #|    0x03,
      #|    0x00,
      #|    0x2a,
      #|    0x05,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0xe4,
      #|    0x03,
      #|    0x00,
      #|    0x2a,
      #|    0x05,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0xe5,
      #|    0x03,
      #|    0x00,
      #|    0x2a,
      #|    0x05,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0xe0,
      #|    0x03,
      #|    0x03,
      #|    0x2a,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|    0xe0,
      #|    0x03,
      #|    0x04,
      #|    0x2a,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|    0xe0,
      #|    0x03,
      #|    0x05,
      #|    0x2a,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 emits noreturn calls and typed traps" {
  let noreturn = @semantic.FunctionBuilder::new(
    "emitted_noreturn_call",
    Platform,
    [GcRef64],
    [],
  )
  let call = @semantic.SemanticCall::new(
    External(@semantic.ExternalSymbol::new("runtime.abort")),
    @semantic.Signature::new([], []),
    Platform,
    @semantic.CallBehavior::new(ReadWrite, true, true, true, true),
  )
  noreturn.noreturn_call_with_metadata(
    call,
    [],
    @semantic.TerminatorMetadata::new(
      Some(@semantic.SourceLocation::new("trap.wat", 9, 4)),
      [noreturn.parameters()[0]],
    ),
  )
  let noreturn_function = lower(noreturn.finish(), test_lowering_context())
  let noreturn_allocation = allocate(noreturn_function)
  debug_inspect(
    emit(
      noreturn_function,
      noreturn_allocation,
      plan_frame(noreturn_function, noreturn_allocation),
    ),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xff,
      #|    0x43,
      #|    0x00,
      #|    0xd1,
      #|    0xf3,
      #|    0x03,
      #|    0x00,
      #|    0xf9,
      #|    0xfe,
      #|    0x07,
      #|    0x00,
      #|    0xf9,
      #|    0xf3,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x94,
      #|    0x00,
      #|    0x00,
      #|    0x20,
      #|    0xd4,
      #|  ],
      #|  relocations: [
      #|    {
      #|      offset: 16,
      #|      kind: AArch64Call26,
      #|      target: External({ name: "runtime.abort" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [
      #|    { offset: 16, source: { file: "trap.wat", line: 9, column: 4 } },
      #|    { offset: 20, source: { file: "trap.wat", line: 9, column: 4 } },
      #|  ],
      #|  traps: [
      #|    {
      #|      offset: 20,
      #|      reason: Unreachable,
      #|      source: Some({ file: "trap.wat", line: 9, column: 4 }),
      #|    },
      #|  ],
      #|  safepoints: [
      #|    {
      #|      offset: 16,
      #|      kind: GcAndCancellation,
      #|      roots: [Register(Int, 19)],
      #|      source: Some({ file: "trap.wat", line: 9, column: 4 }),
      #|      stack_map: None,
      #|    },
      #|  ],
      #|  unwind: [],
      #|}
    ),
  )
  let trapped = @semantic.FunctionBuilder::new(
    "emitted_explicit_trap",
    Internal,
    [Ptr64],
    [],
  )
  trapped.trap(User(7))
  trapped.set_terminator_source(@semantic.SourceLocation::new("trap.wat", 3, 9))
  let trap_function = lower(trapped.finish(), test_lowering_context())
  let trap_allocation = allocate(trap_function)
  debug_inspect(
    emit(
      trap_function,
      trap_allocation,
      plan_frame(trap_function, trap_allocation),
    ),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [0xe1, 0x03, 0x00, 0xaa, 0xe0, 0x00, 0x20, 0xd4],
      #|  relocations: [],
      #|  sources: [{ offset: 4, source: { file: "trap.wat", line: 3, column: 9 } }],
      #|  traps: [
      #|    {
      #|      offset: 4,
      #|      reason: User(7),
      #|      source: Some({ file: "trap.wat", line: 3, column: 9 }),
      #|    },
      #|  ],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 platform calls store overflow arguments in the outgoing area" {
  let parameter_types : Array[@semantic.ValueType] = Array::make(9, I64)
  let builder = @semantic.FunctionBuilder::new(
    "emitted_stack_call",
    Platform,
    parameter_types,
    [],
  )
  let call = @semantic.SemanticCall::new(
    External(@semantic.ExternalSymbol::new("runtime.many")),
    @semantic.Signature::new(parameter_types, []),
    Platform,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.emit(Call(call), builder.parameters(), []) |> ignore
  builder.return_([])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xff,
      #|    0x83,
      #|    0x00,
      #|    0xd1,
      #|    0xfe,
      #|    0x0b,
      #|    0x00,
      #|    0xf9,
      #|    0xe8,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0xe2,
      #|    0x03,
      #|    0x03,
      #|    0xaa,
      #|    0xe3,
      #|    0x03,
      #|    0x04,
      #|    0xaa,
      #|    0xe4,
      #|    0x03,
      #|    0x05,
      #|    0xaa,
      #|    0xe5,
      #|    0x03,
      #|    0x06,
      #|    0xaa,
      #|    0xe6,
      #|    0x03,
      #|    0x07,
      #|    0xaa,
      #|    0xe7,
      #|    0x13,
      #|    0x40,
      #|    0xf9,
      #|    0xe7,
      #|    0x03,
      #|    0x00,
      #|    0xf9,
      #|    0xe7,
      #|    0x03,
      #|    0x06,
      #|    0xaa,
      #|    0xe6,
      #|    0x03,
      #|    0x05,
      #|    0xaa,
      #|    0xe5,
      #|    0x03,
      #|    0x04,
      #|    0xaa,
      #|    0xe4,
      #|    0x03,
      #|    0x03,
      #|    0xaa,
      #|    0xe3,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0xe2,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x08,
      #|    0xaa,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x94,
      #|    0xfe,
      #|    0x0b,
      #|    0x40,
      #|    0xf9,
      #|    0xff,
      #|    0x83,
      #|    0x00,
      #|    0x91,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [
      #|    {
      #|      offset: 80,
      #|      kind: AArch64Call26,
      #|      target: External({ name: "runtime.many" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 internal calls emit code-symbol relocations" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_internal_call",
    Internal,
    [Ptr64],
    [],
  )
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.8")),
    @semantic.Signature::new([Ptr64], []),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.emit(Call(call), builder.parameters(), []) |> ignore
  builder.return_([])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xff,
      #|    0x43,
      #|    0x00,
      #|    0xd1,
      #|    0xfe,
      #|    0x03,
      #|    0x00,
      #|    0xf9,
      #|    0xe1,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x94,
      #|    0xfe,
      #|    0x03,
      #|    0x40,
      #|    0xf9,
      #|    0xff,
      #|    0x43,
      #|    0x00,
      #|    0x91,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [
      #|    {
      #|      offset: 16,
      #|      kind: AArch64Call26,
      #|      target: Code({ name: "wasm.func.8" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 internal calls keep caller-owned outgoing stack arguments" {
  let callee_parameter_types : Array[@semantic.ValueType] = [
    Ptr64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
  ]
  let builder = @semantic.FunctionBuilder::new(
    "emitted_internal_stack_call",
    Internal,
    [Ptr64],
    [],
  )
  let operands = [builder.parameters()[0]]
  for index in 0..<8 {
    operands.push(builder.emit(I64Const(index.to_uint64()), [], [I64])[0])
  }
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.stack")),
    @semantic.Signature::new(callee_parameter_types, []),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.emit(Call(call), operands, []) |> ignore
  builder.return_([])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  inspect(
    frame.summary(),
    content=(
      #|aarch64 frame size=32 align=16
      #|  outgoing 16 bytes at sp+0
      #|  save p30:int at sp+16
      #|
    ),
  )
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xff,
      #|    0x83,
      #|    0x00,
      #|    0xd1,
      #|    0xfe,
      #|    0x0b,
      #|    0x00,
      #|    0xf9,
      #|    0xe1,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0x00,
      #|    0x00,
      #|    0xe0,
      #|    0xd2,
      #|    0x22,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0x43,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0x64,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0x85,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0xa6,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0xc7,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0xe8,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0xe8,
      #|    0x03,
      #|    0x00,
      #|    0xf9,
      #|    0xf0,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x10,
      #|    0xaa,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x94,
      #|    0xfe,
      #|    0x0b,
      #|    0x40,
      #|    0xf9,
      #|    0xff,
      #|    0x83,
      #|    0x00,
      #|    0x91,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [
      #|    {
      #|      offset: 60,
      #|      kind: AArch64Call26,
      #|      target: Code({ name: "wasm.func.stack" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 indirect calls resolve callee and arguments before BLR" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_indirect_call",
    Internal,
    [Ptr64, Ptr64],
    [],
  )
  let parameters = builder.parameters()
  let call = @semantic.SemanticCall::new(
    Indirect,
    @semantic.Signature::new([Ptr64], []),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.emit(Call(call), [parameters[1], parameters[0]], []) |> ignore
  builder.return_([])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xff,
      #|    0x43,
      #|    0x00,
      #|    0xd1,
      #|    0xfe,
      #|    0x03,
      #|    0x00,
      #|    0xf9,
      #|    0xe2,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xf1,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0x20,
      #|    0x02,
      #|    0x3f,
      #|    0xd6,
      #|    0xfe,
      #|    0x03,
      #|    0x40,
      #|    0xf9,
      #|    0xff,
      #|    0x43,
      #|    0x00,
      #|    0x91,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 true tail calls tear down the frame and emit jump relocations" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_tail_call",
    Internal,
    [Ptr64, I64],
    [I64],
  )
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.11")),
    @semantic.Signature::new([Ptr64, I64], [I64]),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.tail_call(call, builder.parameters())
  let function = lower(builder.finish(), test_lowering_context())
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
      #|    0xe1,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|  ],
      #|  relocations: [
      #|    {
      #|      offset: 16,
      #|      kind: AArch64Jump26,
      #|      target: Code({ name: "wasm.func.11" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 indirect true tail calls resolve the callee before BR" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_indirect_tail_call",
    Internal,
    [Ptr64, Ptr64],
    [],
  )
  let parameters = builder.parameters()
  let call = @semantic.SemanticCall::new(
    Indirect,
    @semantic.Signature::new([Ptr64], []),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.tail_call(call, [parameters[1], parameters[0]])
  let function = lower(builder.finish(), test_lowering_context())
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
      #|    0xf1,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0x20,
      #|    0x02,
      #|    0x1f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 true tail calls preserve caller SP with stack arguments" {
  let callee_parameter_types : Array[@semantic.ValueType] = [
    Ptr64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
  ]
  let builder = @semantic.FunctionBuilder::new(
    "emitted_stack_tail_call",
    Internal,
    [Ptr64],
    [],
  )
  let operands = [builder.parameters()[0]]
  for index in 0..<8 {
    operands.push(builder.emit(I64Const(index.to_uint64()), [], [I64])[0])
  }
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.12")),
    @semantic.Signature::new(callee_parameter_types, []),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.tail_call(call, operands)
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  inspect(
    frame.summary(),
    content=(
      #|aarch64 frame size=32 align=16
      #|  tail-args 16 bytes at sp+0 (incoming 0)
      #|
    ),
  )
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xff,
      #|    0x83,
      #|    0x00,
      #|    0xd1,
      #|    0xe1,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0x00,
      #|    0x00,
      #|    0xe0,
      #|    0xd2,
      #|    0x22,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0x43,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0x64,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0x85,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0xa6,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0xc7,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0xe8,
      #|    0x00,
      #|    0x80,
      #|    0xd2,
      #|    0xe8,
      #|    0x03,
      #|    0x00,
      #|    0xf9,
      #|    0xf0,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x10,
      #|    0xaa,
      #|    0xff,
      #|    0x83,
      #|    0x00,
      #|    0x91,
      #|    0xff,
      #|    0x83,
      #|    0x00,
      #|    0xd1,
      #|    0xfe,
      #|    0x0b,
      #|    0x00,
      #|    0xf9,
      #|    0x5e,
      #|    0x00,
      #|    0x00,
      #|    0x10,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x14,
      #|    0xf0,
      #|    0x0b,
      #|    0x40,
      #|    0xf9,
      #|    0xff,
      #|    0x83,
      #|    0x00,
      #|    0x91,
      #|    0x00,
      #|    0x02,
      #|    0x1f,
      #|    0xd6,
      #|  ],
      #|  relocations: [
      #|    {
      #|      offset: 72,
      #|      kind: AArch64Jump26,
      #|      target: Code({ name: "wasm.func.12" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 scalar memory emission records faulting instructions and legalizes offsets" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_scalar_memory",
    Internal,
    [Ptr64, I64, F64],
    [I64],
  )
  let parameters = builder.parameters()
  let loaded = builder.emit_with_metadata(
      Load(
        @semantic.LoadSpec::new(
          W8,
          Signed,
          I64,
          3UL,
          Little,
          Some(MemoryOutOfBounds),
        ),
      ),
      [parameters[0]],
      [I64],
      @semantic.InstructionMetadata::new(
        Some(@semantic.SourceLocation::new("memory.wat", 8, 13)),
        [],
      ),
    )[0]
  builder.emit(
    Store(
      @semantic.StoreSpec::new(W16, I64, 6UL, Little, Some(MemoryOutOfBounds)),
    ),
    [parameters[0], parameters[1]],
    [],
  )
  |> ignore
  builder.emit(
    Store(
      @semantic.StoreSpec::new(
        W64,
        F64,
        0x100000000UL,
        Little,
        Some(MemoryOutOfBounds),
      ),
    ),
    [parameters[0], parameters[2]],
    [],
  )
  |> ignore
  builder.return_([loaded])
  let function = lower(builder.finish(), test_lowering_context())
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
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x41,
      #|    0x0c,
      #|    0x80,
      #|    0x39,
      #|    0x40,
      #|    0x0c,
      #|    0x00,
      #|    0x79,
      #|    0x30,
      #|    0x00,
      #|    0xc0,
      #|    0xd2,
      #|    0x50,
      #|    0x00,
      #|    0x10,
      #|    0x8b,
      #|    0x01,
      #|    0x02,
      #|    0x00,
      #|    0xfd,
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
      #|  sources: [{ offset: 12, source: { file: "memory.wat", line: 8, column: 13 } }],
      #|  traps: [
      #|    {
      #|      offset: 12,
      #|      reason: MemoryOutOfBounds,
      #|      source: Some({ file: "memory.wat", line: 8, column: 13 }),
      #|    },
      #|    { offset: 16, reason: MemoryOutOfBounds, source: None },
      #|    { offset: 28, reason: MemoryOutOfBounds, source: None },
      #|  ],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 checked division emits distinct trap sites" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_checked_divide",
    Internal,
    [Ptr64, I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let result = builder.emit_with_metadata(
      IntBinary(SignedDiv),
      [parameters[1], parameters[2]],
      [I64],
      @semantic.InstructionMetadata::new(
        Some(@semantic.SourceLocation::new("divide.wat", 2, 5)),
        [],
      ),
    )[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe3,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0x41,
      #|    0x00,
      #|    0x00,
      #|    0xb5,
      #|    0x80,
      #|    0x00,
      #|    0x20,
      #|    0xd4,
      #|    0x3f,
      #|    0x04,
      #|    0x00,
      #|    0xb1,
      #|    0x00,
      #|    0x08,
      #|    0x41,
      #|    0xfa,
      #|    0x47,
      #|    0x00,
      #|    0x00,
      #|    0x54,
      #|    0xa0,
      #|    0x00,
      #|    0x20,
      #|    0xd4,
      #|    0x02,
      #|    0x0c,
      #|    0xc1,
      #|    0x9a,
      #|    0xe0,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [
      #|    { offset: 16, source: { file: "divide.wat", line: 2, column: 5 } },
      #|    { offset: 32, source: { file: "divide.wat", line: 2, column: 5 } },
      #|    { offset: 36, source: { file: "divide.wat", line: 2, column: 5 } },
      #|  ],
      #|  traps: [
      #|    {
      #|      offset: 16,
      #|      reason: IntegerDivisionByZero,
      #|      source: Some({ file: "divide.wat", line: 2, column: 5 }),
      #|    },
      #|    {
      #|      offset: 32,
      #|      reason: IntegerOverflow,
      #|      source: Some({ file: "divide.wat", line: 2, column: 5 }),
      #|    },
      #|  ],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 signed remainder skips the division overflow trap" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_signed_remainder",
    Internal,
    [Ptr64, I32, I32],
    [I32],
  )
  let parameters = builder.parameters()
  let result = builder.emit(
      IntBinary(SignedRem),
      [parameters[1], parameters[2]],
      [I32],
    )[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe3,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0x2a,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0x2a,
      #|    0x41,
      #|    0x00,
      #|    0x00,
      #|    0x35,
      #|    0x80,
      #|    0x00,
      #|    0x20,
      #|    0xd4,
      #|    0x10,
      #|    0x0c,
      #|    0xc1,
      #|    0x1a,
      #|    0x02,
      #|    0x82,
      #|    0x01,
      #|    0x1b,
      #|    0xe0,
      #|    0x03,
      #|    0x02,
      #|    0x2a,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [{ offset: 16, reason: IntegerDivisionByZero, source: None }],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 emits remaining pure scalar integer operations" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_pure_integer_operations",
    Internal,
    [Ptr64, I32, I32, I64, I64],
    [I32, I64],
  )
  let parameters = builder.parameters()
  let trailing32 = builder.emit(IntUnary(CountTrailingZeros), [parameters[1]], [
      I32,
    ])[0]
  let population32 = builder.emit(IntUnary(PopulationCount), [parameters[1]], [
      I32,
    ])[0]
  let rotated32 = builder.emit(
      IntBinary(RotateLeft),
      [trailing32, population32],
      [I32],
    )[0]
  let signed_high32 = builder.emit(
      IntHighMultiply(Signed),
      [rotated32, parameters[2]],
      [I32],
    )[0]
  let unsigned_high32 = builder.emit(
      IntHighMultiply(Unsigned),
      [signed_high32, population32],
      [I32],
    )[0]
  let trailing64 = builder.emit(IntUnary(CountTrailingZeros), [parameters[3]], [
      I64,
    ])[0]
  let population64 = builder.emit(IntUnary(PopulationCount), [parameters[3]], [
      I64,
    ])[0]
  let rotated64 = builder.emit(
      IntBinary(RotateLeft),
      [trailing64, population64],
      [I64],
    )[0]
  let signed_high64 = builder.emit(
      IntHighMultiply(Signed),
      [rotated64, parameters[4]],
      [I64],
    )[0]
  let unsigned_high64 = builder.emit(
      IntHighMultiply(Unsigned),
      [signed_high64, population64],
      [I64],
    )[0]
  builder.return_([unsigned_high32, unsigned_high64])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe5,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0x2a,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0x2a,
      #|    0xe2,
      #|    0x03,
      #|    0x03,
      #|    0xaa,
      #|    0xe3,
      #|    0x03,
      #|    0x04,
      #|    0xaa,
      #|    0x04,
      #|    0x00,
      #|    0xc0,
      #|    0x5a,
      #|    0x85,
      #|    0x10,
      #|    0xc0,
      #|    0x5a,
      #|    0x10,
      #|    0x00,
      #|    0x27,
      #|    0x1e,
      #|    0x10,
      #|    0x5a,
      #|    0x20,
      #|    0x0e,
      #|    0x10,
      #|    0xba,
      #|    0x31,
      #|    0x0e,
      #|    0x04,
      #|    0x02,
      #|    0x26,
      #|    0x1e,
      #|    0xe0,
      #|    0x03,
      #|    0x04,
      #|    0x4b,
      #|    0xa6,
      #|    0x2c,
      #|    0xc0,
      #|    0x1a,
      #|    0xd0,
      #|    0x7c,
      #|    0x21,
      #|    0x9b,
      #|    0x00,
      #|    0xfe,
      #|    0x60,
      #|    0xd3,
      #|    0x10,
      #|    0x7c,
      #|    0xa4,
      #|    0x9b,
      #|    0x01,
      #|    0xfe,
      #|    0x60,
      #|    0xd3,
      #|    0x40,
      #|    0x00,
      #|    0xc0,
      #|    0xda,
      #|    0x04,
      #|    0x10,
      #|    0xc0,
      #|    0xda,
      #|    0x50,
      #|    0x00,
      #|    0x67,
      #|    0x9e,
      #|    0x10,
      #|    0x5a,
      #|    0x20,
      #|    0x0e,
      #|    0x10,
      #|    0xba,
      #|    0x31,
      #|    0x0e,
      #|    0x00,
      #|    0x02,
      #|    0x26,
      #|    0x1e,
      #|    0xe2,
      #|    0x03,
      #|    0x00,
      #|    0xcb,
      #|    0x85,
      #|    0x2c,
      #|    0xc2,
      #|    0x9a,
      #|    0xa2,
      #|    0x7c,
      #|    0x43,
      #|    0x9b,
      #|    0x43,
      #|    0x7c,
      #|    0xc0,
      #|    0x9b,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0x2a,
      #|    0xe1,
      #|    0x03,
      #|    0x03,
      #|    0xaa,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 emits null carriers references and scalar values" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_scalar_carriers_and_select",
    Internal,
    [Ptr64, I32, I32, I64, I64, F32, F32, F64, F64],
    [I32, I32, I32, I64, Ptr64, GcRef64, F32, F64],
  )
  let parameters = builder.parameters()
  let null_pointer = builder.emit(NullPtr, [], [Ptr64])[0]
  let null_reference = builder.emit(NullGcRef, [], [GcRef64])[0]
  let reference = builder.emit(GcRefFromBits, [parameters[3]], [GcRef64])[0]
  let address = builder.emit(GcRefAddress, [reference], [Ptr64])[0]
  let pointer_equal = builder.emit(
      ReferenceCompare(Equal),
      [null_pointer, address],
      [I32],
    )[0]
  let reference_not_equal = builder.emit(
      ReferenceCompare(NotEqual),
      [null_reference, reference],
      [I32],
    )[0]
  let selected32 = builder.emit(
      Select,
      [parameters[1], parameters[1], parameters[2]],
      [I32],
    )[0]
  let selected64 = builder.emit(
      Select,
      [parameters[1], parameters[3], parameters[4]],
      [I64],
    )[0]
  let selected_pointer = builder.emit(
      Select,
      [parameters[1], null_pointer, address],
      [Ptr64],
    )[0]
  let selected_reference = builder.emit(
      Select,
      [parameters[1], null_reference, reference],
      [GcRef64],
    )[0]
  let selected32_float = builder.emit(
      Select,
      [parameters[1], parameters[5], parameters[6]],
      [F32],
    )[0]
  let selected64_float = builder.emit(
      Select,
      [parameters[1], parameters[7], parameters[8]],
      [F64],
    )[0]
  builder.return_([
    pointer_equal, reference_not_equal, selected32, selected64, selected_pointer,
    selected_reference, selected32_float, selected64_float,
  ])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe5,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0x2a,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0x2a,
      #|    0xe2,
      #|    0x03,
      #|    0x03,
      #|    0xaa,
      #|    0xe3,
      #|    0x03,
      #|    0x04,
      #|    0xaa,
      #|    0x04,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0x62,
      #|    0x1c,
      #|    0xa3,
      #|    0x4e,
      #|    0x04,
      #|    0x00,
      #|    0xe0,
      #|    0xd2,
      #|    0x05,
      #|    0x00,
      #|    0xe0,
      #|    0xd2,
      #|    0xe6,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0xe7,
      #|    0x03,
      #|    0x06,
      #|    0xaa,
      #|    0x9f,
      #|    0x00,
      #|    0x07,
      #|    0xeb,
      #|    0xe8,
      #|    0x17,
      #|    0x9f,
      #|    0x9a,
      #|    0xbf,
      #|    0x00,
      #|    0x06,
      #|    0xeb,
      #|    0xe9,
      #|    0x07,
      #|    0x9f,
      #|    0x9a,
      #|    0x1f,
      #|    0x00,
      #|    0x00,
      #|    0x71,
      #|    0x0a,
      #|    0x10,
      #|    0x81,
      #|    0x1a,
      #|    0x1f,
      #|    0x00,
      #|    0x00,
      #|    0x71,
      #|    0x41,
      #|    0x10,
      #|    0x83,
      #|    0x9a,
      #|    0x1f,
      #|    0x00,
      #|    0x00,
      #|    0x71,
      #|    0x82,
      #|    0x10,
      #|    0x87,
      #|    0x9a,
      #|    0x1f,
      #|    0x00,
      #|    0x00,
      #|    0x71,
      #|    0xa3,
      #|    0x10,
      #|    0x86,
      #|    0x9a,
      #|    0x1f,
      #|    0x00,
      #|    0x00,
      #|    0x71,
      #|    0x83,
      #|    0x1c,
      #|    0x20,
      #|    0x1e,
      #|    0x1f,
      #|    0x00,
      #|    0x00,
      #|    0x71,
      #|    0x20,
      #|    0x1c,
      #|    0x62,
      #|    0x1e,
      #|    0xe0,
      #|    0x03,
      #|    0x08,
      #|    0x2a,
      #|    0xe4,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0xe2,
      #|    0x03,
      #|    0x0a,
      #|    0x2a,
      #|    0xe5,
      #|    0x03,
      #|    0x03,
      #|    0xaa,
      #|    0xe3,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x09,
      #|    0x2a,
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x60,
      #|    0x1c,
      #|    0xa3,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 emits environment paths and typed symbol relocations" {
  let field = @semantic.EnvironmentField::new("runtime.memory.base", I64)
  let builder = @semantic.FunctionBuilder::new(
    "emitted_addresses_and_environment",
    Internal,
    [Ptr64],
    [Ptr64, Ptr64, Ptr64, I64],
  )
  let code = builder.emit(
      CodeAddress(@semantic.CodeSymbol::new("callee")),
      [],
      [Ptr64],
    )[0]
  let external = builder.emit(
      ExternalAddress(@semantic.ExternalSymbol::new("runtime.helper")),
      [],
      [Ptr64],
    )[0]
  let data = builder.emit(
      DataAddress(@semantic.DataSymbol::new("constant.pool")),
      [],
      [Ptr64],
    )[0]
  let environment = builder.emit(
      EnvironmentField(field),
      [builder.parameters()[0]],
      [I64],
    )[0]
  builder.return_([code, external, data, environment])
  let context = test_lowering_context().with_environment_field(field, [8, 24])
  let function = lower(builder.finish(), context)
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
      #|    0xaa,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x90,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x91,
      #|    0x02,
      #|    0x00,
      #|    0x00,
      #|    0x90,
      #|    0x42,
      #|    0x00,
      #|    0x00,
      #|    0x91,
      #|    0x03,
      #|    0x00,
      #|    0x00,
      #|    0x90,
      #|    0x63,
      #|    0x00,
      #|    0x00,
      #|    0x91,
      #|    0x24,
      #|    0x04,
      #|    0x40,
      #|    0xf9,
      #|    0x81,
      #|    0x0c,
      #|    0x40,
      #|    0xf9,
      #|    0xf0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0xe2,
      #|    0x03,
      #|    0x03,
      #|    0xaa,
      #|    0xe3,
      #|    0x03,
      #|    0x10,
      #|    0xaa,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [
      #|    {
      #|      offset: 4,
      #|      kind: AArch64Page21,
      #|      target: Code({ name: "callee" }),
      #|      addend: 0,
      #|    },
      #|    {
      #|      offset: 8,
      #|      kind: AArch64PageOffset12,
      #|      target: Code({ name: "callee" }),
      #|      addend: 0,
      #|    },
      #|    {
      #|      offset: 12,
      #|      kind: AArch64Page21,
      #|      target: External({ name: "runtime.helper" }),
      #|      addend: 0,
      #|    },
      #|    {
      #|      offset: 16,
      #|      kind: AArch64PageOffset12,
      #|      target: External({ name: "runtime.helper" }),
      #|      addend: 0,
      #|    },
      #|    {
      #|      offset: 20,
      #|      kind: AArch64Page21,
      #|      target: Data({ name: "constant.pool" }),
      #|      addend: 0,
      #|    },
      #|    {
      #|      offset: 24,
      #|      kind: AArch64PageOffset12,
      #|      target: Data({ name: "constant.pool" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 scalar floating-point emission preserves constant bits" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_scalar_float",
    Internal,
    [Ptr64, F32, F32, F64],
    [F32, I32],
  )
  let parameters = builder.parameters()
  let one = builder.emit(F32Const(0x3F800000U), [], [F32])[0]
  let sum = builder.emit(FloatBinary(Add), [parameters[1], one], [F32])[0]
  let negative_zero = builder.emit(F64Const(0x8000000000000000UL), [], [F64])[0]
  let absolute = builder.emit(FloatUnary(Absolute), [parameters[3]], [F64])[0]
  let comparison = builder.emit(
      FloatCompare(LessOrEqual),
      [absolute, negative_zero],
      [I32],
    )[0]
  builder.return_([sum, comparison])
  let function = lower(builder.finish(), test_lowering_context())
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
      #|    0xaa,
      #|    0x03,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x40,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0x10,
      #|    0xf0,
      #|    0xa7,
      #|    0x52,
      #|    0x01,
      #|    0x02,
      #|    0x27,
      #|    0x1e,
      #|    0x62,
      #|    0x28,
      #|    0x21,
      #|    0x1e,
      #|    0x10,
      #|    0x00,
      #|    0xf0,
      #|    0xd2,
      #|    0x01,
      #|    0x02,
      #|    0x67,
      #|    0x9e,
      #|    0x03,
      #|    0xc0,
      #|    0x60,
      #|    0x1e,
      #|    0x60,
      #|    0x20,
      #|    0x61,
      #|    0x1e,
      #|    0xe0,
      #|    0x87,
      #|    0x9f,
      #|    0x9a,
      #|    0x40,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 scalar conversion emission preserves register-bank transfers" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_scalar_conversions",
    Internal,
    [Ptr64, I32, I64, F32, F64],
    [I64, F64],
  )
  let parameters = builder.parameters()
  let extended = builder.emit(Convert(I64ExtendI32(Signed)), [parameters[1]], [
      I64,
    ])[0]
  let float_bits = builder.emit(Convert(Bitcast(F64, I64)), [parameters[4]], [
      I64,
    ])[0]
  let integer_result = builder.emit(IntBinary(Add), [extended, float_bits], [
      I64,
    ])[0]
  let converted = builder.emit(
      Convert(IntToFloat(I64, F64, Unsigned)),
      [parameters[2]],
      [F64],
    )[0]
  let promoted = builder.emit(Convert(F64PromoteF32), [parameters[3]], [F64])[0]
  let float_result = builder.emit(FloatBinary(Add), [converted, promoted], [F64])[0]
  builder.return_([integer_result, float_result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xe3,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x01,
      #|    0x2a,
      #|    0xe1,
      #|    0x03,
      #|    0x02,
      #|    0xaa,
      #|    0x02,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x02,
      #|    0x7c,
      #|    0x40,
      #|    0x93,
      #|    0x00,
      #|    0x00,
      #|    0x66,
      #|    0x9e,
      #|    0x43,
      #|    0x00,
      #|    0x00,
      #|    0x8b,
      #|    0x20,
      #|    0x00,
      #|    0x63,
      #|    0x9e,
      #|    0x41,
      #|    0xc0,
      #|    0x22,
      #|    0x1e,
      #|    0x02,
      #|    0x28,
      #|    0x61,
      #|    0x1e,
      #|    0xe0,
      #|    0x03,
      #|    0x03,
      #|    0xaa,
      #|    0x40,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 emits scalar rounding and NaN predicates" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_float_rounding",
    Internal,
    [Ptr64, F32, F32, F64, F64],
    [F32, F64, I32, I32],
  )
  let parameters = builder.parameters()
  let ceil32 = builder.emit(FloatUnary(Ceil), [parameters[1]], [F32])[0]
  let floor32 = builder.emit(FloatUnary(Floor), [ceil32], [F32])[0]
  let truncate32 = builder.emit(FloatUnary(Truncate), [floor32], [F32])[0]
  let nearest32 = builder.emit(FloatUnary(Nearest), [truncate32], [F32])[0]
  let ceil64 = builder.emit(FloatUnary(Ceil), [parameters[3]], [F64])[0]
  let floor64 = builder.emit(FloatUnary(Floor), [ceil64], [F64])[0]
  let truncate64 = builder.emit(FloatUnary(Truncate), [floor64], [F64])[0]
  let nearest64 = builder.emit(FloatUnary(Nearest), [truncate64], [F64])[0]
  let ordered = builder.emit(
      FloatCompare(Ordered),
      [parameters[1], parameters[2]],
      [I32],
    )[0]
  let unordered = builder.emit(
      FloatCompare(Unordered),
      [parameters[3], parameters[4]],
      [I32],
    )[0]
  builder.return_([nearest32, nearest64, ordered, unordered])
  let function = lower(builder.finish(), test_lowering_context())
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
      #|    0xaa,
      #|    0x04,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0x62,
      #|    0x1c,
      #|    0xa3,
      #|    0x4e,
      #|    0x83,
      #|    0xc0,
      #|    0x24,
      #|    0x1e,
      #|    0x65,
      #|    0x40,
      #|    0x25,
      #|    0x1e,
      #|    0xa3,
      #|    0xc0,
      #|    0x25,
      #|    0x1e,
      #|    0x65,
      #|    0x40,
      #|    0x24,
      #|    0x1e,
      #|    0x23,
      #|    0xc0,
      #|    0x64,
      #|    0x1e,
      #|    0x66,
      #|    0x40,
      #|    0x65,
      #|    0x1e,
      #|    0xc3,
      #|    0xc0,
      #|    0x65,
      #|    0x1e,
      #|    0x66,
      #|    0x40,
      #|    0x64,
      #|    0x1e,
      #|    0x80,
      #|    0x20,
      #|    0x20,
      #|    0x1e,
      #|    0xe0,
      #|    0x67,
      #|    0x9f,
      #|    0x9a,
      #|    0x20,
      #|    0x20,
      #|    0x62,
      #|    0x1e,
      #|    0xe1,
      #|    0x77,
      #|    0x9f,
      #|    0x9a,
      #|    0xa0,
      #|    0x1c,
      #|    0xa5,
      #|    0x4e,
      #|    0xc1,
      #|    0x1c,
      #|    0xa6,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 emits scalar min max and bit-exact copy-sign" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_float_minmax_copysign",
    Internal,
    [Ptr64],
    [F32, F64, F32, F64],
  )
  let positive_zero32 = builder.emit(F32Const(0U), [], [F32])[0]
  let negative_zero32 = builder.emit(F32Const(0x80000000U), [], [F32])[0]
  let positive_zero64 = builder.emit(F64Const(0UL), [], [F64])[0]
  let negative_zero64 = builder.emit(F64Const(0x8000000000000000UL), [], [F64])[0]
  let minimum = builder.emit(
      FloatBinary(Min),
      [positive_zero32, negative_zero32],
      [F32],
    )[0]
  let maximum = builder.emit(
      FloatBinary(Max),
      [negative_zero64, positive_zero64],
      [F64],
    )[0]
  let nan32 = builder.emit(F32Const(0x7FC12345U), [], [F32])[0]
  let copied32 = builder.emit(FloatBinary(CopySign), [nan32, negative_zero32], [
      F32,
    ])[0]
  let nan64 = builder.emit(F64Const(0xFFF8123456789ABCUL), [], [F64])[0]
  let copied64 = builder.emit(FloatBinary(CopySign), [nan64, positive_zero64], [
      F64,
    ])[0]
  builder.return_([minimum, maximum, copied32, copied64])
  let function = lower(builder.finish(), test_lowering_context())
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
      #|    0xaa,
      #|    0x10,
      #|    0x00,
      #|    0xa0,
      #|    0x52,
      #|    0x00,
      #|    0x02,
      #|    0x27,
      #|    0x1e,
      #|    0x10,
      #|    0x00,
      #|    0xb0,
      #|    0x52,
      #|    0x01,
      #|    0x02,
      #|    0x27,
      #|    0x1e,
      #|    0x10,
      #|    0x00,
      #|    0xe0,
      #|    0xd2,
      #|    0x02,
      #|    0x02,
      #|    0x67,
      #|    0x9e,
      #|    0x10,
      #|    0x00,
      #|    0xf0,
      #|    0xd2,
      #|    0x03,
      #|    0x02,
      #|    0x67,
      #|    0x9e,
      #|    0x04,
      #|    0x58,
      #|    0x21,
      #|    0x1e,
      #|    0x60,
      #|    0x48,
      #|    0x62,
      #|    0x1e,
      #|    0xb0,
      #|    0x68,
      #|    0x84,
      #|    0x52,
      #|    0x30,
      #|    0xf8,
      #|    0xaf,
      #|    0x72,
      #|    0x03,
      #|    0x02,
      #|    0x27,
      #|    0x1e,
      #|    0x10,
      #|    0x00,
      #|    0xb0,
      #|    0x52,
      #|    0x10,
      #|    0x02,
      #|    0x27,
      #|    0x1e,
      #|    0x30,
      #|    0x1c,
      #|    0x63,
      #|    0x6e,
      #|    0x05,
      #|    0x1e,
      #|    0xb0,
      #|    0x4e,
      #|    0x90,
      #|    0x57,
      #|    0x93,
      #|    0xd2,
      #|    0x10,
      #|    0xcf,
      #|    0xaa,
      #|    0xf2,
      #|    0x90,
      #|    0x46,
      #|    0xc2,
      #|    0xf2,
      #|    0x10,
      #|    0xff,
      #|    0xff,
      #|    0xf2,
      #|    0x01,
      #|    0x02,
      #|    0x67,
      #|    0x9e,
      #|    0x10,
      #|    0x00,
      #|    0xf0,
      #|    0xd2,
      #|    0x10,
      #|    0x02,
      #|    0x67,
      #|    0x9e,
      #|    0x50,
      #|    0x1c,
      #|    0x61,
      #|    0x6e,
      #|    0x03,
      #|    0x1e,
      #|    0xb0,
      #|    0x4e,
      #|    0x01,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x80,
      #|    0x1c,
      #|    0xa4,
      #|    0x4e,
      #|    0xa2,
      #|    0x1c,
      #|    0xa5,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 emits every scalar fused operation" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_float_fused",
    Internal,
    [Ptr64, F32, F32, F32, F64, F64, F64],
    [F32, F64],
  )
  let parameters = builder.parameters()
  let add32 = builder.emit(
      FloatTernary(FusedMultiplyAdd),
      [parameters[1], parameters[2], parameters[3]],
      [F32],
    )[0]
  let negated_add32 = builder.emit(
      FloatTernary(FusedNegatedMultiplyAdd),
      [parameters[1], parameters[2], add32],
      [F32],
    )[0]
  let subtract32 = builder.emit(
      FloatTernary(FusedMultiplySubtract),
      [parameters[1], parameters[2], negated_add32],
      [F32],
    )[0]
  let negated_subtract32 = builder.emit(
      FloatTernary(FusedNegatedMultiplySubtract),
      [parameters[1], parameters[2], subtract32],
      [F32],
    )[0]
  let add64 = builder.emit(
      FloatTernary(FusedMultiplyAdd),
      [parameters[4], parameters[5], parameters[6]],
      [F64],
    )[0]
  let negated_add64 = builder.emit(
      FloatTernary(FusedNegatedMultiplyAdd),
      [parameters[4], parameters[5], add64],
      [F64],
    )[0]
  let subtract64 = builder.emit(
      FloatTernary(FusedMultiplySubtract),
      [parameters[4], parameters[5], negated_add64],
      [F64],
    )[0]
  let negated_subtract64 = builder.emit(
      FloatTernary(FusedNegatedMultiplySubtract),
      [parameters[4], parameters[5], subtract64],
      [F64],
    )[0]
  builder.return_([negated_subtract32, negated_subtract64])
  let function = lower(builder.finish(), test_lowering_context())
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
      #|    0xaa,
      #|    0x06,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x41,
      #|    0x1c,
      #|    0xa2,
      #|    0x4e,
      #|    0x62,
      #|    0x1c,
      #|    0xa3,
      #|    0x4e,
      #|    0x83,
      #|    0x1c,
      #|    0xa4,
      #|    0x4e,
      #|    0xa4,
      #|    0x1c,
      #|    0xa5,
      #|    0x4e,
      #|    0xc5,
      #|    0x04,
      #|    0x00,
      #|    0x1f,
      #|    0xc1,
      #|    0x94,
      #|    0x00,
      #|    0x1f,
      #|    0xc5,
      #|    0x84,
      #|    0x20,
      #|    0x1f,
      #|    0xc1,
      #|    0x14,
      #|    0x20,
      #|    0x1f,
      #|    0x40,
      #|    0x10,
      #|    0x43,
      #|    0x1f,
      #|    0x44,
      #|    0x80,
      #|    0x43,
      #|    0x1f,
      #|    0x40,
      #|    0x90,
      #|    0x63,
      #|    0x1f,
      #|    0x44,
      #|    0x00,
      #|    0x63,
      #|    0x1f,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x81,
      #|    0x1c,
      #|    0xa4,
      #|    0x4e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 trapping float-to-int emits three precise trap sites" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_float_to_int",
    Internal,
    [Ptr64, F32, F64],
    [I32, I64],
  )
  let parameters = builder.parameters()
  let trapping = builder.emit_with_metadata(
      Convert(FloatToInt(F32, I32, Signed, Trapping)),
      [parameters[1]],
      [I32],
      @semantic.InstructionMetadata::new(
        Some(@semantic.SourceLocation::new("convert.wat", 6, 9)),
        [],
      ),
    )[0]
  let saturating = builder.emit(
      Convert(FloatToInt(F64, I64, Unsigned, Saturating)),
      [parameters[2]],
      [I64],
    )[0]
  builder.return_([trapping, saturating])
  let function = lower(builder.finish(), test_lowering_context())
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
      #|    0xaa,
      #|    0x02,
      #|    0x1c,
      #|    0xa0,
      #|    0x4e,
      #|    0x20,
      #|    0x1c,
      #|    0xa1,
      #|    0x4e,
      #|    0x40,
      #|    0x20,
      #|    0x22,
      #|    0x1e,
      #|    0x47,
      #|    0x00,
      #|    0x00,
      #|    0x54,
      #|    0x60,
      #|    0x00,
      #|    0x20,
      #|    0xd4,
      #|    0x10,
      #|    0xe0,
      #|    0xb9,
      #|    0x52,
      #|    0x01,
      #|    0x02,
      #|    0x27,
      #|    0x1e,
      #|    0x40,
      #|    0x20,
      #|    0x21,
      #|    0x1e,
      #|    0x45,
      #|    0x00,
      #|    0x00,
      #|    0x54,
      #|    0x60,
      #|    0x00,
      #|    0x20,
      #|    0xd4,
      #|    0x10,
      #|    0xe0,
      #|    0xa9,
      #|    0x52,
      #|    0x01,
      #|    0x02,
      #|    0x27,
      #|    0x1e,
      #|    0x40,
      #|    0x20,
      #|    0x21,
      #|    0x1e,
      #|    0x4b,
      #|    0x00,
      #|    0x00,
      #|    0x54,
      #|    0x60,
      #|    0x00,
      #|    0x20,
      #|    0xd4,
      #|    0x40,
      #|    0x00,
      #|    0x38,
      #|    0x1e,
      #|    0x01,
      #|    0x00,
      #|    0x79,
      #|    0x9e,
      #|    0xc0,
      #|    0x03,
      #|    0x5f,
      #|    0xd6,
      #|  ],
      #|  relocations: [],
      #|  sources: [
      #|    { offset: 20, source: { file: "convert.wat", line: 6, column: 9 } },
      #|    { offset: 40, source: { file: "convert.wat", line: 6, column: 9 } },
      #|    { offset: 60, source: { file: "convert.wat", line: 6, column: 9 } },
      #|    { offset: 64, source: { file: "convert.wat", line: 6, column: 9 } },
      #|  ],
      #|  traps: [
      #|    {
      #|      offset: 20,
      #|      reason: InvalidConversionToInteger,
      #|      source: Some({ file: "convert.wat", line: 6, column: 9 }),
      #|    },
      #|    {
      #|      offset: 40,
      #|      reason: InvalidConversionToInteger,
      #|      source: Some({ file: "convert.wat", line: 6, column: 9 }),
      #|    },
      #|    {
      #|      offset: 60,
      #|      reason: InvalidConversionToInteger,
      #|      source: Some({ file: "convert.wat", line: 6, column: 9 }),
      #|    },
      #|  ],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "AArch64 edge emission resolves register cycles through reserved scratch" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new_with_results(
    "edge_cycle",
    [I64, I64],
    [I64],
  )
  let entry = builder.entry_block()
  let exit = builder.create_block([I64, I64])
  let first = builder.parameter(0)
  let second = builder.parameter(1)
  builder.set_terminator(
    entry,
    Jump,
    [],
    [@vcode.Edge::new(exit, [first, second])],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let exit_first = builder.block_parameter(exit, 0)
  let exit_second = builder.block_parameter(exit, 1)
  let (outgoing, _) = builder.append_body(
    exit,
    OutgoingReg(I64, @vcode.PhysicalReg::new(0, Int)),
    [@vcode.Input::any(exit_first)],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  builder.set_terminator(
    exit,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  let allocation = @vcode.Allocation::for_function(function)
  let int0 = @vcode.PhysicalReg::new(0, Int)
  let int1 = @vcode.PhysicalReg::new(1, Int)
  allocation.assign_value(first, Register(int0)) |> ignore
  allocation.assign_value(second, Register(int1)) |> ignore
  allocation.assign_value(exit_first, Register(int1)) |> ignore
  allocation.assign_value(exit_second, Register(int0)) |> ignore
  allocation.assign_operand(outgoing, 0, int1) |> ignore
  allocation.add_edit(
    @vcode.Edit::edge_move(entry, 0, first, Register(int0), Register(int1)),
  )
  |> ignore
  allocation.add_edit(
    @vcode.Edit::edge_move(entry, 0, second, Register(int1), Register(int0)),
  )
  |> ignore
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: AArch64,
      #|  code: [
      #|    0xf0,
      #|    0x03,
      #|    0x01,
      #|    0xaa,
      #|    0xe1,
      #|    0x03,
      #|    0x00,
      #|    0xaa,
      #|    0xe0,
      #|    0x03,
      #|    0x10,
      #|    0xaa,
      #|    0x01,
      #|    0x00,
      #|    0x00,
      #|    0x14,
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
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}
