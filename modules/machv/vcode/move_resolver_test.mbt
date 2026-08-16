///|
test "legacy parallel move resolver accepts empty inputs without scratch" {
  debug_inspect(resolve_parallel_moves([], [], []), content="[]")
}

///|
test "parallel move resolver preserves cycles and stack transfers" {
  let int0 = PhysicalReg::new(0, Int)
  let int1 = PhysicalReg::new(1, Int)
  let int16 = PhysicalReg::new(16, Int)
  let function : Builder[TestInst] = Builder::new("move_slots", [])
  let allocation = Allocation::for_function(function.finish())
  let stack0 = allocation.create_stack_slot(I64, 8, 8)
  let stack1 = allocation.create_stack_slot(I64, 8, 8)
  debug_inspect(
    resolve_parallel_moves(
      [
        ParallelMove::new(I64, Register(int0), Register(int1)),
        ParallelMove::new(I64, Register(int1), Register(int0)),
        ParallelMove::new(I64, Stack(stack0), Stack(stack1)),
      ],
      [int16],
      [PhysicalReg::new(16, FpVector)],
    ),
    content=(
      #|[
      #|  { ty: I64, from: stack0, to: p16:int },
      #|  { ty: I64, from: p16:int, to: stack1 },
      #|  { ty: I64, from: p1:int, to: p16:int },
      #|  { ty: I64, from: p0:int, to: p1:int },
      #|  { ty: I64, from: p16:int, to: p0:int },
      #|]
    ),
  )
}

///|
test "parallel move resolver shares the physical FP and SIMD bank" {
  let fp0 = PhysicalReg::new(0, FpVector)
  let fp1 = PhysicalReg::new(1, FpVector)
  let fp16 = PhysicalReg::new(16, FpVector)
  debug_inspect(
    resolve_parallel_moves(
      [
        ParallelMove::new(F32, Register(fp0), Register(fp1)),
        ParallelMove::new(V128, Register(fp1), Register(fp0)),
      ],
      [PhysicalReg::new(16, Int)],
      [fp16],
    ),
    content=(
      #|[
      #|  { ty: V128, from: p1:fpvec, to: p16:fpvec },
      #|  { ty: F32, from: p0:fpvec, to: p1:fpvec },
      #|  { ty: V128, from: p16:fpvec, to: p0:fpvec },
      #|]
    ),
  )
}

///|
test "parallel move resolver never reuses a final destination as scratch" {
  let int0 = PhysicalReg::new(0, Int)
  let int1 = PhysicalReg::new(1, Int)
  let int2 = PhysicalReg::new(2, Int)
  let int16 = PhysicalReg::new(16, Int)
  let int17 = PhysicalReg::new(17, Int)
  debug_inspect(
    resolve_parallel_moves(
      [
        ParallelMove::new(I64, Register(int0), Register(int1)),
        ParallelMove::new(I64, Register(int1), Register(int0)),
        ParallelMove::new(I64, Register(int2), Register(int16)),
      ],
      [int16, int17],
      [PhysicalReg::new(16, FpVector)],
    ),
    content=(
      #|[
      #|  { ty: I64, from: p2:int, to: p16:int },
      #|  { ty: I64, from: p1:int, to: p17:int },
      #|  { ty: I64, from: p0:int, to: p1:int },
      #|  { ty: I64, from: p17:int, to: p0:int },
      #|]
    ),
  )
}

///|
test "call transfer planner snapshots stack arguments before register cycles" {
  let int0 = PhysicalReg::new(0, Int)
  let int1 = PhysicalReg::new(1, Int)
  let int16 = PhysicalReg::new(16, Int)
  let function : Builder[TestInst] = Builder::new("call_transfer_slots", [])
  let allocation = Allocation::for_function(function.finish())
  let stack0 = allocation.create_stack_slot(I64, 8, 8)
  debug_inspect(
    plan_call_transfers(
      allocation,
      [
        CallTransfer::to_stack(I64, Register(int0), 0),
        CallTransfer::to_register(I64, Register(int1), int0),
        CallTransfer::to_stack(I64, Stack(stack0), 8),
        CallTransfer::to_register(I64, Register(int0), int1),
      ],
      0,
      16,
      [int16],
      [PhysicalReg::new(16, FpVector)],
      [],
    ),
    content=(
      #|{
      #|  stack_transfers: [
      #|    { ty: I64, source: p0:int, offset: 0, scratch: None },
      #|    { ty: I64, source: stack0, offset: 8, scratch: Some(p16:int) },
      #|  ],
      #|  register_moves: [
      #|    { ty: I64, from: p0:int, to: p16:int },
      #|    { ty: I64, from: p1:int, to: p0:int },
      #|    { ty: I64, from: p16:int, to: p1:int },
      #|  ],
      #|}
    ),
  )
}

///|
test "call transfer planner protects safepoint root homes" {
  let int0 = PhysicalReg::new(0, Int)
  let int1 = PhysicalReg::new(1, Int)
  let function : Builder[TestInst] = Builder::new("protected_call", [])
  let allocation = Allocation::for_function(function.finish())
  try
    plan_call_transfers(
      allocation,
      [CallTransfer::to_register(I64, Register(int1), int0)],
      0,
      0,
      [PhysicalReg::new(16, Int)],
      [PhysicalReg::new(16, FpVector)],
      [Register(int0)],
    )
  catch {
    error =>
      debug_inspect(
        error,
        content="ProtectedLocationOverwrite(index=0, location=p0:int)",
      )
  } noraise {
    _ => fail("expected a protected root overwrite error")
  }
}

///|
test "call transfer planner rejects overlapping outgoing slots" {
  let int0 = PhysicalReg::new(0, Int)
  let int1 = PhysicalReg::new(1, Int)
  let function : Builder[TestInst] = Builder::new("overlapping_call", [])
  let allocation = Allocation::for_function(function.finish())
  try
    plan_call_transfers(
      allocation,
      [
        CallTransfer::to_stack(I64, Register(int0), 0),
        CallTransfer::to_stack(I32, Register(int1), 4),
      ],
      0,
      16,
      [PhysicalReg::new(16, Int)],
      [PhysicalReg::new(16, FpVector)],
      [],
    )
  catch {
    error =>
      debug_inspect(
        error,
        content="OverlappingStackDestination(first=0, second=1)",
      )
  } noraise {
    _ => fail("expected an overlapping stack destination error")
  }
}

///|
test "call transfer planner covers duplicate sources mixed banks and call metadata" {
  let int0 = PhysicalReg::new(0, Int)
  let int1 = PhysicalReg::new(1, Int)
  let callee = PhysicalReg::new(2, Int)
  let result_area = PhysicalReg::new(3, Int)
  let fp0 = PhysicalReg::new(0, FpVector)
  let fp1 = PhysicalReg::new(1, FpVector)
  let function : Builder[TestInst] = Builder::new("mixed_call", [])
  let allocation = Allocation::for_function(function.finish())
  let float_slot = allocation.create_stack_slot(F64, 8, 8)
  debug_inspect(
    plan_call_transfers(
      allocation,
      [
        CallTransfer::to_register(Ptr64, Register(callee), int0),
        CallTransfer::to_register(Ptr64, Register(result_area), int1),
        CallTransfer::to_register(F64, Stack(float_slot), fp0),
        CallTransfer::to_stack(V128, Register(fp1), 16),
        CallTransfer::to_stack(I64, Register(callee), 0),
      ],
      0,
      32,
      [PhysicalReg::new(16, Int)],
      [PhysicalReg::new(16, FpVector)],
      [],
    ),
    content=(
      #|{
      #|  stack_transfers: [
      #|    { ty: V128, source: p1:fpvec, offset: 16, scratch: None },
      #|    { ty: I64, source: p2:int, offset: 0, scratch: None },
      #|  ],
      #|  register_moves: [
      #|    { ty: Ptr64, from: p2:int, to: p0:int },
      #|    { ty: Ptr64, from: p3:int, to: p1:int },
      #|    { ty: F64, from: stack0, to: p0:fpvec },
      #|  ],
      #|}
    ),
  )
}

///|
test "call transfer planner validates source stack ownership type and layout" {
  let function : Builder[TestInst] = Builder::new("source_contract", [])
  let allocation = Allocation::for_function(function.finish())
  let foreign_function : Builder[TestInst] = Builder::new("foreign", [])
  let foreign_allocation = Allocation::for_function(foreign_function.finish())
  let foreign = foreign_allocation.create_stack_slot(I64, 8, 8)
  try
    plan_call_transfers(
      allocation,
      [CallTransfer::to_register(I64, Stack(foreign), PhysicalReg::new(0, Int))],
      0,
      0,
      [PhysicalReg::new(16, Int)],
      [PhysicalReg::new(16, FpVector)],
      [],
    )
  catch {
    error => debug_inspect(error, content="ForeignSourceStack(index=0)")
  } noraise {
    _ => fail("expected a foreign source stack error")
  }
  let wrong_type = allocation.create_stack_slot(F64, 8, 8)
  try
    plan_call_transfers(
      allocation,
      [
        CallTransfer::to_register(
          I64,
          Stack(wrong_type),
          PhysicalReg::new(0, Int),
        ),
      ],
      0,
      0,
      [PhysicalReg::new(16, Int)],
      [PhysicalReg::new(16, FpVector)],
      [],
    )
  catch {
    error =>
      debug_inspect(
        error,
        content="InvalidSourceStackType(index=0, expected=I64, actual=F64)",
      )
  } noraise {
    _ => fail("expected a source stack type error")
  }
  let invalid_layout = allocation.create_stack_slot(I64, 4, 4)
  try
    plan_call_transfers(
      allocation,
      [
        CallTransfer::to_register(
          I64,
          Stack(invalid_layout),
          PhysicalReg::new(0, Int),
        ),
      ],
      0,
      0,
      [PhysicalReg::new(16, Int)],
      [PhysicalReg::new(16, FpVector)],
      [],
    )
  catch {
    error => debug_inspect(error, content="InvalidSourceStackLayout(index=0)")
  } noraise {
    _ => fail("expected a source stack layout error")
  }
}

///|
test "call transfer planner enforces the outgoing stack interval" {
  let function : Builder[TestInst] = Builder::new("outgoing_range", [])
  let allocation = Allocation::for_function(function.finish())
  try
    plan_call_transfers(
      allocation,
      [CallTransfer::to_stack(I64, Register(PhysicalReg::new(0, Int)), 8)],
      0,
      8,
      [PhysicalReg::new(16, Int)],
      [PhysicalReg::new(16, FpVector)],
      [],
    )
  catch {
    error =>
      debug_inspect(
        error,
        content="OutgoingStackDestinationOutOfRange(index=0, offset=8)",
      )
  } noraise {
    _ => fail("expected an outgoing stack range error")
  }
}

///|
test "call transfer planner does not destroy protected or pending scratch sources" {
  let function : Builder[TestInst] = Builder::new("scratch_contract", [])
  let allocation = Allocation::for_function(function.finish())
  let source_slot = allocation.create_stack_slot(I64, 8, 8)
  let int0 = PhysicalReg::new(0, Int)
  let int1 = PhysicalReg::new(1, Int)
  let int2 = PhysicalReg::new(2, Int)
  debug_inspect(
    plan_call_transfers(
      allocation,
      [
        CallTransfer::to_stack(I64, Stack(source_slot), 0),
        CallTransfer::to_stack(I64, Register(int0), 8),
      ],
      0,
      16,
      [int0, int1, int2],
      [PhysicalReg::new(16, FpVector)],
      [Register(int1)],
    ),
    content=(
      #|{
      #|  stack_transfers: [
      #|    { ty: I64, source: stack0, offset: 0, scratch: Some(p2:int) },
      #|    { ty: I64, source: p0:int, offset: 8, scratch: None },
      #|  ],
      #|  register_moves: [],
      #|}
    ),
  )
}

///|
test "call transfer planner rejects invalid class destination and scratch contracts" {
  let function : Builder[TestInst] = Builder::new("invalid_contracts", [])
  let allocation = Allocation::for_function(function.finish())
  let int0 = PhysicalReg::new(0, Int)
  let int1 = PhysicalReg::new(1, Int)
  let fp0 = PhysicalReg::new(0, FpVector)
  try
    plan_call_transfers(
      allocation,
      [CallTransfer::to_register(I64, Register(fp0), int0)],
      0,
      0,
      [PhysicalReg::new(16, Int)],
      [PhysicalReg::new(16, FpVector)],
      [],
    )
  catch {
    error => debug_inspect(error, content="InvalidSourceClass(index=0)")
  } noraise {
    _ => fail("expected a source class error")
  }
  try
    plan_call_transfers(
      allocation,
      [CallTransfer::to_register(I64, Register(int0), fp0)],
      0,
      0,
      [PhysicalReg::new(16, Int)],
      [PhysicalReg::new(16, FpVector)],
      [],
    )
  catch {
    error => debug_inspect(error, content="InvalidDestinationClass(index=0)")
  } noraise {
    _ => fail("expected a destination class error")
  }
  try
    plan_call_transfers(
      allocation,
      [
        CallTransfer::to_register(I64, Register(int0), int1),
        CallTransfer::to_register(I64, Register(int1), int1),
      ],
      0,
      0,
      [PhysicalReg::new(16, Int)],
      [PhysicalReg::new(16, FpVector)],
      [],
    )
  catch {
    error =>
      debug_inspect(
        error,
        content="DuplicateRegisterDestination(index=1, register=p1:int)",
      )
  } noraise {
    _ => fail("expected a duplicate register destination error")
  }
  try
    plan_call_transfers(
      allocation,
      [CallTransfer::to_stack(I32, Register(int0), 2)],
      0,
      8,
      [PhysicalReg::new(16, Int)],
      [PhysicalReg::new(16, FpVector)],
      [],
    )
  catch {
    error =>
      debug_inspect(error, content="InvalidStackOffset(index=0, offset=2)")
  } noraise {
    _ => fail("expected a stack alignment error")
  }
  let source_slot = allocation.create_stack_slot(I64, 8, 8)
  try
    plan_call_transfers(
      allocation,
      [CallTransfer::to_stack(I64, Stack(source_slot), 0)],
      0,
      8,
      [],
      [PhysicalReg::new(16, FpVector)],
      [],
    )
  catch {
    error =>
      debug_inspect(
        error,
        content="MoveResolutionFailed(cause=MissingScratch(class=Int))",
      )
  } noraise {
    _ => fail("expected a missing scratch error")
  }
  try
    plan_call_transfers(
      allocation,
      [CallTransfer::to_stack(I64, Stack(source_slot), 0)],
      0,
      8,
      [fp0],
      [PhysicalReg::new(16, FpVector)],
      [],
    )
  catch {
    error =>
      debug_inspect(
        error,
        content=(
          #|MoveResolutionFailed(cause=InvalidScratch(reg=p0:fpvec, expected=Int))
        ),
      )
  } noraise {
    _ => fail("expected an invalid scratch class error")
  }
}
