///|
priv enum TestInst {
  Add
  Call
  Jump
  Return
} derive(Debug)

///|
fn build_test_function() -> @vcode.Function[TestInst] raise @vcode.VCodeBuildError {
  let builder : @vcode.Builder[TestInst] = @vcode.Builder::new("sum", [I64])
  let entry = builder.entry_block()
  let lhs = builder.parameter(0)
  let exit = builder.create_block([I64])
  let (add, results) = builder.append_body(
    entry,
    Add,
    [@vcode.Input::any(lhs)],
    [@vcode.Output::any(I64)],
    [@vcode.PhysicalReg::new(9, Int)],
    @vcode.InstructionMetadata::empty(),
  )
  builder.set_terminator(
    entry,
    Jump,
    [],
    [@vcode.Edge::new(exit, [results[0]])],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    exit,
    Return,
    [@vcode.Input::any(builder.block_parameter(exit, 0))],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  add |> ignore
  exit |> ignore
  function
}

///|
test "CheckedBuilder rejects incomplete construction at sealing" {
  let builder : @vcode.CheckedBuilder[TestInst] = @vcode.CheckedBuilder::new(
    "missing_terminator",
    [],
  )
  try builder.finish() |> ignore catch {
    error => inspect(error, content="MissingTerminator(block=block0)")
  } noraise {
    _ => fail("expected incomplete checked construction to be rejected")
  }
}

///|
test "CheckedBuilder rejects malformed edges before mutation" {
  let builder : @vcode.CheckedBuilder[TestInst] = @vcode.CheckedBuilder::new(
    "bad_edge",
    [],
  )
  let entry = builder.entry_block()
  let exit = builder.create_block([I64])
  try
    builder.set_terminator(
      entry,
      Jump,
      [],
      [@vcode.Edge::new(exit, [])],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
  catch {
    error => inspect(error, content="InvalidEdgeArity(block=block1)")
  } noraise {
    _ => fail("expected malformed checked edge to be rejected")
  }
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
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
  builder.finish() |> ignore
}

///|
test "CheckedBuilder preserves operand checks on the single validation path" {
  let builder : @vcode.CheckedBuilder[TestInst] = @vcode.CheckedBuilder::new(
    "checked_operands",
    [I64],
  )
  let foreign : @vcode.CheckedBuilder[TestInst] = @vcode.CheckedBuilder::new(
    "foreign",
    [I64],
  )
  let entry = builder.entry_block()
  let value = builder.parameter(0)
  try
    builder.append_body(
      entry,
      Add,
      [@vcode.Input::any(foreign.parameter(0))],
      [@vcode.Output::any(I64)],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
  catch {
    ForeignValue(_) => ()
    _ => fail("expected foreign input rejection")
  } noraise {
    _ => fail("expected foreign input rejection")
  }
  try
    builder.append_body(
      entry,
      Add,
      [@vcode.Input::any(value)],
      [@vcode.Output::tied(I64, 0), @vcode.Output::tied(I64, 0)],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
  catch {
    InvalidOperandConstraint => ()
    _ => fail("expected duplicate tie rejection")
  } noraise {
    _ => fail("expected duplicate tie rejection")
  }
  builder.set_terminator(
    entry,
    Return,
    [@vcode.Input::any(value)],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  inspect(builder.finish().instruction_count(), content="1")
}

///|
test "CheckedBuilder unconstrained path preserves ownership and VCode facts" {
  let builder : @vcode.CheckedBuilder[TestInst] = @vcode.CheckedBuilder::new(
    "checked_unconstrained",
    [I64],
  )
  let foreign : @vcode.CheckedBuilder[TestInst] = @vcode.CheckedBuilder::new(
    "foreign",
    [I64],
  )
  let entry = builder.entry_block()
  try
    builder.append_body_unconstrained(
      entry,
      Add,
      [foreign.parameter(0)],
      [I64],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
  catch {
    ForeignValue(_) => ()
    _ => fail("expected foreign input rejection")
  } noraise {
    _ => fail("expected foreign input rejection")
  }
  let (_, results) = builder.append_body_unconstrained(
    entry,
    Add,
    [builder.parameter(0)],
    [I64],
    [@vcode.PhysicalReg::new(9, Int)],
    @vcode.InstructionMetadata::empty(),
  )
  builder.set_terminator(
    entry,
    Return,
    [@vcode.Input::any(results[0])],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  @vcode.verify_selected(function)
  inspect(
    function.summary(),
    content=(
      #|vcode checked_unconstrained(v0:i64)
      #|block0:
      #|  i0 Add uses=[v0:any@early] defs=[v1:any@late] clobbers=[p9:int]
      #|  i1 Return uses=[v1:any@early]
      #|
    ),
  )
}

///|
test "Builder rejects duplicate tied outputs before mutation" {
  let builder : @vcode.Builder[TestInst] = @vcode.Builder::new(
    "duplicate_tie",
    [I64],
  )
  let entry = builder.entry_block()
  let value = builder.parameter(0)
  try
    builder.append_body(
      entry,
      Add,
      [@vcode.Input::any(value)],
      [@vcode.Output::tied(I64, 0), @vcode.Output::tied(I64, 0)],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
  catch {
    InvalidOperandConstraint => ()
    _ => fail("expected duplicate tie rejection")
  } noraise {
    _ => fail("expected duplicate tie rejection")
  }
  builder.set_terminator(
    entry,
    Return,
    [@vcode.Input::any(value)],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  inspect(builder.finish().instruction_count(), content="1")
}

///|
test "Target VCode snapshots selected SSA and compact allocation facts" {
  let function = build_test_function()
  @vcode.verify_selected(function)
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
test "output register preferences remain soft allocation hints" {
  let builder : @vcode.Builder[TestInst] = @vcode.Builder::new(
    "preferred_output",
    [],
  )
  let entry = builder.entry_block()
  let (_, results) = builder.append_body(
    entry,
    Add,
    [],
    [
      @vcode.Output::any_location(I64).with_preference(
        @vcode.PhysicalReg::new(1, Int),
      ),
    ],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  builder.set_terminator(
    entry,
    Return,
    [@vcode.Input::any(results[0])],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  @vcode.verify_selected(function)
  inspect(
    function.summary(),
    content=(
      #|vcode preferred_output()
      #|block0:
      #|  i0 Add defs=[v0:any-location(prefer=p1:int)@late]
      #|  i1 Return uses=[v0:any@early]
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
  let allocation = @vcode.Allocation::for_function(function)
  allocation.assign_value(
    function.value_at(0).unwrap(),
    Register(@vcode.PhysicalReg::new(0, Int)),
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
test "flat function access follows layout without collection snapshots" {
  let function = build_test_function()
  let entry = function.layout_block_at(0).unwrap()
  let exit = function.layout_block_at(1).unwrap()
  inspect(function.block_parameter_count(entry), content="0")
  inspect(function.block_parameter_count(exit), content="1")
  inspect(
    function.value_index(function.block_parameter_at(exit, 0).unwrap()).unwrap(),
    content="1",
  )
  inspect(function.block_instruction_count(entry), content="2")
  let jump = function.block_instruction_at(entry, 1).unwrap()
  inspect(function.instruction_index(jump).unwrap(), content="1")
  inspect(function.instruction_successor_count(jump), content="1")
  inspect(
    function
    .block_index(function.instruction_successor_target(jump, 0).unwrap())
    .unwrap(),
    content="1",
  )
  inspect(function.instruction_successor_argument_count(jump, 0), content="1")
  inspect(
    function
    .value_index(
      function.instruction_successor_argument_at(jump, 0, 0).unwrap(),
    )
    .unwrap(),
    content="2",
  )
}

///|
test "allocation view resolves successors after layout changes" {
  let function = build_test_function()
  function.set_layout([function.block_at(1).unwrap(), function.entry_block()])
  inspect(function.allocation_layout_block_id_at(0), content="1")
  inspect(function.allocation_layout_block_id_at(1), content="0")
  inspect(function.allocation_block_instruction_count(1), content="2")
  inspect(function.allocation_block_instruction_at(1, 1), content="1")
  inspect(function.allocation_block_successor_count(1), content="1")
  inspect(function.allocation_block_successor_at(1, 0), content="0")
  inspect(function.allocation_edge_argument_count(1, 0), content="1")
  inspect(function.allocation_edge_argument_at(1, 0, 0).id, content="2")
}

///|
test "plan storage adoption rejects undersized spill metadata" {
  let builder : @vcode.Builder[TestInst] = @vcode.Builder::new("plan_storage", [
    I64,
  ])
  builder.set_terminator(
    builder.entry_block(),
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  inspect(
    @vcode.AllocationBuilder::from_plan_storage(
      function,
      [Some(@vcode.AllocationLocation::spill(0))],
      [[]],
      [0],
      [4],
      [4],
    )
    is None,
    content="true",
  )
  inspect(
    @vcode.AllocationBuilder::from_plan_storage(
      function,
      [Some(@vcode.AllocationLocation::spill(0))],
      [[]],
      [0],
      [8],
      [8],
    )
    is Some(_),
    content="true",
  )
}

///|
test "Allocation remains separate and verifies edits, slots, and safepoints" {
  let builder : @vcode.Builder[TestInst] = @vcode.Builder::new("pressure", [
    GcRef64,
  ])
  let entry = builder.entry_block()
  let root = builder.parameter(0)
  let (call, results) = builder.append_body(
    entry,
    Add,
    [@vcode.Input::fixed(root, @vcode.PhysicalReg::new(0, Int))],
    [@vcode.Output::tied(GcRef64, 0)],
    [@vcode.PhysicalReg::new(1, Int)],
    @vcode.InstructionMetadata::safepoint([root]),
  )
  let return_inst = builder.set_terminator(
    entry,
    Return,
    [@vcode.Input::any(results[0])],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  let function = builder.finish()
  let operands = function.instruction_operands(call)
  inspect(
    operands[0].constraint == FixedReg(@vcode.PhysicalReg::new(0, Int)),
    content="true",
  )
  inspect(operands[1].constraint == AnyReg, content="true")
  inspect(
    operands[0].tie_id >= 0 && operands[0].tie_id == operands[1].tie_id,
    content="true",
  )
  let allocation = @vcode.Allocation::for_function(function)
  let slot = allocation.create_stack_slot(GcRef64, 8, 8)
  allocation.assign_value(root, Stack(slot)) |> ignore
  allocation.assign_value(results[0], Stack(slot)) |> ignore
  allocation.assign_operand(call, 0, @vcode.PhysicalReg::new(0, Int)) |> ignore
  allocation.assign_operand(call, 1, @vcode.PhysicalReg::new(0, Int)) |> ignore
  allocation.assign_operand(return_inst, 0, @vcode.PhysicalReg::new(0, Int))
  |> ignore
  allocation.add_edit(
    @vcode.Edit::reload(
      function.before(call).unwrap(),
      root,
      slot,
      @vcode.PhysicalReg::new(0, Int),
    ),
  )
  |> ignore
  allocation.add_edit(
    @vcode.Edit::spill(
      function.after(call).unwrap(),
      results[0],
      @vcode.PhysicalReg::new(0, Int),
      slot,
    ),
  )
  |> ignore
  allocation.add_edit(
    @vcode.Edit::reload(
      function.before(return_inst).unwrap(),
      results[0],
      slot,
      @vcode.PhysicalReg::new(0, Int),
    ),
  )
  |> ignore
  allocation.add_safepoint_root(call, root, Stack(slot)) |> ignore
  @vcode.verify_allocated(function, allocation)
  debug_inspect(
    allocation.statistics(),
    content=(
      #|{
      #|  spill_slots: 1,
      #|  spills: 1,
      #|  reloads: 2,
      #|  reg_moves: 0,
      #|  spill_to_spill: 0,
      #|}
    ),
  )
  let frame = @vcode.FrameLayout::new(function, allocation, 16, 16)
  frame.place_slot(slot, 0) |> ignore
  let foreign_allocation = @vcode.Allocation::for_function(function)
  let foreign_slot = foreign_allocation.create_stack_slot(GcRef64, 8, 8)
  assert_false(frame.place_slot(foreign_slot, 8))
  @vcode.verify_framed(function, allocation, frame)
  @vcode.verify_emission_input(function, allocation, frame)
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
test "Allocation checker requires indexed reload and spill edits" {
  let builder : @vcode.Builder[TestInst] = @vcode.Builder::new(
    "indexed_edits",
    [I64],
  )
  let entry = builder.entry_block()
  let parameter = builder.parameter(0)
  let (add, results) = builder.append_body(
    entry,
    Add,
    [@vcode.Input::any(parameter)],
    [@vcode.Output::any(I64)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  let return_inst = builder.set_terminator(
    entry,
    Return,
    [@vcode.Input::any_location(results[0])],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  let function = builder.finish()
  let allocation = @vcode.Allocation::for_function(function)
  let parameter_slot = allocation.create_stack_slot(I64, 8, 8)
  let result_slot = allocation.create_stack_slot(I64, 8, 8)
  let transfer_reg = @vcode.PhysicalReg::new(0, Int)
  allocation.assign_value(parameter, Stack(parameter_slot)) |> ignore
  allocation.assign_value(results[0], Stack(result_slot)) |> ignore
  allocation.assign_operand(add, 0, transfer_reg) |> ignore
  allocation.assign_operand(add, 1, transfer_reg) |> ignore
  allocation.assign_operand_location(return_inst, 0, Stack(result_slot))
  |> ignore
  @vcode.verify_allocated(function, allocation) catch {
    error => inspect(error, content="MissingReload(instruction=i0, operand=0)")
  }
  allocation.add_edit(
    @vcode.Edit::reload(
      function.before(add).unwrap(),
      parameter,
      parameter_slot,
      transfer_reg,
    ),
  )
  |> ignore
  @vcode.verify_allocated(function, allocation) catch {
    error => inspect(error, content="MissingReload(instruction=i1, operand=0)")
  }
  allocation.add_edit(
    @vcode.Edit::spill(
      function.after(add).unwrap(),
      results[0],
      transfer_reg,
      result_slot,
    ),
  )
  |> ignore
  debug_inspect(
    allocation.edits_at(add, Before).map(edit => edit.kind()),
    content=(
      #|[Reload(value=v0, slot=stack0, reg=p0:int)]
    ),
  )
  debug_inspect(
    allocation.edits_at(add, After).map(edit => edit.kind()),
    content=(
      #|[Spill(value=v1, reg=p0:int, slot=stack1)]
    ),
  )
  @vcode.verify_allocated(function, allocation)
}

///|
test "Allocation checker rejects a live reference in a clobbered integer register" {
  let builder : @vcode.Builder[TestInst] = @vcode.Builder::new("clobber", [
    GcRef64,
  ])
  let entry = builder.entry_block()
  let value = builder.parameter(0)
  let (call, _) = builder.append_body(
    entry,
    Add,
    [],
    [],
    [@vcode.PhysicalReg::new(0, Int)],
    @vcode.InstructionMetadata::empty(),
  )
  let return_inst = builder.set_terminator(
    entry,
    Return,
    [@vcode.Input::any(value)],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  let function = builder.finish()
  let allocation = @vcode.Allocation::for_function(function)
  allocation.assign_value(value, Register(@vcode.PhysicalReg::new(0, Int)))
  |> ignore
  allocation.assign_operand(return_inst, 0, @vcode.PhysicalReg::new(0, Int))
  |> ignore
  @vcode.verify_allocated(function, allocation) catch {
    error =>
      inspect(error, content="ClobberViolation(instruction=i0, value=v0)")
  }
  inspect(function.instruction_index(call).unwrap(), content="0")
}

///|
test "Allocation checker permits a late definition in a clobbered register" {
  let builder : @vcode.Builder[TestInst] = @vcode.Builder::new(
    "late_clobber_def",
    [],
  )
  let entry = builder.entry_block()
  let (instruction, results) = builder.append_body(
    entry,
    Add,
    [],
    [@vcode.Output::fixed(I64, @vcode.PhysicalReg::new(0, Int))],
    [@vcode.PhysicalReg::new(0, Int)],
    @vcode.InstructionMetadata::empty(),
  )
  let return_inst = builder.set_terminator(
    entry,
    Return,
    [@vcode.Input::any(results[0])],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  let function = builder.finish()
  let allocation = @vcode.Allocation::for_function(function)
  allocation.assign_value(results[0], Register(@vcode.PhysicalReg::new(0, Int)))
  |> ignore
  allocation.assign_operand(instruction, 0, @vcode.PhysicalReg::new(0, Int))
  |> ignore
  allocation.assign_operand(return_inst, 0, @vcode.PhysicalReg::new(0, Int))
  |> ignore
  inspect(@vcode.verify_allocated(function, allocation), content="()")
}

///|
test "Allocation checker rejects interfering values in one location" {
  let builder : @vcode.Builder[TestInst] = @vcode.Builder::new("interference", [
    I64,
    I64,
  ])
  let entry = builder.entry_block()
  let lhs = builder.parameter(0)
  let rhs = builder.parameter(1)
  let (add, result) = builder.append_body(
    entry,
    Add,
    [@vcode.Input::any(lhs), @vcode.Input::any(rhs)],
    [@vcode.Output::any(I64)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  let return_inst = builder.set_terminator(
    entry,
    Return,
    [@vcode.Input::any(result[0])],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  let function = builder.finish()
  let allocation = @vcode.Allocation::for_function(function)
  allocation.assign_value(lhs, Register(@vcode.PhysicalReg::new(0, Int)))
  |> ignore
  allocation.assign_value(rhs, Register(@vcode.PhysicalReg::new(0, Int)))
  |> ignore
  allocation.assign_value(result[0], Register(@vcode.PhysicalReg::new(1, Int)))
  |> ignore
  allocation.assign_operand(add, 0, @vcode.PhysicalReg::new(0, Int)) |> ignore
  allocation.assign_operand(add, 1, @vcode.PhysicalReg::new(0, Int)) |> ignore
  allocation.assign_operand(add, 2, @vcode.PhysicalReg::new(1, Int)) |> ignore
  allocation.assign_operand(return_inst, 0, @vcode.PhysicalReg::new(1, Int))
  |> ignore
  @vcode.verify_allocated(function, allocation) catch {
    error =>
      inspect(error, content="Interference(left=v0, right=v1, location=p0:int)")
  }
}

///|
test "Allocation checker keeps register-only and location-aware inputs distinct" {
  let builder : @vcode.Builder[TestInst] = @vcode.Builder::new(
    "operand_location",
    [I64],
  )
  let entry = builder.entry_block()
  let value = builder.parameter(0)
  let return_inst = builder.set_terminator(
    entry,
    Return,
    [@vcode.Input::any(value)],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  let function = builder.finish()
  let allocation = @vcode.Allocation::for_function(function)
  let slot = allocation.create_stack_slot(I64, 8, 8)
  allocation.assign_value(value, Stack(slot)) |> ignore
  allocation.assign_operand_location(return_inst, 0, Stack(slot)) |> ignore
  let error = try {
    @vcode.verify_allocated(function, allocation)
    "accepted"
  } catch {
    error => error.to_string()
  }
  inspect(
    error,
    content="RegisterConstraintViolation(instruction=i0, operand=0)",
  )
}

///|
test "Allocation checker requires and validates edge parallel moves" {
  let builder : @vcode.Builder[TestInst] = @vcode.Builder::new("edge_move", [
    I64,
  ])
  let entry = builder.entry_block()
  let value = builder.parameter(0)
  let exit = builder.create_block([I64])
  builder.set_terminator(
    entry,
    Jump,
    [],
    [@vcode.Edge::new(exit, [value])],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let parameter = builder.block_parameter(exit, 0)
  let return_inst = builder.set_terminator(
    exit,
    Return,
    [@vcode.Input::any(parameter)],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  let function = builder.finish()
  let allocation = @vcode.Allocation::for_function(function)
  let source : @vcode.Location = Register(@vcode.PhysicalReg::new(0, Int))
  let destination : @vcode.Location = Register(@vcode.PhysicalReg::new(1, Int))
  allocation.assign_value(value, source) |> ignore
  allocation.assign_value(parameter, destination) |> ignore
  allocation.assign_operand(return_inst, 0, @vcode.PhysicalReg::new(1, Int))
  |> ignore
  @vcode.verify_allocated(function, allocation) catch {
    error => inspect(error, content="InvalidEdgeMove(index=-1)")
  }
  allocation.add_edit(
    @vcode.Edit::edge_move(entry, 0, value, source, destination),
  )
  |> ignore
  assert_eq(allocation.edge_edits_at(entry, 0).length(), 1)
  assert_true(allocation.edge_edits_at(entry, 1).is_empty())
  let foreign = build_test_function()
  assert_true(allocation.edge_edits_at(foreign.entry_block(), 0).is_empty())
  @vcode.verify_allocated(function, allocation)
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
  let allocation = @vcode.Allocation::for_function(function)
  @vcode.verify_allocated(function, allocation) catch {
    error => inspect(error, content="MissingValueLocation(value=v0)")
  }
  let frame = @vcode.FrameLayout::new(function, allocation, 16, 16)
  @vcode.verify_framed(function, allocation, frame) catch {
    error =>
      inspect(
        error,
        content="AllocationFailure(cause=MissingValueLocation(value=v0))",
      )
  }
  @vcode.verify_emission_input(function, allocation, frame) catch {
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
  let allocation = @vcode.Allocation::for_function(function)
  let foreign_allocation = @vcode.Allocation::for_function(foreign)
  let foreign_slot = foreign_allocation.create_stack_slot(I64, 8, 8)
  assert_false(
    allocation.assign_value(
      foreign.value_at(0).unwrap(),
      Register(@vcode.PhysicalReg::new(0, Int)),
    ),
  )
  assert_false(
    allocation.assign_operand(
      foreign.instruction_at(0).unwrap(),
      0,
      @vcode.PhysicalReg::new(0, Int),
    ),
  )
  assert_false(
    allocation.assign_value(function.value_at(0).unwrap(), Stack(foreign_slot)),
  )
  assert_false(
    allocation.assign_operand_location(
      function.instruction_at(0).unwrap(),
      0,
      Stack(foreign_slot),
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
  let builder : @vcode.Builder[TestInst] = @vcode.Builder::new("terminated", [])
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
  try
    builder.append_body(
      entry,
      Add,
      [],
      [],
      [],
      @vcode.InstructionMetadata::empty(),
    )
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
  let builder : @vcode.Builder[TestInst] = @vcode.Builder::new("metadata", [
    GcRef64,
  ])
  let entry = builder.entry_block()
  let root = builder.parameter(0)
  builder.append_body(
    entry,
    Call,
    [@vcode.Input::any(root)],
    [],
    [],
    @vcode.InstructionMetadata::new(
      source=@native.SourceLocation::new("fixture.wat", 7, 11),
      trap=MemoryOutOfBounds,
      safepoint=GcAndCancellation,
      live_gc_roots=[root],
      symbol=External(@native.ExternalSymbol::new("runtime.grow")),
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
  @vcode.verify_selected(function)
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
