// Bitwise rules
// ============================================================================
// Bitwise identity rules
// ============================================================================

///|
/// x & 0 = 0
fn rule_and_zero() -> RewriteRule {
  {
    name: "and_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(0L) ||
            eg.find_const(node.children[1]) is Some(0L) {
            let zero = eg.add_const(0L)
            let new_id = eg.merge(class_id, zero)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x | 0 = x
fn rule_or_zero() -> RewriteRule {
  {
    name: "or_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(0L) {
            let new_id = eg.merge(class_id, node.children[0])
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(0L) {
            let new_id = eg.merge(class_id, node.children[1])
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x ^ 0 = x
fn rule_xor_zero() -> RewriteRule {
  {
    name: "xor_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(0L) {
            let new_id = eg.merge(class_id, node.children[0])
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(0L) {
            let new_id = eg.merge(class_id, node.children[1])
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x & -1 = x (all bits set)
fn rule_and_all_ones() -> RewriteRule {
  {
    name: "and_all_ones",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(-1L) {
            let new_id = eg.merge(class_id, node.children[0])
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(-1L) {
            let new_id = eg.merge(class_id, node.children[1])
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x | -1 = -1
fn rule_or_all_ones() -> RewriteRule {
  {
    name: "or_all_ones",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(-1L) ||
            eg.find_const(node.children[1]) is Some(-1L) {
            let all_ones = eg.add_const(-1L)
            let new_id = eg.merge(class_id, all_ones)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}
