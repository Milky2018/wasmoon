// Strength reduction rules
// ============================================================================
// More strength reduction rules
// ============================================================================

///|
/// x / 2^n = x >> n (for unsigned, or when x >= 0)
/// Note: This is only valid for unsigned division
fn rule_udiv_pow2() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Udiv && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c) {
            if log2_if_pow2(c) is Some(shift) {
              let shift_const = eg.add_const(shift.to_int64())
              let new_node = eg.add_binop(Ushr, node.children[0], shift_const)
              let new_id = eg.merge(class_id, new_node)
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
/// x % 2^n = x & (2^n - 1) (for unsigned)
fn rule_urem_pow2() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Urem && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c) {
            if log2_if_pow2(c) is Some(_) {
              let mask = eg.add_const(c - 1L)
              let new_node = eg.add_and(node.children[0], mask)
              let new_id = eg.merge(class_id, new_node)
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
/// x * 3 = (x << 1) + x
fn rule_mul_3() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(3L) {
            let one = eg.add_const(1L)
            let shifted = eg.add_shl(node.children[0], one)
            let new_node = eg.add_add(shifted, node.children[0])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(3L) {
            let one = eg.add_const(1L)
            let shifted = eg.add_shl(node.children[1], one)
            let new_node = eg.add_add(shifted, node.children[1])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x * 5 = (x << 2) + x
fn rule_mul_5() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(5L) {
            let two = eg.add_const(2L)
            let shifted = eg.add_shl(node.children[0], two)
            let new_node = eg.add_add(shifted, node.children[0])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(5L) {
            let two = eg.add_const(2L)
            let shifted = eg.add_shl(node.children[1], two)
            let new_node = eg.add_add(shifted, node.children[1])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x * 7 = (x << 3) - x
fn rule_mul_7() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(7L) {
            let three = eg.add_const(3L)
            let shifted = eg.add_shl(node.children[0], three)
            let new_node = eg.add_sub(shifted, node.children[0])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(7L) {
            let three = eg.add_const(3L)
            let shifted = eg.add_shl(node.children[1], three)
            let new_node = eg.add_sub(shifted, node.children[1])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x * 9 = (x << 3) + x
fn rule_mul_9() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(9L) {
            let three = eg.add_const(3L)
            let shifted = eg.add_shl(node.children[0], three)
            let new_node = eg.add_add(shifted, node.children[0])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(9L) {
            let three = eg.add_const(3L)
            let shifted = eg.add_shl(node.children[1], three)
            let new_node = eg.add_add(shifted, node.children[1])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}
