///|
/// MachV block - a basic block in MachV
pub struct Block {
  id : Int
  insts : Array[@instr.Inst] // Instructions in this block
  params : Array[@abi.VReg] // Block parameters
  mut terminator : @instr.Terminator? // How the block ends
}

///|
pub fn Block::Block(id : Int) -> Block {
  { id, insts: [], params: [], terminator: None }
}

///|
pub fn Block::add_inst(self : Block, inst : @instr.Inst) -> Unit {
  self.insts.push(inst)
}

///|
pub fn Block::set_terminator(self : Block, term : @instr.Terminator) -> Unit {
  self.terminator = Some(term)
}

///|
pub fn Block::insts(self : Block) -> Array[@instr.Inst] {
  self.insts
}

///|
pub fn Block::terminator(self : Block) -> @instr.Terminator? {
  self.terminator
}
