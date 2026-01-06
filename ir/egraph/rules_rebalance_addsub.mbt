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
fn rule_sub_sub_sub_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let a = node.children[0]
          if get_sub_operands(eg, node.children[1]) is Some((b, inner)) {
            if get_sub_operands(eg, inner) is Some((c, d)) {
              let ab = eg.add_sub(a, b)
              let cd = eg.add_sub(c, d)
              let result = eg.add_add(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// a - (b - (c + d)) -> (a - b) + (c + d)
fn rule_sub_sub_add_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let a = node.children[0]
          if get_sub_operands(eg, node.children[1]) is Some((b, inner)) {
            if get_add_ops(eg, inner) is Some((c, d)) {
              let ab = eg.add_sub(a, b)
              let cd = eg.add_add(c, d)
              let result = eg.add_add(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// a - (b + (c - d)) -> (a - b) - (c - d)
fn rule_sub_add_sub_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let a = node.children[0]
          if get_add_ops(eg, node.children[1]) is Some((b, inner)) {
            if get_sub_operands(eg, inner) is Some((c, d)) {
              let ab = eg.add_sub(a, b)
              let cd = eg.add_sub(c, d)
              let result = eg.add_sub(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// a - (b + (c + d)) -> (a - b) - (c + d)
fn rule_sub_add_add_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let a = node.children[0]
          if get_add_ops(eg, node.children[1]) is Some((b, inner)) {
            if get_add_ops(eg, inner) is Some((c, d)) {
              let ab = eg.add_sub(a, b)
              let cd = eg.add_add(c, d)
              let result = eg.add_sub(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// a + (b - (c - d)) -> (a + b) - (c - d)
fn rule_add_sub_sub_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let a = node.children[0]
          if get_sub_operands(eg, node.children[1]) is Some((b, inner)) {
            if get_sub_operands(eg, inner) is Some((c, d)) {
              let ab = eg.add_add(a, b)
              let cd = eg.add_sub(c, d)
              let result = eg.add_sub(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// a + (b - (c + d)) -> (a + b) - (c + d)
fn rule_add_sub_add_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let a = node.children[0]
          if get_sub_operands(eg, node.children[1]) is Some((b, inner)) {
            if get_add_ops(eg, inner) is Some((c, d)) {
              let ab = eg.add_add(a, b)
              let cd = eg.add_add(c, d)
              let result = eg.add_sub(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// a + (b + (c - d)) -> (a + b) + (c - d)
fn rule_add_add_sub_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let a = node.children[0]
          if get_add_ops(eg, node.children[1]) is Some((b, inner)) {
            if get_sub_operands(eg, inner) is Some((c, d)) {
              let ab = eg.add_add(a, b)
              let cd = eg.add_sub(c, d)
              let result = eg.add_add(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}

// Left-nested patterns: ((a op b) op c) op d

///|
/// ((a - b) - c) - d -> (a - b) - (c + d)
fn rule_sub_sub_sub_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let d = node.children[1]
          if get_sub_operands(eg, node.children[0]) is Some((inner, c)) {
            if get_sub_operands(eg, inner) is Some((a, b)) {
              let ab = eg.add_sub(a, b)
              let cd = eg.add_add(c, d)
              let result = eg.add_sub(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// ((a - b) - c) + d -> (a - b) - (c - d)
fn rule_sub_sub_add_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let d = node.children[1]
          if get_sub_operands(eg, node.children[0]) is Some((inner, c)) {
            if get_sub_operands(eg, inner) is Some((a, b)) {
              let ab = eg.add_sub(a, b)
              let cd = eg.add_sub(c, d)
              let result = eg.add_sub(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// ((a - b) + c) - d -> (a - b) + (c - d)
fn rule_sub_add_sub_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let d = node.children[1]
          if get_add_ops(eg, node.children[0]) is Some((inner, c)) {
            if get_sub_operands(eg, inner) is Some((a, b)) {
              let ab = eg.add_sub(a, b)
              let cd = eg.add_sub(c, d)
              let result = eg.add_add(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// ((a - b) + c) + d -> (a - b) + (c + d)
fn rule_sub_add_add_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let d = node.children[1]
          if get_add_ops(eg, node.children[0]) is Some((inner, c)) {
            if get_sub_operands(eg, inner) is Some((a, b)) {
              let ab = eg.add_sub(a, b)
              let cd = eg.add_add(c, d)
              let result = eg.add_add(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// ((a + b) - c) - d -> (a + b) - (c + d)
fn rule_add_sub_sub_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let d = node.children[1]
          if get_sub_operands(eg, node.children[0]) is Some((inner, c)) {
            if get_add_ops(eg, inner) is Some((a, b)) {
              let ab = eg.add_add(a, b)
              let cd = eg.add_add(c, d)
              let result = eg.add_sub(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// ((a + b) - c) + d -> (a + b) - (c - d)
fn rule_add_sub_add_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let d = node.children[1]
          if get_sub_operands(eg, node.children[0]) is Some((inner, c)) {
            if get_add_ops(eg, inner) is Some((a, b)) {
              let ab = eg.add_add(a, b)
              let cd = eg.add_sub(c, d)
              let result = eg.add_sub(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// ((a + b) + c) - d -> (a + b) + (c - d)
fn rule_add_add_sub_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let d = node.children[1]
          if get_add_ops(eg, node.children[0]) is Some((inner, c)) {
            if get_add_ops(eg, inner) is Some((a, b)) {
              let ab = eg.add_add(a, b)
              let cd = eg.add_sub(c, d)
              let result = eg.add_add(ab, cd)
              let new_id = eg.subsume(class_id, result)
              changed = new_id != class_id || changed
            }
          }
        }
      }
      changed
    },
  }
}
