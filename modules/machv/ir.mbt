///|
/// Opaque function-owned SSA value handle.
pub struct Value {
  priv owner : Ref[Unit]
  priv id : Int
}

///|
fn Value::new(owner : Ref[Unit], id : Int) -> Value {
  { owner, id }
}

///|
pub impl Eq for Value with fn equal(self, other) {
  physical_equal(self.owner, other.owner) && self.id == other.id
}

///|
pub impl Hash for Value with fn hash_combine(self, hasher) {
  self.id.hash_combine(hasher)
}

///|
pub impl Debug for Value with fn to_repr(self) {
  Repr::literal("v\{self.id}")
}

///|
/// Opaque function-owned basic-block handle.
pub struct Block {
  priv owner : Ref[Unit]
  priv id : Int
}

///|
fn Block::new(owner : Ref[Unit], id : Int) -> Block {
  { owner, id }
}

///|
pub impl Eq for Block with fn equal(self, other) {
  physical_equal(self.owner, other.owner) && self.id == other.id
}

///|
pub impl Hash for Block with fn hash_combine(self, hasher) {
  self.id.hash_combine(hasher)
}

///|
pub impl Debug for Block with fn to_repr(self) {
  Repr::literal("block\{self.id}")
}

///|
/// Opaque function-owned instruction handle.
pub struct Instruction {
  priv owner : Ref[Unit]
  priv id : Int
}

///|
fn Instruction::new(owner : Ref[Unit], id : Int) -> Instruction {
  { owner, id }
}

///|
pub impl Eq for Instruction with fn equal(self, other) {
  physical_equal(self.owner, other.owner) && self.id == other.id
}

///|
pub impl Hash for Instruction with fn hash_combine(self, hasher) {
  self.id.hash_combine(hasher)
}

///|
pub impl Debug for Instruction with fn to_repr(self) {
  Repr::literal("inst\{self.id}")
}

///|
pub struct Edge {
  target : Block
  arguments : Array[Value]
} derive(Debug, Eq)

///|
fn Edge::new(target : Block, arguments : Array[Value]) -> Edge {
  { target, arguments: arguments.copy() }
}

///|
fn Edge::copy(self : Edge) -> Edge {
  Edge::new(self.target, self.arguments)
}

///|
pub struct SwitchCase {
  bits : UInt64
  edge : Edge
} derive(Debug, Eq)

///|
fn SwitchCase::new(bits : UInt64, edge : Edge) -> SwitchCase {
  { bits, edge }
}

///|
fn SwitchCase::copy(self : SwitchCase) -> SwitchCase {
  SwitchCase::new(self.bits, self.edge.copy())
}

///|
pub(all) enum Terminator {
  Jump(Edge)
  Branch(Value, Edge, Edge)
  Switch(Value, Array[SwitchCase], Edge)
  Return(Array[Value])
  TailCall(SemanticCall, Array[Value])
  Trap(TrapReason)
} derive(Debug, Eq)

///|
fn Terminator::copy(self : Terminator) -> Terminator {
  match self {
    Jump(edge) => Jump(edge.copy())
    Branch(condition, true_edge, false_edge) =>
      Branch(condition, true_edge.copy(), false_edge.copy())
    Switch(index, cases, default_edge) =>
      Switch(index, cases.map(case => case.copy()), default_edge.copy())
    Return(values) => Return(values.copy())
    TailCall(call, operands) => TailCall(call.copy(), operands.copy())
    Trap(reason) => Trap(reason)
  }
}

///|
pub struct TerminatorMetadata {
  source : SourceLocation?
  live_gc_roots : Array[Value]
} derive(Debug, Eq)

///|
pub fn TerminatorMetadata::empty() -> TerminatorMetadata {
  { source: None, live_gc_roots: [] }
}

///|
pub fn TerminatorMetadata::new(
  source : SourceLocation?,
  live_gc_roots : Array[Value],
) -> TerminatorMetadata {
  { source, live_gc_roots: live_gc_roots.copy() }
}

///|
pub struct TerminatorRecord {
  kind : Terminator
  metadata : TerminatorMetadata
} derive(Debug, Eq)

///|
fn TerminatorRecord::new(
  kind : Terminator,
  metadata : TerminatorMetadata,
) -> TerminatorRecord {
  {
    kind: kind.copy(),
    metadata: {
      source: metadata.source,
      live_gc_roots: metadata.live_gc_roots.copy(),
    },
  }
}

///|
fn TerminatorRecord::copy(self : TerminatorRecord) -> TerminatorRecord {
  TerminatorRecord::new(self.kind, self.metadata)
}

///|
pub struct InstructionMetadata {
  source : SourceLocation?
  live_gc_roots : Array[Value]
} derive(Debug, Eq)

///|
pub fn InstructionMetadata::empty() -> InstructionMetadata {
  { source: None, live_gc_roots: [] }
}

///|
pub fn InstructionMetadata::new(
  source : SourceLocation?,
  live_gc_roots : Array[Value],
) -> InstructionMetadata {
  { source, live_gc_roots: live_gc_roots.copy() }
}

///|
priv enum ValueDefinition {
  FunctionParameter(Int)
  BlockParameter(Block, Int)
  InstructionResult(Instruction, Int)
  RemovedInstructionResult(Instruction, Int)
}

///|
priv struct ValueData {
  ty : ValueType
  mut definition : ValueDefinition
}

///|
priv struct BlockData {
  parameters : Array[Value]
  instructions : Array[Instruction]
  mut terminator : TerminatorRecord?
}

///|
priv struct InstructionData {
  operation : Operation
  operands : Array[Value]
  results : Array[Value]
  metadata : InstructionMetadata
  mut alive : Bool
  mut parent : Block?
}

///|
/// A target-neutral semantic machine function.
///
/// Storage is private and canonical. Public queries return handles or
/// snapshots; construction and transformation go through owner-aware seams.
pub struct Function {
  priv owner : Ref[Unit]
  priv name : String
  priv protocol : CallProtocol
  priv signature : Signature
  priv parameters : Array[Value]
  priv values : Array[ValueData]
  priv blocks : Array[BlockData]
  priv instructions : Array[InstructionData]
}

///|
fn Function::new(
  name : String,
  protocol : CallProtocol,
  signature : Signature,
) -> Function {
  let function = {
    owner: Ref(()),
    name,
    protocol,
    signature: Signature::new(signature.params, signature.results),
    parameters: [],
    values: [],
    blocks: [],
    instructions: [],
  }
  for index, ty in signature.params {
    let value = function.allocate_value(ty, FunctionParameter(index))
    function.parameters.push(value)
  }
  function.allocate_block([]) |> ignore
  function
}

///|
fn Function::owns_value(self : Function, value : Value) -> Bool {
  physical_equal(self.owner, value.owner) &&
  value.id >= 0 &&
  value.id < self.values.length()
}

///|
fn Function::owns_block(self : Function, block : Block) -> Bool {
  physical_equal(self.owner, block.owner) &&
  block.id >= 0 &&
  block.id < self.blocks.length()
}

///|
fn Function::owns_instruction(
  self : Function,
  instruction : Instruction,
) -> Bool {
  physical_equal(self.owner, instruction.owner) &&
  instruction.id >= 0 &&
  instruction.id < self.instructions.length()
}

///|
fn Function::allocate_value(
  self : Function,
  ty : ValueType,
  definition : ValueDefinition,
) -> Value {
  let value = Value::new(self.owner, self.values.length())
  self.values.push({ ty, definition })
  value
}

///|
fn Function::allocate_block(
  self : Function,
  parameter_types : Array[ValueType],
) -> Block {
  let block = Block::new(self.owner, self.blocks.length())
  let parameters : Array[Value] = []
  for index, ty in parameter_types {
    parameters.push(self.allocate_value(ty, BlockParameter(block, index)))
  }
  self.blocks.push({ parameters, instructions: [], terminator: None })
  block
}

///|
fn Function::append_instruction(
  self : Function,
  block : Block,
  operation : Operation,
  operands : Array[Value],
  result_types : Array[ValueType],
  metadata : InstructionMetadata,
) -> Array[Value] {
  let instruction = Instruction::new(self.owner, self.instructions.length())
  let results : Array[Value] = []
  for index, ty in result_types {
    results.push(self.allocate_value(ty, InstructionResult(instruction, index)))
  }
  self.instructions.push({
    operation: operation.copy(),
    operands: operands.copy(),
    results,
    metadata: {
      source: metadata.source,
      live_gc_roots: metadata.live_gc_roots.copy(),
    },
    alive: true,
    parent: Some(block),
  })
  self.blocks[block.id].instructions.push(instruction)
  results
}

///|
pub fn Function::name(self : Function) -> String {
  self.name
}

///|
pub fn Function::protocol(self : Function) -> CallProtocol {
  self.protocol
}

///|
pub fn Function::signature(self : Function) -> Signature {
  Signature::new(self.signature.params, self.signature.results)
}

///|
pub fn Function::parameters(self : Function) -> Array[Value] {
  self.parameters.copy()
}

///|
pub fn Function::blocks(self : Function) -> Array[Block] {
  Array::makei(self.blocks.length(), index => Block::new(self.owner, index))
}

///|
pub fn Function::value_count(self : Function) -> Int {
  self.values.length()
}

///|
pub fn Function::value_index(self : Function, value : Value) -> Int? {
  if self.owns_value(value) {
    Some(value.id)
  } else {
    None
  }
}

///|
pub fn Function::block_count(self : Function) -> Int {
  self.blocks.length()
}

///|
pub fn Function::block_index(self : Function, block : Block) -> Int? {
  if self.owns_block(block) {
    Some(block.id)
  } else {
    None
  }
}

///|
pub fn Function::instruction_count(self : Function) -> Int {
  let mut count = 0
  for data in self.instructions {
    if data.alive {
      count += 1
    }
  }
  count
}

///|
pub fn Function::instruction_index(
  self : Function,
  instruction : Instruction,
) -> Int? {
  if self.owns_instruction(instruction) &&
    self.instructions[instruction.id].alive {
    Some(instruction.id)
  } else {
    None
  }
}

///|
pub fn Function::value_type(self : Function, value : Value) -> ValueType? {
  if self.owns_value(value) {
    Some(self.values[value.id].ty)
  } else {
    None
  }
}

///|
pub fn Function::block_parameters(
  self : Function,
  block : Block,
) -> Array[Value] {
  if self.owns_block(block) {
    self.blocks[block.id].parameters.copy()
  } else {
    []
  }
}

///|
pub fn Function::block_instructions(
  self : Function,
  block : Block,
) -> Array[Instruction] {
  if self.owns_block(block) {
    self.blocks[block.id].instructions.copy()
  } else {
    []
  }
}

///|
pub fn Function::block_terminator(
  self : Function,
  block : Block,
) -> TerminatorRecord? {
  if self.owns_block(block) {
    match self.blocks[block.id].terminator {
      Some(record) => Some(record.copy())
      None => None
    }
  } else {
    None
  }
}

///|
pub fn Function::instruction_operation(
  self : Function,
  instruction : Instruction,
) -> Operation? {
  if self.owns_instruction(instruction) &&
    self.instructions[instruction.id].alive {
    Some(self.instructions[instruction.id].operation.copy())
  } else {
    None
  }
}

///|
pub fn Function::instruction_operands(
  self : Function,
  instruction : Instruction,
) -> Array[Value] {
  if self.owns_instruction(instruction) &&
    self.instructions[instruction.id].alive {
    self.instructions[instruction.id].operands.copy()
  } else {
    []
  }
}

///|
pub fn Function::instruction_results(
  self : Function,
  instruction : Instruction,
) -> Array[Value] {
  if self.owns_instruction(instruction) &&
    self.instructions[instruction.id].alive {
    self.instructions[instruction.id].results.copy()
  } else {
    []
  }
}

///|
pub fn Function::instruction_metadata(
  self : Function,
  instruction : Instruction,
) -> InstructionMetadata? {
  if self.owns_instruction(instruction) &&
    self.instructions[instruction.id].alive {
    let metadata = self.instructions[instruction.id].metadata
    Some({
      source: metadata.source,
      live_gc_roots: metadata.live_gc_roots.copy(),
    })
  } else {
    None
  }
}
