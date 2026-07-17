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
fn contains_reg(regs : Array[PhysicalReg], preg : PhysicalReg) -> Bool {
  for reg in regs {
    if reg == preg {
      return true
    }
  }
  false
}

///|
fn physical_reg_key(reg : PhysicalReg) -> (Int, Int) {
  let class = match reg.class {
    Int => 0
    Float => 1
    Vector => 2
  }
  (class, reg.id)
}

///|
fn collect_register_clobber_points(
  program : Program,
) -> Map[(Int, Int), Array[ProgramPoint]] {
  let points_by_reg : Map[(Int, Int), Array[ProgramPoint]] = Map([])
  for block in program.blocks {
    for inst_index, inst in block.instructions {
      let point = ProgramPoint::ProgramPoint(block.id, inst_index)
      for clobber in inst.clobbers {
        let key = physical_reg_key(clobber)
        match points_by_reg.get(key) {
          Some(points) => points.push(point)
          None => points_by_reg[key] = [point]
        }
      }
    }
  }
  points_by_reg
}

///|
fn is_clobbered_while_live(
  clobber_points : Map[(Int, Int), Array[ProgramPoint]],
  range : LiveRange,
  preg : PhysicalReg,
  block_order : Array[Int],
) -> Bool {
  match clobber_points.get(physical_reg_key(preg)) {
    Some(points) =>
      for point in points {
        if range.is_live_across(point, block_order) {
          return true
        }
      }
    None => ()
  }
  false
}

///|
fn available_regs_for_range(
  physical_regs : Array[PhysicalReg],
  clobber_points : Map[(Int, Int), Array[ProgramPoint]],
  range : LiveRange,
  block_order : Array[Int],
) -> Array[PhysicalReg] {
  let out : Array[PhysicalReg] = []
  for preg in compatible_regs(physical_regs, range.vreg.class) {
    if !is_clobbered_while_live(clobber_points, range, preg, block_order) {
      out.push(preg)
    }
  }
  if range.get_fixed_reg() is Some(fixed) &&
    fixed.class == range.vreg.class &&
    !contains_reg(out, fixed) &&
    !is_clobbered_while_live(clobber_points, range, fixed, block_order) {
    out.push(fixed)
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
fn reg_conflicts_with_active(
  active : Array[(LiveRange, PhysicalReg)],
  current : LiveRange,
  preg : PhysicalReg,
  block_order : Array[Int],
) -> Bool {
  for item in active {
    let (active_range, active_reg) = item
    if active_reg == preg &&
      !active_range.overlap_allowed_by_tie(current, block_order) {
      return true
    }
  }
  false
}

///|
fn find_tied_active_reg(
  regs : Array[PhysicalReg],
  active : Array[(LiveRange, PhysicalReg)],
  current : LiveRange,
  block_order : Array[Int],
) -> PhysicalReg? {
  for item in active {
    let (active_range, preg) = item
    if contains_reg(regs, preg) &&
      active_range.overlaps(current, block_order) &&
      active_range.overlap_allowed_by_tie(current, block_order) &&
      !reg_conflicts_with_active(active, current, preg, block_order) {
      return Some(preg)
    }
  }
  None
}

///|
fn choose_free_reg(
  regs : Array[PhysicalReg],
  active : Array[(LiveRange, PhysicalReg)],
  current : LiveRange,
  fixed : PhysicalReg?,
  block_order : Array[Int],
) -> PhysicalReg? {
  if fixed is Some(preg) {
    if !reg_conflicts_with_active(active, current, preg, block_order) {
      for reg in regs {
        if reg == preg {
          return Some(preg)
        }
      }
    }
    return None
  }
  if find_tied_active_reg(regs, active, current, block_order) is Some(preg) {
    return Some(preg)
  }
  for preg in regs {
    if !reg_conflicts_with_active(active, current, preg, block_order) {
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
  allowed_regs : Array[PhysicalReg],
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
    if same_required_reg &&
      range.vreg.class == current.vreg.class &&
      contains_reg(allowed_regs, preg) {
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
/// Allocate virtual registers over the small abstract `Program` model using a
/// linear-scan allocator.
///
/// This is the simple allocator for examples and model-level tests. Production
/// embedding pipelines should use the `backtracking_*` APIs in this package
/// through an adapter such as `machv_regalloc`.
///
/// TODO(regalloc): add interval splitting, bundle coalescing, rematerialization,
/// and target-provided spill-cost modeling.
pub fn allocate_linear_scan(program : Program) -> Allocation {
  let allocation = Allocation::Allocation()
  let ranges = build_live_ranges(program)
  let clobber_points = collect_register_clobber_points(program)
  let active : Array[(LiveRange, PhysicalReg)] = []
  for interval in ranges.ranges {
    expire_old_intervals(active, interval, ranges.block_order)
    let regs = available_regs_for_range(
      program.physical_regs,
      clobber_points,
      interval,
      ranges.block_order,
    )
    match
      choose_free_reg(
        regs,
        active,
        interval,
        interval.get_fixed_reg(),
        ranges.block_order,
      ) {
      Some(preg) => {
        allocation.assign(interval.vreg, Reg(preg))
        interval.allocation = Some(Reg(preg))
        active.push((interval, preg))
      }
      None =>
        match
          choose_spill_candidate(active, interval, regs, ranges.block_order) {
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
