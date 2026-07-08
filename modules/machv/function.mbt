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
pub(all) struct AbstractFunction {
  name : String
  params : Array[VReg]
  results : Array[RegClass]
  blocks : Array[Block]
  stack_slots : Array[StackSlot]
  mut num_spill_slots : Int
  param_pregs : Array[PReg?]
  param_locations : Array[AbiValueLocation]
  result_locations : Array[AbiValueLocation]
  mut return_area : AbiReturnArea?
  mut int_stack_params : Int
  mut max_outgoing_args_size : Int
  mut next_block_id : Int
  mut next_inst_id : Int
  mut next_vreg_id : Int
  mut next_stack_slot_id : Int
} derive(Debug)

///|
pub fn AbstractFunction::new(name : String) -> AbstractFunction {
  {
    name,
    params: [],
    results: [],
    blocks: [],
    stack_slots: [],
    num_spill_slots: 0,
    param_pregs: [],
    param_locations: [],
    result_locations: [],
    return_area: None,
    int_stack_params: 0,
    max_outgoing_args_size: 0,
    next_block_id: 0,
    next_inst_id: 0,
    next_vreg_id: 0,
    next_stack_slot_id: 0,
  }
}

///|
pub fn AbstractFunction::new_block(self : AbstractFunction) -> Block {
  let block = Block::new(self.next_block_id)
  self.next_block_id = self.next_block_id + 1
  self.blocks.push(block)
  block
}

///|
pub fn AbstractFunction::new_vreg(
  self : AbstractFunction,
  class : RegClass,
) -> VReg {
  let reg = { id: self.next_vreg_id, class }
  self.next_vreg_id = self.next_vreg_id + 1
  reg
}

///|
pub fn AbstractFunction::add_param(
  self : AbstractFunction,
  class : RegClass,
) -> VReg {
  let vreg = self.new_vreg(class)
  self.params.push(vreg)
  vreg
}

///|
pub fn AbstractFunction::push_param(
  self : AbstractFunction,
  vreg : VReg,
) -> Unit {
  self.params.push(vreg)
}

///|
pub fn AbstractFunction::add_result(
  self : AbstractFunction,
  class : RegClass,
) -> Unit {
  self.results.push(class)
}

///|
pub fn AbstractFunction::new_inst(
  self : AbstractFunction,
  opcode : Opcode,
) -> Instruction {
  let inst = Instruction::new(self.next_inst_id, opcode)
  self.next_inst_id = self.next_inst_id + 1
  inst
}

///|
pub fn AbstractFunction::new_stack_slot(
  self : AbstractFunction,
  size : Int,
  align : Int,
) -> StackSlot {
  let slot = { id: self.next_stack_slot_id, size, align }
  self.next_stack_slot_id = self.next_stack_slot_id + 1
  self.stack_slots.push(slot)
  slot
}

///|
pub fn AbstractFunction::set_num_spill_slots(
  self : AbstractFunction,
  n : Int,
) -> Unit {
  self.num_spill_slots = n
}

///|
pub fn AbstractFunction::add_param_preg(
  self : AbstractFunction,
  preg : PReg?,
) -> Unit {
  self.param_pregs.push(preg)
}

///|
pub fn AbstractFunction::add_param_location(
  self : AbstractFunction,
  location : AbiValueLocation,
) -> Unit {
  self.param_locations.push(location)
}

///|
pub fn AbstractFunction::add_result_location(
  self : AbstractFunction,
  location : AbiValueLocation,
) -> Unit {
  self.result_locations.push(location)
}

///|
pub fn AbstractFunction::set_return_area(
  self : AbstractFunction,
  area : AbiReturnArea,
) -> Unit {
  self.return_area = Some(area)
}

///|
pub fn AbstractFunction::set_int_stack_params(
  self : AbstractFunction,
  n : Int,
) -> Unit {
  self.int_stack_params = n
}

///|
pub fn AbstractFunction::update_max_outgoing_args_size(
  self : AbstractFunction,
  size : Int,
) -> Unit {
  if size > self.max_outgoing_args_size {
    self.max_outgoing_args_size = size
  }
}

///|
pub fn AbstractFunction::get_max_outgoing_args_size(
  self : AbstractFunction,
) -> Int {
  self.max_outgoing_args_size
}

///|
pub fn AbstractFunction::get_num_spill_slots(self : AbstractFunction) -> Int {
  self.num_spill_slots
}
