///|
pub type VCodeLoop = @machv.Loop

///|
pub struct VCodeCFG {
  core : @machv.CFG
  size : Int
  preds : Array[Array[Int]]
  succs : Array[Array[Int]]
}

///|
pub fn VCodeCFG::build(func : @regalloc.VCodeFunction) -> VCodeCFG {
  let core = @machv.CFG::build(func.to_machv())
  { core, size: core.size, preds: core.preds, succs: core.succs }
}

///|
fn VCodeCFG::reverse_postorder(self : VCodeCFG) -> Array[Int] {
  self.core.reverse_postorder()
}

///|
pub fn VCodeCFG::compute_dominators(self : VCodeCFG) -> Array[Int] {
  self.core.compute_dominators()
}

///|
pub fn VCodeCFG::find_back_edges(self : VCodeCFG) -> Array[(Int, Int)] {
  self.core.find_back_edges()
}

///|
pub fn VCodeCFG::find_loops(self : VCodeCFG) -> Array[VCodeLoop] {
  self.core.find_loops()
}
