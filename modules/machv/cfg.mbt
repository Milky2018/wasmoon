///|
pub(all) struct CFG {
  size : Int
  preds : Array[Array[Int]]
  succs : Array[Array[Int]]
}

///|
pub(all) struct Loop {
  header : Int
  body : Array[Int]
  latch : Int
}

///|
fn terminator_successor_ids(term : Terminator) -> Array[Int] {
  match term {
    TermJump(target, _) => [target]
    TermBranch(_, then_b, else_b)
    | TermBranchCmp(_, _, _, _, then_b, else_b)
    | TermBranchCmpImm(_, _, _, _, then_b, else_b)
    | TermBranchZero(_, _, _, then_b, else_b) => [then_b, else_b]
    TermBrTable(_, targets, default) => {
      let result : Array[Int] = []
      for target in targets {
        result.push(target)
      }
      result.push(default)
      result
    }
    TermReturn(_) | TermTrap(_) => []
  }
}

///|
pub fn CFG::build(func : Function) -> CFG {
  let blocks = func.blocks
  let n = blocks.length()
  let preds : Array[Array[Int]] = []
  let succs : Array[Array[Int]] = []
  let block_id_to_index : Map[Int, Int] = {}
  for _ in 0..<n {
    preds.push([])
    succs.push([])
  }
  for i, block in blocks {
    block_id_to_index.set(block.id, i)
  }
  for block_idx, block in blocks {
    if block.terminator is Some(term) {
      let block_succs : Array[Int] = []
      for succ_id in terminator_successor_ids(term) {
        if block_id_to_index.get(succ_id) is Some(succ_idx) {
          block_succs.push(succ_idx)
          preds[succ_idx].push(block_idx)
        }
      }
      succs[block_idx] = block_succs
    }
  }
  { size: n, preds, succs }
}

///|
fn CFG::postorder(self : CFG) -> Array[Int] {
  let visited : Array[Bool] = Array::make(self.size, false)
  let result : Array[Int] = []
  fn visit(cfg : CFG, block : Int, visited : Array[Bool], result : Array[Int]) {
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
pub fn CFG::reverse_postorder(self : CFG) -> Array[Int] {
  let po = self.postorder()
  po.rev_in_place()
  po
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
pub fn CFG::compute_dominators(self : CFG) -> Array[Int] {
  let idom : Array[Int] = Array::make(self.size, -1)
  if self.size == 0 {
    return idom
  }
  idom[0] = 0
  let rpo = self.reverse_postorder()
  let rpo_num : Array[Int] = Array::make(self.size, -1)
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
pub fn CFG::find_back_edges(self : CFG) -> Array[(Int, Int)] {
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
fn CFG::find_loop_body(
  self : CFG,
  header : Int,
  latches : Array[Int],
) -> Array[Int] {
  let body : Map[Int, Bool] = {}
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
    for pred in self.preds[block] {
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
pub fn CFG::find_loops(self : CFG) -> Array[Loop] {
  let loops : Array[Loop] = []
  let header_to_latches : Map[Int, Array[Int]] = {}
  for edge in self.find_back_edges() {
    let (latch, header) = edge
    match header_to_latches.get(header) {
      Some(latches) => latches.push(latch)
      None => header_to_latches.set(header, [latch])
    }
  }
  header_to_latches.each(fn(header, latches) {
    loops.push({
      header,
      body: self.find_loop_body(header, latches),
      latch: latches[0],
    })
  })
  loops
}
