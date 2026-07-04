///|
pub(all) struct CFG {
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
    Return(_) | TrapExit(_) => []
  }
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
pub fn CFG::postorder(self : CFG) -> Array[Int] {
  let visited = Array::make(self.size, false)
  let result : Array[Int] = []
  if self.size > 0 && self.valid[0] {
    postorder_visit(self, 0, visited, result)
  }
  result
}

///|
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
  for succ in cfg.successors[block_id] {
    postorder_visit(cfg, succ, visited, result)
  }
  result.push(block_id)
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
  let idom = self.compute_dominators()
  dominates_with_idom(idom, a, b)
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
