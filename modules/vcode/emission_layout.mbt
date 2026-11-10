///|
/// Group call-free cyclic regions without changing allocation positions.
/// Strongly connected components also cover irreducible selected CFGs.
fn[Inst] Function::compact_emission_loops(
  self : Function[Inst],
  layout : Array[Block],
  cold : Array[Bool],
  calls : Array[Bool],
) -> Array[Block] {
  let successors = Array::makei(self.blocks.length(), id => {
    match self.blocks[id].terminator {
      Some(term) =>
        self.instructions[term.id].successors.map(edge => edge.target.id)
      None => []
    }
  })
  if !layout.any(block => {
      successors[block.id].any(target => {
        self.blocks[target].layout_index <= self.blocks[block.id].layout_index
      })
    }) {
    return layout.filter(block => !cold[block.id])
  }
  let seen = Array::make(self.blocks.length(), false)
  let order : Array[Int32] = []
  for block in layout {
    if seen[block.id] {
      continue
    }
    let stack : Array[(Int32, Int32)] = [(block.id, 0)]
    seen[block.id] = true
    while stack.last() is Some((id, next)) {
      if next == successors[id].length() {
        stack.pop() |> ignore
        order.push(id)
      } else {
        stack[stack.length() - 1] = (id, next + 1)
        let target = successors[id][next]
        if !seen[target] {
          seen[target] = true
          stack.push((target, 0))
        }
      }
    }
  }
  let predecessors = self.predecessors()
  let components = Array::make(self.blocks.length(), -1)
  let pure : Array[Bool] = []
  let counts : Array[Int32] = []
  for i = order.length() - 1; i >= 0; i = i - 1 {
    let id = order[i]
    if components[id] >= 0 {
      continue
    }
    let component = pure.length()
    pure.push(true)
    counts.push(0)
    components[id] = component
    let stack = [id]
    while stack.pop() is Some(current) {
      counts[component] += 1
      if calls[current] || cold[current] {
        pure[component] = false
      }
      for predecessor in predecessors[current] {
        if components[predecessor] < 0 {
          components[predecessor] = component
          stack.push(predecessor)
        }
      }
    }
  }
  // Preserve the original order within a region, including its first entry.
  let members : Array[Array[Block]] = Array::makei(pure.length(), _ => [])
  for block in layout {
    members[components[block.id]].push(block)
  }
  let emitted = Array::make(pure.length(), false)
  let result : Array[Block] = []
  for block in layout {
    if cold[block.id] {
      continue
    }
    let component = components[block.id]
    if pure[component] && counts[component] > 1 {
      if !emitted[component] {
        result.append(members[component])
        emitted[component] = true
      }
    } else {
      result.push(block)
    }
  }
  result
}

///|
/// Keep the register-allocation order intact. Emission alone places returning
/// helper diamonds after the normal blocks, preserving every original edge.
pub fn[Inst] Function::emission_layout(self : Function[Inst]) -> Array[Block] {
  let layout = self.layout()
  let calls = Array::makei(self.blocks.length(), id => {
    self.blocks[id].body.any(inst => {
      self.instructions[inst.id].clobber_count != 0
    })
  })
  let cold = Array::make(self.blocks.length(), false)
  for block in layout {
    guard self.blocks[block.id].terminator is Some(term) &&
      self.instructions[term.id].successors is [left, right] else {
      continue
    }
    for
      (slow, fast) in [(left.target, right.target), (right.target, left.target)] {
      if !calls[slow.id] || calls[fast.id] || slow == layout[0] {
        continue
      }
      guard self.blocks[slow.id].terminator is Some(slow_term) &&
        self.instructions[slow_term.id].successors is [joined] else {
        continue
      }
      if fast == joined.target {
        cold[slow.id] = true
      } else if self.blocks[fast.id].terminator is Some(fast_term) &&
        self.instructions[fast_term.id].successors is [other_join] &&
        joined.target == other_join.target {
        cold[slow.id] = true
      }
    }
  }
  self.compact_emission_loops(layout, cold, calls) +
  layout.filter(block => cold[block.id])
}
