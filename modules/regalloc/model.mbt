///|
pub(all) enum RegClass {
  Int
  Float
  Vector
} derive(Eq, Debug)

///|
pub(all) struct VirtualReg {
  id : Int
  class : RegClass
} derive(Eq, Debug)

///|
pub(all) struct PhysicalReg {
  id : Int
  class : RegClass
} derive(Eq, Debug)

///|
pub(all) enum OperandRole {
  Use
  Def
  UseDef
} derive(Eq, Debug)

///|
pub(all) struct Operand {
  vreg : VirtualReg
  role : OperandRole
  constraint : OperandConstraint
  tie_id : Int
} derive(Eq, Debug)

///|
pub fn Operand::use_reg(vreg : VirtualReg) -> Operand {
  { vreg, role: Use, constraint: AnyReg, tie_id: -1 }
}

///|
pub fn Operand::def(vreg : VirtualReg) -> Operand {
  { vreg, role: Def, constraint: AnyReg, tie_id: -1 }
}

///|
pub fn Operand::with_constraint(
  self : Operand,
  constraint : OperandConstraint,
) -> Operand {
  { vreg: self.vreg, role: self.role, constraint, tie_id: self.tie_id }
}

///|
pub fn Operand::with_tie(self : Operand, tie_id : Int) -> Operand {
  { vreg: self.vreg, role: self.role, constraint: self.constraint, tie_id }
}

///|
pub(all) struct Instruction {
  id : Int
  operands : Array[Operand]
  clobbers : Array[PhysicalReg]
} derive(Debug)

///|
pub fn Instruction::new(id : Int) -> Instruction {
  { id, operands: [], clobbers: [] }
}

///|
pub fn Instruction::add_operand(self : Instruction, operand : Operand) -> Unit {
  self.operands.push(operand)
}

///|
pub fn Instruction::add_clobber(self : Instruction, preg : PhysicalReg) -> Unit {
  self.clobbers.push(preg)
}

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
pub(all) struct Program {
  blocks : Array[Block]
  physical_regs : Array[PhysicalReg]
} derive(Debug)

///|
pub fn Program::new(physical_regs : Array[PhysicalReg]) -> Program {
  { blocks: [], physical_regs }
}

///|
pub fn Program::add_block(self : Program, block : Block) -> Unit {
  self.blocks.push(block)
}
