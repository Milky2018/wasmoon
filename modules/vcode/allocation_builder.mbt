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
/// Creates final output tables for selected operands, including implicit GC
/// roots that are visible to allocation but not ordinary instruction operands.
pub fn[Inst] AllocationBuilder::for_selected_function(
  function : Function[Inst],
) -> AllocationBuilder[Inst] {
  {
    function,
    allocation: Allocation::for_function_with_storage(
      function,
      Array::make(function.value_count(), None),
      Array::makei(function.instruction_count(), instruction => {
        Array::make(
          function.instructions[instruction].allocation_operand_count,
          None,
        )
      }),
      [],
    ),
  }
}

///|
pub fn[Inst] AllocationBuilder::create_stack_slot(
  self : AllocationBuilder[Inst],
  value : Int32,
  size : Int32,
  alignment : Int32,
) -> Int32 {
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
  value : Int32,
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
  value : Int32,
) -> AllocationLocation? {
  self.allocation.value_locations[value]
}

///|
pub fn[Inst] AllocationBuilder::assign_operand(
  self : AllocationBuilder[Inst],
  instruction : Int32,
  operand : Int32,
  location : AllocationLocation,
) -> Bool {
  if instruction < 0 || instruction >= self.function.instructions.length() {
    return false
  }
  let data = self.function.instructions[instruction]
  if operand < 0 ||
    operand >= self.allocation.operand_locations[instruction].length() {
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
  instruction : Int32,
  placement : PointPlacement,
  value : Int32,
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
  source_block : Int32,
  successor : Int32,
  value : Int32,
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
  instruction : Int32,
  value : Int32,
) -> Bool {
  if instruction < 0 ||
    instruction >= self.function.instructions.length() ||
    value < 0 ||
    value >= self.function.values.length() ||
    self.allocation.value_locations[value] is None {
    return false
  }
  self.allocation.record_safepoint_root({
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
      self.allocation.record_safepoint_root({
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

///|
/// Completes selected-function output without relying on the optional dataflow
/// verifier. Every home and implicit operand must have been assigned.
pub fn[Inst] AllocationBuilder::finish_selected(
  self : AllocationBuilder[Inst],
) -> Allocation? {
  for location in self.allocation.value_locations {
    if location is None {
      return None
    }
  }
  for locations in self.allocation.operand_locations {
    for location in locations {
      if location is None {
        return None
      }
    }
  }
  if !self.add_function_safepoint_roots() {
    return None
  }
  Some(self.allocation)
}
