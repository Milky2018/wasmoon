// Select optimization rules
// Implements Cranelift selects.isle optimization rules
// ============================================================================

///|
/// select(_, x, x) = x
/// When both branches are the same, the condition doesn't matter
fn rule_select_same() -> RewriteRule {
  {
    name: "select_same",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          // select(cond, x, y) where x == y
          if eg.equiv(node.children[1], node.children[2]) {
            let new_id = eg.subsume(class_id, node.children[1])
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// select(icmp, 1, 0) -> uextend(icmp)
/// When selecting between 1 and 0 based on a comparison, just use the comparison result
fn rule_select_icmp_one_zero() -> RewriteRule {
  {
    name: "select_icmp_one_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          // Check if true branch is 1 and false branch is 0
          if eg.find_const(node.children[1]) is Some(1L) {
            if eg.find_const(node.children[2]) is Some(0L) {
              // Check if condition is an icmp
              for cond_node in eg.get_nodes(node.children[0]) {
                match cond_node.op {
                  Icmp(_) | Eq | Ne => {
                    // select(icmp, 1, 0) = icmp (the icmp already produces 0/1)
                    let new_id = eg.merge(class_id, node.children[0])
                    changed = new_id != class_id || changed
                  }
                  _ => ()
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

///|
/// select(icmp, 0, 1) -> uextend(complement(icmp))
/// Push zeroes to the right by complementing the condition
fn rule_select_icmp_zero_one() -> RewriteRule {
  {
    name: "select_icmp_zero_one",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          // Check if true branch is 0 and false branch is non-zero
          if eg.find_const(node.children[1]) is Some(0L) {
            if eg.find_const(node.children[2]) is Some(nz) && nz != 0L {
              // Check if condition is an icmp
              for cond_node in eg.get_nodes(node.children[0]) {
                if cond_node.op is Icmp(cc) {
                  // select(icmp(cc), 0, 1) = icmp(complement(cc))
                  let comp_cc = intcc_complement(cc)
                  let new_icmp = eg.add({
                    op: Icmp(comp_cc),
                    children: cond_node.children,
                  })
                  // Now we have select(icmp_comp, nonzero, 0) which is truthy form
                  // But if nonzero is 1, we can just use icmp_comp
                  if nz == 1L {
                    let new_id = eg.merge(class_id, new_icmp)
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

///|
/// select(d, a, select(d, _, y)) = select(d, a, y)
/// Nested select with same condition - inner true branch is unreachable
fn rule_select_nested_same_cond_right() -> RewriteRule {
  {
    name: "select_nested_same_cond_right",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let d = node.children[0]
          let a = node.children[1]
          // Check if false branch is also a select with same condition
          for inner in eg.get_nodes(node.children[2]) {
            if inner.op is Select && inner.children.length() == 3 {
              if eg.equiv(inner.children[0], d) {
                // select(d, a, select(d, _, y)) = select(d, a, y)
                let new_select = eg.add({
                  op: Select,
                  children: [d, a, inner.children[2]],
                })
                let new_id = eg.subsume(class_id, new_select)
                changed = new_id != class_id || changed
              }
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// select(d, select(d, x, _), a) = select(d, x, a)
/// Nested select with same condition - inner false branch is unreachable
fn rule_select_nested_same_cond_left() -> RewriteRule {
  {
    name: "select_nested_same_cond_left",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let d = node.children[0]
          let a = node.children[2]
          // Check if true branch is also a select with same condition
          for inner in eg.get_nodes(node.children[1]) {
            if inner.op is Select && inner.children.length() == 3 {
              if eg.equiv(inner.children[0], d) {
                // select(d, select(d, x, _), a) = select(d, x, a)
                let new_select = eg.add({
                  op: Select,
                  children: [d, inner.children[1], a],
                })
                let new_id = eg.subsume(class_id, new_select)
                changed = new_id != class_id || changed
              }
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// select(uextend(icmp), x, y) = select(icmp, x, y)
/// Remove unnecessary uextend on condition
fn rule_select_uextend_cond() -> RewriteRule {
  {
    name: "select_uextend_cond",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          // Check if condition is uextend of an icmp
          for cond_node in eg.get_nodes(node.children[0]) {
            match cond_node.op {
              Uextend(_, _) =>
                if cond_node.children.length() == 1 {
                  // Check if inner is an icmp
                  for inner in eg.get_nodes(cond_node.children[0]) {
                    match inner.op {
                      Icmp(_) | Eq | Ne => {
                        let new_select = eg.add({
                          op: Select,
                          children: [
                            cond_node.children[0],
                            node.children[1],
                            node.children[2],
                          ],
                        })
                        let new_id = eg.merge(class_id, new_select)
                        changed = new_id != class_id || changed
                      }
                      _ => ()
                    }
                  }
                }
              _ => ()
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// iadd(select(c, x, y), z) = select(c, x+z, y+z) when x, y, z are constants
/// Fold add into select branches
fn rule_add_select_const() -> RewriteRule {
  {
    name: "add_select_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          // Check if z (second operand) is constant
          if eg.find_const(node.children[1]) is Some(z) {
            // Check if first operand is select
            for sel in eg.get_nodes(node.children[0]) {
              if sel.op is Select && sel.children.length() == 3 {
                // Check if both branches are constants
                if eg.find_const(sel.children[1]) is Some(x) {
                  if eg.find_const(sel.children[2]) is Some(y) {
                    // iadd(select(c, x, y), z) = select(c, x+z, y+z)
                    let x_plus_z = eg.add_const(x + z)
                    let y_plus_z = eg.add_const(y + z)
                    let new_select = eg.add({
                      op: Select,
                      children: [sel.children[0], x_plus_z, y_plus_z],
                    })
                    let new_id = eg.merge(class_id, new_select)
                    changed = new_id != class_id || changed
                  }
                }
              }
            }
          }
          // Also check the symmetric case: iadd(z, select(c, x, y))
          if eg.find_const(node.children[0]) is Some(z) {
            for sel in eg.get_nodes(node.children[1]) {
              if sel.op is Select && sel.children.length() == 3 {
                if eg.find_const(sel.children[1]) is Some(x) {
                  if eg.find_const(sel.children[2]) is Some(y) {
                    let x_plus_z = eg.add_const(x + z)
                    let y_plus_z = eg.add_const(y + z)
                    let new_select = eg.add({
                      op: Select,
                      children: [sel.children[0], x_plus_z, y_plus_z],
                    })
                    let new_id = eg.merge(class_id, new_select)
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
