// Shift rules
// ============================================================================
// Shift rules
// ============================================================================

///|
/// x << 0 = x
fn rule_shl_zero() -> RewriteRule {
  {
    name: "shl_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Shl && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(0L) {
            let new_id = eg.merge(class_id, node.children[0])
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x >> 0 = x (both arithmetic and logical)
fn rule_shr_zero() -> RewriteRule {
  {
    name: "shr_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Sshr || node.op is Ushr) && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(0L) {
            let new_id = eg.merge(class_id, node.children[0])
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// 0 << x = 0, 0 >> x = 0
fn rule_shift_of_zero() -> RewriteRule {
  {
    name: "shift_of_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Shl || node.op is Sshr || node.op is Ushr) &&
          node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(0L) {
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
/// (x << a) << b = x << (a + b) when a + b < 64
fn rule_shl_shl() -> RewriteRule {
  {
    name: "shl_shl",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Shl && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(b) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Shl && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(a) {
                  let total = a + b
                  if total >= 0L && total < 64L {
                    let total_const = eg.add_const(total)
                    let new_node = eg.add_shl(inner.children[0], total_const)
                    let new_id = eg.merge(class_id, new_node)
                    changed = new_id != class_id || changed
                  }
                }
              }
            }
          }
        }
      }
      changed
    },
  }
}
