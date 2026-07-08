///|
pub(all) struct SpillSlotReservation {
  slot : Int
  next_slot : Int
  slots_used : Int
} derive(Eq, Debug)

///|
/// Reserve spill slots in 8-byte units.
///
/// Vector values require a 16-byte-aligned slot and occupy two 8-byte units.
pub fn reserve_spill_slot(
  next_slot : Int,
  class : RegClass,
) -> SpillSlotReservation {
  match class {
    Vector => {
      let aligned = if next_slot % 2 == 0 { next_slot } else { next_slot + 1 }
      { slot: aligned, next_slot: aligned + 2, slots_used: 2 }
    }
    Int | Float => { slot: next_slot, next_slot: next_slot + 1, slots_used: 1 }
  }
}
