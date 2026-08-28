///|
test "X64 pipeline emits an allocated scalar function" {
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
      #|  architecture: X64,
      #|  code: [0x48, 0x89, 0xf8, 0x48, 0x01, 0xf0, 0xc3],
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
test "X64 compile runs the complete target pipeline" {
  let builder = @semantic.FunctionBuilder::new(
    "compiled_add",
    Platform,
    [I64, I64],
    [I64],
  )
  let sum = builder.emit(IntBinary(Add), builder.parameters(), [I64])[0]
  builder.return_([sum])
  let selection_events : Array[@vcode.TargetCompileEvent] = []
  let selected = select(builder.finish(), test_lowering_context(), on_event=event => {
    selection_events.push(event)
  })
  debug_inspect(
    selection_events,
    content=(
      #|[
      #|  TargetConstructionStarted,
      #|  TargetSealingStarted,
      #|  TargetSelectionFinished,
      #|]
    ),
  )
  let events : Array[@vcode.TargetCompileEvent] = []
  let (object, frame_size) = compile_selected(selected, on_event=fn(event) {
    events.push(event)
  })
  debug_inspect(
    object.code(),
    content=(
      #|[0x48, 0x89, 0xf8, 0x48, 0x01, 0xf0, 0xc3]
    ),
  )
  inspect(frame_size, content="0")
  debug_inspect(
    events,
    content=(
      #|[
      #|  RegallocStarted,
      #|  RegallocPhaseStarted("function_view"),
      #|  RegallocPhaseStarted("input_validation"),
      #|  RegallocPhaseStarted("live_ranges"),
      #|  RegallocPhaseStarted("segment_construction"),
      #|  RegallocPhaseStarted("bundle_formation"),
      #|  RegallocPhaseStarted("bundle_allocation"),
      #|  RegallocLoopMeasured(
      #|    {
      #|      queue_pops: 5,
      #|      register_probes: 5,
      #|      occupied_segments_scanned: 1,
      #|      conflicts: 0,
      #|      evictions: 0,
      #|      bundle_splits: 0,
      #|      second_chance_attempts: 0,
      #|      max_queue_length: 5,
      #|    },
      #|  ),
      #|  RegallocPhaseStarted("home_assignment"),
      #|  RegallocPhaseStarted("operand_assignment"),
      #|  RegallocPhaseStarted("edge_transfers"),
      #|  RegallocPhaseStarted("edit_resolution"),
      #|  RegallocPhaseStarted("verification"),
      #|  RegallocPhasesFinished,
      #|  RegallocFinished(
      #|    {
      #|      spill_slots: 0,
      #|      spills: 0,
      #|      reloads: 0,
      #|      reg_moves: 0,
      #|      spill_to_spill: 0,
      #|    },
      #|  ),
      #|  FramePlanningStarted,
      #|  FramePlanningFinished,
      #|  EmissionStarted,
      #|  EmissionFinished,
      #|]
    ),
  )
}

///|
test "X64 pipeline emits masked scalar shifts" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_i32_shift",
    Platform,
    [I32, I32],
    [I32],
  )
  let shifted = builder.emit(IntBinary(ShiftLeft), builder.parameters(), [I32])[0]
  builder.return_([shifted])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: X64,
      #|  code: [0x89, 0xf8, 0x89, 0xf1, 0xd3, 0xe0, 0xc3],
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
test "X64 pipeline preserves constant i32 shift operands" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_constant_i32_shift",
    Platform,
    [],
    [I32],
  )
  let one = builder.emit(I32Const(1U), [], [I32])[0]
  let count = builder.emit(I32Const(32U), [], [I32])[0]
  let shifted = builder.emit(IntBinary(ShiftLeft), [one, count], [I32])[0]
  let ten = builder.emit(I32Const(10U), [], [I32])[0]
  let result = builder.emit(IntBinary(Add), [ten, shifted], [I32])[0]
  builder.return_([result])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: X64,
      #|  code: [
      #|    0x48,
      #|    0xb8,
      #|    0x01,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0xb9,
      #|    0x20,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0xd3,
      #|    0xe0,
      #|    0x48,
      #|    0xb9,
      #|    0x0a,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x41,
      #|    0x89,
      #|    0xca,
      #|    0x41,
      #|    0x01,
      #|    0xc2,
      #|    0x44,
      #|    0x89,
      #|    0xd0,
      #|    0xc3,
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
test "X64 pipeline preserves wrapped i32 branch conditions" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_wrapped_i32_branch",
    Platform,
    [],
    [I32],
  )
  let when_true = builder.create_block([])
  let when_false = builder.create_block([])
  let high = builder.emit(I32Const(0x80000000U), [], [I32])[0]
  let one = builder.emit(I32Const(1U), [], [I32])[0]
  let count = builder.emit(I32Const(31U), [], [I32])[0]
  let shifted = builder.emit(IntBinary(ShiftLeft), [one, count], [I32])[0]
  let condition = builder.emit(IntBinary(Add), [high, shifted], [I32])[0]
  builder.branch(condition, when_true, [], when_false, [])
  builder.switch_to_block(when_true)
  let taken = builder.emit(I32Const(1U), [], [I32])[0]
  builder.return_([taken])
  builder.switch_to_block(when_false)
  let not_taken = builder.emit(I32Const(42U), [], [I32])[0]
  builder.return_([not_taken])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: X64,
      #|  code: [
      #|    0x48,
      #|    0xb8,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x80,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0xb9,
      #|    0x01,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0xba,
      #|    0x1f,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x41,
      #|    0x89,
      #|    0xca,
      #|    0x89,
      #|    0xd1,
      #|    0x41,
      #|    0xd3,
      #|    0xe2,
      #|    0x44,
      #|    0x89,
      #|    0xd1,
      #|    0x01,
      #|    0xc8,
      #|    0x85,
      #|    0xc0,
      #|    0x0f,
      #|    0x85,
      #|    0x0b,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0xb8,
      #|    0x2a,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0xc3,
      #|    0x48,
      #|    0xb8,
      #|    0x01,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0xc3,
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
test "X64 pipeline emits chained scalar conversions" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_scalar_conversions",
    Platform,
    [I32],
    [I32],
  )
  let as_float = builder.emit(
      Convert(IntToFloat(I32, F32, Signed)),
      builder.parameters(),
      [F32],
    )[0]
  let as_integer = builder.emit(
      Convert(FloatToInt(F32, I32, Signed, Trapping)),
      [as_float],
      [I32],
    )[0]
  builder.return_([as_integer])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: X64,
      #|  code: [
      #|    0xf3,
      #|    0x0f,
      #|    0x2a,
      #|    0xc7,
      #|    0x0f,
      #|    0x2e,
      #|    0xc0,
      #|    0x0f,
      #|    0x8b,
      #|    0x03,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0xcc,
      #|    0x03,
      #|    0x00,
      #|    0x49,
      #|    0xba,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0xcf,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x66,
      #|    0x41,
      #|    0x0f,
      #|    0x6e,
      #|    0xca,
      #|    0x0f,
      #|    0x2e,
      #|    0xc1,
      #|    0x0f,
      #|    0x83,
      #|    0x03,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0xcc,
      #|    0x03,
      #|    0x00,
      #|    0x49,
      #|    0xba,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x4f,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x66,
      #|    0x41,
      #|    0x0f,
      #|    0x6e,
      #|    0xca,
      #|    0x0f,
      #|    0x2e,
      #|    0xc1,
      #|    0x0f,
      #|    0x82,
      #|    0x03,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0xcc,
      #|    0x03,
      #|    0x00,
      #|    0xf3,
      #|    0x0f,
      #|    0x2c,
      #|    0xc0,
      #|    0xc3,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [
      #|    { offset: 13, reason: InvalidConversionToInteger, source: None },
      #|    { offset: 40, reason: InvalidConversionToInteger, source: None },
      #|    { offset: 67, reason: InvalidConversionToInteger, source: None },
      #|  ],
      #|  safepoints: [],
      #|  unwind: [],
      #|}
    ),
  )
}

///|
test "X64 pipeline emits every saturating scalar float conversion" {
  let cases : Array[
    (@semantic.FloatType, @semantic.IntegerType, @semantic.Signedness),
  ] = [
    (F32, I32, Signed),
    (F32, I32, Unsigned),
    (F32, I64, Signed),
    (F32, I64, Unsigned),
    (F64, I32, Signed),
    (F64, I32, Unsigned),
    (F64, I64, Signed),
    (F64, I64, Unsigned),
  ]
  let objects : Array[@code_object.UnlinkedCodeObject] = []
  for index, conversion in cases {
    let (float, integer, signedness) = conversion
    let source_type : @semantic.ValueType = if float == F32 { F32 } else { F64 }
    let result_type : @semantic.ValueType = if integer == I32 {
      I32
    } else {
      I64
    }
    let builder = @semantic.FunctionBuilder::new(
      "saturating_float_to_int_\{index}",
      Platform,
      [source_type],
      [result_type],
    )
    let result = builder.emit(
        Convert(FloatToInt(float, integer, signedness, Saturating)),
        builder.parameters(),
        [result_type],
      )[0]
    builder.return_([result])
    let function = lower(builder.finish(), test_lowering_context())
    let allocation = allocate(function)
    let frame = plan_frame(function, allocation)
    objects.push(emit(function, allocation, frame))
  }
  debug_inspect(
    objects,
    content=(
      #|[
      #|  {
      #|    architecture: X64,
      #|    code: [
      #|      0x0f,
      #|      0x2e,
      #|      0xc0,
      #|      0x0f,
      #|      0x8a,
      #|      0x3b,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xcf,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x66,
      #|      0x45,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x82,
      #|      0x31,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x4f,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x66,
      #|      0x45,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x83,
      #|      0x27,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xf3,
      #|      0x0f,
      #|      0x2c,
      #|      0xc0,
      #|      0xe9,
      #|      0x28,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe9,
      #|      0x19,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x80,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe9,
      #|      0x0a,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0x7f,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xc3,
      #|    ],
      #|    relocations: [],
      #|    sources: [],
      #|    traps: [],
      #|    safepoints: [],
      #|    unwind: [],
      #|  },
      #|  {
      #|    architecture: X64,
      #|    code: [
      #|      0x0f,
      #|      0x2e,
      #|      0xc0,
      #|      0x0f,
      #|      0x8a,
      #|      0x3c,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x66,
      #|      0x45,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x86,
      #|      0x23,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x80,
      #|      0x4f,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x66,
      #|      0x45,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x83,
      #|      0x19,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xf3,
      #|      0x48,
      #|      0x0f,
      #|      0x2c,
      #|      0xc0,
      #|      0xe9,
      #|      0x19,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe9,
      #|      0x0a,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xc3,
      #|    ],
      #|    relocations: [],
      #|    sources: [],
      #|    traps: [],
      #|    safepoints: [],
      #|    unwind: [],
      #|  },
      #|  {
      #|    architecture: X64,
      #|    code: [
      #|      0x0f,
      #|      0x2e,
      #|      0xc0,
      #|      0x0f,
      #|      0x8a,
      #|      0x3c,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xdf,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x66,
      #|      0x45,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x82,
      #|      0x32,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x5f,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x66,
      #|      0x45,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x83,
      #|      0x28,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xf3,
      #|      0x48,
      #|      0x0f,
      #|      0x2c,
      #|      0xc0,
      #|      0xe9,
      #|      0x28,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe9,
      #|      0x19,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x80,
      #|      0xe9,
      #|      0x0a,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0x7f,
      #|      0xc3,
      #|    ],
      #|    relocations: [],
      #|    sources: [],
      #|    traps: [],
      #|    safepoints: [],
      #|    unwind: [],
      #|  },
      #|  {
      #|    architecture: X64,
      #|    code: [
      #|      0x0f,
      #|      0x2e,
      #|      0xc0,
      #|      0x0f,
      #|      0x8a,
      #|      0x76,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x66,
      #|      0x45,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x86,
      #|      0x5d,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x80,
      #|      0x5f,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x66,
      #|      0x45,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x83,
      #|      0x53,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x5f,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x66,
      #|      0x45,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x82,
      #|      0x21,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xf3,
      #|      0x44,
      #|      0x0f,
      #|      0x10,
      #|      0xf0,
      #|      0xf3,
      #|      0x45,
      #|      0x0f,
      #|      0x5c,
      #|      0xf7,
      #|      0xf3,
      #|      0x49,
      #|      0x0f,
      #|      0x2c,
      #|      0xc6,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x80,
      #|      0x4c,
      #|      0x09,
      #|      0xd0,
      #|      0xe9,
      #|      0x05,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xf3,
      #|      0x48,
      #|      0x0f,
      #|      0x2c,
      #|      0xc0,
      #|      0xe9,
      #|      0x19,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe9,
      #|      0x0a,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xc3,
      #|    ],
      #|    relocations: [],
      #|    sources: [],
      #|    traps: [],
      #|    safepoints: [],
      #|    unwind: [],
      #|  },
      #|  {
      #|    architecture: X64,
      #|    code: [
      #|      0x66,
      #|      0x0f,
      #|      0x2e,
      #|      0xc0,
      #|      0x0f,
      #|      0x8a,
      #|      0x3d,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe0,
      #|      0xc1,
      #|      0x66,
      #|      0x4d,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x66,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x82,
      #|      0x32,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe0,
      #|      0x41,
      #|      0x66,
      #|      0x4d,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x66,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x83,
      #|      0x27,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xf2,
      #|      0x0f,
      #|      0x2c,
      #|      0xc0,
      #|      0xe9,
      #|      0x28,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe9,
      #|      0x19,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x80,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe9,
      #|      0x0a,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0x7f,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xc3,
      #|    ],
      #|    relocations: [],
      #|    sources: [],
      #|    traps: [],
      #|    safepoints: [],
      #|    unwind: [],
      #|  },
      #|  {
      #|    architecture: X64,
      #|    code: [
      #|      0x66,
      #|      0x0f,
      #|      0x2e,
      #|      0xc0,
      #|      0x0f,
      #|      0x8a,
      #|      0x3e,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x66,
      #|      0x4d,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x66,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x86,
      #|      0x24,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xf0,
      #|      0x41,
      #|      0x66,
      #|      0x4d,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x66,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x83,
      #|      0x19,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xf2,
      #|      0x48,
      #|      0x0f,
      #|      0x2c,
      #|      0xc0,
      #|      0xe9,
      #|      0x19,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe9,
      #|      0x0a,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xc3,
      #|    ],
      #|    relocations: [],
      #|    sources: [],
      #|    traps: [],
      #|    safepoints: [],
      #|    unwind: [],
      #|  },
      #|  {
      #|    architecture: X64,
      #|    code: [
      #|      0x66,
      #|      0x0f,
      #|      0x2e,
      #|      0xc0,
      #|      0x0f,
      #|      0x8a,
      #|      0x3e,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe0,
      #|      0xc3,
      #|      0x66,
      #|      0x4d,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x66,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x82,
      #|      0x33,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe0,
      #|      0x43,
      #|      0x66,
      #|      0x4d,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x66,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x83,
      #|      0x28,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xf2,
      #|      0x48,
      #|      0x0f,
      #|      0x2c,
      #|      0xc0,
      #|      0xe9,
      #|      0x28,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe9,
      #|      0x19,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x80,
      #|      0xe9,
      #|      0x0a,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0x7f,
      #|      0xc3,
      #|    ],
      #|    relocations: [],
      #|    sources: [],
      #|    traps: [],
      #|    safepoints: [],
      #|    unwind: [],
      #|  },
      #|  {
      #|    architecture: X64,
      #|    code: [
      #|      0x66,
      #|      0x0f,
      #|      0x2e,
      #|      0xc0,
      #|      0x0f,
      #|      0x8a,
      #|      0x79,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x66,
      #|      0x4d,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x66,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x86,
      #|      0x5f,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xf0,
      #|      0x43,
      #|      0x66,
      #|      0x4d,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x66,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x83,
      #|      0x54,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe0,
      #|      0x43,
      #|      0x66,
      #|      0x4d,
      #|      0x0f,
      #|      0x6e,
      #|      0xfa,
      #|      0x66,
      #|      0x41,
      #|      0x0f,
      #|      0x2e,
      #|      0xc7,
      #|      0x0f,
      #|      0x82,
      #|      0x21,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xf2,
      #|      0x44,
      #|      0x0f,
      #|      0x10,
      #|      0xf0,
      #|      0xf2,
      #|      0x45,
      #|      0x0f,
      #|      0x5c,
      #|      0xf7,
      #|      0xf2,
      #|      0x49,
      #|      0x0f,
      #|      0x2c,
      #|      0xc6,
      #|      0x49,
      #|      0xba,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x80,
      #|      0x4c,
      #|      0x09,
      #|      0xd0,
      #|      0xe9,
      #|      0x05,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xf2,
      #|      0x48,
      #|      0x0f,
      #|      0x2c,
      #|      0xc0,
      #|      0xe9,
      #|      0x19,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0xe9,
      #|      0x0a,
      #|      0x00,
      #|      0x00,
      #|      0x00,
      #|      0x48,
      #|      0xb8,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xff,
      #|      0xc3,
      #|    ],
      #|    relocations: [],
      #|    sources: [],
      #|    traps: [],
      #|    safepoints: [],
      #|    unwind: [],
      #|  },
      #|]
    ),
  )
}

///|
test "X64 pipeline emits scalar float and vector operations" {
  let builder = @semantic.FunctionBuilder::new(
    "emitted_float_vector",
    Platform,
    [F32, F32, V128, V128],
    [V128],
  )
  let parameters = builder.parameters()
  let scalar = builder.emit(FloatBinary(Min), [parameters[0], parameters[1]], [
      F32,
    ])[0]
  scalar |> ignore
  let vector = builder.emit(
      Vector(IntBinary(I32x4, Add)),
      [parameters[2], parameters[3]],
      [V128],
    )[0]
  builder.return_([vector])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: X64,
      #|  code: [0x0f, 0x28, 0xc2, 0x66, 0x0f, 0xfe, 0xc3, 0xc3],
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
test "X64 pipeline emits internal result-area calls" {
  let types : Array[@semantic.ValueType] = [I64, I64, I64, F32, F64, V128]
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
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: X64,
      #|  code: [
      #|    0x55,
      #|    0x48,
      #|    0x89,
      #|    0xe5,
      #|    0x48,
      #|    0x81,
      #|    0xec,
      #|    0x30,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x89,
      #|    0x9c,
      #|    0x24,
      #|    0x20,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x4c,
      #|    0x89,
      #|    0xd3,
      #|    0x49,
      #|    0x89,
      #|    0xe2,
      #|    0xe8,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x8b,
      #|    0x8c,
      #|    0x24,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0xf3,
      #|    0x0f,
      #|    0x6f,
      #|    0x94,
      #|    0x24,
      #|    0x10,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x89,
      #|    0x8b,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0xf3,
      #|    0x0f,
      #|    0x7f,
      #|    0x93,
      #|    0x10,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x8b,
      #|    0x9c,
      #|    0x24,
      #|    0x20,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x81,
      #|    0xc4,
      #|    0x30,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x5d,
      #|    0xc3,
      #|  ],
      #|  relocations: [
      #|    {
      #|      offset: 26,
      #|      kind: X64PcRelative32,
      #|      target: Code({ name: "wasm.func.result_area" }),
      #|      addend: 0,
      #|    },
      #|  ],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [
      #|    { offset: 1, operation: StackAlloc(size=8) },
      #|    { offset: 1, operation: SaveRegister(Int, 5, cfa_offset=-16) },
      #|    { offset: 4, operation: SetFramePointer(Int, 5, cfa_offset=16) },
      #|    { offset: 11, operation: StackAlloc(size=48) },
      #|    { offset: 19, operation: SaveRegister(Int, 3, cfa_offset=-32) },
      #|  ],
      #|}
    ),
  )
}

///|
test "X64 pipeline emits indirect internal result-area calls" {
  let result_types : Array[@semantic.ValueType] = [I32, I32, I32]
  let builder = @semantic.FunctionBuilder::new(
    "emitted_indirect_internal_result_area",
    Internal,
    [Ptr64, Ptr64],
    result_types,
  )
  let parameters = builder.parameters()
  let call = @semantic.SemanticCall::new(
    Indirect,
    @semantic.Signature::new([Ptr64], result_types),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  let results = builder.emit(
    Call(call),
    [parameters[1], parameters[0]],
    result_types,
  )
  builder.return_(results)
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: X64,
      #|  code: [
      #|    0x55,
      #|    0x48,
      #|    0x89,
      #|    0xe5,
      #|    0x48,
      #|    0x81,
      #|    0xec,
      #|    0x20,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x89,
      #|    0x9c,
      #|    0x24,
      #|    0x10,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x4c,
      #|    0x89,
      #|    0xd3,
      #|    0x48,
      #|    0x89,
      #|    0xf0,
      #|    0x49,
      #|    0x89,
      #|    0xe2,
      #|    0xff,
      #|    0xd0,
      #|    0x8b,
      #|    0x8c,
      #|    0x24,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x89,
      #|    0x8b,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x8b,
      #|    0x9c,
      #|    0x24,
      #|    0x10,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x81,
      #|    0xc4,
      #|    0x20,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x5d,
      #|    0xc3,
      #|  ],
      #|  relocations: [],
      #|  sources: [],
      #|  traps: [],
      #|  safepoints: [],
      #|  unwind: [
      #|    { offset: 1, operation: StackAlloc(size=8) },
      #|    { offset: 1, operation: SaveRegister(Int, 5, cfa_offset=-16) },
      #|    { offset: 4, operation: SetFramePointer(Int, 5, cfa_offset=16) },
      #|    { offset: 11, operation: StackAlloc(size=32) },
      #|    { offset: 19, operation: SaveRegister(Int, 3, cfa_offset=-32) },
      #|  ],
      #|}
    ),
  )
}

///|
test "X64 pipeline forwards result areas through internal tail calls" {
  let types : Array[@semantic.ValueType] = [I64, I64, I64, F32, F64, V128]
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
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  debug_inspect(
    emit(function, allocation, frame),
    content=(
      #|{
      #|  architecture: X64,
      #|  code: [0x4c, 0x89, 0xd0, 0x49, 0x89, 0xc2, 0xe9, 0x00, 0x00, 0x00, 0x00],
      #|  relocations: [
      #|    {
      #|      offset: 7,
      #|      kind: X64PcRelative32,
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
test "X64 calls zero-extend stack i32 arguments" {
  let parameter_types : Array[@semantic.ValueType] = [
    Ptr64,
    I32,
    I32,
    I32,
    I32,
    I32,
    I32,
  ]
  let builder = @semantic.FunctionBuilder::new(
    "emitted_i32_stack_call",
    Internal,
    [Ptr64],
    [],
  )
  let operands = [builder.parameters()[0]]
  for index in 0..<6 {
    operands.push(
      builder.emit(I32Const(index.reinterpret_as_uint()), [], [I32])[0],
    )
  }
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.i32_stack_args")),
    @semantic.Signature::new(parameter_types, []),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.emit(Call(call), operands, []) |> ignore
  builder.return_([])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  let code = emit(function, allocation, frame).code()
  debug_inspect(
    code[71:79].to_owned(),
    content="[0x48, 0x89, 0x84, 0x24, 0x00, 0x00, 0x00, 0x00]",
  )
}

///|
/// A counted loop whose back edge carries block arguments through a split
/// edge block. With coalesced allocation that block is a bare forwarding
/// jump, and the loop's conditional branch must target the loop head
/// directly instead of hopping through it every iteration.
test "X64 pipeline threads a moveless loop back edge to the loop head" {
  let builder = @semantic.FunctionBuilder::new(
    "threaded_back_edge",
    Platform,
    [I32],
    [I32],
  )
  let count = builder.parameters()[0]
  let loop_head = builder.create_block([I32, I32])
  let back_edge = builder.create_block([])
  let exit = builder.create_block([])
  let zero = builder.emit(I32Const(0U), [], [I32])[0]
  builder.jump(loop_head, [count, zero])
  builder.switch_to_block(loop_head)
  let n = builder.block_parameters(loop_head)[0]
  let x = builder.block_parameters(loop_head)[1]
  let three = builder.emit(I32Const(3U), [], [I32])[0]
  let one = builder.emit(I32Const(1U), [], [I32])[0]
  let next_x = builder.emit(IntBinary(Add), [x, three], [I32])[0]
  let next_n = builder.emit(IntBinary(Sub), [n, one], [I32])[0]
  builder.branch(next_n, back_edge, [], exit, [])
  builder.switch_to_block(back_edge)
  builder.jump(loop_head, [next_n, next_x])
  builder.switch_to_block(exit)
  builder.return_([next_x])
  let selected = lower(builder.finish(), test_lowering_context())
  let (object, _) = compile(selected)
  // Find every jcc rel32 (0x0F 0x8x) and record its resolved target. The
  // loop's conditional branch must resolve backward to the loop body, and
  // the byte at its target must not be an unconditional jmp (0xE9), which
  // would mean the edge still hops through the forwarding block.
  let code = object.code()
  let branch_targets : Array[(Int, Int)] = []
  for offset in 0..<(code.length() - 5) {
    if code[offset] == b'\x0F' && (code[offset + 1].to_int() & 0xF0) == 0x80 {
      let rel = code[offset + 2].to_int() |
        (code[offset + 3].to_int() << 8) |
        (code[offset + 4].to_int() << 16) |
        (code[offset + 5].to_int() << 24)
      branch_targets.push((offset, offset + 6 + rel))
    }
  }
  guard branch_targets is [(branch_offset, target_offset)] else {
    fail("expected exactly one conditional branch, got \{Repr(branch_targets)}")
  }
  debug_inspect(target_offset < branch_offset, content="true")
  // Pin the exact destination byte offset of the loop body's first
  // instruction; a merely-backward target would accept a miscompile.
  inspect(target_offset, content="10")
}

///|
/// The refusal side of back-edge threading: with parallel moves pending on
/// the forwarding block's jump, the conditional branch must keep routing
/// through it. One value feeding both loop parameters forces at least one
/// move regardless of register assignment.
test "X64 pipeline keeps a loop back edge with moves unthreaded" {
  let builder = @semantic.FunctionBuilder::new(
    "unthreaded_back_edge",
    Platform,
    [I32],
    [I32],
  )
  let count = builder.parameters()[0]
  let loop_head = builder.create_block([I32, I32])
  let back_edge = builder.create_block([])
  let exit = builder.create_block([])
  let zero = builder.emit(I32Const(0U), [], [I32])[0]
  builder.jump(loop_head, [count, zero])
  builder.switch_to_block(loop_head)
  let n = builder.block_parameters(loop_head)[0]
  let x = builder.block_parameters(loop_head)[1]
  let three = builder.emit(I32Const(3U), [], [I32])[0]
  let one = builder.emit(I32Const(1U), [], [I32])[0]
  let next_x = builder.emit(IntBinary(Add), [x, three], [I32])[0]
  let next_n = builder.emit(IntBinary(Sub), [n, one], [I32])[0]
  builder.branch(next_n, back_edge, [], exit, [])
  builder.switch_to_block(back_edge)
  builder.jump(loop_head, [next_n, next_n])
  builder.switch_to_block(exit)
  builder.return_([next_x])
  let selected = lower(builder.finish(), test_lowering_context())
  let (object, _) = compile(selected)
  let code = object.code()
  let branch_targets : Array[(Int, Int)] = []
  for offset in 0..<(code.length() - 5) {
    if code[offset] == b'\x0F' && (code[offset + 1].to_int() & 0xF0) == 0x80 {
      let rel = code[offset + 2].to_int() |
        (code[offset + 3].to_int() << 8) |
        (code[offset + 4].to_int() << 16) |
        (code[offset + 5].to_int() << 24)
      branch_targets.push((offset, offset + 6 + rel))
    }
  }
  guard branch_targets is [(_, target_offset)] else {
    fail("expected exactly one conditional branch, got \{Repr(branch_targets)}")
  }
  // Offset 10 is the loop body's first instruction, as pinned by the
  // threading test above; with moves pending it must not be the target.
  debug_inspect(target_offset == 10, content="false")
}

///|
fn x64_test_contains_bytes(code : Array[Byte], expected : Array[Byte]) -> Bool {
  if expected.is_empty() {
    return true
  }
  if expected.length() > code.length() {
    return false
  }
  for start in 0..<=(code.length() - expected.length()) {
    let mut matches = true
    for offset in 0..<expected.length() {
      if code[start + offset] != expected[offset] {
        matches = false
        break
      }
    }
    if matches {
      return true
    }
  }
  false
}

///|
test "X64 expanded tail calls preserve SysV callee-entry alignment" {
  let builder = @semantic.FunctionBuilder::new(
    "expanded_tail_alignment",
    Internal,
    [Ptr64],
    [],
  )
  let operands = [builder.parameters()[0]]
  for index in 0..<8 {
    operands.push(builder.emit(I64Const(index.to_uint64()), [], [I64])[0])
  }
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.expanded_tail_callee")),
    @semantic.Signature::new([Ptr64, I64, I64, I64, I64, I64, I64, I64, I64], []),
    Internal,
    @semantic.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  builder.tail_call(call, operands)
  let selected = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(selected)
  let frame = plan_frame(selected, allocation)
  inspect(
    frame.summary(),
    content=(
      #|x64 frame size=56 align=16
      #|  tail-args 32 bytes at sp+16
      #|  tail-transfer return=8 padding=8 adjust=48 cleanup=40
      #|  save p3:int at sp+0
      #|  save p12:int at sp+8
      #|
    ),
  )
  let code = emit(selected, allocation, frame).code()
  let subtracts_aligned_transfer = x64_test_contains_bytes(code, [
    0x5D, 0x48, 0x81, 0xEC, 0x30, 0x00, 0x00, 0x00,
  ])
  let thunk_discards_arguments_and_padding = x64_test_contains_bytes(code, [
    0x48, 0x81, 0xC4, 0x28, 0x00, 0x00, 0x00,
  ])
  debug_inspect(
    (subtracts_aligned_transfer, thunk_discards_arguments_and_padding),
    content="(true, true)",
  )
}
