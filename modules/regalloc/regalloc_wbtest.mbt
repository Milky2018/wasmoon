///|
test "live range lookup uses a direct per-class dense index" {
  let ranges = LiveRangeSet::LiveRangeSet([])
  let int_reg : VirtualReg = { id: 4096, class: Int }
  let float_reg : VirtualReg = { id: 4096, class: Float }
  ranges.add_range(LiveRange(0, int_reg))
  ranges.add_range(LiveRange(1, float_reg))
  debug_inspect(
    (
      ranges.int_ranges_by_id.length(),
      ranges.float_ranges_by_id.length(),
      ranges.vector_ranges_by_id.length(),
      ranges.get_by_vreg(int_reg).map(range => range.id()),
      ranges.get_by_vreg(float_reg).map(range => range.id()),
    ),
    content="(4097, 4097, 0, Some(0), Some(1))",
  )
}

///|
test "sparse vreg set promotes and unions high virtual register ids" {
  let left = SparseVRegSet::new()
  for id in [0, 64, 128, 192, 256, 320, 384, 448, 512] {
    left.set(id, true)
  }
  let right = SparseVRegSet::new()
  right.set(1_000_000, true)
  right.set(128, true)
  inspect(left.union_with(right), content="true")
  inspect(left.union_with(right), content="false")
  debug_inspect(
    left.to_sorted_array(),
    content="[0, 64, 128, 192, 256, 320, 384, 448, 512, 1000000]",
  )
  left.set(1_000_000, false)
  debug_inspect(
    left.to_sorted_array(),
    content="[0, 64, 128, 192, 256, 320, 384, 448, 512]",
  )
}

///|
test "sparse live sets preserve defs and successor propagation" {
  let cfg : DenseCfgEdges = { preds: [[], [0], [1]], succs: [[1], [2], []] }
  let sets = compute_live_sets_from_use_defs(3, 1_000_001, cfg, [
    {
      vreg_id: 1_000_000,
      def_point: Some(ProgramPoint(0, 0)),
      is_entry_param_def: false,
      use_points: [ProgramPoint(2, 0)],
    },
  ])
  debug_inspect(sets.live_in, content="[[], [1000000], [1000000]]")
  debug_inspect(sets.live_out, content="[[1000000], [1000000], []]")
}

///|
test "sparse live sets cover diamond loop and unreachable CFG regions" {
  let cfg : DenseCfgEdges = {
    preds: [[], [0, 3], [0], [1, 2], []],
    succs: [[1, 2], [3], [3], [1], []],
  }
  let sets = compute_live_sets_from_use_defs(5, 1_000_001, cfg, [
    {
      vreg_id: 7,
      def_point: Some(ProgramPoint(0, 0)),
      is_entry_param_def: false,
      use_points: [ProgramPoint(3, 0)],
    },
    {
      vreg_id: 1_000_000,
      def_point: None,
      is_entry_param_def: false,
      use_points: [ProgramPoint(4, 0)],
    },
  ])
  debug_inspect(sets.live_in, content="[[], [7], [7], [7], [1000000]]")
  debug_inspect(sets.live_out, content="[[7], [7], [7], [7], []]")
}

///|
test "count sorted integer points in open range" {
  let points = [2, 4, 4, 8, 10]
  inspect(@planning.lower_bound_sorted_int(points, 4), content="1")
  inspect(@planning.upper_bound_sorted_int(points, 4), content="3")
  inspect(@planning.count_sorted_ints_in_open_range(points, 4, 10), content="1")
  inspect(@planning.count_sorted_ints_in_open_range(points, 1, 11), content="5")
  inspect(
    @planning.count_sorted_ints_in_open_range(points, 10, 12),
    content="0",
  )
}

///|
test "compute sparse live sets over reusable CFG model" {
  let cfg : DenseCfgEdges = { preds: [[], [0], [1]], succs: [[1], [2], []] }
  let live_sets = compute_live_sets_from_use_defs(3, 2, cfg, [
    {
      vreg_id: 0,
      def_point: Some(ProgramPoint(0, 1)),
      is_entry_param_def: false,
      use_points: [ProgramPoint(2, 0)],
    },
    {
      vreg_id: 1,
      def_point: Some(ProgramPoint(0, -2)),
      is_entry_param_def: true,
      use_points: [ProgramPoint(1, 0)],
    },
  ])
  debug_inspect(live_sets.live_in, content="[[1], [0, 1], [0]]")
  debug_inspect(live_sets.live_out, content="[[0, 1], [0], []]")
}

///|
test "plan long-distance rematerialization clones by pure use positions" {
  let v0 : VirtualReg = { id: 0, class: Int }
  let defs : Array[@planning.RematDefInfo] = [
    { vreg: v0, block_id: 0, inst_index: 0 },
  ]
  let uses : Array[@planning.RematUseInfo] = [
    { vreg: v0, block_id: 0, inst_index: 2 },
    { vreg: v0, block_id: 0, inst_index: 4 },
    { vreg: v0, block_id: 1, inst_index: 8 },
    { vreg: v0, block_id: 0, inst_index: 9 },
  ]
  let plan = @planning.plan_long_distance_rematerializations(
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
  let defs : Array[@planning.RematDefInfo] = [
    { vreg: v0, block_id: 0, inst_index: 0 },
  ]
  let uses : Array[@planning.RematUseInfo] = [
    { vreg: v0, block_id: 0, inst_index: 3 },
    { vreg: v0, block_id: 1, inst_index: 2 },
    { vreg: v0, block_id: 1, inst_index: 4 },
    { vreg: v0, block_id: 2, inst_index: 1 },
  ]
  let plan = @planning.plan_cross_block_rematerializations(defs, uses)
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
  let a = ProgramRange::ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 2))
  let b = ProgramRange::ProgramRange(ProgramPoint(0, 2), ProgramPoint(0, 4))
  let c = ProgramRange::ProgramRange(ProgramPoint(0, 1), ProgramPoint(0, 3))
  let result = @planning.compact_spill_slots(
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
  let full = ProgramRange::ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 5))
  let later = ProgramRange::ProgramRange(ProgramPoint(0, 5), ProgramPoint(0, 7))
  let result = @planning.compact_spill_slots(
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
test "choose fixed register hint by frequency and low-id tie break" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let r2 : PhysicalReg = { id: 2, class: Int }
  debug_inspect(
    @planning.choose_fixed_reg_hint([r0, r1, r2], [r2, r1, r2]),
    content="Some({ id: 2, class: Int })",
  )
  debug_inspect(
    @planning.choose_fixed_reg_hint([r0, r1, r2], [r2, r1]),
    content="Some({ id: 1, class: Int })",
  )
  debug_inspect(
    @planning.choose_fixed_reg_hint([r0], [{ id: 9, class: Int }]),
    content="None",
  )
}

///|
test "scan conflicts reports evictable owners and first conflict point" {
  let span : @planning.OrderedProgramSpan = {
    start: ProgramPoint(0, 1),
    start_ord: 10,
    end_ord: 30,
  }
  let occupied : Array[@planning.OccupiedProgramSpan] = [
    {
      owner_id: 7,
      span: { start: ProgramPoint(0, 0), start_ord: 0, end_ord: 12 },
      owner_weight: 2,
      owner_pinned: false,
    },
    {
      owner_id: 8,
      span: { start: ProgramPoint(0, 2), start_ord: 20, end_ord: 40 },
      owner_weight: 5,
      owner_pinned: false,
    },
  ]
  let result = @planning.scan_conflicts_with_cutoff([span], occupied, 9, None)
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
  let occupied : Array[@planning.OrderedProgramSpan] = [
    { start: ProgramPoint(0, 0), start_ord: 0, end_ord: 4 },
    { start: ProgramPoint(0, 1), start_ord: 8, end_ord: 12 },
  ]
  inspect(@planning.lower_bound_ordered_span_by_end(occupied, 6), content="1")
  inspect(
    @planning.has_ordered_span_conflict(
      [{ start: ProgramPoint(0, 2), start_ord: 6, end_ord: 7 }],
      occupied,
    ),
    content="false",
  )
  inspect(
    @planning.has_ordered_span_conflict(
      [{ start: ProgramPoint(0, 2), start_ord: 6, end_ord: 9 }],
      occupied,
    ),
    content="true",
  )
}

///|
test "allocated span table inserts and removes by owner" {
  let a : @planning.OrderedProgramSpan = {
    start: ProgramPoint(0, 0),
    start_ord: 0,
    end_ord: 4,
  }
  let b : @planning.OrderedProgramSpan = {
    start: ProgramPoint(0, 2),
    start_ord: 8,
    end_ord: 12,
  }
  let c : @planning.OrderedProgramSpan = {
    start: ProgramPoint(0, 1),
    start_ord: 5,
    end_ord: 7,
  }
  let inserted = @planning.insert_allocated_spans(
    [{ owner_id: 1, span: a }, { owner_id: 3, span: b }],
    2,
    [c],
  )
  debug_inspect(
    inserted,
    content=(
      #|[
      #|  {
      #|    owner_id: 1,
      #|    span: { start: { block: 0, inst: 0 }, start_ord: 0, end_ord: 4 },
      #|  },
      #|  {
      #|    owner_id: 2,
      #|    span: { start: { block: 0, inst: 1 }, start_ord: 5, end_ord: 7 },
      #|  },
      #|  {
      #|    owner_id: 3,
      #|    span: { start: { block: 0, inst: 2 }, start_ord: 8, end_ord: 12 },
      #|  },
      #|]
    ),
  )
  debug_inspect(
    @planning.remove_allocated_spans(inserted, 2),
    content=(
      #|[
      #|  {
      #|    owner_id: 1,
      #|    span: { start: { block: 0, inst: 0 }, start_ord: 0, end_ord: 4 },
      #|  },
      #|  {
      #|    owner_id: 3,
      #|    span: { start: { block: 0, inst: 2 }, start_ord: 8, end_ord: 12 },
      #|  },
      #|]
    ),
  )
}

///|
test "compute block point bases from block order and lengths" {
  debug_inspect(
    @planning.compute_block_point_bases([2, 0, 1], [3, 1, 0]),
    content="[0, 6, 10]",
  )
}

///|
test "scan conflicts rejects pinned and cutoff conflicts" {
  let span : @planning.OrderedProgramSpan = {
    start: ProgramPoint(0, 0),
    start_ord: 0,
    end_ord: 20,
  }
  let pinned = @planning.scan_conflicts_with_cutoff(
    [span],
    [
      {
        owner_id: 1,
        span: { start: ProgramPoint(0, 1), start_ord: 5, end_ord: 10 },
        owner_weight: 1,
        owner_pinned: true,
      },
    ],
    9,
    None,
  )
  inspect(pinned.rejected, content="true")
  let cutoff = @planning.scan_conflicts_with_cutoff(
    [span],
    [
      {
        owner_id: 2,
        span: { start: ProgramPoint(0, 1), start_ord: 5, end_ord: 10 },
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
  let order = @planning.plan_register_probe_order(
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
  let flat = @planning.plan_register_probe_order(
    [r0, r1, r2],
    [],
    [],
    false,
    2,
    2,
    None,
  )
  debug_inspect(flat, content="[{ id: 2, class: Int }, { id: 0, class: Int }]")
}

///|
test "fixed constraint edit planner emits before and after moves" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let r2 : PhysicalReg = { id: 2, class: Int }
  let edits = @planning.plan_fixed_constraint_edits([
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
    @planning.plan_temp_register_pool(used, [3, 9], [1, 10, 11], [2, 8, 9]),
    content="[3, 9, 11, 8, 1, 2]",
  )
}

///|
test "temp register choice rotates pool and steals with preserve slot" {
  debug_inspect(
    @planning.choose_temp_register(Int, [3], [3, 4], [5], [], true, 0, 7),
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
    @planning.choose_temp_register(Vector, [3, 4], [3, 4], [5], [], true, 0, 7),
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
  let cache = @planning.ActiveReloadCache::ActiveReloadCache(3)
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
test "resolve_parallel_moves breaks register cycles with scratch" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let r2 : PhysicalReg = { id: 2, class: Int }
  let moves : Array[@planning.ParallelMove] = [
    { from: Reg(r0), to: Reg(r1), class: Int },
    { from: Reg(r1), to: Reg(r0), class: Int },
  ]
  let resolved = @planning.resolve_parallel_moves(moves, [r2], [])
  inspect(resolved.length(), content="3")
  inspect(resolved[0].from == Reg(r1), content="true")
  inspect(resolved[0].to == Reg(r2), content="true")
  inspect(resolved[2].to == Reg(r0), content="true")
}

///|
test "resolve_parallel_moves lowers stack to stack through scratch" {
  let scratch : PhysicalReg = { id: 10, class: Int }
  let moves : Array[@planning.ParallelMove] = [
    { from: Spill(0), to: Spill(1), class: Int },
  ]
  let resolved = @planning.resolve_parallel_moves(moves, [scratch], [])
  inspect(resolved.length(), content="2")
  inspect(resolved[0].from == Spill(0), content="true")
  inspect(resolved[0].to == Reg(scratch), content="true")
  inspect(resolved[1].from == Reg(scratch), content="true")
  inspect(resolved[1].to == Spill(1), content="true")
}

///|
test "instruction edit resolution preserves position order and edge edits" {
  let plan = AllocationPlan::new(4)
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let r2 : PhysicalReg = { id: 2, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let v2 : VirtualReg = { id: 2, class: Int }
  plan.add_edit({ value: v0, from: Reg(r0), to: Reg(r1), position: Before(2) })
  plan.add_edit({ value: v1, from: Reg(r1), to: Reg(r2), position: After(0) })
  plan.add_edit({ value: v2, from: Reg(r2), to: Reg(r0), position: Before(1) })
  plan.add_edit({ value: v0, from: Reg(r0), to: Reg(r1), position: Before(2) })
  plan.add_edit({
    value: v1,
    from: Reg(r1),
    to: Reg(r0),
    position: Edge(source_block=3, successor_index=1),
  })
  resolve_instruction_edits(plan, MachineEnv::new([r0, r1, r2], [r2]))
  debug_inspect(
    plan.edits(),
    content=(
      #|[
      #|  {
      #|    value: { id: 0, class: Int },
      #|    from: Reg({ id: 0, class: Int }),
      #|    to: Reg({ id: 1, class: Int }),
      #|    position: Before(2),
      #|  },
      #|  {
      #|    value: { id: 1, class: Int },
      #|    from: Reg({ id: 1, class: Int }),
      #|    to: Reg({ id: 2, class: Int }),
      #|    position: After(0),
      #|  },
      #|  {
      #|    value: { id: 2, class: Int },
      #|    from: Reg({ id: 2, class: Int }),
      #|    to: Reg({ id: 0, class: Int }),
      #|    position: Before(1),
      #|  },
      #|  {
      #|    value: { id: 1, class: Int },
      #|    from: Reg({ id: 1, class: Int }),
      #|    to: Reg({ id: 0, class: Int }),
      #|    position: Edge(source_block=3, successor_index=1),
      #|  },
      #|]
    ),
  )
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
  let frame = @planning.StackFrame::StackFrame(16)
  let offset1 = frame.alloc_spill_slot({ id: 0, class: Int }, 8, 8)
  inspect(offset1, content="-8")
  let offset2 = frame.alloc_spill_slot({ id: 1, class: Int }, 8, 8)
  inspect(offset2, content="-16")
  frame.finalize()
  inspect(frame.size(), content="16")
}

///|
test "stack frame aligns mixed slots" {
  let frame = @planning.StackFrame::StackFrame(16)
  inspect(frame.alloc_spill_slot({ id: 0, class: Int }, 4, 4), content="-4")
  inspect(frame.alloc_spill_slot({ id: 1, class: Int }, 8, 8), content="-16")
  frame.finalize()
  inspect(frame.size(), content="16")
}

///|
test "stack frame records callee saved registers" {
  let frame = @planning.StackFrame::StackFrame(16)
  inspect(frame.add_callee_saved({ id: 19, class: Int }), content="-8")
  inspect(frame.add_callee_saved({ id: 20, class: Int }), content="-16")
  frame.finalize()
  inspect(frame.get_callee_saved().length(), content="2")
}

///|
test "spill weight applies loop and constraint bonuses" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let uses : Array[UsePosition] = [
    UsePosition(ProgramPoint(0, 0), LiveDef, AnyReg),
    UsePosition(ProgramPoint(1, 0), LiveUse, FixedReg(r0)),
  ]
  inspect(@planning.compute_spill_weight(uses, [0, 2]), content="22000")
}

///|
test "spill weight has minimum one" {
  inspect(@planning.compute_spill_weight([], []), content="1")
}

///|
test "reload intervals keep repeated spill-slot uses" {
  let v0 : VirtualReg = { id: 0, class: Int }
  let intervals = @planning.compute_reload_intervals([
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
  let intervals = @planning.compute_reload_intervals([
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
    @planning.compute_reload_intervals([
      { block_id: 0, inst_index: 0, spill_slot: 1, vreg: v0 },
      { block_id: 0, inst_index: 2, spill_slot: 1, vreg: v0 },
    ]).length(),
    content="0",
  )
  inspect(
    @planning.compute_reload_intervals(
      [
        { block_id: 0, inst_index: 0, spill_slot: 1, vreg: v0 },
        { block_id: 0, inst_index: 2, spill_slot: 1, vreg: v0 },
      ],
      allow_vector=true,
    ).length(),
    content="1",
  )
}

///|
priv struct VerifierCfgView {
  value_count : Int
  blocks : Array[Array[Int]]
  operands : Array[Array[Operand]]
  successors : Array[Array[Int]]
  entry_values : Array[VirtualReg]
  parameters : Array[Array[VirtualReg]]
  edge_arguments : Array[Array[Array[VirtualReg]]]
  successor_queries : Ref[Int]
  block_visits : Ref[Int]
}

///|
impl FunctionView for VerifierCfgView with fn value_count(self) -> Int {
  self.value_count
}

///|
impl FunctionView for VerifierCfgView with fn value_class(_self, _value) -> RegClass {
  Int
}

///|
impl FunctionView for VerifierCfgView with fn value_spill_size(_self, _value) -> Int {
  8
}

///|
impl FunctionView for VerifierCfgView with fn value_spill_alignment(
  _self,
  _value,
) -> Int {
  8
}

///|
impl FunctionView for VerifierCfgView with fn values_share_spill_slot(
  _self,
  _lhs,
  _rhs,
) -> Bool {
  true
}

///|
impl FunctionView for VerifierCfgView with fn entry_values(self) -> Array[
  VirtualReg,
] {
  self.entry_values.copy()
}

///|
impl FunctionView for VerifierCfgView with fn block_count(self) -> Int {
  self.blocks.length()
}

///|
impl FunctionView for VerifierCfgView with fn block_id_at(_self, block) -> Int {
  block
}

///|
impl FunctionView for VerifierCfgView with fn block_parameters(self, block) -> Array[
  VirtualReg,
] {
  self.parameters[block].copy()
}

///|
impl FunctionView for VerifierCfgView with fn block_instructions(self, block) -> Array[
  Int,
] {
  self.block_visits.val = self.block_visits.val + 1
  self.blocks[block].copy()
}

///|
impl FunctionView for VerifierCfgView with fn block_successors(self, block) -> Array[
  Int,
] {
  self.successor_queries.val = self.successor_queries.val + 1
  self.successors[block].copy()
}

///|
impl FunctionView for VerifierCfgView with fn edge_arguments(
  self,
  block,
  successor,
) -> Array[VirtualReg] {
  self.edge_arguments[block][successor].copy()
}

///|
impl FunctionView for VerifierCfgView with fn instruction_operands(
  self,
  instruction,
) -> Array[Operand] {
  self.operands[instruction].copy()
}

///|
impl FunctionView for VerifierCfgView with fn instruction_clobbers(
  _self,
  _instruction,
) -> Array[PhysicalReg] {
  []
}

///|
test "operand assignment reuses a tied group's resident register" {
  let spilled : VirtualReg = { id: 0, class: Int }
  let resident : VirtualReg = { id: 1, class: Int }
  let r0 : PhysicalReg = { id: 0, class: Int }
  let function : VerifierCfgView = {
    value_count: 2,
    blocks: [[0]],
    operands: [
      [
        Operand::use_reg(spilled).with_constraint(AnyLocation).with_tie(0),
        Operand::def(resident).with_tie(0),
      ],
    ],
    successors: [[]],
    entry_values: [spilled],
    parameters: [[]],
    edge_arguments: [[]],
    successor_queries: Ref(0),
    block_visits: Ref(0),
  }
  let plan = AllocationPlan::new(2)
  let slot = plan.create_spill_slot(8, 8)
  plan.assign_value(spilled, Spill(slot))
  plan.assign_value(resident, Reg(r0))
  let (segments, segments_by_value) = build_allocation_segments(
    build_function_live_ranges(function),
    allocatable=[r0],
  )
  for segment in segments_by_value[spilled.id] {
    segments[segment].location = Some(SegmentSpill)
  }
  for segment in segments_by_value[resident.id] {
    segments[segment].location = Some(SegmentReg(r0))
  }
  assign_segment_operands(
    plan,
    function,
    MachineEnv::new([r0], []),
    segments,
    segments_by_value,
  )
  verify_function_allocation(function, MachineEnv::new([r0], []), plan)
  debug_inspect(
    (plan.operand_location(0, 0), plan.operand_location(0, 1)),
    content="(Some(Reg({ id: 0, class: Int })), Some(Reg({ id: 0, class: Int })))",
  )
}

///|
fn verify_wrong_location(
  function : VerifierCfgView,
  def_instruction : Int?,
  use_instruction : Int,
) -> VerifyError? {
  let value : VirtualReg = { id: 0, class: Int }
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let plan = AllocationPlan::new(1)
  plan.assign_value(value, Reg(r0))
  if def_instruction is Some(instruction) {
    plan.assign_operand(instruction, 0, Reg(r0))
  }
  plan.assign_operand(use_instruction, 0, Reg(r1))
  try {
    verify_function_allocation(function, MachineEnv::new([r0, r1], []), plan)
    None
  } catch {
    error => Some(error)
  }
}

///|
test "plan verifier rejects a spilled AnyReg operand" {
  let value : VirtualReg = { id: 0, class: Int }
  let function : VerifierCfgView = {
    value_count: 1,
    blocks: [[0]],
    operands: [[Operand::use_reg(value)]],
    successors: [[]],
    entry_values: [value],
    parameters: [[]],
    edge_arguments: [[]],
    successor_queries: Ref(0),
    block_visits: Ref(0),
  }
  let plan = AllocationPlan::new(1)
  let slot = plan.create_spill_slot(8, 8)
  plan.assign_value(value, Spill(slot))
  plan.assign_operand(0, 0, Spill(slot))
  let error = try {
    verify_function_allocation(function, MachineEnv::new([], []), plan)
    None
  } catch {
    error => Some(error)
  }
  debug_inspect(
    error,
    content="Some(InvalidPlan(message=\"register-constrained operand allocated outside a register\"))",
  )
}

///|
test "plan verifier always enters a self-looping entry block" {
  let value : VirtualReg = { id: 0, class: Int }
  debug_inspect(
    verify_wrong_location(
      {
        value_count: 1,
        blocks: [[0]],
        operands: [[Operand::use_reg(value)]],
        successors: [[0]],
        entry_values: [value],
        parameters: [[]],
        edge_arguments: [[[]]],
        successor_queries: Ref(0),
        block_visits: Ref(0),
      },
      None,
      0,
    ),
    content=(
      #|Some(
      #|  IncorrectValue(
      #|    vreg={ id: 0, class: Int },
      #|    location=Reg({ id: 1, class: Int }),
      #|  ),
      #|)
    ),
  )
}

///|
test "plan verifier checks an unreachable cyclic component" {
  let value : VirtualReg = { id: 0, class: Int }
  debug_inspect(
    verify_wrong_location(
      {
        value_count: 1,
        blocks: [[], [0, 1]],
        operands: [[Operand::def(value)], [Operand::use_reg(value)]],
        successors: [[], [1]],
        entry_values: [],
        parameters: [[], []],
        edge_arguments: [[], [[]]],
        successor_queries: Ref(0),
        block_visits: Ref(0),
      },
      Some(0),
      1,
    ),
    content=(
      #|Some(
      #|  IncorrectValue(
      #|    vreg={ id: 0, class: Int },
      #|    location=Reg({ id: 1, class: Int }),
      #|  ),
      #|)
    ),
  )
}

///|
test "plan verifier queries each block successor list once" {
  let successor_queries = Ref(0)
  let value : VirtualReg = { id: 0, class: Int }
  let register : PhysicalReg = { id: 0, class: Int }
  let function : VerifierCfgView = {
    value_count: 1,
    blocks: [[], [], [], []],
    operands: [],
    successors: [[1], [2], [3], []],
    entry_values: [value],
    parameters: [[], [], [], []],
    edge_arguments: [[[]], [[]], [[]], []],
    successor_queries,
    block_visits: Ref(0),
  }
  let plan = AllocationPlan::new(1)
  plan.assign_value(value, Reg(register))
  verify_function_allocation(function, MachineEnv::new([register], []), plan)
  inspect(successor_queries.val, content="4")
}

///|
test "production fragments cache local allocation metadata" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let range = LiveRange::LiveRange(0, { id: 0, class: Int })
  range.add_range(ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 2)))
  range.add_range(ProgramRange(ProgramPoint(2, 0), ProgramPoint(2, 2)))
  range.add_use(
    UsePosition(ProgramPoint(0, 1), LiveUse, AnyReg).with_preference(Some(r1)),
  )
  range.add_use(
    UsePosition(ProgramPoint(2, 1), LiveUse, FixedReg(r0)).with_preference(
      Some(r0),
    ),
  )
  let ranges = LiveRangeSet::LiveRangeSet([0, 1, 2])
  ranges.add_range(range)
  let (segments, _) = build_allocation_segments(ranges, allocatable=[r0, r1])
  debug_inspect(
    segments.map(segment => {
      (
        segment.weight,
        segment.has_fixed_constraint,
        segment.fixed_hint,
        segment.preference_hint,
      )
    }),
    content=(
      #|[
      #|  (667, false, None, Some({ id: 1, class: Int })),
      #|  (1000, true, Some({ id: 0, class: Int }), Some({ id: 0, class: Int })),
      #|]
    ),
  )
}

///|
test "any-location definitions materialize in their stable home" {
  let value : VirtualReg = { id: 0, class: Int }
  let register : PhysicalReg = { id: 0, class: Int }
  let function : VerifierCfgView = {
    value_count: 1,
    blocks: [[0]],
    operands: [[Operand::def(value).with_constraint(AnyLocation)]],
    successors: [[]],
    entry_values: [],
    parameters: [[]],
    edge_arguments: [[]],
    successor_queries: Ref(0),
    block_visits: Ref(0),
  }
  let plan = AllocationPlan::new(1)
  let slot = plan.create_spill_slot(8, 8)
  plan.assign_value(value, Spill(slot))
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value,
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 2)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: Some(SegmentReg(register)),
    },
  ]
  assign_segment_operands(
    plan,
    function,
    MachineEnv::new([register], []),
    segments,
    [[0]],
  )
  |> ignore
  debug_inspect(
    (plan.operand_location(0, 0), plan.edits()),
    content="(Some(Spill(0)), [])",
  )
}

///|
test "production register allocation index orders updates by range end" {
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value: { id: 0, class: Int },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 2)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
    {
      id: 1,
      value: { id: 1, class: Int },
      range: ProgramRange(ProgramPoint(0, 4), ProgramPoint(0, 6)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
    {
      id: 2,
      value: { id: 2, class: Int },
      range: ProgramRange(ProgramPoint(0, 8), ProgramPoint(0, 10)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
    {
      id: 3,
      value: { id: 3, class: Int },
      range: ProgramRange(ProgramPoint(0, 5), ProgramPoint(0, 7)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
  ]
  let allocations = RegisterAllocationIndex::new(1, segments, [0])
  allocations.insert(0, 2)
  allocations.insert(0, 0)
  allocations.insert(0, 1)
  let stack : Array[Int] = []
  let ordered : Array[Int] = []
  allocations.seek(0, ProgramPoint(0, -1), stack)
  while allocations.next(stack) is Some(segment) {
    ordered.push(segment)
  }
  debug_inspect(ordered, content="[0, 1, 2]")
  allocations.remove(0, 1)
  ordered.clear()
  allocations.seek(0, ProgramPoint(0, -1), stack)
  while allocations.next(stack) is Some(segment) {
    ordered.push(segment)
  }
  debug_inspect(ordered, content="[0, 2]")
}

///|
/// ISS-370 regression: `index_plan_edits` buckets by position, and bucket
/// order must preserve the plan's edit order. The three moves below form a
/// dependency chain at one position — each requires the location produced by
/// the previous one — so any reordering inside the bucket fails verification
/// with `IncorrectValue`.
test "plan verifier applies same-position edits in plan order" {
  let value : VirtualReg = { id: 0, class: Int }
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let r2 : PhysicalReg = { id: 2, class: Int }
  let function : VerifierCfgView = {
    value_count: 1,
    blocks: [[0]],
    operands: [[Operand::use_reg(value)]],
    successors: [[]],
    entry_values: [value],
    parameters: [[]],
    edge_arguments: [[]],
    successor_queries: Ref(0),
    block_visits: Ref(0),
  }
  let plan = AllocationPlan::new(1)
  plan.assign_value(value, Reg(r0))
  plan.add_edit({ value, from: Reg(r0), to: Reg(r1), position: Before(0) })
  plan.add_edit({ value, from: Reg(r1), to: Reg(r2), position: Before(0) })
  plan.add_edit({ value, from: Reg(r2), to: Reg(r0), position: Before(0) })
  plan.assign_operand(0, 0, Reg(r0))
  verify_function_allocation(function, MachineEnv::new([r0, r1, r2], []), plan)
}

///|
/// ISS-370 regression: reverse postorder is a topological order on an
/// acyclic CFG, so every join merges all of its incoming states before its
/// block is processed and the whole function verifies in one pass — each
/// block exactly once. The chain of diamonds below refines the dataflow
/// state at every join (each arm publishes the value in a different extra
/// register, and the meet drops it), which is the shape that made the
/// previous LIFO worklist reprocess the downstream chain once per join and
/// grow verification cost with nesting depth.
test "plan verifier processes a deep diamond join chain once per block" {
  let diamonds = 8
  let block_count = 3 * diamonds + 1
  let value : VirtualReg = { id: 0, class: Int }
  let r0 : PhysicalReg = { id: 0, class: Int }
  let registers : Array[PhysicalReg] = Array::makei(diamonds + 1, id => {
    id,
    class: Int,
  })
  let blocks : Array[Array[Int]] = Array::makei(block_count, _ => [])
  let successors : Array[Array[Int]] = Array::makei(block_count, _ => [])
  let parameters : Array[Array[VirtualReg]] = Array::makei(block_count, _ => [])
  let edge_arguments : Array[Array[Array[VirtualReg]]] = Array::makei(
    block_count,
    _ => [],
  )
  let plan = AllocationPlan::new(1)
  plan.assign_value(value, Reg(r0))
  for i in 0..<diamonds {
    let top = 3 * i
    let left = 3 * i + 1
    let right = 3 * i + 2
    let join = 3 * i + 3
    successors[top] = [left, right]
    edge_arguments[top] = [[], []]
    successors[left] = [join]
    edge_arguments[left] = [[]]
    successors[right] = [join]
    edge_arguments[right] = [[]]
    // Only the right arm publishes the value in a per-diamond extra
    // register, so every join must drop it — and because the extra register
    // differs per level, a scheduler that enters a join with partial
    // predecessor state has to re-propagate the shrink one level at a time.
    plan.add_edit({
      value,
      from: Reg(r0),
      to: Reg(registers[i + 1]),
      position: Edge(source_block=right, successor_index=0),
    })
  }
  let function : VerifierCfgView = {
    value_count: 1,
    blocks,
    operands: [],
    successors,
    entry_values: [value],
    parameters,
    edge_arguments,
    successor_queries: Ref(0),
    block_visits: Ref(0),
  }
  verify_function_allocation(function, MachineEnv::new(registers, []), plan)
  inspect(function.block_visits.val, content="25")
  inspect(function.successor_queries.val, content="25")
}
