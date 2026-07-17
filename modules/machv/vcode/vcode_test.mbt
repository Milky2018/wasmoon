///|
priv enum TestInst {
  Add
  Call
  Jump
  Return
} derive(Debug)

///|
fn build_test_function() -> Function[TestInst] raise VCodeBuildError {
  let builder : Builder[TestInst] = Builder::new("sum", [I64])
  let entry = builder.entry_block()
  let lhs = builder.parameter(0)
  let exit = builder.create_block([I64])
  let (add, results) = builder.append_body(
    entry,
    Add,
    [Input::any(lhs)],
    [Output::any(I64)],
    [PhysicalReg::new(9, Int)],
    InstructionMetadata::empty(),
  )
  builder.set_terminator(
    entry,
    Jump,
    [],
    [Edge::new(exit, [results[0]])],
    [],
    InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    exit,
    Return,
    [Input::any(builder.block_parameter(exit, 0))],
    [],
    [],
    InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  add |> ignore
  exit |> ignore
  function
}

///|
test "Target VCode snapshots selected SSA and compact allocation facts" {
  let function = build_test_function()
  verify_selected(function)
  inspect(
    function.summary(),
    content=(
      #|vcode sum(v0:i64)
      #|block0:
      #|  i0 Add uses=[v0:any@early] defs=[v2:any@late] clobbers=[p9:int]
      #|  i1 Jump -> block1(v2)
      #|block1(v1:i64):
      #|  i2 Return uses=[v1:any@early]
      #|
    ),
  )
}

///|
test "instruction and program-point handles survive layout and allocation" {
  let function = build_test_function()
  let before = function.instruction_at(0).unwrap()
  let point = function.before(before).unwrap()
  function.set_layout([function.block_at(1).unwrap(), function.entry_block()])
  let allocation = Allocation::for_function(function)
  allocation.assign_value(
    function.value_at(0).unwrap(),
    Register(PhysicalReg::new(0, Int)),
  )
  |> ignore
  inspect(function.instruction_index(before).unwrap(), content="0")
  inspect(
    function
    .instruction_index(function.program_point_instruction(point).unwrap())
    .unwrap(),
    content="0",
  )
  inspect(allocation.source_instruction_count(), content="3")
}

///|
test "Allocation remains separate and verifies edits, slots, and safepoints" {
  let builder : Builder[TestInst] = Builder::new("pressure", [GcRef64])
  let entry = builder.entry_block()
  let root = builder.parameter(0)
  let (call, results) = builder.append_body(
    entry,
    Add,
    [Input::fixed(root, PhysicalReg::new(0, Int))],
    [Output::tied(GcRef64, 0)],
    [PhysicalReg::new(1, Int)],
    InstructionMetadata::safepoint([root]),
  )
  let return_inst = builder.set_terminator(
    entry,
    Return,
    [Input::any(results[0])],
    [],
    [],
    InstructionMetadata::empty(),
  )
  let function = builder.finish()
  let allocation = Allocation::for_function(function)
  let slot = allocation.create_stack_slot(GcRef64, 8, 8)
  allocation.assign_value(root, Stack(slot)) |> ignore
  allocation.assign_value(results[0], Stack(slot)) |> ignore
  allocation.assign_operand(call, 0, PhysicalReg::new(0, Int)) |> ignore
  allocation.assign_operand(call, 1, PhysicalReg::new(0, Int)) |> ignore
  allocation.assign_operand(return_inst, 0, PhysicalReg::new(0, Int)) |> ignore
  allocation.add_edit(
    Edit::reload(
      function.before(call).unwrap(),
      root,
      slot,
      PhysicalReg::new(0, Int),
    ),
  )
  |> ignore
  allocation.add_edit(
    Edit::spill(
      function.after(call).unwrap(),
      results[0],
      PhysicalReg::new(0, Int),
      slot,
    ),
  )
  |> ignore
  allocation.add_edit(
    Edit::reload(
      function.before(return_inst).unwrap(),
      results[0],
      slot,
      PhysicalReg::new(0, Int),
    ),
  )
  |> ignore
  allocation.add_safepoint_root(call, root, Stack(slot)) |> ignore
  verify_allocated(function, allocation)
  let frame = FrameLayout::new(function, allocation, 16, 16)
  frame.place_slot(slot, 0) |> ignore
  let foreign_allocation = Allocation::for_function(function)
  let foreign_slot = foreign_allocation.create_stack_slot(GcRef64, 8, 8)
  assert_false(frame.place_slot(foreign_slot, 8))
  verify_framed(function, allocation, frame)
  verify_emission_input(function, allocation, frame)
  inspect(
    allocation.summary(),
    content=(
      #|allocation pressure
      #|  v0:gcref64 -> stack0:gcref64(size=8, align=8)
      #|  v1:gcref64 -> stack0:gcref64(size=8, align=8)
      #|  i0 operand0 -> p0:int
      #|  i0 operand1 -> p0:int
      #|  i1 operand0 -> p0:int
      #|  before(i0): reload v0 stack0 -> p0:int
      #|  after(i0): spill v1 p0:int -> stack0
      #|  before(i1): reload v1 stack0 -> p0:int
      #|  i0 root v0 -> stack0
      #|
    ),
  )
}

///|
test "Allocation checker rejects a live reference in a clobbered integer register" {
  let builder : Builder[TestInst] = Builder::new("clobber", [GcRef64])
  let entry = builder.entry_block()
  let value = builder.parameter(0)
  let (call, _) = builder.append_body(
    entry,
    Add,
    [],
    [],
    [PhysicalReg::new(0, Int)],
    InstructionMetadata::empty(),
  )
  let return_inst = builder.set_terminator(
    entry,
    Return,
    [Input::any(value)],
    [],
    [],
    InstructionMetadata::empty(),
  )
  let function = builder.finish()
  let allocation = Allocation::for_function(function)
  allocation.assign_value(value, Register(PhysicalReg::new(0, Int))) |> ignore
  allocation.assign_operand(return_inst, 0, PhysicalReg::new(0, Int)) |> ignore
  verify_allocated(function, allocation) catch {
    error =>
      inspect(error, content="ClobberViolation(instruction=i0, value=v0)")
  }
  inspect(function.instruction_index(call).unwrap(), content="0")
}

///|
test "Allocation checker rejects interfering values in one location" {
  let builder : Builder[TestInst] = Builder::new("interference", [I64, I64])
  let entry = builder.entry_block()
  let lhs = builder.parameter(0)
  let rhs = builder.parameter(1)
  let (add, result) = builder.append_body(
    entry,
    Add,
    [Input::any(lhs), Input::any(rhs)],
    [Output::any(I64)],
    [],
    InstructionMetadata::empty(),
  )
  let return_inst = builder.set_terminator(
    entry,
    Return,
    [Input::any(result[0])],
    [],
    [],
    InstructionMetadata::empty(),
  )
  let function = builder.finish()
  let allocation = Allocation::for_function(function)
  allocation.assign_value(lhs, Register(PhysicalReg::new(0, Int))) |> ignore
  allocation.assign_value(rhs, Register(PhysicalReg::new(0, Int))) |> ignore
  allocation.assign_value(result[0], Register(PhysicalReg::new(1, Int)))
  |> ignore
  allocation.assign_operand(add, 0, PhysicalReg::new(0, Int)) |> ignore
  allocation.assign_operand(add, 1, PhysicalReg::new(0, Int)) |> ignore
  allocation.assign_operand(add, 2, PhysicalReg::new(1, Int)) |> ignore
  allocation.assign_operand(return_inst, 0, PhysicalReg::new(1, Int)) |> ignore
  verify_allocated(function, allocation) catch {
    error =>
      inspect(error, content="Interference(left=v0, right=v1, location=p0:int)")
  }
}

///|
test "Allocation checker requires and validates edge parallel moves" {
  let builder : Builder[TestInst] = Builder::new("edge_move", [I64])
  let entry = builder.entry_block()
  let value = builder.parameter(0)
  let exit = builder.create_block([I64])
  builder.set_terminator(
    entry,
    Jump,
    [],
    [Edge::new(exit, [value])],
    [],
    InstructionMetadata::empty(),
  )
  |> ignore
  let parameter = builder.block_parameter(exit, 0)
  let return_inst = builder.set_terminator(
    exit,
    Return,
    [Input::any(parameter)],
    [],
    [],
    InstructionMetadata::empty(),
  )
  let function = builder.finish()
  let allocation = Allocation::for_function(function)
  let source : Location = Register(PhysicalReg::new(0, Int))
  let destination : Location = Register(PhysicalReg::new(1, Int))
  allocation.assign_value(value, source) |> ignore
  allocation.assign_value(parameter, destination) |> ignore
  allocation.assign_operand(return_inst, 0, PhysicalReg::new(1, Int)) |> ignore
  verify_allocated(function, allocation) catch {
    error => inspect(error, content="InvalidEdgeMove(index=0)")
  }
  allocation.add_edit(Edit::edge_move(entry, 0, value, source, destination))
  |> ignore
  verify_allocated(function, allocation)
  inspect(
    allocation.summary(),
    content=(
      #|allocation edge_move
      #|  v0:i64 -> p0:int
      #|  v1:i64 -> p1:int
      #|  i1 operand0 -> p1:int
      #|  edge(block0, 0): move v0 p0:int -> p1:int
      #|
    ),
  )
}

///|
test "verifier checkpoints return structured stage errors" {
  let function = build_test_function()
  let allocation = Allocation::for_function(function)
  verify_allocated(function, allocation) catch {
    error => inspect(error, content="MissingValueLocation(value=v0)")
  }
  let frame = FrameLayout::new(function, allocation, 16, 16)
  verify_framed(function, allocation, frame) catch {
    error =>
      inspect(
        error,
        content="AllocationFailure(cause=MissingValueLocation(value=v0))",
      )
  }
  verify_emission_input(function, allocation, frame) catch {
    error =>
      inspect(
        error,
        content="FrameFailure(cause=AllocationFailure(cause=MissingValueLocation(value=v0)))",
      )
  }
}

///|
test "Allocation mutation rejects foreign handles without changing data" {
  let function = build_test_function()
  let foreign = build_test_function()
  let allocation = Allocation::for_function(function)
  assert_false(
    allocation.assign_value(
      foreign.value_at(0).unwrap(),
      Register(PhysicalReg::new(0, Int)),
    ),
  )
  assert_false(
    allocation.assign_operand(
      foreign.instruction_at(0).unwrap(),
      0,
      PhysicalReg::new(0, Int),
    ),
  )
  inspect(
    allocation.summary(),
    content=(
      #|allocation sum
      #|
    ),
  )
}

///|
test "Builder rejects body instructions after a terminator without mutation" {
  let builder : Builder[TestInst] = Builder::new("terminated", [])
  let entry = builder.entry_block()
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    InstructionMetadata::empty(),
  )
  |> ignore
  try
    builder.append_body(entry, Add, [], [], [], InstructionMetadata::empty())
    |> ignore
  catch {
    error => inspect(error, content="BlockAlreadyTerminated(block=block0)")
  } noraise {
    _ => fail("expected an instruction after a terminator to be rejected")
  }
  inspect(
    builder.finish().summary(),
    content=(
      #|vcode terminated()
      #|block0:
      #|  i0 Return
      #|
    ),
  )
}

///|
test "VCode preserves typed source trap safepoint and symbol metadata" {
  let builder : Builder[TestInst] = Builder::new("metadata", [GcRef64])
  let entry = builder.entry_block()
  let root = builder.parameter(0)
  builder.append_body(
    entry,
    Call,
    [Input::any(root)],
    [],
    [],
    InstructionMetadata::new(
      source=@semantic.SourceLocation::new("fixture.wat", 7, 11),
      trap=MemoryOutOfBounds,
      safepoint=GcAndCancellation,
      live_gc_roots=[root],
      symbol=External(@semantic.ExternalSymbol::new("runtime.grow")),
    ),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  verify_selected(function)
  inspect(
    function.summary(),
    content=(
      #|vcode metadata(v0:gcref64)
      #|block0:
      #|  i0 Call uses=[v0:any@early] source={ file: "fixture.wat", line: 7, column: 11 } trap=MemoryOutOfBounds safepoint=GcAndCancellation roots=[v0] symbol=External({ name: "runtime.grow" })
      #|  i1 Return
      #|
    ),
  )
}
