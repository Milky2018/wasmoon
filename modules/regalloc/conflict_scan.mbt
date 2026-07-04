///|
pub(all) struct OrderedProgramSpan {
  start : ProgramPoint
  start_ord : Int
  end_ord : Int
} derive(Eq, Debug)

///|
pub(all) struct OccupiedProgramSpan {
  owner_id : Int
  span : OrderedProgramSpan
  owner_weight : Int
  owner_pinned : Bool
} derive(Eq, Debug)

///|
pub(all) struct ConflictScanResult {
  conflict_ids : Array[Int]
  max_conflict_weight : Int
  first_conflict_point : ProgramPoint?
  rejected : Bool
} derive(Eq, Debug)

///|
fn conflict_later_start(
  lhs : OrderedProgramSpan,
  rhs : OrderedProgramSpan,
) -> ProgramPoint {
  if lhs.start_ord >= rhs.start_ord {
    lhs.start
  } else {
    rhs.start
  }
}

///|
fn conflict_already_seen(seen : Array[Int], owner_id : Int) -> Bool {
  for id in seen {
    if id == owner_id {
      return true
    }
  }
  false
}

///|
pub fn scan_conflicts_with_cutoff(
  spans : Array[OrderedProgramSpan],
  occupied : Array[OccupiedProgramSpan],
  current_weight : Int,
  max_allowable_cost : Int?,
) -> ConflictScanResult {
  let conflict_ids : Array[Int] = []
  let seen : Array[Int] = []
  let mut max_conflict_weight = 0
  let mut first_conflict_point : ProgramPoint? = None
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
    j = j + 1
  }
  while i < spans.length() && j < occupied.length() {
    let span = spans[i]
    let occ = occupied[j]
    if span.end_ord <= occ.span.start_ord {
      i = i + 1
      continue
    }
    if occ.span.end_ord <= span.start_ord {
      j = j + 1
      continue
    }
    if first_conflict_point is None {
      first_conflict_point = Some(conflict_later_start(span, occ.span))
    }
    if !conflict_already_seen(seen, occ.owner_id) {
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
      i = i + 1
    } else {
      j = j + 1
    }
  }
  { conflict_ids, max_conflict_weight, first_conflict_point, rejected: false }
}
