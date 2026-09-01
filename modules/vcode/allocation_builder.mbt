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
/// Adopts canonical location tables produced for this exact selected function.
///
/// The caller must stop mutating the source tables after adoption. Shape,
/// location class, spill ownership, size, and alignment are checked here so
/// callers that disable the final allocation verifier retain the same local
/// construction guarantees as incremental builder writes.
pub fn[Inst] AllocationBuilder::from_plan_storage(
  function : Function[Inst],
  value_locations : Array[AllocationLocation?],
  operand_locations : Array[Array[AllocationLocation?]],
  spill_owners : Array[Int],
  spill_sizes : Array[Int],
  spill_alignments : Array[Int],
) -> AllocationBuilder[Inst]? {
  if value_locations.length() != function.values.length() ||
    operand_locations.length() != function.instructions.length() ||
    spill_owners.length() != spill_sizes.length() ||
    spill_owners.length() != spill_alignments.length() {
    return None
  }
  let stack_slots : Array[StackSlotData] = []
  for slot in 0..<spill_owners.length() {
    let owner = spill_owners[slot]
    if owner < 0 || owner >= function.values.length() {
      return None
    }
    let minimum = match function.values[owner].ty {
      I32 | F32 => 4
      I64 | F64 | Ptr64 | GcRef64 => 8
      V128 => 16
    }
    if spill_sizes[slot] < minimum ||
      spill_alignments[slot] < minimum ||
      (spill_alignments[slot] & (spill_alignments[slot] - 1)) != 0 {
      return None
    }
    stack_slots.push({
      ty: function.values[owner].ty,
      size: spill_sizes[slot],
      alignment: spill_alignments[slot],
    })
  }
  let allocation = Allocation::for_function_with_storage(
    function, value_locations, operand_locations, stack_slots,
  )
  for value in 0..<value_locations.length() {
    guard value_locations[value] is Some(location) else { return None }
    if !allocation.dense_location_matches(location, function.values[value].ty) {
      return None
    }
  }
  for instruction in 0..<operand_locations.length() {
    let data = function.instructions[instruction]
    let locations = operand_locations[instruction]
    if locations.length() != data.allocation_operand_count {
      return None
    }
    for operand in 0..<locations.length() {
      guard locations[operand] is Some(location) else { return None }
      let value = function.operands[data.operand_start + operand].vreg.id
      if !allocation.dense_location_matches(location, function.values[value].ty) {
        return None
      }
    }
  }
  Some({ function, allocation, })
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
  self.function.operands[data.operand_start + operand].vreg.id
}

///|
pub fn[Inst] AllocationBuilder::create_stack_slot(
  self : AllocationBuilder[Inst],
  value : Int,
  size : Int,
  alignment : Int,
) -> Int {
  let slot = self.allocation.create_stack_slot(
    self.function.values[value].ty,
    size,
    alignment,
  )
  slot.id
}

///|
pub fn[Inst] AllocationBuilder::assign_value(
  self : AllocationBuilder[Inst],
  value : Int,
  location : AllocationLocation,
) -> Bool {
  if value < 0 ||
    value >= self.function.values.length() ||
    !self.allocation.dense_location_matches(
      location,
      self.function.values[value].ty,
    ) {
    return false
  }
  self.allocation.value_locations[value] = Some(location)
  true
}

///|
pub fn[Inst] AllocationBuilder::value_location(
  self : AllocationBuilder[Inst],
  value : Int,
) -> AllocationLocation? {
  self.allocation.value_locations[value]
}

///|
pub fn[Inst] AllocationBuilder::assign_operand(
  self : AllocationBuilder[Inst],
  instruction : Int,
  operand : Int,
  location : AllocationLocation,
) -> Bool {
  if instruction < 0 || instruction >= self.function.instructions.length() {
    return false
  }
  let data = self.function.instructions[instruction]
  if operand < 0 || operand >= data.operand_count {
    return false
  }
  let value = self.function.operands[data.operand_start + operand].vreg.id
  if !self.allocation.dense_location_matches(
      location,
      self.function.values[value].ty,
    ) {
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
  from : AllocationLocation,
  to : AllocationLocation,
) -> Bool {
  if instruction < 0 ||
    instruction >= self.function.instructions.length() ||
    value < 0 ||
    value >= self.function.values.length() ||
    !self.allocation.dense_location_matches(
      from,
      self.function.values[value].ty,
    ) ||
    !self.allocation.dense_location_matches(to, self.function.values[value].ty) {
    return false
  }
  let value = Value::new(self.function.owner, value)
  let instruction = Instruction::new(self.function.owner, instruction)
  let point = ProgramPoint::new(self.function.owner, instruction, placement)
  let edit = match (from.register(), to.register()) {
    (Some(from_reg), Some(to_reg)) =>
      Edit::register_move(point, value, from_reg, to_reg)
    (Some(reg), None) => {
      let slot = to.spill_index().unwrap()
      Edit::spill(
        point,
        value,
        reg,
        StackSlot::new(self.allocation.owner, slot),
      )
    }
    (None, Some(reg)) => {
      let slot = from.spill_index().unwrap()
      Edit::reload(
        point,
        value,
        StackSlot::new(self.allocation.owner, slot),
        reg,
      )
    }
    (None, None) => return false
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
  from : AllocationLocation,
  to : AllocationLocation,
) -> Bool {
  if source_block < 0 ||
    source_block >= self.function.blocks.length() ||
    successor < 0 ||
    value < 0 ||
    value >= self.function.values.length() ||
    !self.allocation.dense_location_matches(
      from,
      self.function.values[value].ty,
    ) ||
    !self.allocation.dense_location_matches(to, self.function.values[value].ty) {
    return false
  }
  self.allocation.append_edit(
    Edit::edge_move(
      Block::new(self.function.owner, source_block),
      successor,
      Value::new(self.function.owner, value),
      self.allocation.export_location(from).unwrap(),
      self.allocation.export_location(to).unwrap(),
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
/// Adds every selected VCode safepoint root through dense internal ids.
///
/// Selected-function validation already established metadata ownership and
/// root types; this method retains allocation-location checks without copying
/// layouts, instruction metadata, or owner-tagged root snapshots.
pub fn[Inst] AllocationBuilder::add_function_safepoint_roots(
  self : AllocationBuilder[Inst],
) -> Bool {
  for instruction, data in self.function.instructions {
    for root in data.metadata.live_gc_roots {
      if !self.function.owns_value(root) {
        return false
      }
      guard self.allocation.value_locations[root.id] is Some(location) else {
        return false
      }
      self.allocation.safepoint_roots.push({
        instruction: Instruction::new(self.function.owner, instruction),
        value: root,
        location,
      })
    }
  }
  true
}

///|
pub fn[Inst] AllocationBuilder::finish(
  self : AllocationBuilder[Inst],
) -> Allocation {
  self.allocation
}
