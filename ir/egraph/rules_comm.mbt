// Commutativity rules
// ============================================================================
// Commutativity rules
// ============================================================================

///|
/// x + y = y + x (commutativity of addition)
fn rule_add_comm() -> RewriteRule {
  {
    name: "add_comm",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let swapped = eg.add_add(node.children[1], node.children[0])
          let new_id = eg.merge(class_id, swapped)
          changed = new_id != class_id || changed
        }
      }
      changed
    },
  }
}

///|
/// x * y = y * x (commutativity of multiplication)
fn rule_mul_comm() -> RewriteRule {
  {
    name: "mul_comm",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          let swapped = eg.add_mul(node.children[1], node.children[0])
          let new_id = eg.merge(class_id, swapped)
          changed = new_id != class_id || changed
        }
      }
      changed
    },
  }
}

///|
/// x & y = y & x (commutativity of and)
fn rule_and_comm() -> RewriteRule {
  {
    name: "and_comm",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          let swapped = eg.add_and(node.children[1], node.children[0])
          let new_id = eg.merge(class_id, swapped)
          changed = new_id != class_id || changed
        }
      }
      changed
    },
  }
}

///|
/// x | y = y | x (commutativity of or)
fn rule_or_comm() -> RewriteRule {
  {
    name: "or_comm",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          let swapped = eg.add_or(node.children[1], node.children[0])
          let new_id = eg.merge(class_id, swapped)
          changed = new_id != class_id || changed
        }
      }
      changed
    },
  }
}

///|
/// x ^ y = y ^ x (commutativity of xor)
fn rule_xor_comm() -> RewriteRule {
  {
    name: "xor_comm",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          let swapped = eg.add_xor(node.children[1], node.children[0])
          let new_id = eg.merge(class_id, swapped)
          changed = new_id != class_id || changed
        }
      }
      changed
    },
  }
}
