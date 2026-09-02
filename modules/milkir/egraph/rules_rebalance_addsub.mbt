// Add/Sub mixed rebalancing rules
// ============================================================================
// These rules handle mixed add/sub patterns to improve ILP.
//
// Key patterns (all use subsume to avoid exponential blow-up):
// - a - (b - (c - d)) -> (a - b) + (c - d)
// - a - (b - (c + d)) -> (a - b) + (c + d)
// - etc.
// ============================================================================

///|
/// Helper: check if a class has a Sub node and return its operands
fn get_sub_operands(eg : EGraph, id : EClassId) -> (EClassId, EClassId)? {
  for node in eg.get_nodes(id) {
    if node.op is Sub && node.children.length() == 2 {
      return Some((node.children[0], node.children[1]))
    }
  }
  None
}

///|
/// Helper: check if a class has an Add node (for addsub rules)
fn get_add_ops(eg : EGraph, id : EClassId) -> (EClassId, EClassId)? {
  for node in eg.get_nodes(id) {
    if node.op is Add && node.children.length() == 2 {
      return Some((node.children[0], node.children[1]))
    }
  }
  None
}

// Right-nested patterns: a op (b op (c op d))

///|
/// a - (b - (c - d)) -> (a - b) + (c - d)
fn rule_sub_sub_sub_right(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Sub && node.children.length() == 2 {
    let a = node.children[0]
    if get_sub_operands(eg, node.children[1]) is Some((b, inner)) &&
      get_sub_operands(eg, inner) is Some((c, d)) {
      let ab = eg.add_sub(a, b)
      let cd = eg.add_sub(c, d)
      let result = eg.add_add(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}

///|
/// a - (b - (c + d)) -> (a - b) + (c + d)
fn rule_sub_sub_add_right(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Sub && node.children.length() == 2 {
    let a = node.children[0]
    if get_sub_operands(eg, node.children[1]) is Some((b, inner)) &&
      get_add_ops(eg, inner) is Some((c, d)) {
      let ab = eg.add_sub(a, b)
      let cd = eg.add_add(c, d)
      let result = eg.add_add(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}

///|
/// a - (b + (c - d)) -> (a - b) - (c - d)
fn rule_sub_add_sub_right(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Sub && node.children.length() == 2 {
    let a = node.children[0]
    if get_add_ops(eg, node.children[1]) is Some((b, inner)) &&
      get_sub_operands(eg, inner) is Some((c, d)) {
      let ab = eg.add_sub(a, b)
      let cd = eg.add_sub(c, d)
      let result = eg.add_sub(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}

///|
/// a - (b + (c + d)) -> (a - b) - (c + d)
fn rule_sub_add_add_right(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Sub && node.children.length() == 2 {
    let a = node.children[0]
    if get_add_ops(eg, node.children[1]) is Some((b, inner)) &&
      get_add_ops(eg, inner) is Some((c, d)) {
      let ab = eg.add_sub(a, b)
      let cd = eg.add_add(c, d)
      let result = eg.add_sub(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}

///|
/// a + (b - (c - d)) -> (a + b) - (c - d)
fn rule_add_sub_sub_right(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Add && node.children.length() == 2 {
    let a = node.children[0]
    if get_sub_operands(eg, node.children[1]) is Some((b, inner)) &&
      get_sub_operands(eg, inner) is Some((c, d)) {
      let ab = eg.add_add(a, b)
      let cd = eg.add_sub(c, d)
      let result = eg.add_sub(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}

///|
/// a + (b - (c + d)) -> (a + b) - (c + d)
fn rule_add_sub_add_right(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Add && node.children.length() == 2 {
    let a = node.children[0]
    if get_sub_operands(eg, node.children[1]) is Some((b, inner)) &&
      get_add_ops(eg, inner) is Some((c, d)) {
      let ab = eg.add_add(a, b)
      let cd = eg.add_add(c, d)
      let result = eg.add_sub(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}

///|
/// a + (b + (c - d)) -> (a + b) + (c - d)
fn rule_add_add_sub_right(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Add && node.children.length() == 2 {
    let a = node.children[0]
    if get_add_ops(eg, node.children[1]) is Some((b, inner)) &&
      get_sub_operands(eg, inner) is Some((c, d)) {
      let ab = eg.add_add(a, b)
      let cd = eg.add_sub(c, d)
      let result = eg.add_add(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}

// Left-nested patterns: ((a op b) op c) op d

///|
/// ((a - b) - c) - d -> (a - b) - (c + d)
fn rule_sub_sub_sub_left(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Sub && node.children.length() == 2 {
    let d = node.children[1]
    if get_sub_operands(eg, node.children[0]) is Some((inner, c)) &&
      get_sub_operands(eg, inner) is Some((a, b)) {
      let ab = eg.add_sub(a, b)
      let cd = eg.add_add(c, d)
      let result = eg.add_sub(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}

///|
/// ((a - b) - c) + d -> (a - b) - (c - d)
fn rule_sub_sub_add_left(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Add && node.children.length() == 2 {
    let d = node.children[1]
    if get_sub_operands(eg, node.children[0]) is Some((inner, c)) &&
      get_sub_operands(eg, inner) is Some((a, b)) {
      let ab = eg.add_sub(a, b)
      let cd = eg.add_sub(c, d)
      let result = eg.add_sub(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}

///|
/// ((a - b) + c) - d -> (a - b) + (c - d)
fn rule_sub_add_sub_left(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Sub && node.children.length() == 2 {
    let d = node.children[1]
    if get_add_ops(eg, node.children[0]) is Some((inner, c)) &&
      get_sub_operands(eg, inner) is Some((a, b)) {
      let ab = eg.add_sub(a, b)
      let cd = eg.add_sub(c, d)
      let result = eg.add_add(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}

///|
/// ((a - b) + c) + d -> (a - b) + (c + d)
fn rule_sub_add_add_left(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Add && node.children.length() == 2 {
    let d = node.children[1]
    if get_add_ops(eg, node.children[0]) is Some((inner, c)) &&
      get_sub_operands(eg, inner) is Some((a, b)) {
      let ab = eg.add_sub(a, b)
      let cd = eg.add_add(c, d)
      let result = eg.add_add(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}

///|
/// ((a + b) - c) - d -> (a + b) - (c + d)
fn rule_add_sub_sub_left(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Sub && node.children.length() == 2 {
    let d = node.children[1]
    if get_sub_operands(eg, node.children[0]) is Some((inner, c)) &&
      get_add_ops(eg, inner) is Some((a, b)) {
      let ab = eg.add_add(a, b)
      let cd = eg.add_add(c, d)
      let result = eg.add_sub(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}

///|
/// ((a + b) - c) + d -> (a + b) - (c - d)
fn rule_add_sub_add_left(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Add && node.children.length() == 2 {
    let d = node.children[1]
    if get_sub_operands(eg, node.children[0]) is Some((inner, c)) &&
      get_add_ops(eg, inner) is Some((a, b)) {
      let ab = eg.add_add(a, b)
      let cd = eg.add_sub(c, d)
      let result = eg.add_sub(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}

///|
/// ((a + b) + c) - d -> (a + b) + (c - d)
fn rule_add_add_sub_left(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Sub && node.children.length() == 2 {
    let d = node.children[1]
    if get_add_ops(eg, node.children[0]) is Some((inner, c)) &&
      get_add_ops(eg, inner) is Some((a, b)) {
      let ab = eg.add_add(a, b)
      let cd = eg.add_sub(c, d)
      let result = eg.add_add(ab, cd)
      changed = eg.subsume_changed(class_id, result) || changed
    }
  }
  changed
}
