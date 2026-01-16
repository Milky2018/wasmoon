// VCode CFG for block layout optimization
// Provides control flow analysis and loop detection

///|
/// VCode CFG - Control Flow Graph for VCode functions
pub struct VCodeCFG {
  size : Int
  preds : Array[Array[Int]]
  succs : Array[Array[Int]]
}

///|
/// Build a CFG from a VCodeFunction
pub fn VCodeCFG::build(func : @regalloc.VCodeFunction) -> VCodeCFG {
  let n = func.get_blocks().length()
  let preds : Array[Array[Int]] = []
  let succs : Array[Array[Int]] = []

  // Initialize arrays
  for _ in 0..<n {
    preds.push([])
    succs.push([])
  }

  // Build edges from terminators
  for block_idx, block in func.get_blocks() {
    if block.terminator is Some(term) {
      let block_succs = get_terminator_succs(term)
      succs[block_idx] = block_succs
      for succ in block_succs {
        if succ < n {
          preds[succ].push(block_idx)
        }
      }
    }
  }
  { size: n, preds, succs }
}

///|
/// Extract successor block IDs from terminator
fn get_terminator_succs(term : @instr.VCodeTerminator) -> Array[Int] {
  match term {
    Jump(target, _) => [target]
    Branch(_, then_b, else_b) => [then_b, else_b]
    BranchCmp(_, _, _, _, then_b, else_b) => [then_b, else_b]
    BranchCmpImm(_, _, _, _, then_b, else_b) => [then_b, else_b]
    BranchZero(_, _, _, then_b, else_b) => [then_b, else_b]
    BrTable(_, targets, default) => {
      let result : Array[Int] = []
      for t in targets {
        result.push(t)
      }
      result.push(default)
      result
    }
    Return(_) | Trap(_) => []
  }
}

///|
/// Perform a post-order traversal of the CFG
fn VCodeCFG::postorder(self : VCodeCFG) -> Array[Int] {
  let visited : Array[Bool] = Array::make(self.size, false)
  let result : Array[Int] = []
  fn visit(
    cfg : VCodeCFG,
    block : Int,
    visited : Array[Bool],
    result : Array[Int],
  ) {
    if block < 0 || block >= cfg.size || visited[block] {
      return
    }
    visited[block] = true
    for succ in cfg.succs[block] {
      visit(cfg, succ, visited, result)
    }
    result.push(block)
  }

  if self.size > 0 {
    visit(self, 0, visited, result)
  }
  result
}

///|
/// Perform a reverse post-order traversal of the CFG
fn VCodeCFG::reverse_postorder(self : VCodeCFG) -> Array[Int] {
  let po = self.postorder()
  po.rev_in_place()
  po
}

///|
/// Compute dominators using simple iterative algorithm
/// Returns immediate dominator for each block (-1 for entry/undefined)
pub fn VCodeCFG::compute_dominators(self : VCodeCFG) -> Array[Int] {
  let idom : Array[Int] = Array::make(self.size, -1)
  if self.size == 0 {
    return idom
  }

  // Entry block dominates itself
  idom[0] = 0

  // Get reverse post-order for iteration
  let rpo = self.reverse_postorder()

  // Build RPO numbering for correct intersection
  let rpo_num : Array[Int] = Array::make(self.size, -1)
  for i, block_id in rpo {
    rpo_num[block_id] = i
  }

  // Iterate until fixed point
  let mut changed = true
  while changed {
    changed = false
    for block_id in rpo {
      if block_id == 0 {
        continue
      }
      // Find first processed predecessor
      let mut new_idom = -1
      for pred in self.preds[block_id] {
        if idom[pred] != -1 {
          if new_idom == -1 {
            new_idom = pred
          } else {
            new_idom = intersect_dominators(idom, rpo_num, new_idom, pred)
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
/// Helper for dominator computation - find common dominator
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
/// Check if block a dominates block b
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
/// Find all back edges (source, target) where target dominates source
pub fn VCodeCFG::find_back_edges(self : VCodeCFG) -> Array[(Int, Int)] {
  let idom = self.compute_dominators()
  let back_edges : Array[(Int, Int)] = []
  for block_id in 0..<self.size {
    for succ in self.succs[block_id] {
      if dominates_with_idom(idom, succ, block_id) {
        back_edges.push((block_id, succ))
      }
    }
  }
  back_edges
}

///|
/// Natural loop representation
pub struct VCodeLoop {
  header : Int // Loop header (target of back edges)
  body : Array[Int] // All blocks in the loop
  latch : Int // Block with back edge to header (for single-latch loops)
}

///|
/// Find all natural loops in the CFG
pub fn VCodeCFG::find_loops(self : VCodeCFG) -> Array[VCodeLoop] {
  let loops : Array[VCodeLoop] = []
  let back_edges = self.find_back_edges()

  // Group back edges by header
  let header_to_latches : @hashmap.HashMap[Int, Array[Int]] = @hashmap.new()
  for edge in back_edges {
    let (latch, header) = edge
    match header_to_latches.get(header) {
      Some(latches) => latches.push(latch)
      None => header_to_latches.set(header, [latch])
    }
  }

  // For each header, find the loop body
  header_to_latches.each(fn(header, latches) {
    let body = self.find_loop_body(header, latches)
    // For simple loops, use the single latch; for complex loops, use first latch
    let latch = latches[0]
    loops.push({ header, body, latch })
  })
  loops
}

///|
/// Find all blocks in a natural loop given the header and latch blocks
fn VCodeCFG::find_loop_body(
  self : VCodeCFG,
  header : Int,
  latches : Array[Int],
) -> Array[Int] {
  let body : @hashmap.HashMap[Int, Bool] = @hashmap.new()
  body.set(header, true)

  // Worklist for reverse DFS from latch blocks
  let worklist : Array[Int] = []
  for latch in latches {
    if latch != header {
      worklist.push(latch)
      body.set(latch, true)
    }
  }

  // Walk backwards from latch to header
  while worklist.length() > 0 {
    let block = worklist.pop().unwrap()
    for pred in self.preds[block] {
      if !body.get(pred).unwrap_or(false) {
        body.set(pred, true)
        worklist.push(pred)
      }
    }
  }

  // Convert to array
  let result : Array[Int] = []
  body.each(fn(block_id, _) { result.push(block_id) })
  result
}
