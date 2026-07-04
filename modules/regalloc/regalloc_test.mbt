///|
test "allocate abstract program registers" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0, r1])
  let block = Block::new(0)
  let inst = Instruction::new(0)
  inst.add_operand(Operand::def(v0))
  inst.add_operand(Operand::use_reg(v1))
  block.append(inst)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v0) == Some(Reg(r0)), content="true")
  inspect(allocation.location_of(v1) == Some(Reg(r1)), content="true")
  inspect(allocation.spill_count, content="0")
}

///|
test "allocate spills when class registers are exhausted" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let inst = Instruction::new(0)
  inst.add_operand(Operand::def(v0))
  inst.add_operand(Operand::def(v1))
  block.append(inst)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v1) == Some(Spill(0)), content="true")
  inspect(allocation.spill_count, content="1")
}

///|
test "linear scan reuses registers for non-overlapping intervals" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let first = Instruction::new(0)
  first.add_operand(Operand::def(v0))
  block.append(first)
  let second = Instruction::new(1)
  second.add_operand(Operand::def(v1))
  block.append(second)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v0) == Some(Reg(r0)), content="true")
  inspect(allocation.location_of(v1) == Some(Reg(r0)), content="true")
  inspect(allocation.spill_count, content="0")
}

///|
test "build_live_ranges records spans and uses" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let def_inst = Instruction::new(0)
  def_inst.add_operand(Operand::def(v0))
  block.append(def_inst)
  let use_inst = Instruction::new(1)
  use_inst.add_operand(Operand::use_reg(v0))
  block.append(use_inst)
  program.add_block(block)
  let ranges = build_live_ranges(program)
  inspect(ranges.length(), content="1")
  let range = ranges.get_by_vreg(v0).unwrap()
  inspect(range.start() == Some(ProgramPoint::new(0, 0)), content="true")
  inspect(range.end() == Some(ProgramPoint::new(0, 1)), content="true")
  inspect(range.uses.length(), content="2")
  inspect(range.uses[0].kind == LiveDef, content="true")
  inspect(range.uses[1].kind == LiveUse, content="true")
}

///|
test "build_live_ranges extends values across successor blocks" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let program = Program::new([r0])
  let entry = Block::new(0)
  let def_inst = Instruction::new(0)
  def_inst.add_operand(Operand::def(v0))
  entry.append(def_inst)
  entry.add_successor(1)
  program.add_block(entry)
  let middle = Block::new(1)
  middle.add_successor(2)
  program.add_block(middle)
  let exit = Block::new(2)
  let use_inst = Instruction::new(1)
  use_inst.add_operand(Operand::use_reg(v0))
  exit.append(use_inst)
  program.add_block(exit)
  let ranges = build_live_ranges(program)
  let range = ranges.get_by_vreg(v0).unwrap()
  inspect(
    range.ranges[0].contains(ProgramPoint::new(1, 0), ranges.block_order),
    content="true",
  )
}

///|
test "linear scan keeps successor-live values from reusing a register" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0, r1])
  let entry = Block::new(0)
  let def_v0 = Instruction::new(0)
  def_v0.add_operand(Operand::def(v0))
  entry.append(def_v0)
  entry.add_successor(1)
  program.add_block(entry)
  let middle = Block::new(1)
  let def_v1 = Instruction::new(1)
  def_v1.add_operand(Operand::def(v1))
  def_v1.add_operand(Operand::use_reg(v1))
  middle.append(def_v1)
  middle.add_successor(2)
  program.add_block(middle)
  let exit = Block::new(2)
  let use_v0 = Instruction::new(2)
  use_v0.add_operand(Operand::use_reg(v0))
  exit.append(use_v0)
  program.add_block(exit)
  let allocation = allocate(program)
  inspect(
    allocation.location_of(v0) != allocation.location_of(v1),
    content="true",
  )
  inspect(verify_allocation(program, allocation), content="()")
}

///|
test "linear scan evicts longer active interval for shorter current interval" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let long_def = Instruction::new(0)
  long_def.add_operand(Operand::def(v0))
  block.append(long_def)
  let short_live = Instruction::new(1)
  short_live.add_operand(Operand::def(v1))
  short_live.add_operand(Operand::use_reg(v1))
  block.append(short_live)
  let long_use = Instruction::new(2)
  long_use.add_operand(Operand::use_reg(v0))
  block.append(long_use)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v0) == Some(Spill(0)), content="true")
  inspect(allocation.location_of(v1) == Some(Reg(r0)), content="true")
  inspect(allocation.spill_count, content="1")
}

///|
test "linear scan honors fixed register constraints by evicting active range" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0, r1])
  let block = Block::new(0)
  let long_def = Instruction::new(0)
  long_def.add_operand(Operand::def(v0))
  block.append(long_def)
  let fixed_inst = Instruction::new(1)
  fixed_inst.add_operand(Operand::def(v1).with_constraint(FixedReg(r0)))
  fixed_inst.add_operand(Operand::use_reg(v1).with_constraint(FixedReg(r0)))
  block.append(fixed_inst)
  let long_use = Instruction::new(2)
  long_use.add_operand(Operand::use_reg(v0))
  block.append(long_use)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v0) == Some(Spill(0)), content="true")
  inspect(allocation.location_of(v1) == Some(Reg(r0)), content="true")
}

///|
test "linear scan can use fixed registers outside the allocatable pool" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let scratch : PhysicalReg = { id: 11, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let inst = Instruction::new(0)
  inst.add_operand(Operand::use_reg(v0).with_constraint(FixedReg(scratch)))
  block.append(inst)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v0) == Some(Reg(scratch)), content="true")
  inspect(verify_allocation(program, allocation), content="()")
}

///|
test "plan long-distance rematerialization clones by pure use positions" {
  let v0 : VirtualReg = { id: 0, class: Int }
  let defs : Array[RematDefInfo] = [{ vreg: v0, block_id: 0, inst_index: 0 }]
  let uses : Array[RematUseInfo] = [
    { vreg: v0, block_id: 0, inst_index: 2 },
    { vreg: v0, block_id: 0, inst_index: 4 },
    { vreg: v0, block_id: 1, inst_index: 8 },
    { vreg: v0, block_id: 0, inst_index: 9 },
  ]
  let plan = plan_long_distance_rematerializations(
    defs,
    uses,
    min_distance=4,
    per_vreg_clone_cap=1,
  )
  debug_inspect(
    plan,
    content="[{ vreg: { id: 0, class: Int }, block_id: 0, inst_index: 4 }]",
  )
}

///|
test "plan cross-block rematerialization clones once per use block" {
  let v0 : VirtualReg = { id: 0, class: Int }
  let defs : Array[RematDefInfo] = [{ vreg: v0, block_id: 0, inst_index: 0 }]
  let uses : Array[RematUseInfo] = [
    { vreg: v0, block_id: 0, inst_index: 3 },
    { vreg: v0, block_id: 1, inst_index: 2 },
    { vreg: v0, block_id: 1, inst_index: 4 },
    { vreg: v0, block_id: 2, inst_index: 1 },
  ]
  let plan = plan_cross_block_rematerializations(defs, uses)
  debug_inspect(
    plan,
    content=(
      #|[
      #|  { vreg: { id: 0, class: Int }, block_id: 1, first_inst_index: 2 },
      #|  { vreg: { id: 0, class: Int }, block_id: 2, first_inst_index: 1 },
      #|]
    ),
  )
}

///|
test "compact spill slots reuses non-overlapping scalar slots" {
  let a = ProgramRange::new(ProgramPoint::new(0, 0), ProgramPoint::new(0, 2))
  let b = ProgramRange::new(ProgramPoint::new(0, 2), ProgramPoint::new(0, 4))
  let c = ProgramRange::new(ProgramPoint::new(0, 1), ProgramPoint::new(0, 3))
  let result = compact_spill_slots(
    [
      { old_slot: 0, class: Int, ranges: [a] },
      { old_slot: 1, class: Int, ranges: [b] },
      { old_slot: 2, class: Float, ranges: [c] },
    ],
    [],
    [0],
  )
  debug_inspect(
    result,
    content=(
      #|{
      #|  remaps: [
      #|    { old_slot: 0, new_slot: 0 },
      #|    { old_slot: 1, new_slot: 0 },
      #|    { old_slot: 2, new_slot: 1 },
      #|  ],
      #|  total_slots: 2,
      #|}
    ),
  )
}

///|
test "compact spill slots honors vector alignment and no-share edges" {
  let full = ProgramRange::new(ProgramPoint::new(0, 0), ProgramPoint::new(0, 5))
  let later = ProgramRange::new(
    ProgramPoint::new(0, 5),
    ProgramPoint::new(0, 7),
  )
  let result = compact_spill_slots(
    [
      { old_slot: 0, class: Int, ranges: [full] },
      { old_slot: 1, class: Vector, ranges: [later] },
      { old_slot: 3, class: Vector, ranges: [later] },
    ],
    [{ lhs: 1, rhs: 3 }],
    [0],
  )
  debug_inspect(
    result,
    content=(
      #|{
      #|  remaps: [
      #|    { old_slot: 0, new_slot: 0 },
      #|    { old_slot: 1, new_slot: 2 },
      #|    { old_slot: 3, new_slot: 4 },
      #|  ],
      #|  total_slots: 6,
      #|}
    ),
  )
}

///|
test "priority work queue pops by priority with stable tie-breaks" {
  let queue = PriorityWorkQueue::new()
  queue.push(3, 10)
  queue.push(1, 20)
  queue.push(2, 20)
  queue.push(0, 10)
  inspect(queue.length(), content="4")
  debug_inspect(
    queue.pop(),
    content="Some({ item_id: 1, priority: 20, seq: 1 })",
  )
  debug_inspect(
    queue.pop(),
    content="Some({ item_id: 2, priority: 20, seq: 2 })",
  )
  debug_inspect(
    queue.pop(),
    content="Some({ item_id: 3, priority: 10, seq: 0 })",
  )
  debug_inspect(
    queue.pop(),
    content="Some({ item_id: 0, priority: 10, seq: 3 })",
  )
  debug_inspect(queue.pop(), content="None")
}

///|
test "choose fixed register hint by frequency and low-id tie break" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let r2 : PhysicalReg = { id: 2, class: Int }
  debug_inspect(
    choose_fixed_reg_hint([r0, r1, r2], [r2, r1, r2]),
    content="Some({ id: 2, class: Int })",
  )
  debug_inspect(
    choose_fixed_reg_hint([r0, r1, r2], [r2, r1]),
    content="Some({ id: 1, class: Int })",
  )
  debug_inspect(
    choose_fixed_reg_hint([r0], [{ id: 9, class: Int }]),
    content="None",
  )
}

///|
test "scan conflicts reports evictable owners and first conflict point" {
  let span : OrderedProgramSpan = {
    start: ProgramPoint::new(0, 1),
    start_ord: 10,
    end_ord: 30,
  }
  let occupied : Array[OccupiedProgramSpan] = [
    {
      owner_id: 7,
      span: { start: ProgramPoint::new(0, 0), start_ord: 0, end_ord: 12 },
      owner_weight: 2,
      owner_pinned: false,
    },
    {
      owner_id: 8,
      span: { start: ProgramPoint::new(0, 2), start_ord: 20, end_ord: 40 },
      owner_weight: 5,
      owner_pinned: false,
    },
  ]
  let result = scan_conflicts_with_cutoff([span], occupied, 9, None)
  debug_inspect(
    result,
    content=(
      #|{
      #|  conflict_ids: [7, 8],
      #|  max_conflict_weight: 5,
      #|  first_conflict_point: Some({ block: 0, inst: 1 }),
      #|  rejected: false,
      #|}
    ),
  )
}

///|
test "scan conflicts rejects pinned and cutoff conflicts" {
  let span : OrderedProgramSpan = {
    start: ProgramPoint::new(0, 0),
    start_ord: 0,
    end_ord: 20,
  }
  let pinned = scan_conflicts_with_cutoff(
    [span],
    [
      {
        owner_id: 1,
        span: { start: ProgramPoint::new(0, 1), start_ord: 5, end_ord: 10 },
        owner_weight: 1,
        owner_pinned: true,
      },
    ],
    9,
    None,
  )
  inspect(pinned.rejected, content="true")
  let cutoff = scan_conflicts_with_cutoff(
    [span],
    [
      {
        owner_id: 2,
        span: { start: ProgramPoint::new(0, 1), start_ord: 5, end_ord: 10 },
        owner_weight: 6,
        owner_pinned: false,
      },
    ],
    9,
    Some(4),
  )
  inspect(cutoff.rejected, content="true")
}

///|
test "linear scan co-locates tied use-def operands" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0, r1])
  let block = Block::new(0)
  let def_inst = Instruction::new(0)
  def_inst.add_operand(Operand::def(v0))
  block.append(def_inst)
  let tied_inst = Instruction::new(1)
  tied_inst.add_operand(Operand::use_reg(v0).with_tie(0))
  tied_inst.add_operand(Operand::def(v1).with_tie(0))
  block.append(tied_inst)
  let use_inst = Instruction::new(2)
  use_inst.add_operand(Operand::use_reg(v1))
  block.append(use_inst)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v0) == Some(Reg(r0)), content="true")
  inspect(allocation.location_of(v1) == Some(Reg(r0)), content="true")
  inspect(verify_allocation(program, allocation), content="()")
}

///|
test "linear scan avoids registers clobbered while range is live" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let program = Program::new([r0, r1])
  let block = Block::new(0)
  let def_inst = Instruction::new(0)
  def_inst.add_operand(Operand::def(v0))
  block.append(def_inst)
  let call_inst = Instruction::new(1)
  call_inst.add_clobber(r0)
  block.append(call_inst)
  let use_inst = Instruction::new(2)
  use_inst.add_operand(Operand::use_reg(v0))
  block.append(use_inst)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v0) == Some(Reg(r1)), content="true")
}

///|
test "verify_allocation accepts allocator output" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let inst = Instruction::new(0)
  inst.add_operand(Operand::def(v0))
  block.append(inst)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(verify_allocation(program, allocation), content="()")
}

///|
test "verify_allocation rejects clobbered live register" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let program = Program::new([r0, r1])
  let block = Block::new(0)
  let def_inst = Instruction::new(0)
  def_inst.add_operand(Operand::def(v0))
  block.append(def_inst)
  let call_inst = Instruction::new(1)
  call_inst.add_clobber(r0)
  block.append(call_inst)
  let use_inst = Instruction::new(2)
  use_inst.add_operand(Operand::use_reg(v0))
  block.append(use_inst)
  program.add_block(block)
  let allocation = Allocation::new()
  allocation.assign(v0, Reg(r0))
  try verify_allocation(program, allocation) catch {
    ClobberedRegister(_) => inspect("clobber", content="clobber")
    _ => fail("unexpected verifier error")
  } noraise {
    _ => fail("expected clobber")
  }
}

///|
test "verify_allocation rejects fixed register mismatch" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let program = Program::new([r0, r1])
  let block = Block::new(0)
  let inst = Instruction::new(0)
  inst.add_operand(Operand::def(v0).with_constraint(FixedReg(r1)))
  block.append(inst)
  program.add_block(block)
  let allocation = Allocation::new()
  allocation.assign(v0, Reg(r0))
  try verify_allocation(program, allocation) catch {
    FixedConstraintViolation(_) => inspect("fixed", content="fixed")
    _ => fail("unexpected verifier error")
  } noraise {
    _ => fail("expected fixed constraint violation")
  }
}

///|
test "verify_allocation rejects tied operands in different locations" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0, r1])
  let block = Block::new(0)
  let inst = Instruction::new(0)
  inst.add_operand(Operand::use_reg(v0).with_tie(0))
  inst.add_operand(Operand::def(v1).with_tie(0))
  block.append(inst)
  program.add_block(block)
  let allocation = Allocation::new()
  allocation.assign(v0, Reg(r0))
  allocation.assign(v1, Reg(r1))
  try verify_allocation(program, allocation) catch {
    TiedConstraintViolation(_) => inspect("tied", content="tied")
    _ => fail("unexpected verifier error")
  } noraise {
    _ => fail("expected tied constraint violation")
  }
}

///|
test "verify_allocation rejects overlapping physical register assignments" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let inst = Instruction::new(0)
  inst.add_operand(Operand::def(v0))
  inst.add_operand(Operand::def(v1))
  block.append(inst)
  program.add_block(block)
  let allocation = Allocation::new()
  allocation.assign(v0, Reg(r0))
  allocation.assign(v1, Reg(r0))
  try verify_allocation(program, allocation) catch {
    OverlappingAllocation(_) => inspect("overlap", content="overlap")
    _ => fail("unexpected verifier error")
  } noraise {
    _ => fail("expected overlap")
  }
}

///|
test "resolve_parallel_moves breaks register cycles with scratch" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let r2 : PhysicalReg = { id: 2, class: Int }
  let moves : Array[ParallelMove] = [
    { from: Reg(r0), to: Reg(r1), class: Int },
    { from: Reg(r1), to: Reg(r0), class: Int },
  ]
  let resolved = resolve_parallel_moves(moves, [r2], [])
  inspect(resolved.length(), content="3")
  inspect(resolved[0].from == Reg(r1), content="true")
  inspect(resolved[0].to == Reg(r2), content="true")
  inspect(resolved[2].to == Reg(r0), content="true")
}

///|
test "resolve_parallel_moves lowers stack to stack through scratch" {
  let scratch : PhysicalReg = { id: 10, class: Int }
  let moves : Array[ParallelMove] = [
    { from: Spill(0), to: Spill(1), class: Int },
  ]
  let resolved = resolve_parallel_moves(moves, [scratch], [])
  inspect(resolved.length(), content="2")
  inspect(resolved[0].from == Spill(0), content="true")
  inspect(resolved[0].to == Reg(scratch), content="true")
  inspect(resolved[1].from == Reg(scratch), content="true")
  inspect(resolved[1].to == Spill(1), content="true")
}

///|
test "compute approximate loop depths from successors" {
  let depths = compute_approx_loop_depths([[1], [2], [1, 3], []])
  debug_inspect(depths, content="[0, 1, 1, 0]")
}

///|
test "compute approximate loop depths ignores invalid successors" {
  let depths = compute_approx_loop_depths([[1, -1, 99], [0], []])
  debug_inspect(depths, content="[1, 1, 0]")
}

///|
test "reserve spill slots aligns vector slots" {
  let int_slot = reserve_spill_slot(0, Int)
  inspect(int_slot.slot, content="0")
  inspect(int_slot.next_slot, content="1")
  inspect(int_slot.slots_used, content="1")
  let vector_slot = reserve_spill_slot(1, Vector)
  inspect(vector_slot.slot, content="2")
  inspect(vector_slot.next_slot, content="4")
  inspect(vector_slot.slots_used, content="2")
}

///|
test "stack frame allocates spill slots" {
  let frame = StackFrame::new(16)
  let offset1 = frame.alloc_spill_slot({ id: 0, class: Int }, 8, 8)
  inspect(offset1, content="-8")
  let offset2 = frame.alloc_spill_slot({ id: 1, class: Int }, 8, 8)
  inspect(offset2, content="-16")
  frame.finalize()
  inspect(frame.size(), content="16")
}

///|
test "stack frame aligns mixed slots" {
  let frame = StackFrame::new(16)
  inspect(frame.alloc_spill_slot({ id: 0, class: Int }, 4, 4), content="-4")
  inspect(frame.alloc_spill_slot({ id: 1, class: Int }, 8, 8), content="-16")
  frame.finalize()
  inspect(frame.size(), content="16")
}

///|
test "stack frame records callee saved registers" {
  let frame = StackFrame::new(16)
  inspect(frame.add_callee_saved({ id: 19, class: Int }), content="-8")
  inspect(frame.add_callee_saved({ id: 20, class: Int }), content="-16")
  frame.finalize()
  inspect(frame.get_callee_saved().length(), content="2")
}

///|
test "spill weight applies loop and constraint bonuses" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let uses = [
    UsePosition::new(ProgramPoint::new(0, 0), LiveDef, AnyReg),
    UsePosition::new(ProgramPoint::new(1, 0), LiveUse, FixedReg(r0)),
  ]
  inspect(compute_spill_weight(uses, [0, 2]), content="22000")
}

///|
test "spill weight has minimum one" {
  inspect(compute_spill_weight([], []), content="1")
}

///|
test "reload intervals keep repeated spill-slot uses" {
  let v0 : VirtualReg = { id: 0, class: Int }
  let intervals = compute_reload_intervals([
    { block_id: 7, inst_index: 1, spill_slot: 3, vreg: v0 },
    { block_id: 7, inst_index: 4, spill_slot: 3, vreg: v0 },
  ])
  inspect(intervals.length(), content="1")
  inspect(intervals[0].block_id, content="7")
  inspect(intervals[0].spill_slot, content="3")
  inspect(intervals[0].vreg.id, content="0")
  inspect(intervals[0].vreg.class == Int, content="true")
  inspect(intervals[0].first_inst, content="1")
  inspect(intervals[0].last_inst, content="4")
}

///|
test "reload intervals reject reused spill slots" {
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let intervals = compute_reload_intervals([
    { block_id: 0, inst_index: 0, spill_slot: 2, vreg: v0 },
    { block_id: 0, inst_index: 1, spill_slot: 2, vreg: v1 },
    { block_id: 0, inst_index: 2, spill_slot: 2, vreg: v0 },
  ])
  inspect(intervals.length(), content="0")
}

///|
test "reload intervals skip vectors by default" {
  let v0 : VirtualReg = { id: 0, class: Vector }
  inspect(
    compute_reload_intervals([
      { block_id: 0, inst_index: 0, spill_slot: 1, vreg: v0 },
      { block_id: 0, inst_index: 2, spill_slot: 1, vreg: v0 },
    ]).length(),
    content="0",
  )
  inspect(
    compute_reload_intervals(
      [
        { block_id: 0, inst_index: 0, spill_slot: 1, vreg: v0 },
        { block_id: 0, inst_index: 2, spill_slot: 1, vreg: v0 },
      ],
      allow_vector=true,
    ).length(),
    content="1",
  )
}
