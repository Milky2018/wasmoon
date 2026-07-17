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
      #|    },
      #|  ],
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
test "AArch64 true tail calls forward compatible incoming stack arguments" {
  let parameter_types : Array[@semantic.ValueType] = [
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
    parameter_types,
    [],
  )
  let call = @semantic.SemanticCall::new(
    Internal(@semantic.CodeSymbol::new("wasm.func.12")),
    @semantic.Signature::new(parameter_types, []),
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
      #|    0x03,
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
      #|    0x14,
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
