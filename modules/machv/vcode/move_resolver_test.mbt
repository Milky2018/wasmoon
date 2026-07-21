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
      [
        CallTransfer::to_stack(I64, Register(int0), 0),
        CallTransfer::to_register(I64, Register(int1), int0),
        CallTransfer::to_stack(I64, Stack(stack0), 8),
        CallTransfer::to_register(I64, Register(int0), int1),
      ],
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
  try
    plan_call_transfers(
      [CallTransfer::to_register(I64, Register(int1), int0)],
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
  try
    plan_call_transfers(
      [
        CallTransfer::to_stack(I64, Register(int0), 0),
        CallTransfer::to_stack(I32, Register(int1), 4),
      ],
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
