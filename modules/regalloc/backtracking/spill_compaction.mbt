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
  no_share_edges : Array[@planning.SpillSlotNoShareEdge],
  reserve_slot : (Int, C) -> @regalloc.SpillSlotReservation,
  ranges_overlap : (Array[R], Array[R]) -> Bool,
  compare_start : (P, P) -> Int,
) -> @planning.SpillSlotCompaction {
  let no_share : Map[Int, Set[Int]] = Map([])
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
  let remaps : Array[@planning.SpillSlotRemap] = []
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
