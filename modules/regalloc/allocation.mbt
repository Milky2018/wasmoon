///|
pub(all) enum Location {
  Reg(PhysicalReg)
  Spill(Int)
} derive(Eq, Debug)

///|
pub struct Assignment {
  vreg : VirtualReg
  location : Location
} derive(Eq, Debug)

///|
struct Allocation {
  assignments : Array[Assignment]
  mut spill_count : Int
} derive(Debug)

///|
pub fn Allocation::Allocation() -> Allocation {
  { assignments: [], spill_count: 0 }
}

///|
pub fn Allocation::spill_count(self : Allocation) -> Int {
  self.spill_count
}

///|
pub fn Allocation::assignment_count(self : Allocation) -> Int {
  self.assignments.length()
}

///|
pub fn Allocation::assignment_at(self : Allocation, index : Int) -> Assignment? {
  self.assignments.get(index)
}

///|
pub fn Allocation::assignments(self : Allocation) -> Array[Assignment] {
  self.assignments.copy()
}

///|
pub fn Allocation::assign(
  self : Allocation,
  vreg : VirtualReg,
  location : Location,
) -> Unit {
  for i, assignment in self.assignments {
    if assignment.vreg == vreg {
      self.assignments[i] = { vreg, location }
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
