///|
pub struct CFG {
  size : Int
  num_blocks : Int
  successors : Array[Array[Int]]
  predecessors : Array[Array[Int]]
  valid : Array[Bool]
} derive(Debug)

///|
pub fn CFG::build(func : Function) -> CFG {
  let num_blocks = func.blocks.length()
  let mut max_id = -1
  for block in func.blocks {
    if block.id > max_id {
      max_id = block.id
    }
  }
  let size = max_id + 1
  let successors : Array[Array[Int]] = []
  let predecessors : Array[Array[Int]] = []
  let valid : Array[Bool] = []
  for _ in 0..<size {
    successors.push([])
    predecessors.push([])
    valid.push(false)
  }
  for block in func.blocks {
    valid[block.id] = true
  }
  for block in func.blocks {
    if block.terminator is Some(term) {
      for target in terminator_targets(term) {
        if target >= 0 && target < size && valid[target] {
          successors[block.id].push(target)
          predecessors[target].push(block.id)
        }
      }
    }
  }
  { size, num_blocks, successors, predecessors, valid }
}

///|
fn terminator_targets(term : Terminator) -> Array[Int] {
  match term {
    Jump(target, _) => [target]
    Branch(_, true_target, _, false_target, _) => [true_target, false_target]
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
    Return(_) | Trap(_) | TrapExit(_) => []
  }
}

///|
fn get_terminator_targets(term : Terminator) -> Array[Int] {
  terminator_targets(term)
}

///|
pub fn CFG::is_valid(self : CFG, block_id : Int) -> Bool {
  block_id >= 0 && block_id < self.size && self.valid[block_id]
}

///|
pub fn CFG::get_successors(self : CFG, block_id : Int) -> Array[Int] {
  if self.is_valid(block_id) {
    self.successors[block_id]
  } else {
    []
  }
}

///|
pub fn CFG::get_predecessors(self : CFG, block_id : Int) -> Array[Int] {
  if self.is_valid(block_id) {
    self.predecessors[block_id]
  } else {
    []
  }
}

///|
pub fn CFG::is_entry_or_unreachable(self : CFG, block_id : Int) -> Bool {
  if self.is_valid(block_id) {
    self.predecessors[block_id].length() == 0
  } else {
    true
  }
}

///|
pub fn CFG::is_exit_block(self : CFG, block_id : Int) -> Bool {
  if self.is_valid(block_id) {
    self.successors[block_id].length() == 0
  } else {
    true
  }
}

///|
/// Depth-first postorder over the reachable CFG, entry block first.
///
/// The depth of this walk is the length of a CFG path, which the input
/// function controls, so it keeps its own stack on the heap. A chain of
/// blocks is ordinary in generated code, and a native recursion turns one
/// into a stack overflow inside the optimizer rather than a diagnosable
/// error (ISS-380, ISS-401).
pub fn CFG::postorder(self : CFG) -> Array[Int] {
  let visited = Array::make(self.size, false)
  let result : Array[Int] = []
  if self.size == 0 || !self.valid[0] {
    return result
  }
  // `pending[i]` is the index of the next successor to consider when
  // `stack[i]` comes back to the top. Advancing one successor per visit is
  // what makes this emit the same order as a recursive descent: a block is
  // pushed to `result` only once every successor below it has been.
  let stack = [0]
  let pending = [0]
  visited[0] = true
  while stack.length() > 0 {
    let top = stack.length() - 1
    let block_id = stack[top]
    let successors = self.successors[block_id]
    if pending[top] < successors.length() {
      let succ = successors[pending[top]]
      pending[top] += 1
      if self.is_valid(succ) && !visited[succ] {
        visited[succ] = true
        stack.push(succ)
        pending.push(0)
      }
    } else {
      stack.unsafe_pop() |> ignore
      pending.unsafe_pop() |> ignore
      result.push(block_id)
    }
  }
  result
}

///|
pub fn CFG::reverse_postorder(self : CFG) -> Array[Int] {
  let po = self.postorder()
  po.rev_in_place()
  po
}

///|
pub fn CFG::compute_dominators(self : CFG) -> Array[Int] {
  let idom = Array::make(self.size, -1)
  if self.size == 0 || !self.valid[0] {
    return idom
  }
  idom[0] = 0
  let rpo = self.reverse_postorder()
  let rpo_num = Array::make(self.size, -1)
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
      for pred in self.predecessors[block_id] {
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
pub fn CFG::dominates(self : CFG, a : Int, b : Int) -> Bool {
  self.compute_dominance().dominates(a, b)
}

///|
priv struct Dominance {
  idom : Array[Int]
  preorder : Array[Int]
  subtree_end : Array[Int]
}

///|
/// CFG facts shared by instruction-only optimization passes. The analysis is
/// valid until a pass changes block successors or block identity.
priv struct FunctionAnalysis {
  cfg : CFG
  dominance : Dominance
  domtree : Array[Array[Int]]
  block_idx : Array[Int]
}

///|
fn FunctionAnalysis::build(func : Function) -> FunctionAnalysis {
  let cfg = CFG::build(func)
  let dominance = cfg.compute_dominance()
  let block_idx = Array::make(func.next_block_id, -1)
  for index, block in func.blocks {
    block_idx[block.id] = index
  }
  { cfg, dominance, domtree: build_dominator_tree(dominance.idom), block_idx }
}

///|
fn CFG::compute_dominance(self : CFG) -> Dominance {
  let idom = self.compute_dominators()
  let preorder = Array::make(idom.length(), -1)
  let subtree_end = Array::make(idom.length(), -1)
  let mut next = 0
  if self.is_valid(0) {
    visit_dominator_tree(
      build_dominator_tree(idom),
      0,
      fn(block_id) {
        preorder[block_id] = next
        next = next + 1
        (block_id, true)
      },
      fn(block_id) { subtree_end[block_id] = next },
    )
  }
  { idom, preorder, subtree_end }
}

///|
fn Dominance::dominates(self : Dominance, a : Int, b : Int) -> Bool {
  if a == b {
    return true
  }
  if a < 0 ||
    a >= self.preorder.length() ||
    b < 0 ||
    b >= self.preorder.length() {
    return false
  }
  let a_preorder = self.preorder[a]
  let b_preorder = self.preorder[b]
  a_preorder >= 0 &&
  b_preorder >= a_preorder &&
  b_preorder < self.subtree_end[a]
}

///|
fn build_dominator_tree(idom : Array[Int]) -> Array[Array[Int]] {
  let children : Array[Array[Int]] = []
  for _ in 0..<idom.length() {
    children.push([])
  }
  for i, parent in idom {
    if parent >= 0 && parent != i {
      children[parent].push(i)
    }
  }
  children
}

///|
/// One step of an explicit dominator-tree walk: `Enter` visits a node and
/// schedules its children, `Exit` carries the scope state that node
/// introduced so it can be unwound once the subtree below it is finished.
priv enum DomWalkEvent[Scope] {
  Enter(Int)
  Exit(Scope)
}

///|
/// Walk the dominator tree below `root` in the order a recursive pre-order
/// descent would, without spending native stack on the depth of the tree.
///
/// `enter` visits a node and returns the scope state that node introduced
/// together with whether to descend into its children; `exit` receives that
/// state once the node's whole subtree is done. Scoped passes bind on the way
/// down and restore on the way up, so the two run in exactly the nesting a
/// recursion gave them.
///
/// This exists so that stack safety is settled once rather than per pass.
/// Every dominator-tree pass here used to hand-roll its own descent, which
/// meant "does this survive a deep function?" got answered independently at
/// each site — and answered wrong at all but one of them (ISS-401).
fn[Scope] visit_dominator_tree(
  domtree : Array[Array[Int]],
  root : Int,
  enter : (Int) -> (Scope, Bool),
  exit : (Scope) -> Unit,
) -> Unit {
  let events : Array[DomWalkEvent[Scope]] = [Enter(root)]
  while events.pop() is Some(event) {
    match event {
      Exit(scope) => exit(scope)
      Enter(block_id) => {
        let (scope, descend) = enter(block_id)
        // Pushed before the children so it pops after all of them.
        events.push(Exit(scope))
        if descend && block_id >= 0 && block_id < domtree.length() {
          // Reversed: the stack is LIFO, so this pops the children back out
          // in the order the recursive descent took them.
          for child in domtree[block_id].rev_iter() {
            events.push(Enter(child))
          }
        }
      }
    }
  }
}

///|
pub fn CFG::find_back_edges(self : CFG) -> Array[(Int, Int)] {
  let dominance = self.compute_dominance()
  let back_edges : Array[(Int, Int)] = []
  for block_id in 0..<self.size {
    if !self.valid[block_id] {
      continue
    }
    for succ in self.successors[block_id] {
      if dominance.dominates(succ, block_id) {
        back_edges.push((block_id, succ))
      }
    }
  }
  back_edges
}

///|
pub struct Loop {
  header : Int
  blocks : Array[Int]
  back_edges : Array[(Int, Int)]
} derive(Debug)

///|
pub fn CFG::find_loops(self : CFG) -> Array[Loop] {
  let loops : Array[Loop] = []
  let back_edges = self.find_back_edges()
  // Preserve back-edge discovery order in the public loop array.
  let grouped : Map[Int, Array[(Int, Int)]] = Map([])
  for edge in back_edges {
    let (_, header) = edge
    match grouped.get(header) {
      Some(edges) => edges.push(edge)
      None => grouped.set(header, [edge])
    }
  }
  grouped.each(fn(header, edges) {
    loops.push({
      header,
      blocks: self.find_loop_body(header, edges),
      back_edges: edges,
    })
  })
  loops
}

///|
fn CFG::find_loop_body(
  self : CFG,
  header : Int,
  back_edges : Array[(Int, Int)],
) -> Array[Int] {
  // Preserve the header-first reverse-CFG discovery order.
  let body : Map[Int, Bool] = Map([])
  body.set(header, true)
  let worklist : Array[Int] = []
  for edge in back_edges {
    let (source, _) = edge
    if source != header {
      worklist.push(source)
      body.set(source, true)
    }
  }
  while worklist.length() > 0 {
    let block = worklist.pop().unwrap()
    for pred in self.predecessors[block] {
      if !body.get(pred).unwrap_or(false) {
        body.set(pred, true)
        worklist.push(pred)
      }
    }
  }
  let result : Array[Int] = []
  body.each(fn(block_id, _) { result.push(block_id) })
  result
}

///|
pub fn Loop::contains(self : Loop, block_id : Int) -> Bool {
  for block in self.blocks {
    if block == block_id {
      return true
    }
  }
  false
}

///|
pub fn CFG::get_loop_preheader(self : CFG, loop_ : Loop) -> Int? {
  let mut preheader : Int? = None
  for pred in self.predecessors[loop_.header] {
    if !loop_.contains(pred) {
      match preheader {
        Some(_) => return None
        None => preheader = Some(pred)
      }
    }
  }
  preheader
}

///|
pub fn CFG::to_dot(self : CFG, func_name : String) -> String {
  let mut result = "digraph \{func_name} {\n"
  result = result + "  node [shape=box];\n"
  for block_id in 0..<self.size {
    if !self.valid[block_id] {
      continue
    }
    for succ in self.successors[block_id] {
      result = result + "  block\{block_id} -> block\{succ};\n"
    }
  }
  result + "}\n"
}
