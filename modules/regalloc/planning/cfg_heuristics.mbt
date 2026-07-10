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
pub(all) struct DenseCfgLoop {
  header : Int
  body : Array[Int]
  latch : Int
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

///|
fn intersect_dominators(
  idom : Array[Int],
  rpo_num : Array[Int],
  b1_init : Int,
  b2_init : Int,
) -> Int {
  let mut b1 = b1_init
  let mut b2 = b2_init
  while b1 != b2 {
    while rpo_num[b1] > rpo_num[b2] {
      b1 = idom[b1]
    }
    while rpo_num[b2] > rpo_num[b1] {
      b2 = idom[b2]
    }
  }
  b1
}

///|
pub fn compute_dominators_from_edges(edges : DenseCfgEdges) -> Array[Int] {
  let size = edges.succs.length()
  let idom : Array[Int] = Array::make(size, -1)
  if size == 0 {
    return idom
  }
  idom[0] = 0
  let rpo = compute_reachable_reverse_postorder_from_successors(edges.succs)
  let rpo_num : Array[Int] = Array::make(size, -1)
  for i, block_id in rpo {
    rpo_num[block_id] = i
  }
  let mut changed = true
  while changed {
    changed = false
    for block_id in rpo {
      if block_id == 0 {
        continue
      }
      let mut new_idom = -1
      if block_id < edges.preds.length() {
        for pred in edges.preds[block_id] {
          if pred >= 0 && pred < size && idom[pred] != -1 {
            if new_idom == -1 {
              new_idom = pred
            } else {
              new_idom = intersect_dominators(idom, rpo_num, new_idom, pred)
            }
          }
        }
      }
      if new_idom != -1 && idom[block_id] != new_idom {
        idom[block_id] = new_idom
        changed = true
      }
    }
  }
  idom
}

///|
fn dominates_with_idom(idom : Array[Int], a : Int, b : Int) -> Bool {
  if a == b {
    return true
  }
  let mut current = b
  while current != -1 && current != 0 {
    current = idom[current]
    if current == a {
      return true
    }
  }
  a == 0 && current == 0
}

///|
pub fn find_back_edges_from_edges(edges : DenseCfgEdges) -> Array[(Int, Int)] {
  let idom = compute_dominators_from_edges(edges)
  let back_edges : Array[(Int, Int)] = []
  for block_id in 0..<edges.succs.length() {
    for succ in edges.succs[block_id] {
      if succ >= 0 &&
        succ < idom.length() &&
        dominates_with_idom(idom, succ, block_id) {
        back_edges.push((block_id, succ))
      }
    }
  }
  back_edges
}

///|
fn find_loop_body(
  edges : DenseCfgEdges,
  header : Int,
  latches : Array[Int],
) -> Array[Int] {
  let body : Map[Int, Bool] = Map([])
  body.set(header, true)
  let worklist : Array[Int] = []
  for latch in latches {
    if latch != header {
      worklist.push(latch)
      body.set(latch, true)
    }
  }
  while worklist.length() > 0 {
    let block = worklist.pop().unwrap()
    if block < 0 || block >= edges.preds.length() {
      continue
    }
    for pred in edges.preds[block] {
      if !body.get(pred).unwrap_or(false) {
        body.set(pred, true)
        worklist.push(pred)
      }
    }
  }
  let result : Array[Int] = []
  body.each(fn(block, _) { result.push(block) })
  result.sort()
  result
}

///|
pub fn find_loops_from_edges(edges : DenseCfgEdges) -> Array[DenseCfgLoop] {
  let loops : Array[DenseCfgLoop] = []
  let header_to_latches : Map[Int, Array[Int]] = Map([])
  for edge in find_back_edges_from_edges(edges) {
    let (latch, header) = edge
    match header_to_latches.get(header) {
      Some(latches) => latches.push(latch)
      None => header_to_latches.set(header, [latch])
    }
  }
  header_to_latches.each(fn(header, latches) {
    loops.push({
      header,
      body: find_loop_body(edges, header, latches),
      latch: latches[0],
    })
  })
  loops
}
