///|
/// Dense-index writer used after a verified register-allocation plan has been
/// produced for this exact function.
///
/// The writer avoids reconstructing and revalidating owner-tagged handles for
/// every value, operand, and edit. Indices must come from the matching
/// function and stay within its published counts. Final allocation invariants
/// remain the authoritative validation boundary.
pub struct AllocationBuilder[Inst] {
  priv function : Function[Inst]
  priv allocation : Allocation
}

///|
pub fn[Inst] AllocationBuilder::new(
  function : Function[Inst],
) -> AllocationBuilder[Inst] {
  { function, allocation: Allocation::for_function(function), }
}

///|
pub fn[Inst] AllocationBuilder::value_type_at(
  self : AllocationBuilder[Inst],
  value : Int,
) -> ValueType {
  self.function.values[value].ty
}

///|
pub fn[Inst] AllocationBuilder::operand_value_at(
  self : AllocationBuilder[Inst],
  instruction : Int,
  operand : Int,
) -> Int {
  let data = self.function.instructions[instruction]
  self.function.operands[data.operand_start + operand].value.id
}

///|
pub fn[Inst] AllocationBuilder::create_stack_slot(
  self : AllocationBuilder[Inst],
  value : Int,
  size : Int,
  alignment : Int,
) -> StackSlot {
  self.allocation.create_stack_slot(
    self.function.values[value].ty,
    size,
    alignment,
  )
}

///|
pub fn[Inst] AllocationBuilder::assign_value(
  self : AllocationBuilder[Inst],
  value : Int,
  location : Location,
) -> Bool {
  if value < 0 ||
    value >= self.function.values.length() ||
    !self.allocation.location_matches(location, self.function.values[value].ty) {
    return false
  }
  self.allocation.value_locations[value] = Some(location)
  true
}

///|
pub fn[Inst] AllocationBuilder::value_location(
  self : AllocationBuilder[Inst],
  value : Int,
) -> Location? {
  self.allocation.value_locations[value]
}

///|
pub fn[Inst] AllocationBuilder::assign_operand(
  self : AllocationBuilder[Inst],
  instruction : Int,
  operand : Int,
  location : Location,
) -> Bool {
  if instruction < 0 || instruction >= self.function.instructions.length() {
    return false
  }
  let data = self.function.instructions[instruction]
  if operand < 0 || operand >= data.operand_count {
    return false
  }
  let value = self.function.operands[data.operand_start + operand].value.id
  if !self.allocation.location_matches(location, self.function.values[value].ty) {
    return false
  }
  self.allocation.operand_locations[instruction][operand] = Some(location)
  true
}

///|
pub fn[Inst] AllocationBuilder::add_transfer(
  self : AllocationBuilder[Inst],
  instruction : Int,
  placement : PointPlacement,
  value : Int,
  from : Location,
  to : Location,
) -> Bool {
  if instruction < 0 ||
    instruction >= self.function.instructions.length() ||
    value < 0 ||
    value >= self.function.values.length() ||
    !self.allocation.location_matches(from, self.function.values[value].ty) ||
    !self.allocation.location_matches(to, self.function.values[value].ty) {
    return false
  }
  let value = Value::new(self.function.owner, value)
  let instruction = Instruction::new(self.function.owner, instruction)
  let point = ProgramPoint::new(self.function.owner, instruction, placement)
  let edit = match (from, to) {
    (Register(from_reg), Register(to_reg)) =>
      Edit::register_move(point, value, from_reg, to_reg)
    (Register(reg), Stack(slot)) => Edit::spill(point, value, reg, slot)
    (Stack(slot), Register(reg)) => Edit::reload(point, value, slot, reg)
    (Stack(_), Stack(_)) => return false
  }
  self.allocation.append_edit(edit)
  true
}

///|
pub fn[Inst] AllocationBuilder::add_edge_transfer(
  self : AllocationBuilder[Inst],
  source_block : Int,
  successor : Int,
  value : Int,
  from : Location,
  to : Location,
) -> Bool {
  if source_block < 0 ||
    source_block >= self.function.blocks.length() ||
    successor < 0 ||
    value < 0 ||
    value >= self.function.values.length() ||
    !self.allocation.location_matches(from, self.function.values[value].ty) ||
    !self.allocation.location_matches(to, self.function.values[value].ty) {
    return false
  }
  self.allocation.append_edit(
    Edit::edge_move(
      Block::new(self.function.owner, source_block),
      successor,
      Value::new(self.function.owner, value),
      from,
      to,
    ),
  )
  true
}

///|
pub fn[Inst] AllocationBuilder::add_safepoint_root(
  self : AllocationBuilder[Inst],
  instruction : Int,
  value : Int,
) -> Bool {
  if instruction < 0 ||
    instruction >= self.function.instructions.length() ||
    value < 0 ||
    value >= self.function.values.length() ||
    self.allocation.value_locations[value] is None {
    return false
  }
  self.allocation.safepoint_roots.push({
    instruction: Instruction::new(self.function.owner, instruction),
    value: Value::new(self.function.owner, value),
    location: self.allocation.value_locations[value].unwrap(),
  })
  true
}

///|
pub fn[Inst] AllocationBuilder::finish(
  self : AllocationBuilder[Inst],
) -> Allocation {
  self.allocation
}
