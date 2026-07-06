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
