///|
/// Compute an approximate loop depth for each block from a linear block order
/// and per-block successor lists.
///
/// This mirrors the regalloc2-style CFG heuristic used for spill weighting:
/// a successor whose index is not greater than the current block is treated as
/// a backedge, and depths are approximated by scanning block order while
/// tracking entered/exited backedges.
pub fn compute_approx_loop_depths(
  block_successors : Array[Array[Int]],
) -> Array[Int] {
  let n = block_successors.length()
  if n == 0 {
    return []
  }

  let backedge_in = Array::make(n, 0)
  let backedge_out = Array::make(n, 0)

  for block_idx, successors in block_successors {
    for succ in successors {
      if succ < 0 || succ >= n {
        continue
      }
      if succ <= block_idx {
        backedge_in[succ] = backedge_in[succ] + 1
        backedge_out[block_idx] = backedge_out[block_idx] + 1
      }
    }
  }

  let depths : Array[Int] = []
  let backedge_stack : Array[Int] = []
  let mut cur_depth = 0

  for block_idx in 0..<n {
    if backedge_in[block_idx] > 0 {
      cur_depth = cur_depth + 1
      backedge_stack.push(backedge_in[block_idx])
    }

    depths.push(cur_depth)

    let mut out_count = backedge_out[block_idx]
    while backedge_stack.length() > 0 && out_count > 0 {
      out_count = out_count - 1
      let last = backedge_stack.length() - 1
      backedge_stack[last] = backedge_stack[last] - 1
      if backedge_stack[last] == 0 {
        cur_depth = cur_depth - 1
        backedge_stack.pop() |> ignore
      }
    }
  }

  depths
}
