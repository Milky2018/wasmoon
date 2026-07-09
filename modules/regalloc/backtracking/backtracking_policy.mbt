///|
pub fn should_prefer_caller_saved_for_backtracking(
  class : @regalloc.RegClass,
  enable_backtracking : Bool,
  crosses_call : Bool,
) -> Bool {
  enable_backtracking && !crosses_call && (class == Int || class == Float)
}

///|
pub(all) struct BacktrackingOccupiedSpan[P] {
  owner_id : Int
  span : OrderedSpan[P]
  owner_weight : Int
  owner_pinned : Bool
}

///|
pub(all) struct BacktrackingConflictScanResult[P] {
  conflict_ids : Array[Int]
  max_conflict_weight : Int
  first_conflict_point : P?
  rejected : Bool
}

///|
fn[P] backtracking_later_start(lhs : OrderedSpan[P], rhs : OrderedSpan[P]) -> P {
  if lhs.start_ord >= rhs.start_ord {
    lhs.start
  } else {
    rhs.start
  }
}

///|
fn backtracking_conflict_seen(seen : Array[Int], owner_id : Int) -> Bool {
  for id in seen {
    if id == owner_id {
      return true
    }
  }
  false
}

///|
pub fn[P] scan_backtracking_conflicts_with_cutoff(
  spans : Array[OrderedSpan[P]],
  occupied : Array[BacktrackingOccupiedSpan[P]],
  current_weight : Int,
  max_allowable_cost : Int?,
) -> BacktrackingConflictScanResult[P] {
  let conflict_ids : Array[Int] = []
  let seen : Array[Int] = []
  let mut max_conflict_weight = 0
  let mut first_conflict_point : P? = None
  if spans.is_empty() || occupied.is_empty() {
    return {
      conflict_ids,
      max_conflict_weight,
      first_conflict_point,
      rejected: false,
    }
  }
  let mut i = 0
  let mut j = 0
  while j < occupied.length() && occupied[j].span.end_ord <= spans[0].start_ord {
    j += 1
  }
  while i < spans.length() && j < occupied.length() {
    let span = spans[i]
    let occ = occupied[j]
    if span.end_ord <= occ.span.start_ord {
      i += 1
      continue
    }
    if occ.span.end_ord <= span.start_ord {
      j += 1
      continue
    }
    if first_conflict_point is None {
      first_conflict_point = Some(backtracking_later_start(span, occ.span))
    }
    if !backtracking_conflict_seen(seen, occ.owner_id) {
      seen.push(occ.owner_id)
      if occ.owner_pinned || occ.owner_weight >= current_weight {
        return {
          conflict_ids: [],
          max_conflict_weight: 0,
          first_conflict_point,
          rejected: true,
        }
      }
      conflict_ids.push(occ.owner_id)
      if occ.owner_weight > max_conflict_weight {
        max_conflict_weight = occ.owner_weight
        if max_allowable_cost is Some(limit) && max_conflict_weight > limit {
          return {
            conflict_ids: [],
            max_conflict_weight: 0,
            first_conflict_point,
            rejected: true,
          }
        }
      }
    }
    if span.end_ord <= occ.span.end_ord {
      i += 1
    } else {
      j += 1
    }
  }
  { conflict_ids, max_conflict_weight, first_conflict_point, rejected: false }
}

///|
pub fn[P] has_backtracking_span_conflict(
  spans : Array[OrderedSpan[P]],
  occupied : Array[(Int, OrderedSpan[P])],
) -> Bool {
  if spans.is_empty() || occupied.is_empty() {
    return false
  }
  let mut i = 0
  let mut j = lower_bound_backtracking_span_by_end(occupied, spans[0].start_ord)
  while i < spans.length() && j < occupied.length() {
    let span = spans[i]
    let occ = occupied[j].1
    if span.end_ord <= occ.start_ord {
      i += 1
      continue
    }
    if occ.end_ord <= span.start_ord {
      j += 1
      continue
    }
    return true
  }
  false
}

///|
pub fn[P] should_take_backtracking_split_candidate(
  best_split_cost : Int?,
  best_split_point : P?,
  candidate_cost : Int,
  candidate_point : P,
  compare_points : (P, P) -> Int,
) -> Bool {
  match (best_split_cost, best_split_point) {
    (None, None) => true
    (Some(existing_cost), Some(existing_point)) =>
      if candidate_cost < existing_cost {
        true
      } else {
        candidate_cost == existing_cost &&
        compare_points(candidate_point, existing_point) > 0
      }
    _ => false
  }
}

///|
pub(all) struct BacktrackingSplitRange[P] {
  range_id : Int
  start : P?
  end : P?
}

///|
pub(all) enum BacktrackingSplitPlan {
  BacktrackingSplit(Array[Int], Array[Int])
  BacktrackingMinimal
  BacktrackingSpillWhole
} derive(Debug)

///|
pub fn[P] plan_backtracking_bundle_split(
  ranges : Array[BacktrackingSplitRange[P]],
  split_point : P?,
  split_limit_reached : Bool,
  end_before_or_at_split : (P, P) -> Bool,
  start_after_or_at_split : (P, P) -> Bool,
) -> BacktrackingSplitPlan {
  if split_limit_reached {
    return BacktrackingMinimal
  }
  guard split_point is Some(point) else { return BacktrackingSpillWhole }
  let before_ranges : Array[Int] = []
  let after_ranges : Array[Int] = []
  for range in ranges {
    if range.end is Some(end_point) {
      if end_before_or_at_split(end_point, point) {
        before_ranges.push(range.range_id)
      } else if range.start is Some(start_point) {
        if start_after_or_at_split(start_point, point) {
          after_ranges.push(range.range_id)
        } else {
          after_ranges.push(range.range_id)
        }
      } else {
        after_ranges.push(range.range_id)
      }
    } else {
      after_ranges.push(range.range_id)
    }
  }
  if before_ranges.is_empty() || after_ranges.is_empty() {
    BacktrackingMinimal
  } else {
    BacktrackingSplit(before_ranges, after_ranges)
  }
}
