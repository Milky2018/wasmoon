///|
pub(all) struct Block {
  id : Int
  params : Array[Value]
  instructions : Array[Inst]
  mut terminator : Terminator?
} derive(Debug)

///|
pub fn Block::new(id : Int, params : Array[Value]) -> Block {
  { id, params, instructions: [], terminator: None }
}

///|
pub fn Block::append_inst(self : Block, inst : Inst) -> Unit {
  self.instructions.push(inst)
}

///|
pub fn Block::add_param(self : Block, value : Value) -> Unit {
  self.params.push(value)
}

///|
pub fn Block::set_terminator(self : Block, terminator : Terminator) -> Unit {
  self.terminator = Some(terminator)
}

///|
pub(all) struct Function {
  name : String
  signature : Signature
  blocks : Array[Block]
  stack_slots : Array[StackSlot]
  external_symbols : Array[ExternalSymbol]
  mut next_value_id : Int
  mut next_inst_id : Int
  mut next_block_id : Int
  mut next_stack_slot_id : Int
} derive(Debug)

///|
pub fn Function::new(name : String, signature : Signature) -> Function {
  {
    name,
    signature,
    blocks: [],
    stack_slots: [],
    external_symbols: [],
    next_value_id: 0,
    next_inst_id: 0,
    next_block_id: 0,
    next_stack_slot_id: 0,
  }
}

///|
pub fn Function::new_empty(name : String) -> Function {
  Function::new(name, Signature::new([], []))
}

///|
pub fn Function::new_value(self : Function, ty : Type) -> Value {
  let value = { id: self.next_value_id, ty }
  self.next_value_id = self.next_value_id + 1
  value
}

///|
pub fn Function::new_inst(
  self : Function,
  opcode : Opcode,
  args : Array[Value],
  results : Array[Value],
) -> Inst {
  let inst = Inst::new(self.next_inst_id, opcode, args, results)
  self.next_inst_id = self.next_inst_id + 1
  inst
}

///|
pub fn Function::new_block(self : Function, params : Array[Value]) -> Block {
  let block = Block::new(self.next_block_id, params)
  self.next_block_id = self.next_block_id + 1
  self.blocks.push(block)
  block
}

///|
pub fn Function::new_block0(self : Function) -> Block {
  self.new_block([])
}

///|
pub fn Function::add_param(self : Function, ty : Type) -> Value {
  let value = self.new_value(ty)
  self.signature.params.push(ty)
  value
}

///|
pub fn Function::add_result(self : Function, ty : Type) -> Unit {
  self.signature.results.push(ty)
}

///|
pub fn Function::new_stack_slot(
  self : Function,
  size : Int,
  align : Int,
) -> StackSlot {
  let slot = { id: self.next_stack_slot_id, size, align }
  self.next_stack_slot_id = self.next_stack_slot_id + 1
  self.stack_slots.push(slot)
  slot
}

///|
pub fn Function::declare_external_symbol(
  self : Function,
  name : String,
) -> ExternalSymbol {
  let symbol = ExternalSymbol::new(name)
  self.external_symbols.push(symbol)
  symbol
}
