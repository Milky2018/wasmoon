// Canonicalization rules
// ============================================================================
// Push constants to the right side of commutative operations.
// This enables other rules to only match patterns like `x + k` instead of
// needing to handle both `x + k` and `k + x`.
//
// Key differences from general commutativity:
// 1. Only fires when left operand IS a constant and right IS NOT
// 2. Does NOT use subsume - adds equivalent form (both forms remain valid)
// 3. Targeted at enabling constant folding and other optimizations
// ============================================================================

///|
/// Canonicalize addition: (k + x) -> (x + k) when k is constant
fn rule_canon_add() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let left = node.children[0]
          let right = node.children[1]
          // Only canonicalize when left IS constant and right IS NOT
          if eg.get_const(left) is Some(_) && eg.get_const(right) is None {
            // k + x -> x + k (add equivalent form, don't remove original)
            let canonical = eg.add_add(right, left)
            let new_id = eg.merge(class_id, canonical)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// Canonicalize multiplication: (k * x) -> (x * k) when k is constant
fn rule_canon_mul() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          let left = node.children[0]
          let right = node.children[1]
          if eg.get_const(left) is Some(_) && eg.get_const(right) is None {
            let canonical = eg.add_mul(right, left)
            let new_id = eg.merge(class_id, canonical)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// Canonicalize bitwise AND: (k & x) -> (x & k) when k is constant
fn rule_canon_and() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          let left = node.children[0]
          let right = node.children[1]
          if eg.get_const(left) is Some(_) && eg.get_const(right) is None {
            let canonical = eg.add_and(right, left)
            let new_id = eg.merge(class_id, canonical)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// Canonicalize bitwise OR: (k | x) -> (x | k) when k is constant
fn rule_canon_or() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          let left = node.children[0]
          let right = node.children[1]
          if eg.get_const(left) is Some(_) && eg.get_const(right) is None {
            let canonical = eg.add_or(right, left)
            let new_id = eg.merge(class_id, canonical)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// Canonicalize bitwise XOR: (k ^ x) -> (x ^ k) when k is constant
fn rule_canon_xor() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          let left = node.children[0]
          let right = node.children[1]
          if eg.get_const(left) is Some(_) && eg.get_const(right) is None {
            let canonical = eg.add_xor(right, left)
            let new_id = eg.merge(class_id, canonical)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}
