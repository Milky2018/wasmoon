///|
test "backtracking queue pops higher priority with stable ties" {
  let queue : BacktrackingQueue[Int] = BacktrackingQueue::new(4)
  queue.push(2, 10, Some(20))
  queue.push(1, 20, Some(10))
  queue.push(3, 20, Some(30))
  queue.push(1, 99, Some(99))
  let first = queue.pop().unwrap()
  inspect(first.bundle_id, content="1")
  inspect(first.prio, content="20")
  inspect(first.hint_preg == Some(10), content="true")
  let second = queue.pop().unwrap()
  inspect(second.bundle_id, content="3")
  inspect(second.prio, content="20")
  inspect(second.hint_preg == Some(30), content="true")
  let third = queue.pop().unwrap()
  inspect(third.bundle_id, content="2")
  inspect(third.prio, content="10")
  inspect(third.hint_preg == Some(20), content="true")
  inspect(queue.pop() is None, content="true")
}

///|
test "backtracking spillset state records hints and split caps" {
  let spillsets : BacktrackingSpillsetState[Int] = BacktrackingSpillsetState::new(
    2,
    max_splits_per_spillset=2,
  )
  inspect(spillsets.hint(1) is None, content="true")
  spillsets.record_hint(1, 42)
  inspect(spillsets.hint(1) == Some(42), content="true")
  inspect(spillsets.split_limit_reached(1), content="false")
  spillsets.record_split(1)
  inspect(spillsets.split_limit_reached(1), content="false")
  spillsets.record_split(1)
  inspect(spillsets.split_limit_reached(1), content="true")
}

///|
test "backtracking conflict scan is generic over point type" {
  let span : OrderedSpan[Int] = { start: 10, start_ord: 10, end_ord: 30 }
  let occupied : Array[BacktrackingOccupiedSpan[Int]] = [
    {
      owner_id: 7,
      span: { start: 0, start_ord: 0, end_ord: 12 },
      owner_weight: 2,
      owner_pinned: false,
    },
    {
      owner_id: 8,
      span: { start: 20, start_ord: 20, end_ord: 40 },
      owner_weight: 5,
      owner_pinned: false,
    },
  ]
  let result = scan_backtracking_conflicts_with_cutoff(
    [span],
    occupied,
    9,
    None,
  )
  debug_inspect(result.conflict_ids, content="[7, 8]")
  inspect(result.max_conflict_weight, content="5")
  inspect(result.first_conflict_point == Some(10), content="true")
  inspect(result.rejected, content="false")
  let rejected = scan_backtracking_conflicts_with_cutoff(
    [span],
    [
      {
        owner_id: 9,
        span: { start: 11, start_ord: 11, end_ord: 12 },
        owner_weight: 1,
        owner_pinned: true,
      },
    ],
    9,
    None,
  )
  inspect(rejected.rejected, content="true")
}

///|
test "backtracking split plan is generic over point ordering" {
  let ranges : Array[BacktrackingSplitRange[Int]] = [
    { range_id: 0, start: Some(0), end: Some(4) },
    { range_id: 1, start: Some(6), end: Some(10) },
  ]
  match
    plan_backtracking_bundle_split(
      ranges,
      Some(5),
      false,
      fn(end_point, split_point) { end_point <= split_point },
      fn(start_point, split_point) { start_point >= split_point },
    ) {
    BacktrackingSplit(before, after) => {
      debug_inspect(before, content="[0]")
      debug_inspect(after, content="[1]")
    }
    _ => abort("expected split")
  }
  match
    plan_backtracking_bundle_split(
      ranges,
      Some(20),
      false,
      fn(end_point, split_point) { end_point <= split_point },
      fn(start_point, split_point) { start_point >= split_point },
    ) {
    BacktrackingMinimal => ()
    _ => abort("expected minimal fallback")
  }
  match
    plan_backtracking_bundle_split(
      ranges,
      None,
      false,
      fn(end_point, split_point) { end_point <= split_point },
      fn(start_point, split_point) { start_point >= split_point },
    ) {
    BacktrackingSpillWhole => ()
    _ => abort("expected whole-bundle spill")
  }
}

///|
test "backtracking spill compaction is generic over range and class" {
  fn reserve_test_slot(next_slot : Int, class : Int) -> SpillSlotReservation {
    if class == 2 {
      let aligned = if next_slot % 2 == 0 { next_slot } else { next_slot + 1 }
      { slot: aligned, next_slot: aligned + 2, slots_used: 2 }
    } else {
      { slot: next_slot, next_slot: next_slot + 1, slots_used: 1 }
    }
  }

  fn ranges_overlap(a : Array[(Int, Int)], b : Array[(Int, Int)]) -> Bool {
    for lhs in a {
      for rhs in b {
        if lhs.0 < rhs.1 && rhs.0 < lhs.1 {
          return true
        }
      }
    }
    false
  }

  let spillsets : Array[SpillSetInfo[Int, (Int, Int), Int]] = [
    { old_slot: 0, reg_class: 1, spans: [(0, 4)], start: 0 },
    { old_slot: 1, reg_class: 1, spans: [(5, 8)], start: 5 },
    { old_slot: 2, reg_class: 2, spans: [(10, 12)], start: 10 },
  ]
  let compaction = compact_backtracking_spill_slots(
    spillsets,
    [{ lhs: 0, rhs: 1 }],
    reserve_test_slot,
    ranges_overlap,
    fn(a, b) { a - b },
  )
  debug_inspect(
    compaction.remaps,
    content=(
      #|[
      #|  { old_slot: 0, new_slot: 0 },
      #|  { old_slot: 1, new_slot: 1 },
      #|  { old_slot: 2, new_slot: 2 },
      #|]
    ),
  )
  inspect(compaction.total_slots, content="4")
}

///|
test "backtracking allocation result builder records regs and spills" {
  let result = build_backtracking_allocation_result(
    [
      { vreg_id: 1, allocation: BacktrackingReg(10) },
      { vreg_id: 2, allocation: BacktrackingSpill(3) },
      { vreg_id: 3, allocation: BacktrackingUnallocated },
    ],
    4,
  )
  debug_inspect(result.assignments, content="[(1, 10)]")
  debug_inspect(result.spill_slots, content="[(2, 3)]")
  inspect(result.num_spill_slots, content="4")
}

///|
test "backtracking fixed constraints plan reloads stores and moves" {
  let inst : BacktrackingFixedConstraintInst[Int] = {
    block_index: 0,
    inst_index: 1,
    uses: [
      { operand: BacktrackingVirtual(BacktrackingReg(5), 0), required: 7 },
      { operand: BacktrackingVirtual(BacktrackingSpill(3), 1), required: 8 },
      { operand: BacktrackingPhysical(9, 0), required: 9 },
    ],
    defs: [
      { operand: BacktrackingVirtual(BacktrackingReg(6), 0), required: 7 },
      { operand: BacktrackingVirtual(BacktrackingSpill(4), 1), required: 8 },
    ],
  }
  let edits = plan_backtracking_fixed_constraint_edits([inst], fn(a, b) {
    a == b
  })
  inspect(edits.length(), content="1")
  inspect(edits[0].before.length(), content="2")
  inspect(edits[0].after.length(), content="2")
  match edits[0].before[0].from {
    BacktrackingMoveReg(reg) => inspect(reg, content="5")
    _ => abort("expected reg source")
  }
  match edits[0].before[1].from {
    BacktrackingMoveSpill(slot) => inspect(slot, content="3")
    _ => abort("expected spill source")
  }
  match edits[0].after[1].to {
    BacktrackingMoveSpill(slot) => inspect(slot, content="4")
    _ => abort("expected spill destination")
  }
}

///|
test "backtracking register attempts are generic over machine registers" {
  let spans : Array[OrderedSpan[Int]] = [
    { start: 10, start_ord: 10, end_ord: 20 },
  ]
  let single_pass = try_backtracking_single_pass_register(
    [0, 1],
    [],
    [],
    spans,
    Some(1),
    false,
    8,
    0,
    fn(a, b) { a == b },
    fn(preg, _) { preg == 0 },
  )
  inspect(single_pass == Some(1), content="true")

  let eviction = try_backtracking_eviction_register(
    [0],
    [],
    [],
    spans,
    9,
    None,
    false,
    8,
    0,
    fn(a, b) { a == b },
    fn(reg) { { id: reg, class: Int } },
    fn(_) {
      [
        {
          owner_id: 7,
          span: { start: 0, start_ord: 0, end_ord: 30 },
          owner_weight: 2,
          owner_pinned: false,
        },
      ]
    },
    fn(a, b) { a - b },
  )
  inspect(eviction.reg == Some(0), content="true")
  debug_inspect(eviction.evicted_ids, content="[7]")
  inspect(eviction.split is None, content="true")
}

///|
test "backtracking allocation loop drives production callbacks" {
  let queue : BacktrackingQueue[Int] = BacktrackingQueue::new(2)
  queue.push(0, 10, None)
  queue.push(1, 5, Some(9))
  let attempts = Array::make(2, 0)
  let allocated = Array::make(2, -1)
  let spilled = Array::make(2, false)
  let try_backtracking = fn(bundle : Int, hint : Int?) -> (Int?, (Int, Int)?) {
    ignore(hint)
    (Some(bundle + 100), None)
  }
  let split_bundle = fn(bundle : Int, split : (Int, Int)?) -> Unit {
    ignore(split)
    spilled[bundle] = true
  }
  run_backtracking_allocation_loop(
    queue,
    attempts,
    3,
    true,
    2,
    fn(bundle_id) { bundle_id },
    fn(bundle) { allocated[bundle] >= 0 || spilled[bundle] },
    fn(_) { false },
    fn(_) { false },
    fn(bundle) { bundle == 1 },
    fn(_, hint) { hint },
    try_backtracking,
    fn(_, _) { None },
    fn(bundle, reg) { allocated[bundle] = reg },
    split_bundle,
    fn(bundle) { spilled[bundle] = true },
  )
  inspect(allocated[0], content="100")
  inspect(spilled[1], content="true")
  debug_inspect(attempts, content="[1, 1]")
}
