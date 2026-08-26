///|
pub(all) enum EditPosition {
  Before(Int)
  After(Int)
  Edge(source_block~ : Int, successor_index~ : Int)
} derive(Eq, Hash, Debug)

///|
pub(all) struct AllocationEdit {
  value : VirtualReg
  from : Location
  to : Location
  position : EditPosition
} derive(Eq, Debug)

///|
pub struct OperandAssignment {
  instruction : Int
  operand : Int
  location : Location
} derive(Eq, Debug)

///|
pub struct SpillSlotSpec {
  size : Int
  alignment : Int
} derive(Eq, Debug)

///|
pub struct AllocationPlan {
  priv value_locations : Array[Location?]
  priv operand_locations : Array[Array[Location?]]
  priv edits : Array[AllocationEdit]
  priv spill_slots : Array[SpillSlotSpec]
}

///|
pub impl Debug for AllocationPlan with fn to_repr(self) {
  Repr::record({
    "value_locations": Repr(self.value_locations),
    "operand_assignments": Repr(self.operand_assignments()),
    "edits": Repr(self.edits),
    "spill_slots": Repr(self.spill_slots),
  })
}

///|
pub impl Show for AllocationPlan with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn AllocationPlan::new(value_count : Int) -> AllocationPlan {
  {
    value_locations: Array::make(value_count, None),
    operand_locations: [],
    edits: [],
    spill_slots: [],
  }
}

///|
fn AllocationPlan::assign_value(
  self : AllocationPlan,
  vreg : VirtualReg,
  location : Location,
) -> Unit {
  if vreg.id >= 0 && vreg.id < self.value_locations.length() {
    self.value_locations[vreg.id] = Some(location)
  }
}

///|
fn AllocationPlan::assign_operand(
  self : AllocationPlan,
  instruction : Int,
  operand : Int,
  location : Location,
) -> Unit {
  while self.operand_locations.length() <= instruction {
    self.operand_locations.push([])
  }
  let locations = self.operand_locations[instruction]
  while locations.length() <= operand {
    locations.push(None)
  }
  locations[operand] = Some(location)
}

///|
fn AllocationPlan::add_edit(
  self : AllocationPlan,
  edit : AllocationEdit,
) -> Unit {
  self.edits.push(edit)
}

///|
fn AllocationPlan::create_spill_slot(
  self : AllocationPlan,
  size : Int,
  alignment : Int,
) -> Int {
  let slot = self.spill_slots.length()
  self.spill_slots.push({ size, alignment, })
  slot
}

///|
/// Return the value's default transfer home.
///
/// Segment-specific operand assignments and edits may keep the newest value
/// elsewhere until a transition returns it here.
pub fn AllocationPlan::value_location(
  self : AllocationPlan,
  value : Int,
) -> Location? {
  self.value_locations.get(value).bind(location => location)
}

///|
pub fn AllocationPlan::operand_location(
  self : AllocationPlan,
  instruction : Int,
  operand : Int,
) -> Location? {
  self.operand_locations
  .get(instruction)
  .bind(locations => locations.get(operand).bind(location => location))
}

///|
pub fn AllocationPlan::operand_assignments(
  self : AllocationPlan,
) -> Array[OperandAssignment] {
  let assignments : Array[OperandAssignment] = []
  for instruction, locations in self.operand_locations {
    for operand, location in locations {
      if location is Some(location) {
        assignments.push({ instruction, operand, location, })
      }
    }
  }
  assignments
}

///|
pub fn AllocationPlan::edits(self : AllocationPlan) -> Array[AllocationEdit] {
  self.edits.copy()
}

///|
pub fn AllocationPlan::spill_count(self : AllocationPlan) -> Int {
  self.spill_slots.length()
}

///|
pub fn AllocationPlan::spill_slot(
  self : AllocationPlan,
  index : Int,
) -> SpillSlotSpec? {
  self.spill_slots.get(index)
}
