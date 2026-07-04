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

///|
pub(all) struct DenseCfgEdges {
  preds : Array[Array[Int]]
  succs : Array[Array[Int]]
} derive(Debug)

///|
pub fn build_dense_successor_edges(
  block_ids : Array[Int],
  block_successor_ids : Array[Array[Int]],
) -> DenseCfgEdges {
  let n = block_ids.length()
  let mut max_block_id = -1
  for block_id in block_ids {
    if block_id > max_block_id {
      max_block_id = block_id
    }
  }
  let block_id_to_index = if max_block_id < 0 {
    []
  } else {
    Array::make(max_block_id + 1, -1)
  }
  for i, block_id in block_ids {
    if block_id >= 0 && block_id < block_id_to_index.length() {
      block_id_to_index[block_id] = i
    }
  }

  let preds : Array[Array[Int]] = []
  let succs : Array[Array[Int]] = []
  for _ in 0..<n {
    preds.push([])
    succs.push([])
  }

  for block_idx, successor_ids in block_successor_ids {
    if block_idx >= n {
      break
    }
    let block_succs : Array[Int] = []
    for succ_id in successor_ids {
      if succ_id >= 0 && succ_id < block_id_to_index.length() {
        let succ_idx = block_id_to_index[succ_id]
        if succ_idx >= 0 {
          block_succs.push(succ_idx)
          preds[succ_idx].push(block_idx)
        }
      }
    }
    succs[block_idx] = block_succs
  }

  { preds, succs }
}

///|
/// Compute reverse-postorder block ranks from dense successor lists.
///
/// The returned array maps `block_index -> reverse_postorder_rank`.
pub fn compute_reverse_postorder_from_successors(
  block_successors : Array[Array[Int]],
) -> Array[Int] {
  let n = block_successors.length()
  let visited = Array::make(n, false)
  let postorder : Array[Int] = []

  fn dfs(
    block_successors : Array[Array[Int]],
    block_idx : Int,
    visited : Array[Bool],
    postorder : Array[Int],
  ) -> Unit {
    if block_idx < 0 ||
      block_idx >= block_successors.length() ||
      visited[block_idx] {
      return
    }
    visited[block_idx] = true

    for succ_idx in block_successors[block_idx] {
      dfs(block_successors, succ_idx, visited, postorder)
    }

    postorder.push(block_idx)
  }

  if n > 0 {
    dfs(block_successors, 0, visited, postorder)
  }

  for block_idx in 0..<n {
    if !visited[block_idx] {
      dfs(block_successors, block_idx, visited, postorder)
    }
  }

  let order = Array::make(n, 0)
  let len = postorder.length()
  for i, block_idx in postorder {
    order[block_idx] = len - 1 - i
  }
  order
}

///|
pub fn compute_reachable_reverse_postorder_from_successors(
  block_successors : Array[Array[Int]],
) -> Array[Int] {
  let n = block_successors.length()
  let visited = Array::make(n, false)
  let postorder : Array[Int] = []

  fn dfs(
    block_successors : Array[Array[Int]],
    block_idx : Int,
    visited : Array[Bool],
    postorder : Array[Int],
  ) -> Unit {
    if block_idx < 0 ||
      block_idx >= block_successors.length() ||
      visited[block_idx] {
      return
    }
    visited[block_idx] = true

    for succ_idx in block_successors[block_idx] {
      dfs(block_successors, succ_idx, visited, postorder)
    }

    postorder.push(block_idx)
  }

  if n > 0 {
    dfs(block_successors, 0, visited, postorder)
  }
  postorder.rev_in_place()
  postorder
}
