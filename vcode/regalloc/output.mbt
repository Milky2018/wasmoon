// Cranelift-style regalloc output consumed directly by the emitter.
//
// Design note:
// - Keep VCode unchanged after regalloc.
// - Regalloc produces per-operand allocations plus a stream of edits (moves
//   between regs and spillslots) that the emitter interleaves with original
//   instructions, mirroring Cranelift machinst + regalloc2::Output.

///|
/// A spill slot index (8-byte slot).
pub type SpillSlot = Int

///|
/// A location for a value at a program point: either in a register or in a spill slot.
pub(all) enum Loc {
  Reg(@abi.PReg)
  Spill(SpillSlot)
}

///|
fn Loc::to_string(self : Loc) -> String {
  match self {
    Reg(r) => "\{r}"
    Spill(slot) => "spill(\{slot})"
  }
}

///|
pub impl Show for Loc with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Compatibility helpers for the existing regalloc pipeline.
/// These mirror the historical `PReg::{is_spilled,get_spill_slot}` API but operate
/// on `Loc`.
pub fn Loc::is_spilled(self : Loc) -> Bool {
  match self {
    Spill(_) => true
    _ => false
  }
}

///|
pub fn Loc::get_spill_slot(self : Loc) -> SpillSlot {
  match self {
    Spill(slot) => slot
    _ => abort("Loc::get_spill_slot called on a register loc")
  }
}

///|
/// An edit produced by regalloc to be inserted at a program point.
///
/// Equivalent to regalloc2::Edit::Move in Cranelift: move between two locations.
pub(all) enum Edit {
  Move(Loc, Loc, @abi.RegClass)
}

///|
fn Edit::to_string(self : Edit) -> String {
  match self {
    Move(from, to, _class) => "move \{from} -> \{to}"
  }
}

///|
pub impl Show for Edit with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Regalloc output.
///
/// - `allocs` is a flat array of operand allocations, aligned with `operand_ranges`.
/// - `edits` is a list of edits keyed by a program point (block/inst/pos).
/// - `num_spillslots` is used by stack-frame layout.
pub struct Output {
  // Locations of function parameters after prologue, aligned with `func.params`.
  param_locs : Array[Loc]
  // Flat operand allocations.
  allocs : Array[Loc]
  // (block_id, inst_idx, is_terminator, range_start, def_count, use_count)
  // This mirrors Cranelift’s operand_ranges; we keep block-local inst indexing
  // and treat the terminator as inst_idx==block.insts.length().
  operand_ranges : Array[(Int, Int, Bool, Int, Int, Int)]
  // Quick lookup: (block_id, inst_idx, is_terminator) -> operand_ranges index.
  operand_range_index : Map[(Int, Int, Bool), Int]
  // Edits to insert at program points.
  edits : Array[((Int, Int, ProgPos), Edit)]
  // Fast path for emission: grouped edits per program point.
  edits_by_point : Map[(Int, Int, ProgPos), Array[Edit]]
  // Total number of spill slots reserved.
  mut num_spillslots : Int
}

///|
pub fn Output::new() -> Output {
  {
    param_locs: [],
    allocs: [],
    operand_ranges: [],
    operand_range_index: {},
    edits: [],
    edits_by_point: {},
    num_spillslots: 0,
  }
}

///|
/// A compact human-readable summary for debugging (used by the CLI explore command).
pub fn Output::summary(self : Output) -> String {
  let mut s = "Regalloc output (Cranelift-style):\n"

  // Edits breakdown: this approximates stack traffic induced by spills/reloads.
  let mut reloads = 0
  let mut spills = 0
  let mut reg_moves = 0
  let mut spill_to_spill = 0
  for _, entry in self.edits {
    let (_point, edit) = entry
    match edit {
      Move(from, to, _) =>
        match (from, to) {
          (Spill(_), Reg(_)) => reloads += 1
          (Reg(_), Spill(_)) => spills += 1
          (Reg(_), Reg(_)) => reg_moves += 1
          (Spill(_), Spill(_)) => spill_to_spill += 1
        }
    }
  }

  // Count distinct spill slots referenced (may be less than reserved slots due to reuse).
  let used_slots : @hashset.HashSet[Int] = @hashset.HashSet::new()
  fn record_slot(used : @hashset.HashSet[Int], loc : Loc) -> Unit {
    match loc {
      Spill(slot) => used.add(slot) |> ignore
      _ => ()
    }
  }

  for loc in self.param_locs {
    record_slot(used_slots, loc)
  }
  for loc in self.allocs {
    record_slot(used_slots, loc)
  }
  for _, entry in self.edits {
    let (_point, edit) = entry
    match edit {
      Move(from, to, _) => {
        record_slot(used_slots, from)
        record_slot(used_slots, to)
      }
    }
  }
  s = s +
    "  spillslots: \{self.num_spillslots} (\{self.num_spillslots * 8} bytes)\n"
  s = s + "  spillslots_used: \{used_slots.length()}\n"
  s = s +
    "  edits: \{self.edits.length()} (reloads=\{reloads}, spills=\{spills}, reg_moves=\{reg_moves}, spill_to_spill=\{spill_to_spill})\n"
  s = s + "  operand_ranges: \{self.operand_ranges.length()}\n"
  s = s + "  params: "
  for i in 0..<self.param_locs.length() {
    if i > 0 {
      s = s + ", "
    }
    s = s + self.param_locs[i].to_string()
  }
  s + "\n"
}

///|
pub fn Output::get_num_spillslots(self : Output) -> Int {
  self.num_spillslots
}

///|
pub fn Output::get_param_loc(self : Output, idx : Int) -> Loc {
  self.param_locs[idx]
}

///|
pub fn Output::edits_at(
  self : Output,
  block_id : Int,
  inst_idx : Int,
  pos : ProgPos,
) -> Array[Edit]? {
  self.edits_by_point.get((block_id, inst_idx, pos))
}

///|
pub fn Output::push_edit(
  self : Output,
  block_id : Int,
  inst_idx : Int,
  pos : ProgPos,
  edit : Edit,
) -> Unit {
  self.edits.push(((block_id, inst_idx, pos), edit))
  let key = (block_id, inst_idx, pos)
  let bucket = match self.edits_by_point.get(key) {
    Some(arr) => arr
    None => {
      let arr : Array[Edit] = []
      self.edits_by_point.set(key, arr)
      arr
    }
  }
  bucket.push(edit)
}

///|
/// Record operand allocations for one instruction/terminator.
/// `locs` must have length `def_count + use_count`, in that order.
pub fn Output::push_inst_allocs(
  self : Output,
  block_id : Int,
  inst_idx : Int,
  is_terminator : Bool,
  def_count : Int,
  use_count : Int,
  locs : Array[Loc],
) -> Unit {
  let start = self.allocs.length()
  for loc in locs {
    self.allocs.push(loc)
  }
  let range_idx = self.operand_ranges.length()
  self.operand_ranges.push(
    (block_id, inst_idx, is_terminator, start, def_count, use_count),
  )
  self.operand_range_index.set((block_id, inst_idx, is_terminator), range_idx)
}

///|
fn Output::range_info(
  self : Output,
  block_id : Int,
  inst_idx : Int,
  is_terminator : Bool,
) -> (Int, Int, Int) {
  let idx = self.operand_range_index
    .get((block_id, inst_idx, is_terminator))
    .unwrap()
  let (_b, _i, _t, start, defs, uses) = self.operand_ranges[idx]
  (start, defs, uses)
}

///|
pub fn Output::inst_def_loc(
  self : Output,
  block_id : Int,
  inst_idx : Int,
  is_terminator : Bool,
  def_idx : Int,
) -> Loc {
  let (start, defs, _uses) = self.range_info(block_id, inst_idx, is_terminator)
  guard def_idx >= 0 && def_idx < defs else { abort("bad def_idx") }
  self.allocs[start + def_idx]
}

///|
pub fn Output::inst_use_loc(
  self : Output,
  block_id : Int,
  inst_idx : Int,
  is_terminator : Bool,
  use_idx : Int,
) -> Loc {
  let (start, defs, uses) = self.range_info(block_id, inst_idx, is_terminator)
  guard use_idx >= 0 && use_idx < uses else { abort("bad use_idx") }
  self.allocs[start + defs + use_idx]
}
