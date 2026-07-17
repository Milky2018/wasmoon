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
