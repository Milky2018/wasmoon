// Identity rules for EGraph optimization
// ============================================================================
// Standard rewrite rules
// ============================================================================

///|
/// Helper to check if an e-class contains a specific integer constant
/// Uses cached value for O(1) lookup
fn EGraph::find_const(self : EGraph, id : EClassId) -> Int64? {
  self.get_const(id)
}

///|
/// Helper to check if an e-class contains a specific float constant (as bits)
/// Uses cached value for O(1) lookup
fn EGraph::find_fconst(self : EGraph, id : EClassId) -> UInt64? {
  self.get_fconst(id)
}

///|
/// x + 0 = x
fn rule_add_zero(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Add &&
    node.children.length() == 2 &&
    eg.find_const(node.children[1]) is Some(0L) {
    // x + 0 = x
    changed = eg.merge_changed(class_id, node.children[0]) || changed
  } else if node.op is Add &&
    node.children.length() == 2 &&
    eg.find_const(node.children[0]) is Some(0L) {
    // 0 + x = x
    changed = eg.merge_changed(class_id, node.children[1]) || changed
  }
  changed
}

///|
/// x - 0 = x
fn rule_sub_zero(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Sub &&
    node.children.length() == 2 &&
    eg.find_const(node.children[1]) is Some(0L) {
    // x - 0 = x
    changed = eg.merge_changed(class_id, node.children[0]) || changed
  }
  changed
}

///|
/// x * 1 = x
fn rule_mul_one(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Mul &&
    node.children.length() == 2 &&
    eg.find_const(node.children[1]) is Some(1L) {
    changed = eg.merge_changed(class_id, node.children[0]) || changed
  } else if node.op is Mul &&
    node.children.length() == 2 &&
    eg.find_const(node.children[0]) is Some(1L) {
    changed = eg.merge_changed(class_id, node.children[1]) || changed
  }
  changed
}

///|
/// x * 0 = 0
fn rule_mul_zero(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Mul &&
    node.children.length() == 2 &&
    (
      eg.find_const(node.children[1]) is Some(0L) ||
      eg.find_const(node.children[0]) is Some(0L)
    ) {
    let zero = eg.add_const(0L)
    changed = eg.merge_changed(class_id, zero) || changed
  }
  changed
}

///|
/// x & x = x, x | x = x
fn rule_idempotent(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if (node.op is And || node.op is Or) &&
    node.children.length() == 2 &&
    eg.equiv(node.children[0], node.children[1]) {
    changed = eg.merge_changed(class_id, node.children[0]) || changed
  }
  changed
}

///|
/// x ^ x = 0
fn rule_xor_self(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Xor &&
    node.children.length() == 2 &&
    eg.equiv(node.children[0], node.children[1]) {
    let zero = eg.add_const(0L)
    changed = eg.merge_changed(class_id, zero) || changed
  }
  changed
}

///|
/// x - x = 0
fn rule_sub_self(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Sub &&
    node.children.length() == 2 &&
    eg.equiv(node.children[0], node.children[1]) {
    let zero = eg.add_const(0L)
    changed = eg.merge_changed(class_id, zero) || changed
  }
  changed
}

///|
/// Helper: check if n is a power of 2 and return log2(n)
fn log2_if_pow2(n : Int64) -> Int? {
  if n <= 0L {
    return None
  }
  // Check if n is power of 2: n & (n-1) == 0
  if (n & (n - 1L)) != 0L {
    return None
  }
  // Count trailing zeros to get log2
  let mut count = 0
  let mut val = n
  while (val & 1L) == 0L {
    count = count + 1
    val = val >> 1
  }
  Some(count)
}

///|
/// x * 2^n = x << n (strength reduction)
