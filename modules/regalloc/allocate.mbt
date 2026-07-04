///|
fn contains_vreg(vregs : Array[VirtualReg], vreg : VirtualReg) -> Bool {
  for existing in vregs {
    if existing == vreg {
      return true
    }
  }
  false
}

///|
fn collect_vregs(program : Program) -> Array[VirtualReg] {
  let vregs : Array[VirtualReg] = []
  for block in program.blocks {
    for inst in block.instructions {
      for operand in inst.operands {
        if !contains_vreg(vregs, operand.vreg) {
          vregs.push(operand.vreg)
        }
      }
    }
  }
  vregs
}

///|
fn first_physical_reg(
  physical_regs : Array[PhysicalReg],
  class : RegClass,
  ordinal : Int,
) -> PhysicalReg? {
  let mut seen = 0
  for preg in physical_regs {
    if preg.class == class {
      if seen == ordinal {
        return Some(preg)
      }
      seen = seen + 1
    }
  }
  None
}

///|
fn count_prior_class(
  vregs : Array[VirtualReg],
  index : Int,
  class : RegClass,
) -> Int {
  let mut count = 0
  for i in 0..<index {
    if vregs[i].class == class {
      count = count + 1
    }
  }
  count
}

///|
/// Allocate virtual registers over an abstract program model.
///
/// TODO(regalloc): replace this deterministic baseline with real live-range
/// splitting, coalescing, rematerialization, and spill-cost modeling.
pub fn allocate(program : Program) -> Allocation {
  let allocation = Allocation::new()
  let vregs = collect_vregs(program)
  for i, vreg in vregs {
    let ordinal = count_prior_class(vregs, i, vreg.class)
    match first_physical_reg(program.physical_regs, vreg.class, ordinal) {
      Some(preg) => allocation.assignments.push({ vreg, location: Reg(preg) })
      None => {
        allocation.assignments.push({
          vreg,
          location: Spill(allocation.spill_count),
        })
        allocation.spill_count = allocation.spill_count + 1
      }
    }
  }
  allocation
}
