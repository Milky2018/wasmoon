///|
pub(all) struct Block {
  id : Int
  instructions : Array[Instruction]
  successors : Array[Int]
} derive(Debug)

///|
pub fn Block::new(id : Int) -> Block {
  { id, instructions: [], successors: [] }
}

///|
pub fn Block::append(self : Block, inst : Instruction) -> Unit {
  self.instructions.push(inst)
}

///|
pub fn Block::add_successor(self : Block, block_id : Int) -> Unit {
  self.successors.push(block_id)
}

///|
pub(all) struct Function {
  name : String
  blocks : Array[Block]
  stack_slots : Array[StackSlot]
  mut next_block_id : Int
  mut next_inst_id : Int
  mut next_vreg_id : Int
  mut next_stack_slot_id : Int
} derive(Debug)

///|
pub fn Function::new(name : String) -> Function {
  {
    name,
    blocks: [],
    stack_slots: [],
    next_block_id: 0,
    next_inst_id: 0,
    next_vreg_id: 0,
    next_stack_slot_id: 0,
  }
}

///|
pub fn Function::new_block(self : Function) -> Block {
  let block = Block::new(self.next_block_id)
  self.next_block_id = self.next_block_id + 1
  self.blocks.push(block)
  block
}

///|
pub fn Function::new_vreg(self : Function, class : RegClass) -> VReg {
  let reg = { id: self.next_vreg_id, class }
  self.next_vreg_id = self.next_vreg_id + 1
  reg
}

///|
pub fn Function::new_inst(self : Function, opcode : Opcode) -> Instruction {
  let inst = Instruction::new(self.next_inst_id, opcode)
  self.next_inst_id = self.next_inst_id + 1
  inst
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
