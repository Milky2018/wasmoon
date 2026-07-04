///|
/// Generic MachV instruction opcode.
///
/// TODO(machv): replace textual target opcodes with compact target-owned opcode
/// descriptors once x64_target and aarch64_target are extracted.
pub(all) enum Opcode {
  Target(String)
  Move
  Load(StackSlot)
  Store(StackSlot)
  Call(String)
  Jump(Int)
  Branch(Int, Int)
  Return
} derive(Eq, Debug)

///|
pub(all) struct Constraint {
  operand_index : Int
  allowed_regs : Array[PReg]
} derive(Eq, Debug)

///|
pub(all) struct Instruction {
  id : Int
  opcode : Opcode
  operands : Array[Operand]
  clobbers : Array[PReg]
  constraints : Array[Constraint]
  mut stack_effect : StackEffect
} derive(Eq, Debug)

///|
pub fn Instruction::new(id : Int, opcode : Opcode) -> Instruction {
  {
    id,
    opcode,
    operands: [],
    clobbers: [],
    constraints: [],
    stack_effect: None,
  }
}

///|
pub fn Instruction::add_operand(self : Instruction, operand : Operand) -> Unit {
  self.operands.push(operand)
}

///|
pub fn Instruction::add_clobber(self : Instruction, preg : PReg) -> Unit {
  self.clobbers.push(preg)
}

///|
pub fn Instruction::add_constraint(
  self : Instruction,
  constraint : Constraint,
) -> Unit {
  self.constraints.push(constraint)
}

///|
pub fn Instruction::set_stack_effect(
  self : Instruction,
  effect : StackEffect,
) -> Unit {
  self.stack_effect = effect
}
