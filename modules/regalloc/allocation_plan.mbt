///|
pub(all) enum EditPosition {
  Before(Int)
  After(Int)
  Edge(source_block~ : Int, successor_index~ : Int)
} derive(Eq, Debug)

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
  priv operand_locations : Map[(Int, Int), Location]
  priv operand_assignments : Array[OperandAssignment]
  priv edits : Array[AllocationEdit]
  priv spill_slots : Array[SpillSlotSpec]
} derive(Debug)

///|
pub impl Show for AllocationPlan with fn output(self, logger) {
  logger.write_string(self.to_repr().to_string())
}

///|
fn AllocationPlan::new(value_count : Int) -> AllocationPlan {
  {
    value_locations: Array::make(value_count, None),
    operand_locations: Map([]),
    operand_assignments: [],
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
  self.operand_locations[(instruction, operand)] = location
  self.operand_assignments.push({ instruction, operand, location })
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
  self.spill_slots.push({ size, alignment })
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
  self.operand_locations.get((instruction, operand))
}

///|
pub fn AllocationPlan::operand_assignments(
  self : AllocationPlan,
) -> Array[OperandAssignment] {
  self.operand_assignments.copy()
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
