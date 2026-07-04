///|
/// VCode block - a basic block in VCode
/// TODO(wasmoon_vcode): replace this legacy block container with `@machv.Block`
/// once `VCodeInst` is reduced to a Wasmoon adapter opcode layer.
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
