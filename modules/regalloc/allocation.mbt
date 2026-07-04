///|
pub(all) enum Location {
  Reg(PhysicalReg)
  Spill(Int)
} derive(Eq, Debug)

///|
pub(all) struct Assignment {
  vreg : VirtualReg
  location : Location
} derive(Eq, Debug)

///|
pub(all) struct Allocation {
  assignments : Array[Assignment]
  mut spill_count : Int
} derive(Debug)

///|
pub fn Allocation::new() -> Allocation {
  { assignments: [], spill_count: 0 }
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
