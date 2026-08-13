///|
test "parallel stack-slot cycle preserves both values" {
  let owner = Ref(())
  let stack0 = StackSlot::new(owner, 0)
  let stack1 = StackSlot::new(owner, 1)
  let int16 = PhysicalReg::new(16, Int)
  let int17 = PhysicalReg::new(17, Int)
  debug_inspect(
    resolve_single_bank(
      [
        ParallelMove::new(I32, Stack(stack0), Stack(stack1)),
        ParallelMove::new(I32, Stack(stack1), Stack(stack0)),
      ],
      [int17, int16],
      [PhysicalReg::new(16, FpVector)],
    ),
    content=(
      #|[
      #|  { ty: I32, from: stack1, to: p17:int },
      #|  { ty: I32, from: stack0, to: p16:int },
      #|  { ty: I32, from: p16:int, to: stack1 },
      #|  { ty: I32, from: p17:int, to: stack0 },
      #|]
    ),
  )
}
