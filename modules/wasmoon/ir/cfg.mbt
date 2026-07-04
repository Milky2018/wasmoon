///|
pub type Loop = @milkir.Loop

///|
pub struct CFG {
  core : @milkir.CFG
}

///|
fn get_terminator_targets(term : Terminator) -> Array[Int] {
  match term {
    Jump(target, _) => [target]
    Brz(_, true_target, false_target) | Brnz(_, true_target, false_target) =>
      [true_target, false_target]
    BrTable(_, targets, default_target) => {
      let out : Array[Int] = []
      for target in targets {
        out.push(target)
      }
      out.push(default_target)
      out
    }
    Return(_) | Trap(_) => []
  }
}

///|
pub fn CFG::build(func : Function) -> CFG {
  { core: @milkir.CFG::build(func.to_milkir()) }
}

///|
pub fn CFG::is_valid(self : CFG, block_id : Int) -> Bool {
  self.core.is_valid(block_id)
}

///|
pub fn CFG::get_successors(self : CFG, block_id : Int) -> Array[Int] {
  self.core.get_successors(block_id)
}

///|
pub fn CFG::get_predecessors(self : CFG, block_id : Int) -> Array[Int] {
  self.core.get_predecessors(block_id)
}

///|
pub fn CFG::is_entry_or_unreachable(self : CFG, block_id : Int) -> Bool {
  self.core.is_entry_or_unreachable(block_id)
}

///|
pub fn CFG::is_exit_block(self : CFG, block_id : Int) -> Bool {
  self.core.is_exit_block(block_id)
}

///|
pub fn CFG::postorder(self : CFG) -> Array[Int] {
  self.core.postorder()
}

///|
pub fn CFG::reverse_postorder(self : CFG) -> Array[Int] {
  self.core.reverse_postorder()
}

///|
pub fn CFG::compute_dominators(self : CFG) -> Array[Int] {
  self.core.compute_dominators()
}

///|
pub fn build_dominator_tree(idom : Array[Int]) -> Array[Array[Int]] {
  @milkir.build_dominator_tree(idom)
}

///|
pub fn CFG::dominates(self : CFG, a : Int, b : Int) -> Bool {
  self.core.dominates(a, b)
}

///|
pub fn CFG::find_back_edges(self : CFG) -> Array[(Int, Int)] {
  self.core.find_back_edges()
}

///|
pub fn CFG::to_dot(self : CFG, func_name : String) -> String {
  self.core.to_dot(func_name)
}

///|
pub fn CFG::find_loops(self : CFG) -> Array[Loop] {
  self.core.find_loops()
}

///|
pub fn CFG::get_loop_preheader(self : CFG, loop_ : Loop) -> Int? {
  self.core.get_loop_preheader(loop_)
}
