///|
pub(all) struct Block {
  id : Int
  params : Array[VReg]
  instructions : Array[Instruction]
  successors : Array[Int]
  mut terminator : Terminator?
} derive(Debug)

///|
pub fn Block::new(id : Int) -> Block {
  { id, params: [], instructions: [], successors: [], terminator: None }
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
pub fn Block::add_param(self : Block, param : VReg) -> Unit {
  self.params.push(param)
}

///|
fn terminator_successors(term : Terminator) -> Array[Int] {
  match term {
    TermJump(target, _) => [target]
    TermBranch(_, true_target, _, false_target, _)
    | TermBranchCmp(_, _, _, _, true_target, _, false_target, _)
    | TermBranchZero(_, _, _, true_target, _, false_target, _)
    | TermBranchCmpImm(_, _, _, _, true_target, _, false_target, _) =>
      [true_target, false_target]
    TermBrTable(_, targets, default_target) => {
      let out : Array[Int] = []
      for target in targets {
        out.push(target)
      }
      out.push(default_target)
      out
    }
    TermReturn(_) | TermTrap(_) => []
  }
}

///|
pub fn Block::set_terminator(self : Block, term : Terminator) -> Unit {
  self.terminator = Some(term)
  self.successors.clear()
  for target in terminator_successors(term) {
    self.successors.push(target)
  }
}

///|
pub(all) struct Function {
  name : String
  params : Array[VReg]
  results : Array[RegClass]
  blocks : Array[Block]
  stack_slots : Array[StackSlot]
  mut num_spill_slots : Int
  param_pregs : Array[PReg?]
  mut int_stack_params : Int
  mut max_outgoing_args_size : Int
  mut next_block_id : Int
  mut next_inst_id : Int
  mut next_vreg_id : Int
  mut next_stack_slot_id : Int
} derive(Debug)

///|
pub fn Function::new(name : String) -> Function {
  {
    name,
    params: [],
    results: [],
    blocks: [],
    stack_slots: [],
    num_spill_slots: 0,
    param_pregs: [],
    int_stack_params: 0,
    max_outgoing_args_size: 0,
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
pub fn Function::add_param(self : Function, class : RegClass) -> VReg {
  let vreg = self.new_vreg(class)
  self.params.push(vreg)
  vreg
}

///|
pub fn Function::push_param(self : Function, vreg : VReg) -> Unit {
  self.params.push(vreg)
}

///|
pub fn Function::add_result(self : Function, class : RegClass) -> Unit {
  self.results.push(class)
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

///|
pub fn Function::set_num_spill_slots(self : Function, n : Int) -> Unit {
  self.num_spill_slots = n
}

///|
pub fn Function::add_param_preg(self : Function, preg : PReg?) -> Unit {
  self.param_pregs.push(preg)
}

///|
pub fn Function::set_int_stack_params(self : Function, n : Int) -> Unit {
  self.int_stack_params = n
}

///|
pub fn Function::update_max_outgoing_args_size(
  self : Function,
  size : Int,
) -> Unit {
  if size > self.max_outgoing_args_size {
    self.max_outgoing_args_size = size
  }
}

///|
pub fn Function::get_max_outgoing_args_size(self : Function) -> Int {
  self.max_outgoing_args_size
}

///|
pub fn Function::get_num_spill_slots(self : Function) -> Int {
  self.num_spill_slots
}
