///|
/// MachV block - a basic block in MachV
pub struct MachVBlock {
  id : Int
  insts : Array[@instr.MachVInst] // Instructions in this block
  params : Array[@abi.VReg] // Block parameters
  mut terminator : @instr.MachVTerminator? // How the block ends
}

///|
pub fn MachVBlock::new(id : Int) -> MachVBlock {
  { id, insts: [], params: [], terminator: None }
}

///|
pub fn MachVBlock::add_inst(self : MachVBlock, inst : @instr.MachVInst) -> Unit {
  self.insts.push(inst)
}

///|
pub fn MachVBlock::set_terminator(
  self : MachVBlock,
  term : @instr.MachVTerminator,
) -> Unit {
  self.terminator = Some(term)
}
