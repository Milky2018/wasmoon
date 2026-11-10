///|
/// CFG facts shared by instruction-only optimization passes. The analysis is
/// valid until a pass changes block successors or block identity.
pub struct FunctionAnalysis {
  cfg : @milkir.CFG
  dominance : @milkir.Dominance
  domtree : Array[Array[Int32]]
  block_idx : Array[Int32]
}

///|
pub fn FunctionAnalysis::build(func : @milkir.Function) -> FunctionAnalysis {
  let cfg = @milkir.CFG::build(func)
  let (dominance, domtree) = cfg.compute_dominance_and_tree()
  function_analysis_from_tree(func, cfg, dominance, domtree)
}

///|
/// Complete the optimizer analysis from control flow known to still describe
/// this function. Instruction-only transforms preserve these facts.
pub fn FunctionAnalysis::from_control_flow(
  func : @milkir.Function,
  cfg : @milkir.CFG,
  dominance : @milkir.Dominance,
) -> FunctionAnalysis {
  function_analysis_from_tree(
    func,
    cfg,
    dominance,
    @milkir.build_dominator_tree(dominance.idom),
  )
}

///|
fn function_analysis_from_tree(
  func : @milkir.Function,
  cfg : @milkir.CFG,
  dominance : @milkir.Dominance,
  domtree : Array[Array[Int32]],
) -> FunctionAnalysis {
  let block_idx = Array::make(func.next_block_id, -1)
  for index, block in func.blocks {
    block_idx[block.id] = index
  }
  { cfg, dominance, domtree, block_idx, }
}
