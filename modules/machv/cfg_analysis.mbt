///|
fn terminator_edges(terminator : Terminator) -> Array[Edge] {
  match terminator {
    Jump(edge) => [edge]
    Branch(_, true_edge, false_edge) => [true_edge, false_edge]
    Switch(_, cases, default_edge) => {
      let edges = cases.map(case => case.edge)
      edges.push(default_edge)
      edges
    }
    Return(_) | TailCall(_, _) | NoReturnCall(_, _) | Trap(_) => []
  }
}

///|
fn build_cfg(function : Function) -> (Array[Array[Int]], Array[Array[Int]]) {
  let successors : Array[Array[Int]] = []
  let predecessors : Array[Array[Int]] = []
  for _ in 0..<function.blocks.length() {
    successors.push([])
    predecessors.push([])
  }
  for block_id, data in function.blocks {
    if data.terminator is Some(record) {
      for edge in terminator_edges(record.kind) {
        if function.owns_block(edge.target) {
          successors[block_id].push(edge.target.id)
          predecessors[edge.target.id].push(block_id)
        }
      }
    }
  }
  (successors, predecessors)
}

///|
/// Reachable block indices in reverse postorder, entry block first, followed
/// by unreachable blocks in stable storage order.
pub fn Function::block_indices_in_cfg_order(self : Function) -> Array[Int] {
  let (successors, _) = build_cfg(self)
  let order = reverse_postorder(successors)
  let seen = Array::make(self.blocks.length(), false)
  for block_id in order {
    seen[block_id] = true
  }
  for block_id in 0..<self.blocks.length() {
    if !seen[block_id] {
      order.push(block_id)
    }
  }
  order
}

///|
/// Reachable blocks in reverse postorder, entry block first.
///
/// The depth of this walk is the length of a CFG path, which the input
/// function controls, so it keeps its own stack on the heap rather than
/// recursing: a chain of blocks is ordinary in generated code, and a native
/// recursion turns one into a stack overflow (ISS-401).
fn reverse_postorder(successors : Array[Array[Int]]) -> Array[Int] {
  let visited = Array::make(successors.length(), false)
  let order : Array[Int] = []
  if successors.is_empty() {
    return order
  }
  // `pending[i]` is the index of the next successor to consider when
  // `stack[i]` comes back to the top, so a block joins the postorder only
  // once every successor below it has, exactly as a recursive descent does.
  let stack = [0]
  let pending = [0]
  visited[0] = true
  while stack.length() > 0 {
    let top = stack.length() - 1
    let block_id = stack[top]
    if pending[top] < successors[block_id].length() {
      let successor = successors[block_id][pending[top]]
      pending[top] += 1
      if !visited[successor] {
        visited[successor] = true
        stack.push(successor)
        pending.push(0)
      }
    } else {
      stack.unsafe_pop() |> ignore
      pending.unsafe_pop() |> ignore
      order.push(block_id)
    }
  }
  order.rev_in_place()
  order
}

///|
/// Return reachable blocks in reverse postorder, followed by any unreachable
/// blocks in stable storage order. Target selectors use this order so every
/// reachable SSA definition is materialized before its dominated uses without
/// making physical block allocation order part of the semantic contract.
pub fn Function::blocks_in_cfg_order(self : Function) -> Array[Block] {
  self
  .block_indices_in_cfg_order()
  .map(block_id => Block::new(self.owner, block_id))
}

///|
fn intersect_dominators(
  idom : Array[Int],
  rpo_number : Array[Int],
  first : Int,
  second : Int,
) -> Int {
  let mut left = first
  let mut right = second
  while left != right {
    while rpo_number[left] > rpo_number[right] {
      left = idom[left]
    }
    while rpo_number[right] > rpo_number[left] {
      right = idom[right]
    }
  }
  left
}

///|
fn compute_dominators(
  successors : Array[Array[Int]],
  predecessors : Array[Array[Int]],
) -> Array[Int] {
  let idom = Array::make(successors.length(), -1)
  if successors.is_empty() {
    return idom
  }
  idom[0] = 0
  let rpo = reverse_postorder(successors)
  let rpo_number = Array::make(successors.length(), -1)
  for index, block_id in rpo {
    rpo_number[block_id] = index
  }
  let mut changed = true
  while changed {
    changed = false
    for block_id in rpo {
      if block_id == 0 {
        continue
      }
      let mut new_idom = -1
      for predecessor in predecessors[block_id] {
        if idom[predecessor] != -1 {
          if new_idom == -1 {
            new_idom = predecessor
          } else {
            new_idom = intersect_dominators(
              idom, rpo_number, new_idom, predecessor,
            )
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
