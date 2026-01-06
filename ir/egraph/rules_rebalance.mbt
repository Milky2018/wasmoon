// Tree rebalancing rules
// ============================================================================
// Rebalance expression trees to increase instruction-level parallelism (ILP)
// and canonicalize into shallow-and-wide form for reassociating constants.
//
// Pattern: (a op (b op (c op d))) => ((a op b) op (c op d))
// Pattern: (((a op b) op c) op d) => ((a op b) op (c op d))
//
// Key points:
// 1. Use subsume to avoid exponential e-node blow up
// 2. Match the FULL pattern directly (no iterative matching)
// 3. Write rules for both left-skewed and right-skewed trees
// ============================================================================

///|
/// Helper: check if a class has an Add node and return its operands
fn get_add_operands(eg : EGraph, id : EClassId) -> (EClassId, EClassId)? {
  for node in eg.get_nodes(id) {
    if node.op is Add && node.children.length() == 2 {
      return Some((node.children[0], node.children[1]))
    }
  }
  None
}

///|
/// Helper: check if a class has a Mul node and return its operands
fn get_mul_operands(eg : EGraph, id : EClassId) -> (EClassId, EClassId)? {
  for node in eg.get_nodes(id) {
    if node.op is Mul && node.children.length() == 2 {
      return Some((node.children[0], node.children[1]))
    }
  }
  None
}

///|
/// Helper: check if a class has an And node and return its operands
fn get_and_operands(eg : EGraph, id : EClassId) -> (EClassId, EClassId)? {
  for node in eg.get_nodes(id) {
    if node.op is And && node.children.length() == 2 {
      return Some((node.children[0], node.children[1]))
    }
  }
  None
}

///|
/// Helper: check if a class has a Xor node and return its operands
fn get_xor_operands(eg : EGraph, id : EClassId) -> (EClassId, EClassId)? {
  for node in eg.get_nodes(id) {
    if node.op is Xor && node.children.length() == 2 {
      return Some((node.children[0], node.children[1]))
    }
  }
  None
}

///|
/// Rebalance right-skewed add: a + (b + (c + d)) -> (a + b) + (c + d)
fn rule_rebalance_add_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let a = node.children[0]
          // Check pattern: a + (b + (c + d))
          if get_add_operands(eg, node.children[1]) is Some((b, inner)) {
            if get_add_operands(eg, inner) is Some((c, d)) {
              // Rebalance: (a + b) + (c + d)
              let ab = eg.add_add(a, b)
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
/// Rebalance left-skewed add: ((a + b) + c) + d -> (a + b) + (c + d)
fn rule_rebalance_add_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let d = node.children[1]
          // Check pattern: ((a + b) + c) + d
          if get_add_operands(eg, node.children[0]) is Some((inner, c)) {
            if get_add_operands(eg, inner) is Some((a, b)) {
              // Rebalance: (a + b) + (c + d)
              let ab = eg.add_add(a, b)
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
/// Rebalance right-skewed mul: a * (b * (c * d)) -> (a * b) * (c * d)
fn rule_rebalance_mul_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          let a = node.children[0]
          if get_mul_operands(eg, node.children[1]) is Some((b, inner)) {
            if get_mul_operands(eg, inner) is Some((c, d)) {
              let ab = eg.add_mul(a, b)
              let cd = eg.add_mul(c, d)
              let result = eg.add_mul(ab, cd)
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
/// Rebalance left-skewed mul: ((a * b) * c) * d -> (a * b) * (c * d)
fn rule_rebalance_mul_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          let d = node.children[1]
          if get_mul_operands(eg, node.children[0]) is Some((inner, c)) {
            if get_mul_operands(eg, inner) is Some((a, b)) {
              let ab = eg.add_mul(a, b)
              let cd = eg.add_mul(c, d)
              let result = eg.add_mul(ab, cd)
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
/// Rebalance right-skewed and: a & (b & (c & d)) -> (a & b) & (c & d)
fn rule_rebalance_and_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          let a = node.children[0]
          if get_and_operands(eg, node.children[1]) is Some((b, inner)) {
            if get_and_operands(eg, inner) is Some((c, d)) {
              let ab = eg.add_and(a, b)
              let cd = eg.add_and(c, d)
              let result = eg.add_and(ab, cd)
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
/// Rebalance left-skewed and: ((a & b) & c) & d -> (a & b) & (c & d)
fn rule_rebalance_and_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          let d = node.children[1]
          if get_and_operands(eg, node.children[0]) is Some((inner, c)) {
            if get_and_operands(eg, inner) is Some((a, b)) {
              let ab = eg.add_and(a, b)
              let cd = eg.add_and(c, d)
              let result = eg.add_and(ab, cd)
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
/// Rebalance right-skewed xor: a ^ (b ^ (c ^ d)) -> (a ^ b) ^ (c ^ d)
fn rule_rebalance_xor_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          let a = node.children[0]
          if get_xor_operands(eg, node.children[1]) is Some((b, inner)) {
            if get_xor_operands(eg, inner) is Some((c, d)) {
              let ab = eg.add_xor(a, b)
              let cd = eg.add_xor(c, d)
              let result = eg.add_xor(ab, cd)
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
/// Rebalance left-skewed xor: ((a ^ b) ^ c) ^ d -> (a ^ b) ^ (c ^ d)
fn rule_rebalance_xor_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          let d = node.children[1]
          if get_xor_operands(eg, node.children[0]) is Some((inner, c)) {
            if get_xor_operands(eg, inner) is Some((a, b)) {
              let ab = eg.add_xor(a, b)
              let cd = eg.add_xor(c, d)
              let result = eg.add_xor(ab, cd)
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
