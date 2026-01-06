// Control Flow Graph (CFG) Construction and Analysis
// Provides explicit representation of control flow relationships

///|
/// CFG - Control Flow Graph for a function
/// Provides predecessor/successor relationships for each block
pub struct CFG {
  // Size of arrays (max_block_id + 1, not necessarily equal to block count)
  size : Int
  // Actual number of blocks
  num_blocks : Int
  // Successors for each block (indexed by block ID)
  successors : Array[Array[Int]]
  // Predecessors for each block (indexed by block ID)
  predecessors : Array[Array[Int]]
  // Which block IDs are valid (present in the function)
  valid : Array[Bool]
}

///|
/// Build a CFG from a function
pub fn CFG::build(func : Function) -> CFG {
  let num_blocks = func.blocks.length()
  // Find max block ID to determine array size (handles sparse block IDs)
  let mut max_id = -1
  for block in func.blocks {
    if block.id > max_id {
      max_id = block.id
    }
  }
  let size = max_id + 1
  // Initialize empty adjacency lists and validity tracking
  let successors : Array[Array[Int]] = []
  let predecessors : Array[Array[Int]] = []
  let valid : Array[Bool] = []
  for _ in 0..<size {
    successors.push([])
    predecessors.push([])
    valid.push(false)
  }
  // Mark valid blocks
  for block in func.blocks {
    valid[block.id] = true
  }
  // Build edges from terminators
  for block in func.blocks {
    if block.terminator is Some(term) {
      let targets = get_terminator_targets(term)
      for target in targets {
        if target < size && valid[target] {
          successors[block.id].push(target)
          predecessors[target].push(block.id)
        }
      }
    }
  }
  { size, num_blocks, successors, predecessors, valid }
}

///|
/// Get all target blocks from a terminator
fn get_terminator_targets(term : Terminator) -> Array[Int] {
  match term {
    Jump(target, _) => [target]
    Brz(_, then_target, else_target) | Brnz(_, then_target, else_target) =>
      [then_target, else_target]
    BrTable(_, targets, default_target) => {
      let result : Array[Int] = []
      for t in targets {
        result.push(t)
      }
      result.push(default_target)
      result
    }
    Return(_) | Trap(_) => []
  }
}

///|
/// Check if a block ID is valid (present in the function)
pub fn CFG::is_valid(self : CFG, block_id : Int) -> Bool {
  block_id >= 0 && block_id < self.size && self.valid[block_id]
}

///|
/// Get successors of a block
pub fn CFG::get_successors(self : CFG, block_id : Int) -> Array[Int] {
  if self.is_valid(block_id) {
    self.successors[block_id]
  } else {
    []
  }
}

///|
/// Get predecessors of a block
pub fn CFG::get_predecessors(self : CFG, block_id : Int) -> Array[Int] {
  if self.is_valid(block_id) {
    self.predecessors[block_id]
  } else {
    []
  }
}

///|
/// Check if a block has no predecessors (entry block or unreachable)
pub fn CFG::is_entry_or_unreachable(self : CFG, block_id : Int) -> Bool {
  if self.is_valid(block_id) {
    self.predecessors[block_id].length() == 0
  } else {
    true
  }
}

///|
/// Check if a block has no successors (exit block)
pub fn CFG::is_exit_block(self : CFG, block_id : Int) -> Bool {
  if self.is_valid(block_id) {
    self.successors[block_id].length() == 0
  } else {
    true
  }
}

///|
/// Perform a post-order traversal of the CFG
/// Returns blocks in post-order (children before parents)
pub fn CFG::postorder(self : CFG) -> Array[Int] {
  let visited : Array[Bool] = Array::make(self.size, false)
  let result : Array[Int] = []
  // Start from entry block (block 0)
  if self.size > 0 && self.valid[0] {
    postorder_visit(self, 0, visited, result)
  }
  result
}

///|
/// Helper for post-order traversal
fn postorder_visit(
  cfg : CFG,
  block_id : Int,
  visited : Array[Bool],
  result : Array[Int],
) -> Unit {
  if !cfg.is_valid(block_id) || visited[block_id] {
    return
  }
  visited[block_id] = true
  // Visit all successors first
  for succ in cfg.successors[block_id] {
    postorder_visit(cfg, succ, visited, result)
  }
  // Then add this block
  result.push(block_id)
}

///|
/// Perform a reverse post-order traversal of the CFG
/// Returns blocks in reverse post-order (parents before children)
/// This is useful for dataflow analysis
pub fn CFG::reverse_postorder(self : CFG) -> Array[Int] {
  let po = self.postorder()
  po.rev_in_place()
  po
}

///|
/// Compute dominators using simple iterative algorithm
/// Returns immediate dominator for each block (-1 for undefined/invalid blocks)
pub fn CFG::compute_dominators(self : CFG) -> Array[Int] {
  // Initialize all to undefined (-1)
  let idom : Array[Int] = Array::make(self.size, -1)
  if self.size == 0 || !self.valid[0] {
    return idom
  }
  // Entry block dominates itself
  idom[0] = 0
  // Get reverse post-order for iteration
  let rpo = self.reverse_postorder()
  // Build RPO numbering: block_id -> position in RPO (for correct intersection)
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
      for pred in self.predecessors[block_id] {
        if idom[pred] != -1 {
          if new_idom == -1 {
            new_idom = pred
          } else {
            // Intersect dominators using RPO numbering
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
/// Uses RPO numbering for correct comparison (block IDs may not be in RPO order)
fn intersect_dominators(
  idom : Array[Int],
  rpo_num : Array[Int],
  b1_init : Int,
  b2_init : Int,
) -> Int {
  let mut b1 = b1_init
  let mut b2 = b2_init
  while b1 != b2 {
    // Compare using RPO numbers, not block IDs
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
/// Build dominator tree from immediate dominators
/// Returns children array: domtree[block_id] = array of dominated children
pub fn build_dominator_tree(idom : Array[Int]) -> Array[Array[Int]] {
  let n = idom.length()
  let children : Array[Array[Int]] = []
  for _ in 0..<n {
    children.push([])
  }
  for i, parent in idom {
    // Skip entry block (idom[0] = 0, self-loop) and undefined (-1)
    if parent >= 0 && parent != i {
      children[parent].push(i)
    }
  }
  children
}

///|
/// Check if block a dominates block b
pub fn CFG::dominates(self : CFG, a : Int, b : Int) -> Bool {
  let idom = self.compute_dominators()
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
/// Find all back edges (edges to dominators, indicating loops)
pub fn CFG::find_back_edges(self : CFG) -> Array[(Int, Int)] {
  let idom = self.compute_dominators()
  let back_edges : Array[(Int, Int)] = []
  for block_id in 0..<self.size {
    if !self.valid[block_id] {
      continue
    }
    for succ in self.successors[block_id] {
      // Check if succ dominates block_id (making this a back edge)
      if dominates_with_idom(idom, succ, block_id) {
        back_edges.push((block_id, succ))
      }
    }
  }
  back_edges
}

///|
/// Helper to check domination with precomputed idom
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
/// Print CFG in DOT format for visualization
pub fn CFG::to_dot(self : CFG, func_name : String) -> String {
  let mut result = "digraph \{func_name} {\n"
  result = result + "  node [shape=box];\n"
  // Add edges
  for block_id in 0..<self.size {
    if !self.valid[block_id] {
      continue
    }
    for succ in self.successors[block_id] {
      result = result + "  block\{block_id} -> block\{succ};\n"
    }
  }
  result = result + "}\n"
  result
}

// ============ Loop Analysis ============

///|
/// Loop - represents a natural loop in the CFG
pub struct Loop {
  header : Int // Loop header block (target of back edge)
  blocks : Array[Int] // All blocks in the loop body
  back_edges : Array[(Int, Int)] // Back edges (source, target) for this loop
}

///|
/// Find all natural loops in the CFG
/// Returns a list of loops, each with its header and body blocks
pub fn CFG::find_loops(self : CFG) -> Array[Loop] {
  let loops : Array[Loop] = []
  let back_edges = self.find_back_edges()

  // Group back edges by header
  let header_to_back_edges : @hashmap.HashMap[Int, Array[(Int, Int)]] = @hashmap.new()
  for edge in back_edges {
    let (_, header) = edge
    match header_to_back_edges.get(header) {
      Some(edges) => edges.push(edge)
      None => header_to_back_edges.set(header, [edge])
    }
  }

  // For each header, find the loop body
  header_to_back_edges.each(fn(header, edges) {
    let body = self.find_loop_body(header, edges)
    loops.push({ header, blocks: body, back_edges: edges })
  })
  loops
}

///|
/// Find all blocks in a natural loop given the header and back edges
fn CFG::find_loop_body(
  self : CFG,
  header : Int,
  back_edges : Array[(Int, Int)],
) -> Array[Int] {
  let body : @hashmap.HashMap[Int, Bool] = @hashmap.new()
  body.set(header, true)

  // Worklist for reverse DFS from back edge sources
  let worklist : Array[Int] = []
  for edge in back_edges {
    let (source, _) = edge
    if source != header {
      worklist.push(source)
      body.set(source, true)
    }
  }

  // Walk backwards from back edge sources to header
  while worklist.length() > 0 {
    let block = worklist.pop().unwrap()
    for pred in self.predecessors[block] {
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

///|
/// Check if a block is in a loop
pub fn Loop::contains(self : Loop, block_id : Int) -> Bool {
  for b in self.blocks {
    if b == block_id {
      return true
    }
  }
  false
}

///|
/// Get the preheader block for a loop (the unique predecessor outside the loop)
/// Returns None if there isn't a unique preheader
pub fn CFG::get_loop_preheader(self : CFG, loop_ : Loop) -> Int? {
  let mut preheader : Int? = None
  for pred in self.predecessors[loop_.header] {
    if !loop_.contains(pred) {
      match preheader {
        Some(_) => return None // Multiple preheaders
        None => preheader = Some(pred)
      }
    }
  }
  preheader
}
