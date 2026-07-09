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
struct Instruction {
  id : Int
  operands : Array[Operand]
  clobbers : Array[PhysicalReg]
} derive(Debug)

///|
pub fn Instruction::Instruction(id : Int) -> Instruction {
  { id, operands: [], clobbers: [] }
}

///|
pub fn Instruction::id(self : Instruction) -> Int {
  self.id
}

///|
pub fn Instruction::operand_count(self : Instruction) -> Int {
  self.operands.length()
}

///|
pub fn Instruction::operand_at(self : Instruction, index : Int) -> Operand? {
  self.operands.get(index)
}

///|
pub fn Instruction::add_operand(self : Instruction, operand : Operand) -> Unit {
  self.operands.push(operand)
}

///|
pub fn Instruction::clobber_count(self : Instruction) -> Int {
  self.clobbers.length()
}

///|
pub fn Instruction::clobber_at(self : Instruction, index : Int) -> PhysicalReg? {
  self.clobbers.get(index)
}

///|
pub fn Instruction::add_clobber(self : Instruction, preg : PhysicalReg) -> Unit {
  self.clobbers.push(preg)
}

///|
struct Block {
  id : Int
  instructions : Array[Instruction]
  successors : Array[Int]
} derive(Debug)

///|
pub fn Block::Block(id : Int) -> Block {
  { id, instructions: [], successors: [] }
}

///|
pub fn Block::id(self : Block) -> Int {
  self.id
}

///|
pub fn Block::instruction_count(self : Block) -> Int {
  self.instructions.length()
}

///|
pub fn Block::instruction_at(self : Block, index : Int) -> Instruction? {
  self.instructions.get(index)
}

///|
pub fn Block::append(self : Block, inst : Instruction) -> Unit {
  self.instructions.push(inst)
}

///|
pub fn Block::successor_count(self : Block) -> Int {
  self.successors.length()
}

///|
pub fn Block::successor_at(self : Block, index : Int) -> Int? {
  self.successors.get(index)
}

///|
pub fn Block::add_successor(self : Block, block_id : Int) -> Unit {
  self.successors.push(block_id)
}

///|
struct Program {
  blocks : Array[Block]
  physical_regs : Array[PhysicalReg]
} derive(Debug)

///|
pub fn Program::Program(physical_regs : Array[PhysicalReg]) -> Program {
  { blocks: [], physical_regs }
}

///|
pub fn Program::block_count(self : Program) -> Int {
  self.blocks.length()
}

///|
pub fn Program::block_at(self : Program, index : Int) -> Block? {
  self.blocks.get(index)
}

///|
pub fn Program::physical_reg_count(self : Program) -> Int {
  self.physical_regs.length()
}

///|
pub fn Program::physical_reg_at(self : Program, index : Int) -> PhysicalReg? {
  self.physical_regs.get(index)
}

///|
pub fn Program::add_block(self : Program, block : Block) -> Unit {
  self.blocks.push(block)
}
