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
test "x64 allocation rejects transfer scratch as an unconstrained operand" {
  let builder = @semantic.FunctionBuilder::new(
    "illegal_transfer_operand",
    Internal,
    [Ptr64, I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let sum = builder.emit(IntBinary(Add), [parameters[1], parameters[2]], [I64])[0]
  builder.return_([sum])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let instruction = function.instruction_at(3).unwrap()
  let operand = function.instruction_operand_at(instruction, 0).unwrap()
  let home = match allocation.value_location(operand.value).unwrap() {
    Register(home) => home
    Stack(_) => fail("expected the source value to have a register home")
  }
  let transfer = @vcode.PhysicalReg::new(15, Int)
  assert_true(allocation.assign_operand(instruction, 0, transfer))
  assert_true(
    allocation.add_edit(
      @vcode.Edit::register_move(
        function.before(instruction).unwrap(),
        operand.value,
        home,
        transfer,
      ),
    ),
  )
  let error = try {
    verify_allocation(function, allocation)
    None
  } catch {
    error => Some(error)
  }
  debug_inspect(error, content="Some(IllegalRegister(reg=p15:int))")
}

///|
test "x64 allocation rejects transfer scratch in an allocator edit" {
  let builder = @semantic.FunctionBuilder::new(
    "illegal_transfer_edit",
    Internal,
    [Ptr64, I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let sum = builder.emit(IntBinary(Add), [parameters[1], parameters[2]], [I64])[0]
  builder.return_([sum])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let instruction = function.instruction_at(3).unwrap()
  let operand = function.instruction_operand_at(instruction, 0).unwrap()
  let home = match allocation.value_location(operand.value).unwrap() {
    Register(home) => home
    Stack(_) => fail("expected the source value to have a register home")
  }
  assert_true(
    allocation.add_edit(
      @vcode.Edit::register_move(
        function.before(instruction).unwrap(),
        operand.value,
        home,
        @vcode.PhysicalReg::new(15, Int),
      ),
    ),
  )
  let error = try {
    verify_allocation(function, allocation)
    None
  } catch {
    error => Some(error)
  }
  debug_inspect(error, content="Some(IllegalRegister(reg=p15:int))")
}

///|
test "x64 allocation rejects emitter scratch as an unconstrained operand" {
  let builder = @semantic.FunctionBuilder::new(
    "illegal_emitter_operand",
    Internal,
    [Ptr64, F32, F32],
    [F32],
  )
  let parameters = builder.parameters()
  let sum = builder.emit(FloatBinary(Add), [parameters[1], parameters[2]], [F32])[0]
  builder.return_([sum])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let instruction = function.instruction_at(3).unwrap()
  let operand = function.instruction_operand_at(instruction, 0).unwrap()
  let home = match allocation.value_location(operand.value).unwrap() {
    Register(home) => home
    Stack(_) => fail("expected the source value to have a register home")
  }
  let emitter = @vcode.PhysicalReg::new(15, FpVector)
  assert_true(allocation.assign_operand(instruction, 0, emitter))
  assert_true(
    allocation.add_edit(
      @vcode.Edit::register_move(
        function.before(instruction).unwrap(),
        operand.value,
        home,
        emitter,
      ),
    ),
  )
  let error = try {
    verify_allocation(function, allocation)
    None
  } catch {
    error => Some(error)
  }
  debug_inspect(error, content="Some(IllegalRegister(reg=p15:fpvec))")
}

///|
test "x64 allocation rejects every reserved register as a value home" {
  let errors : Array[X64AllocationError?] = []
  let cases : Array[(@semantic.ValueType, @vcode.PhysicalReg)] = [
    (I64, @vcode.PhysicalReg::new(10, Int)),
    (I64, @vcode.PhysicalReg::new(11, Int)),
    (I64, @vcode.PhysicalReg::new(15, Int)),
    (F64, @vcode.PhysicalReg::new(13, FpVector)),
    (F64, @vcode.PhysicalReg::new(14, FpVector)),
    (F64, @vcode.PhysicalReg::new(15, FpVector)),
  ]
  for case in cases {
    let (ty, reg) = case
    let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
      "illegal_reserved_home",
      [ty],
    )
    let entry = builder.entry_block()
    builder.set_terminator(
      entry,
      Return,
      [],
      [],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
    let value = builder.parameter(0)
    let function = builder.finish()
    let allocation = @vcode.Allocation::for_function(function)
    assert_true(allocation.assign_value(value, Register(reg)))
    errors.push(
      try {
        verify_allocation(function, allocation)
        None
      } catch {
        error => Some(error)
      },
    )
  }
  debug_inspect(
    errors,
    content=(
      #|[
      #|  Some(IllegalRegister(reg=p10:int)),
      #|  Some(IllegalRegister(reg=p11:int)),
      #|  Some(IllegalRegister(reg=p15:int)),
      #|  Some(IllegalRegister(reg=p13:fpvec)),
      #|  Some(IllegalRegister(reg=p14:fpvec)),
      #|  Some(IllegalRegister(reg=p15:fpvec)),
      #|]
    ),
  )
}

///|
test "x64 allocation rejects emitter scratch in an allocator edit" {
  let builder = @semantic.FunctionBuilder::new(
    "illegal_emitter_edit",
    Internal,
    [Ptr64, F64, F64],
    [F64],
  )
  let parameters = builder.parameters()
  let sum = builder.emit(FloatBinary(Add), [parameters[1], parameters[2]], [F64])[0]
  builder.return_([sum])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let instruction = function.instruction_at(3).unwrap()
  let operand = function.instruction_operand_at(instruction, 0).unwrap()
  let home = match allocation.value_location(operand.value).unwrap() {
    Register(home) => home
    Stack(_) => fail("expected the source value to have a register home")
  }
  assert_true(
    allocation.add_edit(
      @vcode.Edit::register_move(
        function.before(instruction).unwrap(),
        operand.value,
        home,
        @vcode.PhysicalReg::new(15, FpVector),
      ),
    ),
  )
  let error = try {
    verify_allocation(function, allocation)
    None
  } catch {
    error => Some(error)
  }
  debug_inspect(error, content="Some(IllegalRegister(reg=p15:fpvec))")
}

///|
test "x64 allocation keeps spill scratch out of unconstrained operands" {
  let builder = @semantic.FunctionBuilder::new(
    "illegal_spill_scratch_operand",
    Internal,
    [Ptr64, I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let sum = builder.emit(IntBinary(Add), [parameters[1], parameters[2]], [I64])[0]
  builder.return_([sum])
  let function = lower(builder.finish(), test_lowering_context())
  let allocation = allocate(function)
  let instruction = function.instruction_at(3).unwrap()
  let operand = function.instruction_operand_at(instruction, 0).unwrap()
  let home = match allocation.value_location(operand.value).unwrap() {
    Register(home) => home
    Stack(_) => fail("expected the source value to have a register home")
  }
  let scratch = @vcode.PhysicalReg::new(10, Int)
  assert_true(allocation.assign_operand(instruction, 0, scratch))
  assert_true(
    allocation.add_edit(
      @vcode.Edit::register_move(
        function.before(instruction).unwrap(),
        operand.value,
        home,
        scratch,
      ),
    ),
  )
  let error = try {
    verify_allocation(function, allocation)
    None
  } catch {
    error => Some(error)
  }
  debug_inspect(error, content="Some(IllegalRegister(reg=p10:int))")
}

///|
test "x64 allocation admits spill scratch only between allocation edits" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "legal_spill_scratch_edit",
    [I64],
  )
  let entry = builder.entry_block()
  let value = builder.parameter(0)
  let (keep_alive, _) = builder.append_body(
    entry,
    KeepAlive(I64),
    [@vcode.Input::any(value)],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
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
  let allocation = @vcode.Allocation::for_function(function)
  let slot = allocation.create_stack_slot(I64, 8, 8)
  let scratch = @vcode.PhysicalReg::new(10, Int)
  let operand = @vcode.PhysicalReg::new(0, Int)
  assert_true(allocation.assign_value(value, Stack(slot)))
  assert_true(allocation.assign_operand(keep_alive, 0, operand))
  assert_true(
    allocation.add_edit(
      @vcode.Edit::reload(
        function.before(keep_alive).unwrap(),
        value,
        slot,
        scratch,
      ),
    ),
  )
  assert_true(
    allocation.add_edit(
      @vcode.Edit::register_move(
        function.before(keep_alive).unwrap(),
        value,
        scratch,
        operand,
      ),
    ),
  )
  verify_allocation(function, allocation)
}

///|
test "x64 allocation preserves fixed-only and spill-fixed operands" {
  let divide_builder = @semantic.FunctionBuilder::new(
    "legal_fixed_only_divisor",
    Platform,
    [I64, I64],
    [I64],
  )
  let quotient = divide_builder.emit(
      IntBinary(SignedDiv),
      divide_builder.parameters(),
      [I64],
    )[0]
  divide_builder.return_([quotient])
  let divide_function = lower(divide_builder.finish(), test_lowering_context())
  let divide_allocation = allocate(divide_function)
  let divide = divide_function.instruction_at(4).unwrap()
  assert_eq(
    divide_allocation.operand_location(divide, 1),
    Some(Register(@vcode.PhysicalReg::new(11, Int))),
  )
  verify_allocation(divide_function, divide_allocation)

  let store_builder = @semantic.FunctionBuilder::new(
    "legal_spill_fixed_store",
    Platform,
    [Ptr64, I32],
    [],
  )
  store_builder.emit(
    AtomicStore(
      @semantic.AtomicSpec::new(W32, I32, 0UL, Little, Some(MemoryOutOfBounds)),
    ),
    store_builder.parameters(),
    [],
  )
  |> ignore
  store_builder.return_([])
  let store_function = lower(store_builder.finish(), test_lowering_context())
  let store_allocation = allocate(store_function)
  let store = store_function.instruction_at(2).unwrap()
  assert_eq(
    store_allocation.operand_location(store, 1),
    Some(Register(@vcode.PhysicalReg::new(10, Int))),
  )
  verify_allocation(store_function, store_allocation)
}

///|
test "x64 allocation binds fixed-only edits to the constrained value" {
  let builder : @vcode.Builder[X64Inst] = @vcode.Builder::new(
    "fixed_only_edit_value",
    [I64, I64],
  )
  let entry = builder.entry_block()
  let dividend = builder.parameter(0)
  let divisor = builder.parameter(1)
  let rax = @vcode.PhysicalReg::new(0, Int)
  let rdx = @vcode.PhysicalReg::new(2, Int)
  let dividend_home = @vcode.PhysicalReg::new(6, Int)
  let divisor_home = @vcode.PhysicalReg::new(7, Int)
  let fixed_only = @vcode.PhysicalReg::new(11, Int)
  let (divide, results) = builder.append_body(
    entry,
    IntBinary(W64, Sdiv),
    [
      @vcode.Input::fixed(dividend, rax),
      @vcode.Input::fixed(divisor, fixed_only),
    ],
    [@vcode.Output::fixed(I64, rax)],
    [rdx],
    @vcode.InstructionMetadata::empty(),
  )
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
  let allocation = @vcode.Allocation::for_function(function)
  assert_true(allocation.assign_value(dividend, Register(dividend_home)))
  assert_true(allocation.assign_value(divisor, Register(divisor_home)))
  assert_true(allocation.assign_value(results[0], Register(rax)))
  assert_true(allocation.assign_operand(divide, 0, rax))
  assert_true(allocation.assign_operand(divide, 1, fixed_only))
  assert_true(allocation.assign_operand(divide, 2, rax))
  let before = function.before(divide).unwrap()
  assert_true(
    allocation.add_edit(
      @vcode.Edit::register_move(before, dividend, dividend_home, fixed_only),
    ),
  )
  assert_true(
    allocation.add_edit(
      @vcode.Edit::register_move(before, dividend, dividend_home, rax),
    ),
  )
  assert_true(
    allocation.add_edit(
      @vcode.Edit::register_move(before, divisor, divisor_home, fixed_only),
    ),
  )
  let error = try {
    verify_allocation(function, allocation)
    None
  } catch {
    error => Some(error)
  }
  debug_inspect(error, content="Some(IllegalRegister(reg=p11:int))")
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
