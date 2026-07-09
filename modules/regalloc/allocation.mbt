///|
pub(all) enum Location {
  Reg(PhysicalReg)
  Spill(Int)
} derive(Eq, Debug)

///|
pub(all) struct Assignment {
  vreg : VirtualReg
  mut location : Location
} derive(Eq, Debug)

///|
pub(all) struct Allocation {
  assignments : Array[Assignment]
  mut spill_count : Int
} derive(Debug)

///|
pub fn Allocation::Allocation() -> Allocation {
  { assignments: [], spill_count: 0 }
}

///|
pub fn Allocation::assign(
  self : Allocation,
  vreg : VirtualReg,
  location : Location,
) -> Unit {
  for assignment in self.assignments {
    if assignment.vreg == vreg {
      assignment.location = location
      return
    }
  }
  self.assignments.push({ vreg, location })
}

///|
pub fn Allocation::location_of(
  self : Allocation,
  vreg : VirtualReg,
) -> Location? {
  for assignment in self.assignments {
    if assignment.vreg == vreg {
      return Some(assignment.location)
    }
  }
  None
}
