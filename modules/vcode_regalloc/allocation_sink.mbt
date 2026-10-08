///|
/// Final VCode output; only strict verification records generic edits.
priv struct VCodeAllocationSink[Inst] {
  builder : @vcode.AllocationBuilder[Inst]
  view : VCodeFunctionView[Inst]
  validation_edits : Array[@regalloc.AllocationEdit]?
  mut rejected : Bool
}

///|
impl[Inst] @regalloc.AllocationSink for VCodeAllocationSink[Inst] with fn assign_value(
  self,
  value,
  location,
) {
  if !self.builder.assign_value(value.id, location) {
    self.rejected = true
  }
}

///|
impl[Inst] @regalloc.AllocationSink for VCodeAllocationSink[Inst] with fn assign_operand(
  self,
  instruction,
  operand,
  location,
) {
  if !self.builder.assign_operand(instruction, operand, location) {
    self.rejected = true
  }
}

///|
impl[Inst] @regalloc.AllocationSink for VCodeAllocationSink[Inst] with fn create_spill_slot(
  self,
  owner,
  size,
  alignment,
) {
  if owner < 0 || owner >= @regalloc.FunctionView::value_count(self.view) {
    self.rejected = true
    return -1
  }
  let minimum = @regalloc.FunctionView::value_spill_size(self.view, owner)
  if size < minimum || alignment < minimum || (alignment & (alignment - 1)) != 0 {
    self.rejected = true
    return -1
  }
  self.builder.create_stack_slot(owner, size, alignment)
}

///|
impl[Inst] @regalloc.AllocationSink for VCodeAllocationSink[Inst] with fn value_location(
  self,
  value,
) {
  self.builder.value_location(value)
}

///|
impl[Inst] @regalloc.AllocationSink for VCodeAllocationSink[Inst] with fn operand_location(
  self,
  instruction,
  operand,
) {
  self.builder.finish().allocated_operand_location_at(instruction, operand)
}

///|
impl[Inst] @regalloc.AllocationSink for VCodeAllocationSink[Inst] with fn spill_slot(
  self,
  index,
) {
  let allocation = self.builder.finish()
  allocation
  .stack_slot_at(index)
  .map(slot => {
    @regalloc.SpillSlotSpec::new(
      allocation.stack_slot_size(slot).unwrap(),
      allocation.stack_slot_alignment(slot).unwrap(),
    )
  })
}

///|
impl[Inst] @regalloc.AllocationSink for VCodeAllocationSink[Inst] with fn add_edit(
  self,
  edit,
) {
  if self.validation_edits is Some(edits) {
    edits.push(edit)
  }
  let accepted = match edit.position {
    Before(instruction) =>
      self.builder.add_transfer(
        instruction,
        Before,
        edit.value.id,
        edit.from,
        edit.to,
      )
    After(instruction) =>
      self.builder.add_transfer(
        instruction,
        After,
        edit.value.id,
        edit.from,
        edit.to,
      )
    Edge(source_block~, successor_index~) =>
      self.builder.add_edge_transfer(
        source_block,
        successor_index,
        edit.value.id,
        edit.from,
        edit.to,
      )
  }
  if !accepted {
    self.rejected = true
  }
}

///|
impl[Inst] @regalloc.AllocationSink for VCodeAllocationSink[Inst] with fn edits(
  self,
) {
  match self.validation_edits {
    Some(edits) => edits.copy()
    None => []
  }
}
