///|
pub(all) struct ReloadUseInfo {
  block_id : Int
  inst_index : Int
  spill_slot : Int
  vreg : VirtualReg
} derive(Eq, Debug)

///|
pub(all) struct ReloadIntervalInfo {
  block_id : Int
  spill_slot : Int
  vreg : VirtualReg
  first_inst : Int
  last_inst : Int
} derive(Eq, Debug)

///|
fn same_reload_key(a : ReloadUseInfo, b : ReloadUseInfo) -> Bool {
  a.block_id == b.block_id && a.spill_slot == b.spill_slot
}

///|
fn has_conflicting_owner(
  uses : Array[ReloadUseInfo],
  item : ReloadUseInfo,
) -> Bool {
  for other in uses {
    if same_reload_key(other, item) && other.vreg.id != item.vreg.id {
      return true
    }
  }
  false
}

///|
fn interval_already_added(
  intervals : Array[ReloadIntervalInfo],
  item : ReloadUseInfo,
) -> Bool {
  for interval in intervals {
    if interval.block_id == item.block_id &&
      interval.spill_slot == item.spill_slot {
      return true
    }
  }
  false
}

///|
/// Compute block-local reload intervals for spill slots used more than once.
///
/// The logic is intentionally independent of any machine IR. Callers project
/// their spilled operand uses into `ReloadUseInfo`, and target adapters decide
/// later which physical registers can hold each interval.
pub fn compute_reload_intervals(
  uses : Array[ReloadUseInfo],
  allow_vector? : Bool = false,
) -> Array[ReloadIntervalInfo] {
  let intervals : Array[ReloadIntervalInfo] = []
  for item in uses {
    if item.vreg.class is Vector && !allow_vector {
      continue
    }
    if interval_already_added(intervals, item) ||
      has_conflicting_owner(uses, item) {
      continue
    }
    let mut first = item.inst_index
    let mut last = item.inst_index
    for other in uses {
      if same_reload_key(other, item) && other.vreg.id == item.vreg.id {
        if other.inst_index < first {
          first = other.inst_index
        }
        if other.inst_index > last {
          last = other.inst_index
        }
      }
    }
    if last > first {
      intervals.push({
        block_id: item.block_id,
        spill_slot: item.spill_slot,
        vreg: item.vreg,
        first_inst: first,
        last_inst: last,
      })
    }
  }
  intervals
}
