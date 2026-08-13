///|
test "x64 target allocates selected scalar VCode" {
  let builder = @semantic.FunctionBuilder::new(
    "allocated_add",
    Internal,
    [Ptr64, I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let sum = builder.emit(IntBinary(Add), [parameters[1], parameters[2]], [I64])[0]
  builder.return_([sum])
  let selected = lower(builder.finish(), test_lowering_context())
  inspect(
    allocate(selected).summary(),
    content=(
      #|allocation allocated_add
      #|  v0:ptr64 -> p7:int
      #|  v1:i64 -> p6:int
      #|  v2:i64 -> p2:int
      #|  v3:ptr64 -> p7:int
      #|  v4:i64 -> p6:int
      #|  v5:i64 -> p2:int
      #|  v6:i64 -> p0:int
      #|  i0 operand0 -> p7:int
      #|  i0 operand1 -> p7:int
      #|  i1 operand0 -> p6:int
      #|  i1 operand1 -> p6:int
      #|  i2 operand0 -> p2:int
      #|  i2 operand1 -> p2:int
      #|  i3 operand0 -> p6:int
      #|  i3 operand1 -> p2:int
      #|  i3 operand2 -> p0:int
      #|  i4 operand0 -> p0:int
      #|
    ),
  )
}

///|
test "x64 frame reserves emergency move storage only when required" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "emergency_move_frame",
    [I64, I64],
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
  builder.set_terminator(
    exit,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let exit_first = builder.block_parameter(exit, 0)
  let exit_second = builder.block_parameter(exit, 1)
  let function = builder.finish()
  let allocation = @vcode.Allocation::for_function(function)
  let stack0 = allocation.create_stack_slot(I64, 8, 8)
  let stack1 = allocation.create_stack_slot(I64, 8, 8)
  allocation.assign_value(first, Stack(stack0)) |> ignore
  allocation.assign_value(second, Stack(stack1)) |> ignore
  allocation.assign_value(exit_first, Stack(stack1)) |> ignore
  allocation.assign_value(exit_second, Stack(stack0)) |> ignore
  allocation.add_edit(
    @vcode.Edit::edge_move(entry, 0, first, Stack(stack0), Stack(stack1)),
  )
  |> ignore
  allocation.add_edit(
    @vcode.Edit::edge_move(entry, 0, second, Stack(stack1), Stack(stack0)),
  )
  |> ignore
  let frame = plan_frame(function, allocation)
  assert_eq(frame.emergency_move_offset(), Some(0))
  inspect(
    frame.summary(),
    content=(
      #|x64 frame size=40 align=16
      #|  emergency-move 16 bytes at sp+0
      #|  place stack0 at sp+16
      #|  place stack1 at sp+24
      #|
    ),
  )
  emit(function, allocation, frame) |> ignore
}
