// Integer comparison optimization rules

// IntCC constants: 0=eq, 1=ne, 2=slt, 3=sle, 4=sgt, 5=sge, 6=ult, 7=ule, 8=ugt, 9=uge

///|
const CC_EQ : Int = 0

///|
const CC_NE : Int = 1

///|
const CC_SLT : Int = 2

///|
const CC_SLE : Int = 3

///|
const CC_SGT : Int = 4

///|
const CC_SGE : Int = 5

///|
const CC_ULT : Int = 6

///|
const CC_ULE : Int = 7

///|
const CC_UGT : Int = 8

///|
const CC_UGE : Int = 9

///|
/// Get the complement of a comparison condition
fn intcc_complement(cc : Int) -> Int {
  match cc {
    0 => 1 // eq -> ne
    1 => 0 // ne -> eq
    2 => 5 // slt -> sge
    3 => 4 // sle -> sgt
    4 => 3 // sgt -> sle
    5 => 2 // sge -> slt
    6 => 9 // ult -> uge
    7 => 8 // ule -> ugt
    8 => 7 // ugt -> ule
    9 => 6 // uge -> ult
    _ => cc
  }
}

///|
/// Swap operands (reverse) of a comparison condition
fn intcc_swap(cc : Int) -> Int {
  match cc {
    0 => 0 // eq -> eq
    1 => 1 // ne -> ne
    2 => 4 // slt -> sgt
    3 => 5 // sle -> sge
    4 => 2 // sgt -> slt
    5 => 3 // sge -> sle
    6 => 8 // ult -> ugt
    7 => 9 // ule -> uge
    8 => 6 // ugt -> ult
    9 => 7 // uge -> ule
    _ => cc
  }
}

// ============================================================================
// Self-comparison rules: x cmp x
// ============================================================================

///|
/// eq(x, x) → 1
fn rule_eq_self() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Eq && node.children.length() == 2 {
          let left = eg.find(node.children[0])
          let right = eg.find(node.children[1])
          if left == right {
            let one = eg.add_const(1L)
            let new_id = eg.merge(class_id, one)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// ne(x, x) → 0
fn rule_ne_self() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ne && node.children.length() == 2 {
          let left = eg.find(node.children[0])
          let right = eg.find(node.children[1])
          if left == right {
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
/// icmp(cc, x, x) → 0 or 1 depending on cc
/// Strict inequalities (slt, sgt, ult, ugt) are false
/// Loose inequalities (sle, sge, ule, uge) are true
fn rule_icmp_self() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if node.children.length() == 2 {
              let left = eg.find(node.children[0])
              let right = eg.find(node.children[1])
              if left == right {
                // Strict inequalities are false, loose inequalities are true
                let result = match cc {
                  2 | 4 | 6 | 8 => 0L // slt, sgt, ult, ugt -> false
                  3 | 5 | 7 | 9 => 1L // sle, sge, ule, uge -> true
                  _ => continue
                }
                let const_node = eg.add_const(result)
                let new_id = eg.merge(class_id, const_node)
                changed = new_id != class_id || changed
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

// ============================================================================
// icmp-of-icmp rules
// ============================================================================

///|
/// ne(icmp(...), 0) → icmp(...)
/// e.g. ne(ugt(x, y), 0) == ugt(x, y)
fn rule_ne_icmp_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ne && node.children.length() == 2 {
          // Check if right is zero
          for right in eg.get_nodes(node.children[1]) {
            if right.op == Const(0L) {
              // Check if left is icmp (possibly through uextend)
              for left in eg.get_nodes(node.children[0]) {
                match left.op {
                  Icmp(_) => {
                    // ne(icmp(...), 0) = icmp(...)
                    let new_id = eg.merge(class_id, node.children[0])
                    changed = new_id != class_id || changed
                  }
                  Uextend(_, _) =>
                    if left.children.length() == 1 {
                      for inner in eg.get_nodes(left.children[0]) {
                        if inner.op is Icmp(_) {
                          // ne(uextend(icmp(...)), 0) = icmp(...)
                          let new_id = eg.merge(class_id, left.children[0])
                          changed = new_id != class_id || changed
                        }
                      }
                    }
                  _ => ()
                }
              }
            }
          }
          // Also check symmetric case: ne(0, icmp(...))
          for left in eg.get_nodes(node.children[0]) {
            if left.op == Const(0L) {
              for right in eg.get_nodes(node.children[1]) {
                match right.op {
                  Icmp(_) => {
                    let new_id = eg.merge(class_id, node.children[1])
                    changed = new_id != class_id || changed
                  }
                  Uextend(_, _) =>
                    if right.children.length() == 1 {
                      for inner in eg.get_nodes(right.children[0]) {
                        if inner.op is Icmp(_) {
                          let new_id = eg.merge(class_id, right.children[0])
                          changed = new_id != class_id || changed
                        }
                      }
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
/// eq(icmp(cc, x, y), 0) → icmp(complement(cc), x, y)
/// e.g. eq(ugt(x, y), 0) == ule(x, y)
fn rule_eq_icmp_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Eq && node.children.length() == 2 {
          // Check eq(icmp(...), 0)
          for right in eg.get_nodes(node.children[1]) {
            if right.op == Const(0L) {
              for left in eg.get_nodes(node.children[0]) {
                match left.op {
                  Icmp(cc) =>
                    if left.children.length() == 2 {
                      // eq(icmp(cc, x, y), 0) = icmp(complement(cc), x, y)
                      let new_node = eg.add({
                        op: Icmp(intcc_complement(cc)),
                        children: [left.children[0], left.children[1]],
                      })
                      let new_id = eg.merge(class_id, new_node)
                      changed = new_id != class_id || changed
                    }
                  Uextend(_, _) =>
                    if left.children.length() == 1 {
                      for inner in eg.get_nodes(left.children[0]) {
                        match inner.op {
                          Icmp(cc) =>
                            if inner.children.length() == 2 {
                              let new_node = eg.add({
                                op: Icmp(intcc_complement(cc)),
                                children: [inner.children[0], inner.children[1]],
                              })
                              let new_id = eg.merge(class_id, new_node)
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
          // Symmetric: eq(0, icmp(...))
          for left in eg.get_nodes(node.children[0]) {
            if left.op == Const(0L) {
              for right in eg.get_nodes(node.children[1]) {
                match right.op {
                  Icmp(cc) =>
                    if right.children.length() == 2 {
                      let new_node = eg.add({
                        op: Icmp(intcc_complement(cc)),
                        children: [right.children[0], right.children[1]],
                      })
                      let new_id = eg.merge(class_id, new_node)
                      changed = new_id != class_id || changed
                    }
                  Uextend(_, _) =>
                    if right.children.length() == 1 {
                      for inner in eg.get_nodes(right.children[0]) {
                        match inner.op {
                          Icmp(cc) =>
                            if inner.children.length() == 2 {
                              let new_node = eg.add({
                                op: Icmp(intcc_complement(cc)),
                                children: [inner.children[0], inner.children[1]],
                              })
                              let new_id = eg.merge(class_id, new_node)
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
        }
      }
      changed
    },
  }
}

///|
/// ne(icmp(cc, x, y), 1) → icmp(complement(cc), x, y)
/// e.g. ne(ugt(x, y), 1) == ule(x, y)
fn rule_ne_icmp_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ne && node.children.length() == 2 {
          for right in eg.get_nodes(node.children[1]) {
            if right.op == Const(1L) {
              for left in eg.get_nodes(node.children[0]) {
                match left.op {
                  Icmp(cc) =>
                    if left.children.length() == 2 {
                      let new_node = eg.add({
                        op: Icmp(intcc_complement(cc)),
                        children: [left.children[0], left.children[1]],
                      })
                      let new_id = eg.merge(class_id, new_node)
                      changed = new_id != class_id || changed
                    }
                  Uextend(_, _) =>
                    if left.children.length() == 1 {
                      for inner in eg.get_nodes(left.children[0]) {
                        match inner.op {
                          Icmp(cc) =>
                            if inner.children.length() == 2 {
                              let new_node = eg.add({
                                op: Icmp(intcc_complement(cc)),
                                children: [inner.children[0], inner.children[1]],
                              })
                              let new_id = eg.merge(class_id, new_node)
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
        }
      }
      changed
    },
  }
}

///|
/// eq(icmp(...), 1) → icmp(...)
/// e.g. eq(ugt(x, y), 1) == ugt(x, y)
fn rule_eq_icmp_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Eq && node.children.length() == 2 {
          for right in eg.get_nodes(node.children[1]) {
            if right.op == Const(1L) {
              for left in eg.get_nodes(node.children[0]) {
                match left.op {
                  Icmp(_) => {
                    let new_id = eg.merge(class_id, node.children[0])
                    changed = new_id != class_id || changed
                  }
                  Uextend(_, _) =>
                    if left.children.length() == 1 {
                      for inner in eg.get_nodes(left.children[0]) {
                        if inner.op is Icmp(_) {
                          let new_id = eg.merge(class_id, left.children[0])
                          changed = new_id != class_id || changed
                        }
                      }
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

// ============================================================================
// band(icmp, 1) simplification
// ============================================================================

///|
/// band(icmp(...), 1) → icmp(...)
/// Masking comparison result with 1 is a no-op
fn rule_band_icmp_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          // Check band(icmp(...), 1)
          for right in eg.get_nodes(node.children[1]) {
            if right.op == Const(1L) {
              for left in eg.get_nodes(node.children[0]) {
                match left.op {
                  Icmp(_) | Eq | Ne => {
                    let new_id = eg.merge(class_id, node.children[0])
                    changed = new_id != class_id || changed
                  }
                  Uextend(_, _) =>
                    if left.children.length() == 1 {
                      for inner in eg.get_nodes(left.children[0]) {
                        if inner.op is Icmp(_) ||
                          inner.op is Eq ||
                          inner.op is Ne {
                          // Keep the uextend
                          let new_id = eg.merge(class_id, node.children[0])
                          changed = new_id != class_id || changed
                        }
                      }
                    }
                  _ => ()
                }
              }
            }
          }
          // Symmetric: band(1, icmp(...))
          for left in eg.get_nodes(node.children[0]) {
            if left.op == Const(1L) {
              for right in eg.get_nodes(node.children[1]) {
                match right.op {
                  Icmp(_) | Eq | Ne => {
                    let new_id = eg.merge(class_id, node.children[1])
                    changed = new_id != class_id || changed
                  }
                  Uextend(_, _) =>
                    if right.children.length() == 1 {
                      for inner in eg.get_nodes(right.children[0]) {
                        if inner.op is Icmp(_) ||
                          inner.op is Eq ||
                          inner.op is Ne {
                          let new_id = eg.merge(class_id, node.children[1])
                          changed = new_id != class_id || changed
                        }
                      }
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

// ============================================================================
// Comparisons against zero
// ============================================================================

///|
/// ult(x, 0) → false
fn rule_ult_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_ULT && node.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op == Const(0L) {
                  let zero = eg.add_const(0L)
                  let new_id = eg.merge(class_id, zero)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// ule(x, 0) → eq(x, 0)
fn rule_ule_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_ULE && node.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op == Const(0L) {
                  // ule(x, 0) = eq(x, 0)
                  let new_node = eg.add({
                    op: Eq,
                    children: [node.children[0], node.children[1]],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// ugt(x, 0) → ne(x, 0)
fn rule_ugt_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_UGT && node.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op == Const(0L) {
                  // ugt(x, 0) = ne(x, 0)
                  let new_node = eg.add({
                    op: Ne,
                    children: [node.children[0], node.children[1]],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// uge(x, 0) → true
fn rule_uge_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_UGE && node.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op == Const(0L) {
                  let one = eg.add_const(1L)
                  let new_id = eg.merge(class_id, one)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

// ============================================================================
// Prefer comparing against zero
// ============================================================================

///|
/// uge(x, 1) → ne(x, 0)
fn rule_uge_one_to_ne_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_UGE && node.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op == Const(1L) {
                  // uge(x, 1) = ne(x, 0)
                  let zero = eg.add_const(0L)
                  let new_node = eg.add({
                    op: Ne,
                    children: [node.children[0], zero],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// ult(x, 1) → eq(x, 0)
fn rule_ult_one_to_eq_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_ULT && node.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op == Const(1L) {
                  // ult(x, 1) = eq(x, 0)
                  let zero = eg.add_const(0L)
                  let new_node = eg.add({
                    op: Eq,
                    children: [node.children[0], zero],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// sge(x, 1) → sgt(x, 0)
fn rule_sge_one_to_sgt_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_SGE && node.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op == Const(1L) {
                  // sge(x, 1) = sgt(x, 0)
                  let zero = eg.add_const(0L)
                  let new_node = eg.add({
                    op: Icmp(CC_SGT),
                    children: [node.children[0], zero],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// slt(x, 1) → sle(x, 0)
fn rule_slt_one_to_sle_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_SLT && node.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op == Const(1L) {
                  // slt(x, 1) = sle(x, 0)
                  let zero = eg.add_const(0L)
                  let new_node = eg.add({
                    op: Icmp(CC_SLE),
                    children: [node.children[0], zero],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// sgt(x, -1) → sge(x, 0)
fn rule_sgt_neg_one_to_sge_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_SGT && node.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op == Const(-1L) {
                  // sgt(x, -1) = sge(x, 0)
                  let zero = eg.add_const(0L)
                  let new_node = eg.add({
                    op: Icmp(CC_SGE),
                    children: [node.children[0], zero],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// sle(x, -1) → slt(x, 0)
fn rule_sle_neg_one_to_slt_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_SLE && node.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op == Const(-1L) {
                  // sle(x, -1) = slt(x, 0)
                  let zero = eg.add_const(0L)
                  let new_node = eg.add({
                    op: Icmp(CC_SLT),
                    children: [node.children[0], zero],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

// ============================================================================
// Add/sub comparison simplification
// ============================================================================

///|
/// eq(a+k, b+k) → eq(a, b)
/// Adding same value to both sides doesn't change equality
fn rule_eq_add_cancel() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Eq && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Add && left.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op is Add && right.children.length() == 2 {
                  // Check if any operand matches
                  let l0 = eg.find(left.children[0])
                  let l1 = eg.find(left.children[1])
                  let r0 = eg.find(right.children[0])
                  let r1 = eg.find(right.children[1])
                  // eq(a+k, b+k) -> eq(a, b)
                  if l1 == r1 {
                    let new_node = eg.add({
                      op: Eq,
                      children: [left.children[0], right.children[0]],
                    })
                    let new_id = eg.merge(class_id, new_node)
                    changed = new_id != class_id || changed
                  } else if l1 == r0 {
                    let new_node = eg.add({
                      op: Eq,
                      children: [left.children[0], right.children[1]],
                    })
                    let new_id = eg.merge(class_id, new_node)
                    changed = new_id != class_id || changed
                  } else if l0 == r1 {
                    let new_node = eg.add({
                      op: Eq,
                      children: [left.children[1], right.children[0]],
                    })
                    let new_id = eg.merge(class_id, new_node)
                    changed = new_id != class_id || changed
                  } else if l0 == r0 {
                    let new_node = eg.add({
                      op: Eq,
                      children: [left.children[1], right.children[1]],
                    })
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

///|
/// ne(a+k, b+k) → ne(a, b)
fn rule_ne_add_cancel() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ne && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Add && left.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op is Add && right.children.length() == 2 {
                  let l0 = eg.find(left.children[0])
                  let l1 = eg.find(left.children[1])
                  let r0 = eg.find(right.children[0])
                  let r1 = eg.find(right.children[1])
                  if l1 == r1 {
                    let new_node = eg.add({
                      op: Ne,
                      children: [left.children[0], right.children[0]],
                    })
                    let new_id = eg.merge(class_id, new_node)
                    changed = new_id != class_id || changed
                  } else if l1 == r0 {
                    let new_node = eg.add({
                      op: Ne,
                      children: [left.children[0], right.children[1]],
                    })
                    let new_id = eg.merge(class_id, new_node)
                    changed = new_id != class_id || changed
                  } else if l0 == r1 {
                    let new_node = eg.add({
                      op: Ne,
                      children: [left.children[1], right.children[0]],
                    })
                    let new_id = eg.merge(class_id, new_node)
                    changed = new_id != class_id || changed
                  } else if l0 == r0 {
                    let new_node = eg.add({
                      op: Ne,
                      children: [left.children[1], right.children[1]],
                    })
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

// ============================================================================
// XOR comparison simplification
// ============================================================================

///|
/// eq(x, bxor(x, y)) → eq(y, 0)
fn rule_eq_xor_self() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Eq && node.children.length() == 2 {
          let left_id = eg.find(node.children[0])
          for right in eg.get_nodes(node.children[1]) {
            if right.op is Xor && right.children.length() == 2 {
              let r0 = eg.find(right.children[0])
              let r1 = eg.find(right.children[1])
              if left_id == r0 {
                // eq(x, xor(x, y)) = eq(y, 0)
                let zero = eg.add_const(0L)
                let new_node = eg.add({
                  op: Eq,
                  children: [right.children[1], zero],
                })
                let new_id = eg.merge(class_id, new_node)
                changed = new_id != class_id || changed
              } else if left_id == r1 {
                // eq(x, xor(y, x)) = eq(y, 0)
                let zero = eg.add_const(0L)
                let new_node = eg.add({
                  op: Eq,
                  children: [right.children[0], zero],
                })
                let new_id = eg.merge(class_id, new_node)
                changed = new_id != class_id || changed
              }
            }
          }
          // Symmetric case
          let right_id = eg.find(node.children[1])
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Xor && left.children.length() == 2 {
              let l0 = eg.find(left.children[0])
              let l1 = eg.find(left.children[1])
              if right_id == l0 {
                let zero = eg.add_const(0L)
                let new_node = eg.add({
                  op: Eq,
                  children: [left.children[1], zero],
                })
                let new_id = eg.merge(class_id, new_node)
                changed = new_id != class_id || changed
              } else if right_id == l1 {
                let zero = eg.add_const(0L)
                let new_node = eg.add({
                  op: Eq,
                  children: [left.children[0], zero],
                })
                let new_id = eg.merge(class_id, new_node)
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
/// ne(x, bxor(x, y)) → ne(y, 0)
fn rule_ne_xor_self() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ne && node.children.length() == 2 {
          let left_id = eg.find(node.children[0])
          for right in eg.get_nodes(node.children[1]) {
            if right.op is Xor && right.children.length() == 2 {
              let r0 = eg.find(right.children[0])
              let r1 = eg.find(right.children[1])
              if left_id == r0 {
                let zero = eg.add_const(0L)
                let new_node = eg.add({
                  op: Ne,
                  children: [right.children[1], zero],
                })
                let new_id = eg.merge(class_id, new_node)
                changed = new_id != class_id || changed
              } else if left_id == r1 {
                let zero = eg.add_const(0L)
                let new_node = eg.add({
                  op: Ne,
                  children: [right.children[0], zero],
                })
                let new_id = eg.merge(class_id, new_node)
                changed = new_id != class_id || changed
              }
            }
          }
          // Symmetric case
          let right_id = eg.find(node.children[1])
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Xor && left.children.length() == 2 {
              let l0 = eg.find(left.children[0])
              let l1 = eg.find(left.children[1])
              if right_id == l0 {
                let zero = eg.add_const(0L)
                let new_node = eg.add({
                  op: Ne,
                  children: [left.children[1], zero],
                })
                let new_id = eg.merge(class_id, new_node)
                changed = new_id != class_id || changed
              } else if right_id == l1 {
                let zero = eg.add_const(0L)
                let new_node = eg.add({
                  op: Ne,
                  children: [left.children[0], zero],
                })
                let new_id = eg.merge(class_id, new_node)
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

// ============================================================================
// Subtraction comparison
// ============================================================================

///|
/// ugt(x - y, x) → ugt(y, x)
/// Unsigned overflow detection pattern
fn rule_ugt_sub_self() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_UGT && node.children.length() == 2 {
              let right_id = eg.find(node.children[1])
              for left in eg.get_nodes(node.children[0]) {
                if left.op is Sub && left.children.length() == 2 {
                  let sub_left = eg.find(left.children[0])
                  if sub_left == right_id {
                    // ugt(x - y, x) = ugt(y, x)
                    let new_node = eg.add({
                      op: Icmp(CC_UGT),
                      children: [left.children[1], node.children[1]],
                    })
                    let new_id = eg.merge(class_id, new_node)
                    changed = new_id != class_id || changed
                  }
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// ule(x - y, x) → ule(y, x)
fn rule_ule_sub_self() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_ULE && node.children.length() == 2 {
              let right_id = eg.find(node.children[1])
              for left in eg.get_nodes(node.children[0]) {
                if left.op is Sub && left.children.length() == 2 {
                  let sub_left = eg.find(left.children[0])
                  if sub_left == right_id {
                    // ule(x - y, x) = ule(y, x)
                    let new_node = eg.add({
                      op: Icmp(CC_ULE),
                      children: [left.children[1], node.children[1]],
                    })
                    let new_id = eg.merge(class_id, new_node)
                    changed = new_id != class_id || changed
                  }
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

// ============================================================================
// bnot comparison swap
// ============================================================================

///|
/// ult(bnot(x), bnot(y)) → ugt(x, y)
fn rule_ult_bnot_swap() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_ULT && node.children.length() == 2 {
              for left in eg.get_nodes(node.children[0]) {
                if left.op is Bnot && left.children.length() == 1 {
                  for right in eg.get_nodes(node.children[1]) {
                    if right.op is Bnot && right.children.length() == 1 {
                      // ult(bnot(x), bnot(y)) = ugt(x, y)
                      let new_node = eg.add({
                        op: Icmp(CC_UGT),
                        children: [left.children[0], right.children[0]],
                      })
                      let new_id = eg.merge(class_id, new_node)
                      changed = new_id != class_id || changed
                    }
                  }
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// slt(bnot(x), bnot(y)) → sgt(x, y)
fn rule_slt_bnot_swap() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_SLT && node.children.length() == 2 {
              for left in eg.get_nodes(node.children[0]) {
                if left.op is Bnot && left.children.length() == 1 {
                  for right in eg.get_nodes(node.children[1]) {
                    if right.op is Bnot && right.children.length() == 1 {
                      // slt(bnot(x), bnot(y)) = sgt(x, y)
                      let new_node = eg.add({
                        op: Icmp(CC_SGT),
                        children: [left.children[0], right.children[0]],
                      })
                      let new_id = eg.merge(class_id, new_node)
                      changed = new_id != class_id || changed
                    }
                  }
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

// ============================================================================
// XOR of comparisons → ne
// ============================================================================

///|
/// xor(sgt(x, y), slt(x, y)) → ne(x, y)
/// a < b ^^ a > b => (a ≠ b)
fn rule_xor_cmp_to_ne() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Icmp(cc1) =>
                if left.children.length() == 2 {
                  for right in eg.get_nodes(node.children[1]) {
                    match right.op {
                      Icmp(cc2) =>
                        if right.children.length() == 2 {
                          let l0 = eg.find(left.children[0])
                          let l1 = eg.find(left.children[1])
                          let r0 = eg.find(right.children[0])
                          let r1 = eg.find(right.children[1])
                          // Check if one is lt and other is gt on same operands
                          let is_lt_gt = (cc1 == CC_SLT && cc2 == CC_SGT) ||
                            (cc1 == CC_SGT && cc2 == CC_SLT) ||
                            (cc1 == CC_ULT && cc2 == CC_UGT) ||
                            (cc1 == CC_UGT && cc2 == CC_ULT)
                          // Same operands in same order
                          if is_lt_gt && l0 == r0 && l1 == r1 {
                            let new_node = eg.add({
                              op: Ne,
                              children: [left.children[0], left.children[1]],
                            })
                            let new_id = eg.merge(class_id, new_node)
                            changed = new_id != class_id || changed
                          }
                          // Swapped operands (e.g., sgt(x,y) xor sgt(y,x))
                          let both_same = (cc1 == CC_SGT && cc2 == CC_SGT) ||
                            (cc1 == CC_SLT && cc2 == CC_SLT) ||
                            (cc1 == CC_UGT && cc2 == CC_UGT) ||
                            (cc1 == CC_ULT && cc2 == CC_ULT)
                          if both_same && l0 == r1 && l1 == r0 {
                            let new_node = eg.add({
                              op: Ne,
                              children: [left.children[0], left.children[1]],
                            })
                            let new_id = eg.merge(class_id, new_node)
                            changed = new_id != class_id || changed
                          }
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

// ============================================================================
// AND of contradictory comparisons → 0
// ============================================================================

///|
/// band(sgt(x, y), slt(x, y)) → 0
/// a < b && a > b = false
fn rule_band_contradictory_cmp() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Icmp(cc1) =>
                if left.children.length() == 2 {
                  for right in eg.get_nodes(node.children[1]) {
                    match right.op {
                      Icmp(cc2) =>
                        if right.children.length() == 2 {
                          let l0 = eg.find(left.children[0])
                          let l1 = eg.find(left.children[1])
                          let r0 = eg.find(right.children[0])
                          let r1 = eg.find(right.children[1])
                          // Same operands in same order
                          if l0 == r0 && l1 == r1 {
                            // Check for contradictory pairs
                            let is_contradictory = (
                                cc1 == CC_SGT && cc2 == CC_SLT
                              ) ||
                              (cc1 == CC_SLT && cc2 == CC_SGT) ||
                              (cc1 == CC_UGT && cc2 == CC_ULT) ||
                              (cc1 == CC_ULT && cc2 == CC_UGT)
                            if is_contradictory {
                              let zero = eg.add_const(0L)
                              let new_id = eg.merge(class_id, zero)
                              changed = new_id != class_id || changed
                            }
                          }
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

// ============================================================================
// Comparison reassociation with constants
// ============================================================================

///|
/// eq(x + k1, k2) → eq(x, k2 - k1)
fn rule_eq_add_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Eq && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(k2) {
            for left in eg.get_nodes(node.children[0]) {
              if left.op is Add && left.children.length() == 2 {
                if eg.find_const(left.children[1]) is Some(k1) {
                  // eq(x + k1, k2) = eq(x, k2 - k1)
                  let diff = eg.add_const(k2 - k1)
                  let new_node = eg.add({
                    op: Eq,
                    children: [left.children[0], diff],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
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
/// ne(x + k1, k2) → ne(x, k2 - k1)
fn rule_ne_add_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ne && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(k2) {
            for left in eg.get_nodes(node.children[0]) {
              if left.op is Add && left.children.length() == 2 {
                if eg.find_const(left.children[1]) is Some(k1) {
                  // ne(x + k1, k2) = ne(x, k2 - k1)
                  let diff = eg.add_const(k2 - k1)
                  let new_node = eg.add({
                    op: Ne,
                    children: [left.children[0], diff],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
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
/// eq(x - k1, k2) → eq(x, k2 + k1)
fn rule_eq_sub_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Eq && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(k2) {
            for left in eg.get_nodes(node.children[0]) {
              if left.op is Sub && left.children.length() == 2 {
                if eg.find_const(left.children[1]) is Some(k1) {
                  // eq(x - k1, k2) = eq(x, k2 + k1)
                  let sum = eg.add_const(k2 + k1)
                  let new_node = eg.add({
                    op: Eq,
                    children: [left.children[0], sum],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
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
/// ne(x - k1, k2) → ne(x, k2 + k1)
fn rule_ne_sub_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ne && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(k2) {
            for left in eg.get_nodes(node.children[0]) {
              if left.op is Sub && left.children.length() == 2 {
                if eg.find_const(left.children[1]) is Some(k1) {
                  // ne(x - k1, k2) = ne(x, k2 + k1)
                  let sum = eg.add_const(k2 + k1)
                  let new_node = eg.add({
                    op: Ne,
                    children: [left.children[0], sum],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
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
// Select of uextend of icmp
// ============================================================================

///|
/// select(uextend(icmp(...)), x, y) → select(icmp(...), x, y)
fn rule_select_uextend_icmp() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          for cond in eg.get_nodes(node.children[0]) {
            match cond.op {
              Uextend(_, _) =>
                if cond.children.length() == 1 {
                  for inner in eg.get_nodes(cond.children[0]) {
                    if inner.op is Icmp(_) || inner.op is Eq || inner.op is Ne {
                      // select(uextend(icmp(...)), x, y) = select(icmp(...), x, y)
                      let new_node = eg.add({
                        op: Select,
                        children: [
                          cond.children[0],
                          node.children[1],
                          node.children[2],
                        ],
                      })
                      let new_id = eg.merge(class_id, new_node)
                      changed = new_id != class_id || changed
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

// ============================================================================
// Canonicalization: push constants to the right
// ============================================================================

///|
/// icmp(cc, k, x) → icmp(swap_cc, x, k) when k is a constant
/// Canonical form: push constants to the right
fn rule_icmp_swap_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if node.children.length() == 2 {
              // Check if left is constant and right is not
              if eg.find_const(node.children[0]) is Some(_) {
                if eg.find_const(node.children[1]) is None {
                  // icmp(cc, k, x) = icmp(swap_cc, x, k)
                  let new_node = eg.add({
                    op: Icmp(intcc_swap(cc)),
                    children: [node.children[1], node.children[0]],
                  })
                  let new_id = eg.subsume(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          Eq =>
            if node.children.length() == 2 {
              // eq(k, x) = eq(x, k)
              if eg.find_const(node.children[0]) is Some(_) {
                if eg.find_const(node.children[1]) is None {
                  let new_node = eg.add({
                    op: Eq,
                    children: [node.children[1], node.children[0]],
                  })
                  let new_id = eg.subsume(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          Ne =>
            if node.children.length() == 2 {
              // ne(k, x) = ne(x, k)
              if eg.find_const(node.children[0]) is Some(_) {
                if eg.find_const(node.children[1]) is None {
                  let new_node = eg.add({
                    op: Ne,
                    children: [node.children[1], node.children[0]],
                  })
                  let new_id = eg.subsume(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// eq(x + K1, y + K2) → eq(x, y + (K2 - K1))
fn rule_eq_add_add_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Eq && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Add && left.children.length() == 2 {
              if eg.find_const(left.children[1]) is Some(k1) {
                for right in eg.get_nodes(node.children[1]) {
                  if right.op is Add && right.children.length() == 2 {
                    if eg.find_const(right.children[1]) is Some(k2) {
                      // eq(x + K1, y + K2) = eq(x, y + (K2 - K1))
                      let diff = eg.add_const(k2 - k1)
                      let y_plus_diff = eg.add_add(right.children[0], diff)
                      let new_node = eg.add({
                        op: Eq,
                        children: [left.children[0], y_plus_diff],
                      })
                      let new_id = eg.merge(class_id, new_node)
                      changed = new_id != class_id || changed
                    }
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
/// ne(x + K1, y + K2) → ne(x, y + (K2 - K1))
fn rule_ne_add_add_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ne && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Add && left.children.length() == 2 {
              if eg.find_const(left.children[1]) is Some(k1) {
                for right in eg.get_nodes(node.children[1]) {
                  if right.op is Add && right.children.length() == 2 {
                    if eg.find_const(right.children[1]) is Some(k2) {
                      // ne(x + K1, y + K2) = ne(x, y + (K2 - K1))
                      let diff = eg.add_const(k2 - k1)
                      let y_plus_diff = eg.add_add(right.children[0], diff)
                      let new_node = eg.add({
                        op: Ne,
                        children: [left.children[0], y_plus_diff],
                      })
                      let new_id = eg.merge(class_id, new_node)
                      changed = new_id != class_id || changed
                    }
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
// Type-aware comparison rules (requires type information)
// These rules use type bounds (UMAX, SMIN, SMAX) for optimization
// ============================================================================

///|
/// ugt(x, UMAX) → false
/// Nothing can be greater than the maximum unsigned value
fn rule_ugt_umax() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_UGT && node.children.length() == 2 {
              // Get type info from operand
              if eg.get_bits(node.children[0]) is Some(bits) {
                let umax = ty_umax(bits)
                if eg.find_const(node.children[1]) is Some(k) && k == umax {
                  // ugt(x, UMAX) = false
                  let zero = eg.add_const(0L)
                  let new_id = eg.merge(class_id, zero)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// uge(x, UMAX) → eq(x, UMAX)
/// Only UMAX is >= UMAX
fn rule_uge_umax() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_UGE && node.children.length() == 2 {
              if eg.get_bits(node.children[0]) is Some(bits) {
                let umax = ty_umax(bits)
                if eg.find_const(node.children[1]) is Some(k) && k == umax {
                  // uge(x, UMAX) = eq(x, UMAX)
                  let new_node = eg.add({
                    op: Eq,
                    children: [node.children[0], node.children[1]],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// ule(x, UMAX) → true
/// Everything is <= UMAX
fn rule_ule_umax() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_ULE && node.children.length() == 2 {
              if eg.get_bits(node.children[0]) is Some(bits) {
                let umax = ty_umax(bits)
                if eg.find_const(node.children[1]) is Some(k) && k == umax {
                  // ule(x, UMAX) = true
                  let one = eg.add_const(1L)
                  let new_id = eg.merge(class_id, one)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// sgt(x, SMAX) → false
/// Nothing can be greater than the maximum signed value
fn rule_sgt_smax() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_SGT && node.children.length() == 2 {
              if eg.get_bits(node.children[0]) is Some(bits) {
                let smax = ty_smax(bits)
                if eg.find_const(node.children[1]) is Some(k) && k == smax {
                  // sgt(x, SMAX) = false
                  let zero = eg.add_const(0L)
                  let new_id = eg.merge(class_id, zero)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// sge(x, SMAX) → eq(x, SMAX)
/// Only SMAX is >= SMAX
fn rule_sge_smax() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_SGE && node.children.length() == 2 {
              if eg.get_bits(node.children[0]) is Some(bits) {
                let smax = ty_smax(bits)
                if eg.find_const(node.children[1]) is Some(k) && k == smax {
                  // sge(x, SMAX) = eq(x, SMAX)
                  let new_node = eg.add({
                    op: Eq,
                    children: [node.children[0], node.children[1]],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// slt(x, SMIN) → false
/// Nothing can be less than the minimum signed value
fn rule_slt_smin() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_SLT && node.children.length() == 2 {
              if eg.get_bits(node.children[0]) is Some(bits) {
                let smin = ty_smin(bits)
                if eg.find_const(node.children[1]) is Some(k) && k == smin {
                  // slt(x, SMIN) = false
                  let zero = eg.add_const(0L)
                  let new_id = eg.merge(class_id, zero)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// sle(x, SMIN) → eq(x, SMIN)
/// Only SMIN is <= SMIN
fn rule_sle_smin() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_SLE && node.children.length() == 2 {
              if eg.get_bits(node.children[0]) is Some(bits) {
                let smin = ty_smin(bits)
                if eg.find_const(node.children[1]) is Some(k) && k == smin {
                  // sle(x, SMIN) = eq(x, SMIN)
                  let new_node = eg.add({
                    op: Eq,
                    children: [node.children[0], node.children[1]],
                  })
                  let new_id = eg.merge(class_id, new_node)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// sge(x, SMIN) → true
/// Everything is >= SMIN
fn rule_sge_smin() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_SGE && node.children.length() == 2 {
              if eg.get_bits(node.children[0]) is Some(bits) {
                let smin = ty_smin(bits)
                if eg.find_const(node.children[1]) is Some(k) && k == smin {
                  // sge(x, SMIN) = true
                  let one = eg.add_const(1L)
                  let new_id = eg.merge(class_id, one)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// sle(x, SMAX) → true
/// Everything is <= SMAX
fn rule_sle_smax() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_SLE && node.children.length() == 2 {
              if eg.get_bits(node.children[0]) is Some(bits) {
                let smax = ty_smax(bits)
                if eg.find_const(node.children[1]) is Some(k) && k == smax {
                  // sle(x, SMAX) = true
                  let one = eg.add_const(1L)
                  let new_id = eg.merge(class_id, one)
                  changed = new_id != class_id || changed
                }
              }
            }
          _ => ()
        }
      }
      changed
    },
  }
}
