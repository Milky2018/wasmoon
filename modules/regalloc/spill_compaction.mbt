///|
pub(all) struct CompactSpillSet {
  old_slot : Int
  class : RegClass
  ranges : Array[ProgramRange]
} derive(Debug)

///|
pub(all) struct SpillSlotNoShareEdge {
  lhs : Int
  rhs : Int
} derive(Eq, Debug)

///|
pub(all) struct SpillSlotRemap {
  old_slot : Int
  new_slot : Int
} derive(Eq, Debug)

///|
pub(all) struct SpillSlotCompaction {
  remaps : Array[SpillSlotRemap]
  total_slots : Int
} derive(Eq, Debug)

///|
priv struct CompactAssignedSlot {
  start : Int
  ranges : Array[ProgramRange]
  old_slots : Array[Int]
}

///|
fn compact_slot_key(slot : Int) -> Int {
  slot
}

///|
fn compact_add_no_share_edge(
  no_share : Map[Int, Set[Int]],
  a : Int,
  b : Int,
) -> Unit {
  if a == b {
    return
  }
  if no_share.get(a) is None {
    no_share.set(a, Set([]))
  }
  no_share.get(a).unwrap().add(b) |> ignore
}

///|
fn compact_point_before(
  lhs : ProgramPoint,
  rhs : ProgramPoint,
  block_order : Array[Int],
) -> Bool {
  lhs.compare_with_order(rhs, block_order) < 0
}

///|
fn compact_ranges_overlap(
  lhs : Array[ProgramRange],
  rhs : Array[ProgramRange],
  block_order : Array[Int],
) -> Bool {
  for a in lhs {
    for b in rhs {
      if compact_point_before(a.start, b.end, block_order) &&
        compact_point_before(b.start, a.end, block_order) {
        return true
      }
    }
  }
  false
}

///|
fn compact_start(
  ranges : Array[ProgramRange],
  block_order : Array[Int],
) -> ProgramPoint {
  let mut start = ranges[0].start
  for i in 1..<ranges.length() {
    let candidate = ranges[i].start
    if candidate.compare_with_order(start, block_order) < 0 {
      start = candidate
    }
  }
  start
}

///|
fn compact_copy_ranges(ranges : Array[ProgramRange]) -> Array[ProgramRange] {
  let out : Array[ProgramRange] = []
  for range in ranges {
    out.push(range)
  }
  out
}

///|
fn compact_slot_disallowed(
  no_share : Map[Int, Set[Int]],
  candidate_old_slot : Int,
  assigned : CompactAssignedSlot,
) -> Bool {
  match no_share.get(candidate_old_slot) {
    Some(disallowed) => {
      for old_slot in assigned.old_slots {
        if disallowed.contains(old_slot) {
          return true
        }
      }
      false
    }
    None => false
  }
}

///|
pub fn compact_spill_slots(
  spillsets : Array[CompactSpillSet],
  no_share_edges : Array[SpillSlotNoShareEdge],
  block_order : Array[Int],
) -> SpillSlotCompaction {
  let no_share : Map[Int, Set[Int]] = {}
  for edge in no_share_edges {
    compact_add_no_share_edge(no_share, edge.lhs, edge.rhs)
    compact_add_no_share_edge(no_share, edge.rhs, edge.lhs)
  }
  let ordered : Array[CompactSpillSet] = []
  for spillset in spillsets {
    if !spillset.ranges.is_empty() {
      ordered.push(spillset)
    }
  }
  ordered.sort_by(fn(a, b) {
    compact_start(a.ranges, block_order).compare_with_order(
      compact_start(b.ranges, block_order),
      block_order,
    )
  })
  let scalar_slots : Array[CompactAssignedSlot] = []
  let vector_slots : Array[CompactAssignedSlot] = []
  let remaps : Array[SpillSlotRemap] = []
  let mut next_slot = 0
  for spillset in ordered {
    let reservation = reserve_spill_slot(next_slot, spillset.class)
    let slots_used = reservation.slots_used
    let pool = if slots_used == 2 { vector_slots } else { scalar_slots }
    let mut placed = false
    for assigned in pool {
      if !compact_slot_disallowed(no_share, spillset.old_slot, assigned) &&
        !compact_ranges_overlap(spillset.ranges, assigned.ranges, block_order) {
        remaps.push({ old_slot: spillset.old_slot, new_slot: assigned.start })
        for range in spillset.ranges {
          assigned.ranges.push(range)
        }
        assigned.old_slots.push(spillset.old_slot)
        placed = true
        break
      }
    }
    if placed {
      continue
    }
    let reserved = reserve_spill_slot(next_slot, spillset.class)
    next_slot = reserved.next_slot
    pool.push({
      start: reserved.slot,
      ranges: compact_copy_ranges(spillset.ranges),
      old_slots: [spillset.old_slot],
    })
    remaps.push({ old_slot: spillset.old_slot, new_slot: reserved.slot })
  }
  remaps.sort_by(fn(a, b) {
    compact_slot_key(a.old_slot) - compact_slot_key(b.old_slot)
  })
  { remaps, total_slots: next_slot }
}

///|
fn[R] backtracking_compact_copy_ranges(ranges : Array[R]) -> Array[R] {
  let out : Array[R] = []
  for range in ranges {
    out.push(range)
  }
  out
}

///|
fn[R] backtracking_compact_slot_disallowed(
  no_share : Map[Int, Set[Int]],
  candidate_old_slot : Int,
  assigned : AssignedSlot[R],
) -> Bool {
  match no_share.get(candidate_old_slot) {
    Some(disallowed) => {
      for old_slot in assigned.old_slots {
        if disallowed.contains(old_slot) {
          return true
        }
      }
      false
    }
    None => false
  }
}

///|
pub fn[C, R, P] compact_backtracking_spill_slots(
  spillsets : Array[SpillSetInfo[C, R, P]],
  no_share_edges : Array[SpillSlotNoShareEdge],
  reserve_slot : (Int, C) -> SpillSlotReservation,
  ranges_overlap : (Array[R], Array[R]) -> Bool,
  compare_start : (P, P) -> Int,
) -> SpillSlotCompaction {
  let no_share : Map[Int, Set[Int]] = {}
  for edge in no_share_edges {
    compact_add_no_share_edge(no_share, edge.lhs, edge.rhs)
    compact_add_no_share_edge(no_share, edge.rhs, edge.lhs)
  }
  let ordered : Array[SpillSetInfo[C, R, P]] = []
  for spillset in spillsets {
    if !spillset.spans.is_empty() {
      ordered.push(spillset)
    }
  }
  ordered.sort_by(fn(a, b) { compare_start(a.start, b.start) })
  let scalar_slots : Array[AssignedSlot[R]] = []
  let vector_slots : Array[AssignedSlot[R]] = []
  let remaps : Array[SpillSlotRemap] = []
  let mut next_slot = 0
  for spillset in ordered {
    let reservation = reserve_slot(next_slot, spillset.reg_class)
    let slots_used = reservation.slots_used
    let pool = if slots_used == 2 { vector_slots } else { scalar_slots }
    let mut placed = false
    for assigned in pool {
      if !backtracking_compact_slot_disallowed(
          no_share,
          spillset.old_slot,
          assigned,
        ) &&
        !ranges_overlap(spillset.spans, assigned.spans) {
        remaps.push({ old_slot: spillset.old_slot, new_slot: assigned.start })
        for range in spillset.spans {
          assigned.spans.push(range)
        }
        assigned.old_slots.push(spillset.old_slot)
        placed = true
        break
      }
    }
    if placed {
      continue
    }
    next_slot = reservation.next_slot
    pool.push({
      start: reservation.slot,
      spans: backtracking_compact_copy_ranges(spillset.spans),
      old_slots: [spillset.old_slot],
    })
    remaps.push({ old_slot: spillset.old_slot, new_slot: reservation.slot })
  }
  remaps.sort_by(fn(a, b) {
    compact_slot_key(a.old_slot) - compact_slot_key(b.old_slot)
  })
  { remaps, total_slots: next_slot }
}
