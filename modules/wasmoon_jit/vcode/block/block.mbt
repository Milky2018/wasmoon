///|
/// VCode block - a basic block in VCode
pub struct VCodeBlock {
  id : Int
  insts : Array[@instr.VCodeInst] // Instructions in this block
  params : Array[@abi.VReg] // Block parameters
  mut terminator : @instr.VCodeTerminator? // How the block ends
}

///|
pub fn VCodeBlock::new(id : Int) -> VCodeBlock {
  { id, insts: [], params: [], terminator: None }
}

///|
pub fn VCodeBlock::add_inst(self : VCodeBlock, inst : @instr.VCodeInst) -> Unit {
  self.insts.push(inst)
}

///|
pub fn VCodeBlock::set_terminator(
  self : VCodeBlock,
  term : @instr.VCodeTerminator,
) -> Unit {
  self.terminator = Some(term)
}
