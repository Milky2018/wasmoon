///|
/// Read-only target-selection contract for verified semantic machine input.
///
/// Targets depend on this narrow indexed surface rather than concrete
/// `Function` storage. The owned semantic IR implements it today; a producer
/// may later provide a verified view without changing either target selector.
pub(open) trait SelectionInput {
  fn name(Self) -> String
  fn protocol(Self) -> CallProtocol
  fn signature(Self) -> Signature
  fn parameters(Self) -> Array[Value]
  fn value_count(Self) -> Int
  fn value_index(Self, Value) -> Int?
  fn value_type(Self, Value) -> ValueType?
  fn block_count(Self) -> Int
  fn block_at(Self, Int) -> Block?
  fn block_index(Self, Block) -> Int?
  fn block_parameter_count(Self, Block) -> Int?
  fn block_parameter_at(Self, Block, Int) -> Value?
  fn block_instruction_count(Self, Block) -> Int?
  fn block_instruction_at(Self, Block, Int) -> Instruction?
  fn block_terminator(Self, Block) -> TerminatorRecord?
  fn block_indices_in_cfg_order(Self) -> Array[Int]
  fn instruction_slot_count(Self) -> Int
  fn instruction_at(Self, Int) -> Instruction?
  fn instruction_index(Self, Instruction) -> Int?
  fn instruction_operation(Self, Instruction) -> Operation?
  fn instruction_operand_count(Self, Instruction) -> Int?
  fn instruction_operand_at(Self, Instruction, Int) -> Value?
  fn instruction_result_count(Self, Instruction) -> Int?
  fn instruction_result_at(Self, Instruction, Int) -> Value?
  fn instruction_metadata_view(Self, Instruction) -> InstructionMetadataView?
  fn stack_objects(Self) -> Array[StackObject]
  fn stack_object_size(Self, StackObject) -> Int?
  fn stack_object_alignment(Self, StackObject) -> Int?
  fn verify(Self) -> Unit raise MachVVerifyError
  fn require_verified(Self) -> Unit raise MachVVerifyError
}

///|
pub impl SelectionInput for Function with fn name(self) {
  Function::name(self)
}

///|
pub impl SelectionInput for Function with fn protocol(self) {
  Function::protocol(self)
}

///|
pub impl SelectionInput for Function with fn signature(self) {
  Function::signature(self)
}

///|
pub impl SelectionInput for Function with fn parameters(self) {
  Function::parameters(self)
}

///|
pub impl SelectionInput for Function with fn value_count(self) {
  Function::value_count(self)
}

///|
pub impl SelectionInput for Function with fn value_index(self, value) {
  Function::value_index(self, value)
}

///|
pub impl SelectionInput for Function with fn value_type(self, value) {
  Function::value_type(self, value)
}

///|
pub impl SelectionInput for Function with fn block_count(self) {
  Function::block_count(self)
}

///|
pub impl SelectionInput for Function with fn block_at(self, index) {
  Function::block_at(self, index)
}

///|
pub impl SelectionInput for Function with fn block_index(self, block) {
  Function::block_index(self, block)
}

///|
pub impl SelectionInput for Function with fn block_parameter_count(self, block) {
  Function::block_parameter_count(self, block)
}

///|
pub impl SelectionInput for Function with fn block_parameter_at(
  self,
  block,
  index,
) {
  Function::block_parameter_at(self, block, index)
}

///|
pub impl SelectionInput for Function with fn block_instruction_count(
  self,
  block,
) {
  Function::block_instruction_count(self, block)
}

///|
pub impl SelectionInput for Function with fn block_instruction_at(
  self,
  block,
  index,
) {
  Function::block_instruction_at(self, block, index)
}

///|
pub impl SelectionInput for Function with fn block_terminator(self, block) {
  Function::block_terminator(self, block)
}

///|
pub impl SelectionInput for Function with fn block_indices_in_cfg_order(self) {
  Function::block_indices_in_cfg_order(self)
}

///|
pub impl SelectionInput for Function with fn instruction_slot_count(self) {
  Function::instruction_slot_count(self)
}

///|
pub impl SelectionInput for Function with fn instruction_at(self, index) {
  Function::instruction_at(self, index)
}

///|
pub impl SelectionInput for Function with fn instruction_index(
  self,
  instruction,
) {
  Function::instruction_index(self, instruction)
}

///|
pub impl SelectionInput for Function with fn instruction_operation(
  self,
  instruction,
) {
  Function::instruction_operation(self, instruction)
}

///|
pub impl SelectionInput for Function with fn instruction_operand_count(
  self,
  instruction,
) {
  Function::instruction_operand_count(self, instruction)
}

///|
pub impl SelectionInput for Function with fn instruction_operand_at(
  self,
  instruction,
  index,
) {
  Function::instruction_operand_at(self, instruction, index)
}

///|
pub impl SelectionInput for Function with fn instruction_result_count(
  self,
  instruction,
) {
  Function::instruction_result_count(self, instruction)
}

///|
pub impl SelectionInput for Function with fn instruction_result_at(
  self,
  instruction,
  index,
) {
  Function::instruction_result_at(self, instruction, index)
}

///|
pub impl SelectionInput for Function with fn instruction_metadata_view(
  self,
  instruction,
) {
  Function::instruction_metadata_view(self, instruction)
}

///|
pub impl SelectionInput for Function with fn stack_objects(self) {
  Function::stack_objects(self)
}

///|
pub impl SelectionInput for Function with fn stack_object_size(self, object) {
  Function::stack_object_size(self, object)
}

///|
pub impl SelectionInput for Function with fn stack_object_alignment(
  self,
  object,
) {
  Function::stack_object_alignment(self, object)
}

///|
pub impl SelectionInput for Function with fn verify(self) {
  Function::verify(self)
}

///|
pub impl SelectionInput for Function with fn require_verified(self) {
  Function::require_verified(self)
}
