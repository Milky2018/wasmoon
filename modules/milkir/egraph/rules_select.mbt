// Select instruction optimization rules
// ============================================================================

// Note: Condition codes (CC_SLT, CC_SLE, etc.) are defined in rules_icmp.mbt

///|
/// select(_, x, x) = x
/// When both branches are the same, the condition doesn't matter
fn rule_select_same() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select &&
          node.children.length() == 3 &&
          eg.equiv(node.children[1], node.children[2]) {
          changed = eg.subsume_changed(class_id, node.children[1]) || changed
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
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select &&
          node.children.length() == 3 &&
          eg.find_const(node.children[1]) is Some(1L) &&
          eg.find_const(node.children[2]) is Some(0L) {
          // Check if condition is an icmp
          for cond_node in eg.get_nodes(node.children[0]) {
            if cond_node.op is Icmp(_) ||
              cond_node.op is Eq ||
              cond_node.op is Ne {
              // select(icmp, 1, 0) = icmp (the icmp already produces 0/1)
              changed = eg.merge_changed(class_id, node.children[0]) || changed
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
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select &&
          node.children.length() == 3 &&
          eg.find_const(node.children[1]) is Some(0L) &&
          eg.find_const(node.children[2]) is Some(nz) &&
          nz != 0L {
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
                changed = eg.merge_changed(class_id, new_icmp) || changed
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
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let d = node.children[0]
          let a = node.children[1]
          // Check if false branch is also a select with same condition
          for inner in eg.get_nodes(node.children[2]) {
            if inner.op is Select &&
              inner.children.length() == 3 &&
              eg.equiv(inner.children[0], d) {
              // select(d, a, select(d, _, y)) = select(d, a, y)
              let new_select = eg.add({
                op: Select,
                children: [d, a, inner.children[2]],
              })
              changed = eg.subsume_changed(class_id, new_select) || changed
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
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let d = node.children[0]
          let a = node.children[2]
          // Check if true branch is also a select with same condition
          for inner in eg.get_nodes(node.children[1]) {
            if inner.op is Select &&
              inner.children.length() == 3 &&
              eg.equiv(inner.children[0], d) {
              // select(d, select(d, x, _), a) = select(d, x, a)
              let new_select = eg.add({
                op: Select,
                children: [d, inner.children[1], a],
              })
              changed = eg.subsume_changed(class_id, new_select) || changed
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
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          // Check if condition is uextend of an icmp
          for cond_node in eg.get_nodes(node.children[0]) {
            if cond_node.op is Uextend(_, _) && cond_node.children.length() == 1 {
              // Check if inner is an icmp
              for inner in eg.get_nodes(cond_node.children[0]) {
                if inner.op is Icmp(_) || inner.op is Eq || inner.op is Ne {
                  let new_select = eg.add({
                    op: Select,
                    children: [
                      cond_node.children[0],
                      node.children[1],
                      node.children[2],
                    ],
                  })
                  changed = eg.merge_changed(class_id, new_select) || changed
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
/// iadd(select(c, x, y), z) = select(c, x+z, y+z) when x, y, z are constants
/// Fold add into select branches
fn rule_add_select_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          // Check if z (second operand) is constant
          if eg.find_const(node.children[1]) is Some(z) {
            // Check if first operand is select
            for sel in eg.get_nodes(node.children[0]) {
              if sel.op is Select &&
                sel.children.length() == 3 &&
                eg.find_const(sel.children[1]) is Some(x) &&
                eg.find_const(sel.children[2]) is Some(y) {
                // iadd(select(c, x, y), z) = select(c, x+z, y+z)
                let x_plus_z = eg.add_const(x + z)
                let y_plus_z = eg.add_const(y + z)
                let new_select = eg.add({
                  op: Select,
                  children: [sel.children[0], x_plus_z, y_plus_z],
                })
                changed = eg.subsume_changed(class_id, new_select) || changed
              }
            }
          }
          // Also check the symmetric case: iadd(z, select(c, x, y))
          if eg.find_const(node.children[0]) is Some(z) {
            for sel in eg.get_nodes(node.children[1]) {
              if sel.op is Select &&
                sel.children.length() == 3 &&
                eg.find_const(sel.children[1]) is Some(x) &&
                eg.find_const(sel.children[2]) is Some(y) {
                let x_plus_z = eg.add_const(x + z)
                let y_plus_z = eg.add_const(y + z)
                let new_select = eg.add({
                  op: Select,
                  children: [sel.children[0], x_plus_z, y_plus_z],
                })
                changed = eg.subsume_changed(class_id, new_select) || changed
              }
            }
          }
        }
      }
      changed
    },
  }
}

// ============================================================================
// Select-to-min/max rules
// ============================================================================

///|
/// select(sgt(x, y), x, y) = smax(x, y)
/// select(sge(x, y), x, y) = smax(x, y)
fn rule_select_to_smax() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let cond = node.children[0]
          let true_val = node.children[1]
          let false_val = node.children[2]
          // Check if condition is icmp(sgt/sge, x, y) and select(cond, x, y)
          for cond_node in eg.get_nodes(cond) {
            if cond_node.op is Icmp(cc) &&
              (cc == CC_SGT || cc == CC_SGE) &&
              cond_node.children.length() == 2 {
              let x = cond_node.children[0]
              let y = cond_node.children[1]
              // select(sgt(x, y), x, y) = smax(x, y)
              if eg.equiv(true_val, x) && eg.equiv(false_val, y) {
                let smax = eg.add({ op: Smax, children: [x, y], })
                changed = eg.merge_changed(class_id, smax) || changed
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
/// select(slt(x, y), x, y) = smin(x, y)
/// select(sle(x, y), x, y) = smin(x, y)
fn rule_select_to_smin() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let cond = node.children[0]
          let true_val = node.children[1]
          let false_val = node.children[2]
          // Check if condition is icmp(slt/sle, x, y) and select(cond, x, y)
          for cond_node in eg.get_nodes(cond) {
            if cond_node.op is Icmp(cc) &&
              (cc == CC_SLT || cc == CC_SLE) &&
              cond_node.children.length() == 2 {
              let x = cond_node.children[0]
              let y = cond_node.children[1]
              // select(slt(x, y), x, y) = smin(x, y)
              if eg.equiv(true_val, x) && eg.equiv(false_val, y) {
                let smin = eg.add({ op: Smin, children: [x, y], })
                changed = eg.merge_changed(class_id, smin) || changed
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
/// select(ugt(x, y), x, y) = umax(x, y)
/// select(uge(x, y), x, y) = umax(x, y)
fn rule_select_to_umax() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let cond = node.children[0]
          let true_val = node.children[1]
          let false_val = node.children[2]
          // Check if condition is icmp(ugt/uge, x, y) and select(cond, x, y)
          for cond_node in eg.get_nodes(cond) {
            if cond_node.op is Icmp(cc) &&
              (cc == CC_UGT || cc == CC_UGE) &&
              cond_node.children.length() == 2 {
              let x = cond_node.children[0]
              let y = cond_node.children[1]
              // select(ugt(x, y), x, y) = umax(x, y)
              if eg.equiv(true_val, x) && eg.equiv(false_val, y) {
                let umax = eg.add({ op: Umax, children: [x, y], })
                changed = eg.merge_changed(class_id, umax) || changed
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
/// select(ult(x, y), x, y) = umin(x, y)
/// select(ule(x, y), x, y) = umin(x, y)
fn rule_select_to_umin() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let cond = node.children[0]
          let true_val = node.children[1]
          let false_val = node.children[2]
          // Check if condition is icmp(ult/ule, x, y) and select(cond, x, y)
          for cond_node in eg.get_nodes(cond) {
            if cond_node.op is Icmp(cc) &&
              (cc == CC_ULT || cc == CC_ULE) &&
              cond_node.children.length() == 2 {
              let x = cond_node.children[0]
              let y = cond_node.children[1]
              // select(ult(x, y), x, y) = umin(x, y)
              if eg.equiv(true_val, x) && eg.equiv(false_val, y) {
                let umin = eg.add({ op: Umin, children: [x, y], })
                changed = eg.merge_changed(class_id, umin) || changed
              }
            }
          }
        }
      }
      changed
    },
  }
}

// ============================================================================
// Swapped select-to-min/max rules
// select(slt(x, y), y, x) = smax(x, y) etc.
// ============================================================================

///|
/// select(slt(x, y), y, x) = smax(x, y)
/// select(sle(x, y), y, x) = smax(x, y)
fn rule_select_to_smax_swapped() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let cond = node.children[0]
          let true_val = node.children[1]
          let false_val = node.children[2]
          for cond_node in eg.get_nodes(cond) {
            if cond_node.op is Icmp(cc) &&
              (cc == CC_SLT || cc == CC_SLE) &&
              cond_node.children.length() == 2 {
              let x = cond_node.children[0]
              let y = cond_node.children[1]
              // select(slt(x, y), y, x) = smax(x, y)
              if eg.equiv(true_val, y) && eg.equiv(false_val, x) {
                let smax = eg.add({ op: Smax, children: [x, y], })
                changed = eg.merge_changed(class_id, smax) || changed
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
/// select(sgt(x, y), y, x) = smin(x, y)
/// select(sge(x, y), y, x) = smin(x, y)
fn rule_select_to_smin_swapped() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let cond = node.children[0]
          let true_val = node.children[1]
          let false_val = node.children[2]
          for cond_node in eg.get_nodes(cond) {
            if cond_node.op is Icmp(cc) &&
              (cc == CC_SGT || cc == CC_SGE) &&
              cond_node.children.length() == 2 {
              let x = cond_node.children[0]
              let y = cond_node.children[1]
              // select(sgt(x, y), y, x) = smin(x, y)
              if eg.equiv(true_val, y) && eg.equiv(false_val, x) {
                let smin = eg.add({ op: Smin, children: [x, y], })
                changed = eg.merge_changed(class_id, smin) || changed
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
/// select(ult(x, y), y, x) = umax(x, y)
/// select(ule(x, y), y, x) = umax(x, y)
fn rule_select_to_umax_swapped() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let cond = node.children[0]
          let true_val = node.children[1]
          let false_val = node.children[2]
          for cond_node in eg.get_nodes(cond) {
            if cond_node.op is Icmp(cc) &&
              (cc == CC_ULT || cc == CC_ULE) &&
              cond_node.children.length() == 2 {
              let x = cond_node.children[0]
              let y = cond_node.children[1]
              // select(ult(x, y), y, x) = umax(x, y)
              if eg.equiv(true_val, y) && eg.equiv(false_val, x) {
                let umax = eg.add({ op: Umax, children: [x, y], })
                changed = eg.merge_changed(class_id, umax) || changed
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
/// select(ugt(x, y), y, x) = umin(x, y)
/// select(uge(x, y), y, x) = umin(x, y)
fn rule_select_to_umin_swapped() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let cond = node.children[0]
          let true_val = node.children[1]
          let false_val = node.children[2]
          for cond_node in eg.get_nodes(cond) {
            if cond_node.op is Icmp(cc) &&
              (cc == CC_UGT || cc == CC_UGE) &&
              cond_node.children.length() == 2 {
              let x = cond_node.children[0]
              let y = cond_node.children[1]
              // select(ugt(x, y), y, x) = umin(x, y)
              if eg.equiv(true_val, y) && eg.equiv(false_val, x) {
                let umin = eg.add({ op: Umin, children: [x, y], })
                changed = eg.merge_changed(class_id, umin) || changed
              }
            }
          }
        }
      }
      changed
    },
  }
}

// ============================================================================
// Select-to-iabs rules
// ============================================================================

///|
/// select(sgt(x, 0), x, -x) = iabs(x)
/// select(sge(x, 0), x, -x) = iabs(x)
fn rule_select_to_iabs_positive() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let cond = node.children[0]
          let true_val = node.children[1]
          let false_val = node.children[2]
          for cond_node in eg.get_nodes(cond) {
            if cond_node.op is Icmp(cc) &&
              (cc == CC_SGT || cc == CC_SGE) &&
              cond_node.children.length() == 2 {
              let x = cond_node.children[0]
              // Check if comparing with 0
              if eg.find_const(cond_node.children[1]) is Some(0L) &&
                eg.equiv(true_val, x) {
                for neg_node in eg.get_nodes(false_val) {
                  if neg_node.op is Neg &&
                    neg_node.children.length() == 1 &&
                    eg.equiv(neg_node.children[0], x) {
                    let iabs = eg.add({ op: Iabs, children: [x], })
                    changed = eg.subsume_changed(class_id, iabs) || changed
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
/// select(slt(x, 0), -x, x) = iabs(x)
/// select(sle(x, 0), -x, x) = iabs(x)
fn rule_select_to_iabs_negative() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          let cond = node.children[0]
          let true_val = node.children[1]
          let false_val = node.children[2]
          for cond_node in eg.get_nodes(cond) {
            if cond_node.op is Icmp(cc) &&
              (cc == CC_SLT || cc == CC_SLE) &&
              cond_node.children.length() == 2 {
              let x = cond_node.children[0]
              // Check if comparing with 0
              if eg.find_const(cond_node.children[1]) is Some(0L) &&
                eg.equiv(false_val, x) {
                for neg_node in eg.get_nodes(true_val) {
                  if neg_node.op is Neg &&
                    neg_node.children.length() == 1 &&
                    eg.equiv(neg_node.children[0], x) {
                    let iabs = eg.add({ op: Iabs, children: [x], })
                    changed = eg.subsume_changed(class_id, iabs) || changed
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

// ============================================================================
// Min/max comparison rules
// ============================================================================

///|
/// sgt(smin(x, y), x) = 0  (min is never greater than x)
/// sgt(smin(x, y), y) = 0  (min is never greater than y)
fn rule_smin_never_greater() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Icmp(cc) && cc == CC_SGT && node.children.length() == 2 {
          let lhs = node.children[0]
          let rhs = node.children[1]
          // Check if lhs is smin(x, y) and rhs is x or y
          for min_node in eg.get_nodes(lhs) {
            if min_node.op is Smin && min_node.children.length() == 2 {
              let x = min_node.children[0]
              let y = min_node.children[1]
              if eg.equiv(rhs, x) || eg.equiv(rhs, y) {
                let zero = eg.add_const(0L)
                changed = eg.subsume_changed(class_id, zero) || changed
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
/// slt(x, smin(x, y)) = 0  (x is never less than min(x, y))
/// slt(x, smin(y, x)) = 0
fn rule_never_less_than_smin() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Icmp(cc) && cc == CC_SLT && node.children.length() == 2 {
          let lhs = node.children[0]
          let rhs = node.children[1]
          // Check if rhs is smin(x, y) and lhs is x or y
          for min_node in eg.get_nodes(rhs) {
            if min_node.op is Smin && min_node.children.length() == 2 {
              let x = min_node.children[0]
              let y = min_node.children[1]
              if eg.equiv(lhs, x) || eg.equiv(lhs, y) {
                let zero = eg.add_const(0L)
                changed = eg.subsume_changed(class_id, zero) || changed
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
/// ugt(umin(x, y), x) = 0  (min is never greater than x)
/// ugt(umin(x, y), y) = 0  (min is never greater than y)
fn rule_umin_never_greater() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Icmp(cc) && cc == CC_UGT && node.children.length() == 2 {
          let lhs = node.children[0]
          let rhs = node.children[1]
          // Check if lhs is umin(x, y) and rhs is x or y
          for min_node in eg.get_nodes(lhs) {
            if min_node.op is Umin && min_node.children.length() == 2 {
              let x = min_node.children[0]
              let y = min_node.children[1]
              if eg.equiv(rhs, x) || eg.equiv(rhs, y) {
                let zero = eg.add_const(0L)
                changed = eg.subsume_changed(class_id, zero) || changed
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
/// ult(x, umin(x, y)) = 0  (x is never less than min(x, y))
/// ult(x, umin(y, x)) = 0
fn rule_never_less_than_umin() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Icmp(cc) && cc == CC_ULT && node.children.length() == 2 {
          let lhs = node.children[0]
          let rhs = node.children[1]
          // Check if rhs is umin(x, y) and lhs is x or y
          for min_node in eg.get_nodes(rhs) {
            if min_node.op is Umin && min_node.children.length() == 2 {
              let x = min_node.children[0]
              let y = min_node.children[1]
              if eg.equiv(lhs, x) || eg.equiv(lhs, y) {
                let zero = eg.add_const(0L)
                changed = eg.subsume_changed(class_id, zero) || changed
              }
            }
          }
        }
      }
      changed
    },
  }
}
