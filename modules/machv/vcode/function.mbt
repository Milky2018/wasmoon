///|
priv enum ValueDefinition {
  FunctionParameter
  BlockParameter(Block)
  InstructionResult(Instruction)
}

///|
priv struct ValueData {
  ty : ValueType
  definition : ValueDefinition
}

///|
priv struct BlockData {
  parameters : Array[Value]
  body : Array[Instruction]
  mut terminator : Instruction?
}

///|
priv enum InstructionRole {
  Body
  Terminator
} derive(Eq)

///|
priv struct InstructionData[Inst] {
  inst : Inst
  parent : Block
  role : InstructionRole
  operand_start : Int
  operand_count : Int
  clobber_start : Int
  clobber_count : Int
  results : Array[Value]
  successors : Array[Edge]
  metadata : InstructionMetadata
}

///|
pub struct Function[Inst] {
  priv owner : Ref[Unit]
  priv name : String
  priv parameters : Array[Value]
  priv values : Array[ValueData]
  priv blocks : Array[BlockData]
  priv instructions : Array[InstructionData[Inst]]
  priv operands : Array[OperandData]
  priv clobbers : Array[PhysicalReg]
  priv mut layout : Array[Block]
}

///|
fn[Inst] Function::new(
  name : String,
  parameter_types : Array[ValueType],
) -> Function[Inst] {
  let function : Function[Inst] = {
    owner: Ref(()),
    name,
    parameters: [],
    values: [],
    blocks: [],
    instructions: [],
    operands: [],
    clobbers: [],
    layout: [],
  }
  for ty in parameter_types {
    let value = function.allocate_value(ty, FunctionParameter)
    function.parameters.push(value)
  }
  let entry = function.allocate_block([])
  function.layout.push(entry)
  function
}

///|
fn[Inst] Function::allocate_value(
  self : Function[Inst],
  ty : ValueType,
  definition : ValueDefinition,
) -> Value {
  let value = Value::new(self.owner, self.values.length())
  self.values.push({ ty, definition })
  value
}

///|
fn[Inst] Function::allocate_block(
  self : Function[Inst],
  parameter_types : Array[ValueType],
) -> Block {
  let block = Block::new(self.owner, self.blocks.length())
  let parameters : Array[Value] = []
  for ty in parameter_types {
    parameters.push(self.allocate_value(ty, BlockParameter(block)))
  }
  self.blocks.push({ parameters, body: [], terminator: None })
  block
}

///|
fn[Inst] Function::owns_value(self : Function[Inst], value : Value) -> Bool {
  physical_equal(self.owner, value.owner) &&
  value.id >= 0 &&
  value.id < self.values.length()
}

///|
fn[Inst] Function::owns_block(self : Function[Inst], block : Block) -> Bool {
  physical_equal(self.owner, block.owner) &&
  block.id >= 0 &&
  block.id < self.blocks.length()
}

///|
fn[Inst] Function::owns_instruction(
  self : Function[Inst],
  instruction : Instruction,
) -> Bool {
  physical_equal(self.owner, instruction.owner) &&
  instruction.id >= 0 &&
  instruction.id < self.instructions.length()
}

///|
pub fn[Inst] Function::name(self : Function[Inst]) -> String {
  self.name
}

///|
pub fn[Inst] Function::entry_block(self : Function[Inst]) -> Block {
  Block::new(self.owner, 0)
}

///|
pub fn[Inst] Function::parameter_count(self : Function[Inst]) -> Int {
  self.parameters.length()
}

///|
pub fn[Inst] Function::parameter_at(
  self : Function[Inst],
  index : Int,
) -> Value? {
  self.parameters.get(index)
}

///|
pub fn[Inst] Function::value_count(self : Function[Inst]) -> Int {
  self.values.length()
}

///|
pub fn[Inst] Function::value_at(self : Function[Inst], index : Int) -> Value? {
  if index >= 0 && index < self.values.length() {
    Some(Value::new(self.owner, index))
  } else {
    None
  }
}

///|
pub fn[Inst] Function::value_index(
  self : Function[Inst],
  value : Value,
) -> Int? {
  if self.owns_value(value) {
    Some(value.id)
  } else {
    None
  }
}

///|
pub fn[Inst] Function::value_type(
  self : Function[Inst],
  value : Value,
) -> ValueType? {
  if self.owns_value(value) {
    Some(self.values[value.id].ty)
  } else {
    None
  }
}

///|
pub fn[Inst] Function::block_count(self : Function[Inst]) -> Int {
  self.blocks.length()
}

///|
pub fn[Inst] Function::block_at(self : Function[Inst], index : Int) -> Block? {
  if index >= 0 && index < self.blocks.length() {
    Some(Block::new(self.owner, index))
  } else {
    None
  }
}

///|
pub fn[Inst] Function::block_index(
  self : Function[Inst],
  block : Block,
) -> Int? {
  if self.owns_block(block) {
    Some(block.id)
  } else {
    None
  }
}

///|
pub fn[Inst] Function::block_parameters(
  self : Function[Inst],
  block : Block,
) -> Array[Value] {
  if self.owns_block(block) {
    self.blocks[block.id].parameters.copy()
  } else {
    []
  }
}

///|
pub fn[Inst] Function::block_body(
  self : Function[Inst],
  block : Block,
) -> Array[Instruction] {
  if self.owns_block(block) {
    self.blocks[block.id].body.copy()
  } else {
    []
  }
}

///|
pub fn[Inst] Function::block_terminator(
  self : Function[Inst],
  block : Block,
) -> Instruction? {
  if self.owns_block(block) {
    self.blocks[block.id].terminator
  } else {
    None
  }
}

///|
pub fn[Inst] Function::instruction_count(self : Function[Inst]) -> Int {
  self.instructions.length()
}

///|
pub fn[Inst] Function::instruction_at(
  self : Function[Inst],
  index : Int,
) -> Instruction? {
  if index >= 0 && index < self.instructions.length() {
    Some(Instruction::new(self.owner, index))
  } else {
    None
  }
}

///|
pub fn[Inst] Function::instruction_index(
  self : Function[Inst],
  instruction : Instruction,
) -> Int? {
  if self.owns_instruction(instruction) {
    Some(instruction.id)
  } else {
    None
  }
}

///|
pub fn[Inst] Function::instruction(
  self : Function[Inst],
  instruction : Instruction,
) -> Inst? {
  if self.owns_instruction(instruction) {
    Some(self.instructions[instruction.id].inst)
  } else {
    None
  }
}

///|
pub fn[Inst] Function::instruction_operands(
  self : Function[Inst],
  instruction : Instruction,
) -> Array[Operand] {
  if !self.owns_instruction(instruction) {
    return []
  }
  let data = self.instructions[instruction.id]
  Array::makei(data.operand_count, index => {
    self.operands[data.operand_start + index].snapshot()
  })
}

///|
pub fn[Inst] Function::instruction_operand_count(
  self : Function[Inst],
  instruction : Instruction,
) -> Int {
  if self.owns_instruction(instruction) {
    self.instructions[instruction.id].operand_count
  } else {
    0
  }
}

///|
pub fn[Inst] Function::instruction_operand_at(
  self : Function[Inst],
  instruction : Instruction,
  index : Int,
) -> Operand? {
  if !self.owns_instruction(instruction) {
    return None
  }
  let data = self.instructions[instruction.id]
  if index < 0 || index >= data.operand_count {
    return None
  }
  Some(self.operands[data.operand_start + index].snapshot())
}

///|
pub fn[Inst] Function::instruction_clobbers(
  self : Function[Inst],
  instruction : Instruction,
) -> Array[PhysicalReg] {
  if !self.owns_instruction(instruction) {
    return []
  }
  let data = self.instructions[instruction.id]
  self.clobbers[data.clobber_start:data.clobber_start + data.clobber_count].to_owned()
}

///|
pub fn[Inst] Function::instruction_clobber_count(
  self : Function[Inst],
  instruction : Instruction,
) -> Int {
  if self.owns_instruction(instruction) {
    self.instructions[instruction.id].clobber_count
  } else {
    0
  }
}

///|
pub fn[Inst] Function::instruction_clobber_at(
  self : Function[Inst],
  instruction : Instruction,
  index : Int,
) -> PhysicalReg? {
  if !self.owns_instruction(instruction) {
    return None
  }
  let data = self.instructions[instruction.id]
  if index < 0 || index >= data.clobber_count {
    return None
  }
  self.clobbers.get(data.clobber_start + index)
}

///|
pub fn[Inst] Function::instruction_results(
  self : Function[Inst],
  instruction : Instruction,
) -> Array[Value] {
  if self.owns_instruction(instruction) {
    self.instructions[instruction.id].results.copy()
  } else {
    []
  }
}

///|
pub fn[Inst] Function::instruction_is_terminator(
  self : Function[Inst],
  instruction : Instruction,
) -> Bool {
  self.owns_instruction(instruction) &&
  self.instructions[instruction.id].role == Terminator
}

///|
pub fn[Inst] Function::instruction_successors(
  self : Function[Inst],
  instruction : Instruction,
) -> Array[Edge] {
  if self.owns_instruction(instruction) {
    self.instructions[instruction.id].successors.map(edge => edge.copy())
  } else {
    []
  }
}

///|
pub fn[Inst] Function::instruction_successor_count(
  self : Function[Inst],
  instruction : Instruction,
) -> Int {
  if self.owns_instruction(instruction) {
    self.instructions[instruction.id].successors.length()
  } else {
    0
  }
}

///|
pub fn[Inst] Function::instruction_successor_at(
  self : Function[Inst],
  instruction : Instruction,
  index : Int,
) -> Edge? {
  if !self.owns_instruction(instruction) {
    return None
  }
  match self.instructions[instruction.id].successors.get(index) {
    Some(edge) => Some(edge.copy())
    None => None
  }
}

///|
pub fn[Inst] Function::instruction_metadata(
  self : Function[Inst],
  instruction : Instruction,
) -> InstructionMetadata? {
  if self.owns_instruction(instruction) {
    Some(self.instructions[instruction.id].metadata.copy())
  } else {
    None
  }
}

///|
pub fn[Inst] Function::layout(self : Function[Inst]) -> Array[Block] {
  self.layout.copy()
}

///|
pub fn[Inst] Function::set_layout(
  self : Function[Inst],
  layout : Array[Block],
) -> Unit raise VCodeBuildError {
  if layout.length() != self.blocks.length() {
    raise InvalidLayout
  }
  let seen = Array::make(self.blocks.length(), false)
  for block in layout {
    if !self.owns_block(block) || seen[block.id] {
      raise InvalidLayout
    }
    seen[block.id] = true
  }
  self.layout = layout.copy()
}

///|
pub fn[Inst] Function::before(
  self : Function[Inst],
  instruction : Instruction,
) -> ProgramPoint? {
  if self.owns_instruction(instruction) {
    Some(ProgramPoint::new(self.owner, instruction, Before))
  } else {
    None
  }
}

///|
pub fn[Inst] Function::after(
  self : Function[Inst],
  instruction : Instruction,
) -> ProgramPoint? {
  if self.owns_instruction(instruction) {
    Some(ProgramPoint::new(self.owner, instruction, After))
  } else {
    None
  }
}

///|
pub fn[Inst] Function::program_point_instruction(
  self : Function[Inst],
  point : ProgramPoint,
) -> Instruction? {
  if physical_equal(self.owner, point.owner) &&
    self.owns_instruction(point.instruction) {
    Some(point.instruction)
  } else {
    None
  }
}
