///|
/// CFG facts shared by instruction-only optimization passes. The analysis is
/// valid until a pass changes block successors or block identity.
priv struct FunctionAnalysis {
  cfg : @milkir.CFG
  dominance : @milkir.Dominance
  domtree : Array[Array[Int]]
  block_idx : Array[Int]
}

///|
fn FunctionAnalysis::build(func : @milkir.Function) -> FunctionAnalysis {
  let cfg = @milkir.CFG::build(func)
  let dominance = cfg.compute_dominance()
  let block_idx = Array::make(func.next_block_id, -1)
  for index, block in func.blocks {
    block_idx[block.id] = index
  }
  {
    cfg,
    dominance,
    domtree: @milkir.build_dominator_tree(dominance.idom),
    block_idx,
  }
}
