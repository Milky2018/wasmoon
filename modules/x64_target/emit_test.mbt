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
      #|  code: [
      #|    0x48,
      #|    0x89,
      #|    0xfa,
      #|    0x48,
      #|    0x89,
      #|    0xf0,
      #|    0x48,
      #|    0x89,
      #|    0xd1,
      #|    0x48,
      #|    0x01,
      #|    0xc1,
      #|    0x48,
      #|    0x89,
      #|    0xc8,
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
      #|  code: [
      #|    0xf3,
      #|    0x0f,
      #|    0x10,
      #|    0xe0,
      #|    0xf3,
      #|    0x0f,
      #|    0x10,
      #|    0xc1,
      #|    0x0f,
      #|    0x28,
      #|    0xc2,
      #|    0x0f,
      #|    0x28,
      #|    0xcb,
      #|    0x0f,
      #|    0x28,
      #|    0xd0,
      #|    0x66,
      #|    0x0f,
      #|    0xfe,
      #|    0xd1,
      #|    0x0f,
      #|    0x28,
      #|    0xc2,
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
      #|    0x48,
      #|    0x89,
      #|    0xf0,
      #|    0x48,
      #|    0x89,
      #|    0xd6,
      #|    0x4c,
      #|    0x89,
      #|    0xd3,
      #|    0xf3,
      #|    0x0f,
      #|    0x10,
      #|    0xd8,
      #|    0xf2,
      #|    0x0f,
      #|    0x10,
      #|    0xc1,
      #|    0x0f,
      #|    0x28,
      #|    0xca,
      #|    0x48,
      #|    0x89,
      #|    0xf2,
      #|    0x48,
      #|    0x89,
      #|    0xc6,
      #|    0x0f,
      #|    0x28,
      #|    0xd1,
      #|    0xf2,
      #|    0x0f,
      #|    0x10,
      #|    0xc8,
      #|    0xf3,
      #|    0x0f,
      #|    0x10,
      #|    0xc3,
      #|    0x49,
      #|    0x89,
      #|    0xe2,
      #|    0xe8,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x89,
      #|    0xd1,
      #|    0x48,
      #|    0x8b,
      #|    0x94,
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
      #|    0x93,
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
      #|    0x89,
      #|    0xca,
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
      #|      offset: 60,
      #|      kind: X64PcRelative32,
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
      #|  code: [
      #|    0x55,
      #|    0x48,
      #|    0x89,
      #|    0xe5,
      #|    0x48,
      #|    0x81,
      #|    0xec,
      #|    0x10,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x89,
      #|    0x9c,
      #|    0x24,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x89,
      #|    0xf0,
      #|    0x48,
      #|    0x89,
      #|    0xd6,
      #|    0x4c,
      #|    0x89,
      #|    0xd2,
      #|    0xf3,
      #|    0x0f,
      #|    0x10,
      #|    0xd8,
      #|    0xf2,
      #|    0x0f,
      #|    0x10,
      #|    0xc1,
      #|    0x0f,
      #|    0x28,
      #|    0xca,
      #|    0x49,
      #|    0x89,
      #|    0xd2,
      #|    0x48,
      #|    0x89,
      #|    0xf2,
      #|    0x48,
      #|    0x89,
      #|    0xc6,
      #|    0x0f,
      #|    0x28,
      #|    0xd1,
      #|    0xf2,
      #|    0x0f,
      #|    0x10,
      #|    0xc8,
      #|    0xf3,
      #|    0x0f,
      #|    0x10,
      #|    0xc3,
      #|    0x48,
      #|    0x8b,
      #|    0x9c,
      #|    0x24,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x48,
      #|    0x81,
      #|    0xc4,
      #|    0x10,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x5d,
      #|    0xe9,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|    0x00,
      #|  ],
      #|  relocations: [
      #|    {
      #|      offset: 76,
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
