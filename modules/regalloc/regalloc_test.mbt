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
test "ordered span conflict scan skips ended occupied spans" {
  let occupied : Array[OrderedProgramSpan] = [
    { start: ProgramPoint::new(0, 0), start_ord: 0, end_ord: 4 },
    { start: ProgramPoint::new(0, 1), start_ord: 8, end_ord: 12 },
  ]
  inspect(lower_bound_ordered_span_by_end(occupied, 6), content="1")
  inspect(
    has_ordered_span_conflict(
      [{ start: ProgramPoint::new(0, 2), start_ord: 6, end_ord: 7 }],
      occupied,
    ),
    content="false",
  )
  inspect(
    has_ordered_span_conflict(
      [{ start: ProgramPoint::new(0, 2), start_ord: 6, end_ord: 9 }],
      occupied,
    ),
    content="true",
  )
}

///|
test "compute block point bases from block order and lengths" {
  debug_inspect(
    compute_block_point_bases([2, 0, 1], [3, 1, 0]),
    content="[0, 6, 10]",
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
test "plan register probe order uses phased rotation and skip" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let r2 : PhysicalReg = { id: 2, class: Int }
  let r3 : PhysicalReg = { id: 3, class: Int }
  let order = plan_register_probe_order(
    [r0, r1, r2, r3],
    [r0, r1],
    [r2, r3],
    true,
    2,
    1,
    Some(r1),
  )
  debug_inspect(
    order,
    content="[{ id: 0, class: Int }, { id: 3, class: Int }, { id: 2, class: Int }]",
  )
  let flat = plan_register_probe_order([r0, r1, r2], [], [], false, 2, 2, None)
  debug_inspect(flat, content="[{ id: 2, class: Int }, { id: 0, class: Int }]")
}

///|
test "select available registers for call-crossing bundles" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let f0 : PhysicalReg = { id: 0, class: Float }
  let f1 : PhysicalReg = { id: 1, class: Float }
  let v0 : PhysicalReg = { id: 0, class: Vector }
  debug_inspect(
    select_available_regs_for_bundle(Int, false, [r0, r1], [r1]),
    content="[{ id: 0, class: Int }, { id: 1, class: Int }]",
  )
  debug_inspect(
    select_available_regs_for_bundle(Int, true, [r0, r1], [r1]),
    content="[{ id: 1, class: Int }]",
  )
  debug_inspect(
    select_available_regs_for_bundle(Float, true, [f0, f1], [f1]),
    content="[{ id: 1, class: Float }]",
  )
  debug_inspect(
    select_available_regs_for_bundle(Vector, true, [v0], [v0]),
    content="[]",
  )
}

///|
test "select caller saved registers from callee saved set" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let r2 : PhysicalReg = { id: 2, class: Int }
  let invalid : PhysicalReg = { id: -1, class: Int }
  inspect(max_physical_reg_id([r0, r2]), content="2")
  debug_inspect(
    select_caller_saved_regs([r0, r1, invalid, r2], [r1]),
    content="[{ id: 0, class: Int }, { id: 2, class: Int }]",
  )
}

///|
test "eviction policy chooses cutoff, best conflict, and later split" {
  debug_inspect(eviction_cutoff(Some(3), Some(5)), content="Some(5)")
  debug_inspect(eviction_cutoff(Some(3), None), content="Some(3)")
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  inspect(
    should_take_eviction_candidate(Some(4), Some(r0), 3, r1, None),
    content="true",
  )
  inspect(
    should_take_eviction_candidate(Some(4), Some(r0), 4, r1, Some(r1)),
    content="true",
  )
  inspect(
    should_take_eviction_candidate(Some(4), Some(r1), 4, r0, Some(r1)),
    content="false",
  )
  inspect(
    should_take_split_candidate(
      Some(5),
      Some(ProgramPoint::new(0, 1)),
      5,
      ProgramPoint::new(0, 3),
      [0],
    ),
    content="true",
  )
}

///|
test "bundle merge planner coalesces only compatible non-overlapping ranges" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let ranges : Array[BundleMergeRange] = [
    {
      id: 0,
      class: Int,
      ranges: [
        ProgramRange::new(ProgramPoint::new(0, 0), ProgramPoint::new(0, 2)),
      ],
      fixed_reg: Some(r0),
      has_fixed_conflict: false,
      has_fixed_def: false,
    },
    {
      id: 1,
      class: Int,
      ranges: [
        ProgramRange::new(ProgramPoint::new(0, 4), ProgramPoint::new(0, 6)),
      ],
      fixed_reg: Some(r0),
      has_fixed_conflict: false,
      has_fixed_def: false,
    },
    {
      id: 2,
      class: Int,
      ranges: [
        ProgramRange::new(ProgramPoint::new(0, 1), ProgramPoint::new(0, 3)),
      ],
      fixed_reg: Some(r0),
      has_fixed_conflict: false,
      has_fixed_def: false,
    },
    {
      id: 3,
      class: Int,
      ranges: [
        ProgramRange::new(ProgramPoint::new(0, 8), ProgramPoint::new(0, 10)),
      ],
      fixed_reg: Some(r1),
      has_fixed_conflict: false,
      has_fixed_def: false,
    },
  ]
  let plan = plan_bundle_merges(
    ranges,
    [
      { target: 0, source: 1 },
      { target: 0, source: 2 },
      { target: 0, source: 3 },
    ],
    [0],
    [16],
  )
  inspect(plan.range_to_bundle[0] == plan.range_to_bundle[1], content="true")
  inspect(plan.range_to_bundle[0] == plan.range_to_bundle[2], content="false")
  inspect(plan.range_to_bundle[0] == plan.range_to_bundle[3], content="false")
}

///|
test "bundle split planner partitions around split point and handles fallbacks" {
  let ranges : Array[BundleSplitRange] = [
    {
      range_id: 0,
      start: Some(ProgramPoint::new(0, 0)),
      end: Some(ProgramPoint::new(0, 2)),
    },
    {
      range_id: 1,
      start: Some(ProgramPoint::new(0, 4)),
      end: Some(ProgramPoint::new(0, 8)),
    },
  ]
  let split = plan_bundle_split(
    ranges,
    Some(ProgramPoint::new(0, 3)),
    [0],
    0,
    8,
  )
  match split {
    Split(before, after) => {
      debug_inspect(before, content="[0]")
      debug_inspect(after, content="[1]")
    }
    _ => abort("expected split")
  }
  match plan_bundle_split(ranges, Some(ProgramPoint::new(0, 9)), [0], 0, 8) {
    Minimal => ()
    _ => abort("expected minimal fallback")
  }
  match plan_bundle_split(ranges, None, [0], 0, 8) {
    SpillWhole => ()
    _ => abort("expected whole-bundle spill")
  }
}

///|
test "allocation policy covers retry and vector call spilling" {
  inspect(allocation_iteration_limit(7), content="70")
  inspect(should_force_spill_after_retry(4, 3, false, false), content="true")
  inspect(should_force_spill_after_retry(4, 3, true, false), content="false")
  inspect(should_force_spill_after_retry(4, 3, false, true), content="false")
  inspect(should_force_spill_for_class_and_call(Vector, true), content="true")
  inspect(should_force_spill_for_class_and_call(Float, true), content="false")
}

///|
test "fixed constraint edit planner emits before and after moves" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let r2 : PhysicalReg = { id: 2, class: Int }
  let edits = plan_fixed_constraint_edits([
    {
      block_index: 1,
      inst_index: 2,
      uses: [
        { operand: Virtual(Some(Reg(r0)), 10), required: r1 },
        { operand: Virtual(Some(Spill(3)), 11), required: r2 },
        { operand: Physical(r2, 12), required: r0 },
      ],
      defs: [
        { operand: Virtual(Some(Reg(r0)), 13), required: r1 },
        { operand: Virtual(Some(Spill(4)), 14), required: r2 },
      ],
    },
  ])
  inspect(edits.length(), content="1")
  inspect(edits[0].block_index, content="1")
  inspect(edits[0].inst_index, content="2")
  debug_inspect(
    edits[0].before,
    content=(
      #|[
      #|  {
      #|    from: Reg({ id: 0, class: Int }),
      #|    to: Reg({ id: 1, class: Int }),
      #|    class_tag: 10,
      #|  },
      #|  { from: Spill(3), to: Reg({ id: 2, class: Int }), class_tag: 11 },
      #|  {
      #|    from: Reg({ id: 2, class: Int }),
      #|    to: Reg({ id: 0, class: Int }),
      #|    class_tag: 12,
      #|  },
      #|]
    ),
  )
  debug_inspect(
    edits[0].after,
    content=(
      #|[
      #|  {
      #|    from: Reg({ id: 1, class: Int }),
      #|    to: Reg({ id: 0, class: Int }),
      #|    class_tag: 13,
      #|  },
      #|  { from: Reg({ id: 2, class: Int }), to: Spill(4), class_tag: 14 },
      #|]
    ),
  )
}

///|
test "temp register pool prefers scratch and high-index candidates" {
  let used = Array::make(12, false)
  used[10] = true
  debug_inspect(
    plan_temp_register_pool(used, [3, 9], [1, 10, 11], [2, 8, 9]),
    content="[3, 9, 11, 8, 1, 2]",
  )
}

///|
test "temp register choice rotates pool and steals with preserve slot" {
  debug_inspect(
    choose_temp_register(Int, [3], [3, 4], [5], [], true, 0, 7),
    content=(
      #|{
      #|  preg: { id: 4, class: Int },
      #|  next_cursor: 1,
      #|  save_slot: None,
      #|  next_spill_slot: 7,
      #|}
    ),
  )
  debug_inspect(
    choose_temp_register(Vector, [3, 4], [3, 4], [5], [], true, 0, 7),
    content=(
      #|{
      #|  preg: { id: 5, class: Vector },
      #|  next_cursor: 1,
      #|  save_slot: Some(8),
      #|  next_spill_slot: 10,
      #|}
    ),
  )
}

///|
test "active reload cache tracks block-local slot reloads" {
  let cache = ActiveReloadCache::new(3)
  debug_inspect(cache.get(1, 1), content="None")
  cache.set(1, 7, 1)
  debug_inspect(cache.get(1, 1), content="Some(7)")
  debug_inspect(cache.get(1, 2), content="None")
  cache.clear(1)
  debug_inspect(cache.get(1, 1), content="None")
  cache.set(4, 9, 1)
  debug_inspect(cache.get(4, 1), content="None")
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
