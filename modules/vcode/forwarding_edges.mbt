///|
/// Resolve the parallel moves attached to one allocated successor edge.
pub fn[Inst] resolve_edge_moves(
  function : Function[Inst],
  allocation : Allocation,
  block : Block,
  successor_index : Int32,
  integer_scratch : PhysicalReg,
  fp_scratch : PhysicalReg,
) -> ResolvedMovePlan raise MoveResolveError {
  if allocation.edge_edits_at(block, successor_index).is_empty() {
    return ResolvedMovePlan::empty()
  }
  plan_parallel_moves(
    allocation_edge_moves(function, allocation, block, successor_index),
    integer_scratch,
    fp_scratch,
  )
}

///|
/// Chase short chains of unconditional forwarding edges. A block can only be
/// bypassed if it has no body, no terminator edits, and no resolved edge moves.
/// Each target still checks the displacement of its final branch encoding.
pub fn[Inst : Eq] threaded_branch_target(
  function : Function[Inst],
  allocation : Allocation,
  target : Block,
  jump : Inst,
  integer_scratch : PhysicalReg,
  fp_scratch : PhysicalReg,
) -> Block raise MoveResolveError {
  let mut current = target
  // Forwarding chains longer than a few hops do not occur in practice; the
  // bound also terminates on a cycle of empty blocks.
  for _hop in 0..<4 {
    if !function.block_body(current).is_empty() {
      break
    }
    guard function.block_terminator(current) is Some(terminator) else { break }
    if function.instruction(terminator) != Some(jump) {
      break
    }
    if !allocation.edits_at(terminator, Before).is_empty() ||
      !allocation.edits_at(terminator, After).is_empty() {
      break
    }
    if !resolve_edge_moves(
        function, allocation, current, 0, integer_scratch, fp_scratch,
      ).steps.is_empty() {
      break
    }
    guard function.instruction_successor_at(terminator, 0) is Some(edge) else {
      break
    }
    if edge.target == current {
      break
    }
    current = edge.target
  }
  current
}

///|
#valtype
pub struct ConditionalEdgeLayout {
  first_target : Block
  first_moves : ResolvedMovePlan
  second_target : Block
  second_moves : ResolvedMovePlan
  first_when_true : Bool
  direct_branch : Bool
  second_falls_through : Bool
}

///|
/// Resolve moves and choose an emission order. Compare the original blocks
/// for fallthrough, and use the threaded destinations for explicit branches.
pub fn[Inst : Eq] plan_conditional_edges(
  function : Function[Inst],
  allocation : Allocation,
  block : Block,
  instruction : Instruction,
  next_block : Block?,
  jump : Inst,
  integer_scratch : PhysicalReg,
  fp_scratch : PhysicalReg,
  split_false_first~ : Bool,
) -> ConditionalEdgeLayout raise MoveResolveError {
  let when_true = function.instruction_successor_at(instruction, 0).unwrap().target
  let when_false = function.instruction_successor_at(instruction, 1).unwrap().target
  let true_moves = resolve_edge_moves(
    function, allocation, block, 0, integer_scratch, fp_scratch,
  )
  let false_moves = resolve_edge_moves(
    function, allocation, block, 1, integer_scratch, fp_scratch,
  )
  let true_target = threaded_branch_target(
    function, allocation, when_true, jump, integer_scratch, fp_scratch,
  )
  let false_target = threaded_branch_target(
    function, allocation, when_false, jump, integer_scratch, fp_scratch,
  )
  let true_empty = true_moves.steps.is_empty()
  let false_empty = false_moves.steps.is_empty()
  let (first_when_true, direct_branch, second_falls_through) = if next_block ==
    Some(when_false) {
    (true, true_empty, true)
  } else if next_block == Some(when_true) {
    (false, false_empty, true)
  } else if true_empty {
    (true, true, false)
  } else if split_false_first {
    (false, false, false)
  } else if false_empty {
    (false, true, false)
  } else {
    (true, false, false)
  }
  let (first_target, first_moves, second_target, second_moves) = if first_when_true {
    (true_target, true_moves, false_target, false_moves)
  } else {
    (false_target, false_moves, true_target, true_moves)
  }
  {
    first_target,
    first_moves,
    second_target,
    second_moves,
    first_when_true,
    direct_branch,
    second_falls_through,
  }
}
