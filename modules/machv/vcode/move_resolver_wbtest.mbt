///|
priv struct SymbolicCell {
  location : Location
  mut value : Int
}

///|
fn symbolic_read(state : Array[SymbolicCell], location : Location) -> Int {
  for cell in state {
    if cell.location == location {
      return cell.value
    }
  }
  abort("missing symbolic location")
}

///|
fn symbolic_write(
  state : Array[SymbolicCell],
  location : Location,
  value : Int,
) -> Unit {
  for cell in state {
    if cell.location == location {
      cell.value = value
      return
    }
  }
  state.push({ location, value })
}

///|
fn symbolic_add_location(
  state : Array[SymbolicCell],
  location : Location,
) -> Unit {
  for cell in state {
    if cell.location == location {
      return
    }
  }
  state.push({ location, value: state.length() })
}

///|
fn assert_plan_preserves_parallel_assignment(
  moves : Array[ParallelMove],
  plan : ResolvedMovePlan,
  scratch_int : PhysicalReg,
  scratch_fp : PhysicalReg,
) -> Unit raise {
  let state : Array[SymbolicCell] = []
  for transfer in moves {
    symbolic_add_location(state, transfer.from)
    symbolic_add_location(state, transfer.to)
  }
  symbolic_add_location(state, Register(scratch_int))
  symbolic_add_location(state, Register(scratch_fp))
  let initial : Array[SymbolicCell] = []
  for cell in state {
    initial.push({ location: cell.location, value: cell.value })
  }
  let mut emergency : Int? = None
  for step in plan.steps {
    match step {
      Transfer(transfer) => {
        if transfer.from is Stack(_) && transfer.to is Stack(_) {
          fail("resolved plan contains a stack-to-stack transfer")
        }
        symbolic_write(state, transfer.to, symbolic_read(state, transfer.from))
      }
      SpillScratchToEmergency(scratch~, ..) =>
        emergency = Some(symbolic_read(state, Register(scratch)))
      ReloadScratchFromEmergency(scratch~, ..) => {
        guard emergency is Some(value) else {
          abort("reload without an emergency spill")
        }
        symbolic_write(state, Register(scratch), value)
        emergency = None
      }
    }
  }
  assert_eq(emergency, None)
  for transfer in moves {
    assert_eq(
      symbolic_read(state, transfer.to),
      symbolic_read(initial, transfer.from),
    )
  }
}

///|
test "parallel stack-slot cycle preserves both values" {
  let owner = Ref(())
  let stack0 = StackSlot::new(owner, 0)
  let stack1 = StackSlot::new(owner, 1)
  let int_scratch = PhysicalReg::new(16, Int)
  let fp_scratch = PhysicalReg::new(16, FpVector)
  let moves = [
    ParallelMove::new(I32, Stack(stack0), Stack(stack1)),
    ParallelMove::new(I32, Stack(stack1), Stack(stack0)),
  ]
  let plan = plan_parallel_moves(moves, int_scratch, fp_scratch)
  assert_eq(plan.requires_emergency, true)
  assert_eq(plan.steps.length(), 6)
  assert_plan_preserves_parallel_assignment(
    moves, plan, int_scratch, fp_scratch,
  )
}

///|
test "register cycle does not require emergency storage" {
  let int0 = PhysicalReg::new(0, Int)
  let int1 = PhysicalReg::new(1, Int)
  let int_scratch = PhysicalReg::new(16, Int)
  let fp_scratch = PhysicalReg::new(16, FpVector)
  let moves = [
    ParallelMove::new(I64, Register(int0), Register(int1)),
    ParallelMove::new(I64, Register(int1), Register(int0)),
  ]
  let plan = plan_parallel_moves(moves, int_scratch, fp_scratch)
  assert_eq(plan.requires_emergency, false)
  assert_plan_preserves_parallel_assignment(
    moves, plan, int_scratch, fp_scratch,
  )
}

///|
test "acyclic stack transfer uses the transfer scratch directly" {
  let owner = Ref(())
  let stack0 = StackSlot::new(owner, 0)
  let stack1 = StackSlot::new(owner, 1)
  let int_scratch = PhysicalReg::new(16, Int)
  let fp_scratch = PhysicalReg::new(16, FpVector)
  let moves = [ParallelMove::new(I64, Stack(stack0), Stack(stack1))]
  let plan = plan_parallel_moves(moves, int_scratch, fp_scratch)
  assert_eq(plan.requires_emergency, false)
  assert_eq(plan.steps.length(), 2)
  assert_plan_preserves_parallel_assignment(
    moves, plan, int_scratch, fp_scratch,
  )
}

///|
test "FP and vector stack cycles share one physical register bank" {
  let owner = Ref(())
  let stack0 = StackSlot::new(owner, 0)
  let stack1 = StackSlot::new(owner, 1)
  let fp0 = PhysicalReg::new(0, FpVector)
  let int_scratch = PhysicalReg::new(16, Int)
  let fp_scratch = PhysicalReg::new(16, FpVector)
  let moves = [
    ParallelMove::new(V128, Stack(stack0), Stack(stack1)),
    ParallelMove::new(F64, Stack(stack1), Register(fp0)),
    ParallelMove::new(F64, Register(fp0), Stack(stack0)),
  ]
  let plan = plan_parallel_moves(moves, int_scratch, fp_scratch)
  assert_eq(plan.requires_emergency, true)
  assert_plan_preserves_parallel_assignment(
    moves, plan, int_scratch, fp_scratch,
  )
}

///|
test "mixed-location multi-node cycle preserves every destination" {
  let owner = Ref(())
  let stack0 = StackSlot::new(owner, 0)
  let stack1 = StackSlot::new(owner, 1)
  let int0 = PhysicalReg::new(0, Int)
  let int_scratch = PhysicalReg::new(16, Int)
  let fp_scratch = PhysicalReg::new(16, FpVector)
  let moves = [
    ParallelMove::new(I64, Stack(stack0), Register(int0)),
    ParallelMove::new(I64, Register(int0), Stack(stack1)),
    ParallelMove::new(I64, Stack(stack1), Stack(stack0)),
  ]
  let plan = plan_parallel_moves(moves, int_scratch, fp_scratch)
  assert_plan_preserves_parallel_assignment(
    moves, plan, int_scratch, fp_scratch,
  )
}
