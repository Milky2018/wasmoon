///|
/// Returns the allocation type for a valid dense value id.
///
/// Allocation consumers call these indexed accessors only after selected VCode
/// validation, so invalid indices are programmer errors.
pub fn[Inst] Function::allocation_value_type_at(
  self : Function[Inst],
  value : Int,
) -> ValueType {
  self.values[value].ty
}

///|
/// Returns a function parameter as a canonical allocation virtual register.
pub fn[Inst] Function::allocation_entry_value_at(
  self : Function[Inst],
  parameter : Int,
) -> AllocationVirtualReg {
  let value = self.parameters[parameter].id
  { id: value, class: reg_class_for_value_type(self.values[value].ty), }
}

///|
/// Returns the stable block id at a valid dense layout index.
pub fn[Inst] Function::allocation_layout_block_id_at(
  self : Function[Inst],
  block : Int,
) -> Int {
  self.layout[block].id
}

///|
pub fn[Inst] Function::allocation_block_parameter_count(
  self : Function[Inst],
  block : Int,
) -> Int {
  self.blocks[self.layout[block].id].parameters.length()
}

///|
pub fn[Inst] Function::allocation_block_parameter_at(
  self : Function[Inst],
  block : Int,
  parameter : Int,
) -> AllocationVirtualReg {
  let value = self.blocks[self.layout[block].id].parameters[parameter].id
  { id: value, class: reg_class_for_value_type(self.values[value].ty), }
}

///|
pub fn[Inst] Function::allocation_block_instruction_count(
  self : Function[Inst],
  block : Int,
) -> Int {
  let data = self.blocks[self.layout[block].id]
  let terminator_count = match data.terminator {
    Some(_) => 1
    None => 0
  }
  data.body.length() + terminator_count
}

///|
pub fn[Inst] Function::allocation_block_instruction_at(
  self : Function[Inst],
  block : Int,
  instruction : Int,
) -> Int {
  let data = self.blocks[self.layout[block].id]
  if instruction < data.body.length() {
    data.body[instruction].id
  } else {
    data.terminator.unwrap().id
  }
}

///|
pub fn[Inst] Function::allocation_block_successor_count(
  self : Function[Inst],
  block : Int,
) -> Int {
  let terminator = self.blocks[self.layout[block].id].terminator.unwrap().id
  self.instructions[terminator].successors.length()
}

///|
pub fn[Inst] Function::allocation_block_successor_at(
  self : Function[Inst],
  block : Int,
  successor : Int,
) -> Int {
  let terminator = self.blocks[self.layout[block].id].terminator.unwrap().id
  let target = self.instructions[terminator].successors[successor].target.id
  self.blocks[target].layout_index
}

///|
pub fn[Inst] Function::allocation_edge_argument_count(
  self : Function[Inst],
  block : Int,
  successor : Int,
) -> Int {
  let terminator = self.blocks[self.layout[block].id].terminator.unwrap().id
  self.instructions[terminator].successors[successor].arguments.length()
}

///|
pub fn[Inst] Function::allocation_edge_argument_at(
  self : Function[Inst],
  block : Int,
  successor : Int,
  argument : Int,
) -> AllocationVirtualReg {
  let terminator = self.blocks[self.layout[block].id].terminator.unwrap().id
  let value = self.instructions[terminator].successors[successor].arguments[argument].id
  { id: value, class: reg_class_for_value_type(self.values[value].ty), }
}

///|
pub fn[Inst] Function::allocation_instruction_operands(
  self : Function[Inst],
  instruction : Int,
) -> ArrayView[AllocationOperand] {
  let data = self.instructions[instruction]
  self.operands[data.operand_start:data.operand_start + data.operand_count]
}

///|
pub fn[Inst] Function::allocation_instruction_clobbers(
  self : Function[Inst],
  instruction : Int,
) -> ArrayView[PhysicalReg] {
  let data = self.instructions[instruction]
  self.clobbers[data.clobber_start:data.clobber_start + data.clobber_count]
}
