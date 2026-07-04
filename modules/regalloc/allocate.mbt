///|
priv struct LiveInterval {
  vreg : VirtualReg
  mut start : Int
  mut end : Int
}

///|
fn LiveInterval::new(vreg : VirtualReg, point : Int) -> LiveInterval {
  { vreg, start: point, end: point }
}

///|
fn LiveInterval::touch(self : LiveInterval, point : Int) -> Unit {
  if point < self.start {
    self.start = point
  }
  if point > self.end {
    self.end = point
  }
}

///|
fn find_interval(
  intervals : Array[LiveInterval],
  vreg : VirtualReg,
) -> LiveInterval? {
  for interval in intervals {
    if interval.vreg == vreg {
      return Some(interval)
    }
  }
  None
}

///|
fn touch_interval(
  intervals : Array[LiveInterval],
  vreg : VirtualReg,
  point : Int,
) -> Unit {
  match find_interval(intervals, vreg) {
    Some(interval) => interval.touch(point)
    None => intervals.push(LiveInterval::new(vreg, point))
  }
}

///|
fn collect_intervals(program : Program) -> Array[LiveInterval] {
  let intervals : Array[LiveInterval] = []
  let mut point = 0
  for block in program.blocks {
    for inst in block.instructions {
      for operand in inst.operands {
        touch_interval(intervals, operand.vreg, point)
      }
      point = point + 1
    }
  }
  intervals.sort_by(fn(a, b) {
    if a.start != b.start {
      a.start - b.start
    } else {
      a.vreg.id - b.vreg.id
    }
  })
  intervals
}

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
  active : Array[(LiveInterval, PhysicalReg)],
  current : LiveInterval,
) -> Unit {
  let mut i = 0
  while i < active.length() {
    let (interval, _) = active[i]
    if interval.end < current.start {
      active.remove(i) |> ignore
    } else {
      i = i + 1
    }
  }
}

///|
fn is_reg_active(
  active : Array[(LiveInterval, PhysicalReg)],
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
  active : Array[(LiveInterval, PhysicalReg)],
) -> PhysicalReg? {
  for preg in regs {
    if !is_reg_active(active, preg) {
      return Some(preg)
    }
  }
  None
}

///|
fn spill_slot_for(allocation : Allocation) -> Location {
  let slot = allocation.spill_count
  allocation.spill_count = allocation.spill_count + 1
  Spill(slot)
}

///|
/// Allocate virtual registers over an abstract program model using a small
/// linear-scan allocator.
///
/// TODO(regalloc): add interval splitting, bundle coalescing, rematerialization,
/// and target-provided spill-cost modeling.
pub fn allocate(program : Program) -> Allocation {
  let allocation = Allocation::new()
  let active : Array[(LiveInterval, PhysicalReg)] = []
  for interval in collect_intervals(program) {
    expire_old_intervals(active, interval)
    let regs = compatible_regs(program.physical_regs, interval.vreg.class)
    match choose_free_reg(regs, active) {
      Some(preg) => {
        allocation.assignments.push({ vreg: interval.vreg, location: Reg(preg) })
        active.push((interval, preg))
      }
      None =>
        allocation.assignments.push({
          vreg: interval.vreg,
          location: spill_slot_for(allocation),
        })
    }
    active.sort_by(fn(a, b) { a.0.end - b.0.end })
  }
  allocation
}
