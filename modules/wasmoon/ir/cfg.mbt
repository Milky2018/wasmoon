///|
pub type Loop = @milkir.Loop

///|
pub struct CFG {
  core : @milkir.CFG
}

///|
fn Type::to_milkir(self : Type) -> @milkir.Type {
  match self {
    I32 => I32
    I64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
    FuncRef | ExternRef => Ref
  }
}

///|
fn Value::to_milkir(self : Value) -> @milkir.Value {
  { id: self.id, ty: self.ty.to_milkir() }
}

///|
fn Terminator::to_milkir(self : Terminator) -> @milkir.Terminator {
  match self {
    Jump(target, args) =>
      Jump(target, args.map(fn(value) { value.to_milkir() }))
    Brz(cond, true_target, false_target) =>
      Brz(cond.to_milkir(), true_target, false_target)
    Brnz(cond, true_target, false_target) =>
      Brnz(cond.to_milkir(), true_target, false_target)
    BrTable(index, targets, default_target) =>
      BrTable(index.to_milkir(), targets, default_target)
    Return(values) => Return(values.map(fn(value) { value.to_milkir() }))
    Trap(reason) => TrapExit(reason)
  }
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
fn Function::to_milkir_cfg_function(self : Function) -> @milkir.Function {
  let signature = @milkir.Signature::new(
    self.params.map(fn(param) {
      let (_, ty) = param
      ty.to_milkir()
    }),
    self.results.map(fn(ty) { ty.to_milkir() }),
  )
  let out = @milkir.Function::new(self.name, signature)
  for block in self.blocks {
    let out_block = @milkir.Block::new(
      block.id,
      block.params.map(fn(param) {
        let (value, _) = param
        value.to_milkir()
      }),
    )
    if block.terminator is Some(term) {
      out_block.set_terminator(term.to_milkir())
    }
    out.blocks.push(out_block)
  }
  out
}

///|
pub fn CFG::build(func : Function) -> CFG {
  { core: @milkir.CFG::build(func.to_milkir_cfg_function()) }
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
