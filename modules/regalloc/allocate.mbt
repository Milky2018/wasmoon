///|
fn compatible_regs(
  physical_regs : Array[PhysicalReg],
  class : RegClass,
) -> Array[PhysicalReg] {
  let out : Array[PhysicalReg] = []
  for preg in physical_regs {
    if preg.class == class {
      out.push(preg)
    }
  }
  out
}

///|
fn expire_old_intervals(
  active : Array[(LiveRange, PhysicalReg)],
  current : LiveRange,
  block_order : Array[Int],
) -> Unit {
  guard current.start() is Some(current_start) else { return }
  let mut i = 0
  while i < active.length() {
    let (interval, _) = active[i]
    match interval.end() {
      Some(active_end) =>
        if active_end.compare_with_order(current_start, block_order) < 0 {
          active.remove(i) |> ignore
        } else {
          i = i + 1
        }
      None => active.remove(i) |> ignore
    }
  }
}

///|
fn is_reg_active(
  active : Array[(LiveRange, PhysicalReg)],
  preg : PhysicalReg,
) -> Bool {
  for item in active {
    let (_, active_reg) = item
    if active_reg == preg {
      return true
    }
  }
  false
}

///|
fn choose_free_reg(
  regs : Array[PhysicalReg],
  active : Array[(LiveRange, PhysicalReg)],
  fixed : PhysicalReg?,
) -> PhysicalReg? {
  if fixed is Some(preg) {
    if !is_reg_active(active, preg) {
      for reg in regs {
        if reg == preg {
          return Some(preg)
        }
      }
    }
    return None
  }
  for preg in regs {
    if !is_reg_active(active, preg) {
      return Some(preg)
    }
  }
  None
}

///|
fn spill_slot_for(allocation : Allocation, range : LiveRange) -> Location {
  let slot = allocation.spill_count
  allocation.spill_count = allocation.spill_count + 1
  range.allocation = Some(Spill(slot))
  Spill(slot)
}

///|
fn range_end_order(range : LiveRange, block_order : Array[Int]) -> Int {
  match range.end() {
    Some(point) => point.order(block_order)
    None => -1
  }
}

///|
fn choose_spill_candidate(
  active : Array[(LiveRange, PhysicalReg)],
  current : LiveRange,
  block_order : Array[Int],
) -> Int? {
  let mut best_index = -1
  let mut best_end = range_end_order(current, block_order)
  let fixed = current.get_fixed_reg()
  for i, item in active {
    let (range, preg) = item
    let same_required_reg = match fixed {
      Some(required) => preg == required
      None => true
    }
    if same_required_reg && range.vreg.class == current.vreg.class {
      let end = range_end_order(range, block_order)
      if end > best_end {
        best_end = end
        best_index = i
      }
    }
  }
  if best_index >= 0 {
    Some(best_index)
  } else {
    None
  }
}

///|
/// Allocate virtual registers over an abstract program model using a small
/// linear-scan allocator.
///
/// TODO(regalloc): add interval splitting, bundle coalescing, rematerialization,
/// and target-provided spill-cost modeling.
pub fn allocate(program : Program) -> Allocation {
  let allocation = Allocation::new()
  let ranges = build_live_ranges(program)
  let active : Array[(LiveRange, PhysicalReg)] = []
  for interval in ranges.ranges {
    expire_old_intervals(active, interval, ranges.block_order)
    let regs = compatible_regs(program.physical_regs, interval.vreg.class)
    match choose_free_reg(regs, active, interval.get_fixed_reg()) {
      Some(preg) => {
        allocation.assign(interval.vreg, Reg(preg))
        interval.allocation = Some(Reg(preg))
        active.push((interval, preg))
      }
      None =>
        match choose_spill_candidate(active, interval, ranges.block_order) {
          Some(evicted_index) => {
            let (evicted, preg) = active.remove(evicted_index)
            allocation.assign(evicted.vreg, spill_slot_for(allocation, evicted))
            allocation.assign(interval.vreg, Reg(preg))
            interval.allocation = Some(Reg(preg))
            active.push((interval, preg))
          }
          None =>
            allocation.assign(
              interval.vreg,
              spill_slot_for(allocation, interval),
            )
        }
    }
    active.sort_by(fn(a, b) {
      range_end_order(a.0, ranges.block_order) -
      range_end_order(b.0, ranges.block_order)
    })
  }
  allocation
}
