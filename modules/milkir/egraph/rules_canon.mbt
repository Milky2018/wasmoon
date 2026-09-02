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
fn rule_canon_add(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Add && node.children.length() == 2 {
    let left = node.children[0]
    let right = node.children[1]
    // Only canonicalize when left IS constant and right IS NOT
    if eg.get_const(left) is Some(_) && eg.get_const(right) is None {
      // k + x -> x + k (add equivalent form, don't remove original)
      let canonical = eg.add_add(right, left)
      changed = eg.merge_changed(class_id, canonical) || changed
    }
  }
  changed
}

///|
/// Canonicalize multiplication: (k * x) -> (x * k) when k is constant
fn rule_canon_mul(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Mul && node.children.length() == 2 {
    let left = node.children[0]
    let right = node.children[1]
    if eg.get_const(left) is Some(_) && eg.get_const(right) is None {
      let canonical = eg.add_mul(right, left)
      changed = eg.merge_changed(class_id, canonical) || changed
    }
  }
  changed
}

///|
/// Canonicalize bitwise AND: (k & x) -> (x & k) when k is constant
fn rule_canon_and(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is And && node.children.length() == 2 {
    let left = node.children[0]
    let right = node.children[1]
    if eg.get_const(left) is Some(_) && eg.get_const(right) is None {
      let canonical = eg.add_and(right, left)
      changed = eg.merge_changed(class_id, canonical) || changed
    }
  }
  changed
}

///|
/// Canonicalize bitwise OR: (k | x) -> (x | k) when k is constant
fn rule_canon_or(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Or && node.children.length() == 2 {
    let left = node.children[0]
    let right = node.children[1]
    if eg.get_const(left) is Some(_) && eg.get_const(right) is None {
      let canonical = eg.add_or(right, left)
      changed = eg.merge_changed(class_id, canonical) || changed
    }
  }
  changed
}

///|
/// Canonicalize bitwise XOR: (k ^ x) -> (x ^ k) when k is constant
fn rule_canon_xor(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Xor && node.children.length() == 2 {
    let left = node.children[0]
    let right = node.children[1]
    if eg.get_const(left) is Some(_) && eg.get_const(right) is None {
      let canonical = eg.add_xor(right, left)
      changed = eg.merge_changed(class_id, canonical) || changed
    }
  }
  changed
}
