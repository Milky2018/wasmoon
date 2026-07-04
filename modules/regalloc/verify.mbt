///|
pub suberror VerifyError {
  Unassigned(vreg~ : VirtualReg)
  FixedConstraintViolation(
    vreg~ : VirtualReg,
    required~ : PhysicalReg,
    actual~ : Location
  )
  OverlappingAllocation(
    left~ : VirtualReg,
    right~ : VirtualReg,
    location~ : Location
  )
  RegisterClassMismatch(vreg~ : VirtualReg, preg~ : PhysicalReg)
  ClobberedRegister(vreg~ : VirtualReg, preg~ : PhysicalReg)
}

///|
fn same_location(lhs : Location, rhs : Location) -> Bool {
  lhs == rhs
}

///|
fn verify_range_assignment(
  range : LiveRange,
  location : Location,
) -> Unit raise VerifyError {
  match location {
    Reg(preg) => {
      if preg.class != range.vreg.class {
        raise RegisterClassMismatch(vreg=range.vreg, preg~)
      }
      if range.get_fixed_reg() is Some(required) && required != preg {
        raise FixedConstraintViolation(
          vreg=range.vreg,
          required~,
          actual=location,
        )
      }
    }
    Spill(_) =>
      if range.get_fixed_reg() is Some(required) {
        raise FixedConstraintViolation(
          vreg=range.vreg,
          required~,
          actual=location,
        )
      }
  }
}

///|
fn verify_clobber_safety(
  program : Program,
  range : LiveRange,
  preg : PhysicalReg,
  block_order : Array[Int],
) -> Unit raise VerifyError {
  for block in program.blocks {
    for inst_index, inst in block.instructions {
      let point = ProgramPoint::new(block.id, inst_index)
      if range.is_live_across(point, block_order) {
        for clobber in inst.clobbers {
          if clobber == preg {
            raise ClobberedRegister(vreg=range.vreg, preg~)
          }
        }
      }
    }
  }
}

///|
pub fn verify_allocation(
  program : Program,
  allocation : Allocation,
) -> Unit raise VerifyError {
  let ranges = build_live_ranges(program)
  for range in ranges.ranges {
    match allocation.location_of(range.vreg) {
      Some(location) => {
        verify_range_assignment(range, location)
        if location is Reg(preg) {
          verify_clobber_safety(program, range, preg, ranges.block_order)
        }
      }
      None => raise Unassigned(vreg=range.vreg)
    }
  }
  for i in 0..<allocation.assignments.length() {
    let lhs = allocation.assignments[i]
    guard ranges.get_by_vreg(lhs.vreg) is Some(lhs_range) else { continue }
    for j in (i + 1)..<allocation.assignments.length() {
      let rhs = allocation.assignments[j]
      if same_location(lhs.location, rhs.location) &&
        ranges.get_by_vreg(rhs.vreg) is Some(rhs_range) &&
        lhs_range.overlaps(rhs_range, ranges.block_order) {
        raise OverlappingAllocation(
          left=lhs.vreg,
          right=rhs.vreg,
          location=lhs.location,
        )
      }
    }
  }
}
