///|
priv struct VCodeCFG {
  preds : Array[Array[Int]]
  succs : Array[Array[Int]]
}

///|
fn terminator_successor_ids(term : @instr.VCodeTerminator) -> Array[Int] {
  match term {
    Jump(target, _) => [target]
    Branch(_, then_b, else_b)
    | BranchCmp(_, _, _, _, then_b, else_b)
    | BranchZero(_, _, _, then_b, else_b)
    | BranchCmpImm(_, _, _, _, then_b, else_b) => [then_b, else_b]
    BrTable(_, targets, default) => {
      let result : Array[Int] = []
      for target in targets {
        result.push(target)
      }
      result.push(default)
      result
    }
    Return(_) | Trap(_) => []
  }
}

///|
fn VCodeCFG::build(func : @regalloc.VCodeFunction) -> VCodeCFG {
  let block_ids : Array[Int] = []
  let block_successor_ids : Array[Array[Int]] = []
  for block in func.get_blocks() {
    block_ids.push(block.id)
    match block.terminator {
      Some(term) => block_successor_ids.push(terminator_successor_ids(term))
      None => block_successor_ids.push([])
    }
  }
  let edges = @core_regalloc.build_dense_successor_edges(
    block_ids, block_successor_ids,
  )
  { preds: edges.preds, succs: edges.succs }
}

///|
fn VCodeCFG::reverse_postorder(self : VCodeCFG) -> Array[Int] {
  @core_regalloc.compute_reachable_reverse_postorder_from_successors(self.succs)
}

///|
