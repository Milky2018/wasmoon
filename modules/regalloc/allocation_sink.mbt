///|
/// Final allocation storage supplied by an embedding. Writes are statically
/// dispatched; the allocator retains only unresolved parallel edits.
/// Implementations must start empty, use dense spill ids, and preserve writes
/// for location queries. `edits` is needed only when verification is enabled.
pub(open) trait AllocationSink {
  fn assign_value(Self, VirtualReg, Location) -> Unit
  fn assign_operand(Self, Int32, Int32, Location) -> Unit
  fn create_spill_slot(Self, Int32, Int32, Int32) -> Int32
  fn value_location(Self, Int32) -> Location?
  fn operand_location(Self, Int32, Int32) -> Location?
  fn spill_slot(Self, Int32) -> SpillSlotSpec?
  fn add_edit(Self, AllocationEdit) -> Unit
  fn edits(Self) -> Array[AllocationEdit]
}

///|
impl AllocationSink for AllocationPlan with fn assign_value(
  self,
  value,
  location,
) {
  self.assign_value(value, location)
}

///|
impl AllocationSink for AllocationPlan with fn assign_operand(
  self,
  instruction,
  operand,
  location,
) {
  self.assign_operand(instruction, operand, location)
}

///|
impl AllocationSink for AllocationPlan with fn create_spill_slot(
  self,
  owner,
  size,
  alignment,
) {
  self.create_spill_slot(owner, size, alignment)
}

///|
impl AllocationSink for AllocationPlan with fn value_location(self, value) {
  self.value_location(value)
}

///|
impl AllocationSink for AllocationPlan with fn operand_location(
  self,
  instruction,
  operand,
) {
  self.operand_location(instruction, operand)
}

///|
impl AllocationSink for AllocationPlan with fn spill_slot(self, index) {
  self.spill_slot(index)
}

///|
impl AllocationSink for AllocationPlan with fn add_edit(self, edit) {
  self.add_edit(edit)
}

///|
impl AllocationSink for AllocationPlan with fn edits(self) {
  self.edits()
}

///|
priv struct AllocationWork[S] {
  sink : S
  edits : Array[AllocationEdit]
}
