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
  TiedConstraintViolation(
    left~ : VirtualReg,
    right~ : VirtualReg,
    left_location~ : Location,
    right_location~ : Location
  )
  ScratchRegisterUnavailable(message~ : String)
} derive(Debug)

///|
pub fn raise_scratch_register_unavailable(
  message~ : String,
) -> Unit raise VerifyError {
  raise ScratchRegisterUnavailable(message~)
}

///|
fn virtual_reg_key(reg : VirtualReg) -> (Int, Int) {
  let class = match reg.class {
    Int => 0
    Float => 1
    Vector => 2
  }
  (class, reg.id)
}

///|
fn location_key(location : Location) -> (Int, Int) {
  match location {
    Reg(reg) => physical_reg_key(reg)
    Spill(slot) => (3, slot)
  }
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
  clobber_points : Map[(Int, Int), Array[ProgramPoint]],
  range : LiveRange,
  preg : PhysicalReg,
  block_order : Array[Int],
) -> Unit raise VerifyError {
  match clobber_points.get(physical_reg_key(preg)) {
    Some(points) =>
      for point in points {
        if range.is_live_across(point, block_order) {
          raise ClobberedRegister(vreg=range.vreg, preg~)
        }
      }
    None => ()
  }
}

///|
fn verify_tied_operands(
  program : Program,
  locations : Map[(Int, Int), Location],
) -> Unit raise VerifyError {
  for block in program.blocks {
    for inst in block.instructions {
      for i, lhs in inst.operands {
        if lhs.tie_id < 0 {
          continue
        }
        guard locations.get(virtual_reg_key(lhs.vreg)) is Some(lhs_location) else {
          raise Unassigned(vreg=lhs.vreg)
        }
        for j in (i + 1)..<inst.operands.length() {
          let rhs = inst.operands[j]
          if rhs.tie_id != lhs.tie_id {
            continue
          }
          guard locations.get(virtual_reg_key(rhs.vreg)) is Some(rhs_location) else {
            raise Unassigned(vreg=rhs.vreg)
          }
          if lhs_location != rhs_location {
            raise TiedConstraintViolation(
              left=lhs.vreg,
              right=rhs.vreg,
              left_location=lhs_location,
              right_location=rhs_location,
            )
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
  let locations : Map[(Int, Int), Location] = Map([])
  for assignment in allocation.assignments {
    locations[virtual_reg_key(assignment.vreg)] = assignment.location
  }
  let clobber_points = collect_register_clobber_points(program)
  let ranges_by_location : Map[(Int, Int), Array[(LiveRange, Location)]] = Map([])
  for range in ranges.ranges {
    match locations.get(virtual_reg_key(range.vreg)) {
      Some(location) => {
        verify_range_assignment(range, location)
        if location is Reg(preg) {
          verify_clobber_safety(clobber_points, range, preg, ranges.block_order)
        }
        let key = location_key(location)
        match ranges_by_location.get(key) {
          Some(assigned) => assigned.push((range, location))
          None => ranges_by_location[key] = [(range, location)]
        }
      }
      None => raise Unassigned(vreg=range.vreg)
    }
  }
  verify_tied_operands(program, locations)
  for _, assigned_ranges in ranges_by_location {
    for i in 0..<assigned_ranges.length() {
      let (lhs_range, lhs_location) = assigned_ranges[i]
      for j in (i + 1)..<assigned_ranges.length() {
        let (rhs_range, _) = assigned_ranges[j]
        if lhs_range.overlaps(rhs_range, ranges.block_order) &&
          !lhs_range.overlap_allowed_by_tie(rhs_range, ranges.block_order) {
          raise OverlappingAllocation(
            left=lhs_range.vreg,
            right=rhs_range.vreg,
            location=lhs_location,
          )
        }
      }
    }
  }
}
