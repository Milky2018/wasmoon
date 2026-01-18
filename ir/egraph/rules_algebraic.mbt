// Algebraic rules (negation, cancellation, division patterns, etc.)
// ============================================================================
// Subtraction rules
// ============================================================================

///|
/// 0 - x = neg(x) - but since we don't have neg yet, create sub(0, x)
/// This helps recognize negation patterns
fn rule_neg_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(0L) {
            // 0 - x is already in canonical form for negation
            // Add the Neg node as equivalent
            let neg_node = eg.add({ op: Neg, children: [node.children[1]] })
            let new_id = eg.merge(class_id, neg_node)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x - (0 - y) = x + y
fn rule_sub_neg() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          for inner in eg.get_nodes(node.children[1]) {
            // x - (-y) = x + y
            if inner.op is Neg && inner.children.length() == 1 {
              let new_node = eg.add_add(node.children[0], inner.children[0])
              let new_id = eg.merge(class_id, new_node)
              changed = new_id != class_id || changed
            }
            // x - (0 - y) = x + y
            if inner.op is Sub && inner.children.length() == 2 {
              if eg.find_const(inner.children[0]) is Some(0L) {
                let new_node = eg.add_add(node.children[0], inner.children[1])
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
/// x + (0 - y) = x - y
fn rule_add_neg() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          for inner in eg.get_nodes(node.children[1]) {
            // x + (-y) = x - y
            if inner.op is Neg && inner.children.length() == 1 {
              let new_node = eg.add_sub(node.children[0], inner.children[0])
              let new_id = eg.merge(class_id, new_node)
              changed = new_id != class_id || changed
            }
            if inner.op is Sub && inner.children.length() == 2 {
              if eg.find_const(inner.children[0]) is Some(0L) {
                // x + (0 - y) = x - y
                let new_node = eg.add_sub(node.children[0], inner.children[1])
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
// Constant reassociation rules
// ============================================================================

///|
/// (a * c1) * c2 = a * (c1 * c2) - reassociate multiplication constants
fn rule_reassoc_mul_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c2) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Mul && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(c1) {
                  // (a * c1) * c2 = a * (c1 * c2)
                  let combined = eg.add_const(c1 * c2)
                  let new_mul = eg.add_mul(inner.children[0], combined)
                  let new_id = eg.merge(class_id, new_mul)
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
/// (a - c1) - c2 = a - (c1 + c2)
fn rule_reassoc_sub_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c2) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Sub && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(c1) {
                  // (a - c1) - c2 = a - (c1 + c2)
                  let combined = eg.add_const(c1 + c2)
                  let new_sub = eg.add_sub(inner.children[0], combined)
                  let new_id = eg.merge(class_id, new_sub)
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
/// x * -1 = -x
fn rule_mul_neg_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          // Check right operand for -1
          if eg.find_const(node.children[1]) is Some(-1L) {
            let neg_x = eg.add_neg(node.children[0])
            let new_id = eg.merge(class_id, neg_x)
            changed = new_id != class_id || changed
          }
          // Check left operand for -1 (commutative)
          if eg.find_const(node.children[0]) is Some(-1L) {
            let neg_x = eg.add_neg(node.children[1])
            let new_id = eg.merge(class_id, neg_x)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// -x * -y = x * y
fn rule_neg_mul_neg() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          // Check if both operands are negations
          let mut left_inner : EClassId? = None
          let mut right_inner : EClassId? = None
          for left_node in eg.get_nodes(node.children[0]) {
            if left_node.op is Neg && left_node.children.length() == 1 {
              left_inner = Some(left_node.children[0])
              break
            }
          }
          for right_node in eg.get_nodes(node.children[1]) {
            if right_node.op is Neg && right_node.children.length() == 1 {
              right_inner = Some(right_node.children[0])
              break
            }
          }
          if left_inner is Some(x) && right_inner is Some(y) {
            let new_mul = eg.add_mul(x, y)
            let new_id = eg.merge(class_id, new_mul)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// (x - y) + y = x
fn rule_sub_add_cancel() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          // Check pattern: (x - y) + y
          for left_node in eg.get_nodes(node.children[0]) {
            if left_node.op is Sub && left_node.children.length() == 2 {
              if eg.equiv(left_node.children[1], node.children[1]) {
                // (x - y) + y = x
                let new_id = eg.merge(class_id, left_node.children[0])
                changed = new_id != class_id || changed
              }
            }
          }
          // Check pattern: y + (x - y)
          for right_node in eg.get_nodes(node.children[1]) {
            if right_node.op is Sub && right_node.children.length() == 2 {
              if eg.equiv(right_node.children[1], node.children[0]) {
                // y + (x - y) = x
                let new_id = eg.merge(class_id, right_node.children[0])
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
/// (x + y) - y = x, (x + y) - x = y
fn rule_add_sub_cancel() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          for left_node in eg.get_nodes(node.children[0]) {
            if left_node.op is Add && left_node.children.length() == 2 {
              // (x + y) - y = x
              if eg.equiv(left_node.children[1], node.children[1]) {
                let new_id = eg.merge(class_id, left_node.children[0])
                changed = new_id != class_id || changed
              }
              // (x + y) - x = y
              if eg.equiv(left_node.children[0], node.children[1]) {
                let new_id = eg.merge(class_id, left_node.children[1])
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
/// (x - y) - x = -y
fn rule_sub_sub_cancel() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          for left_node in eg.get_nodes(node.children[0]) {
            if left_node.op is Sub && left_node.children.length() == 2 {
              // (x - y) - x = -y
              if eg.equiv(left_node.children[0], node.children[1]) {
                let neg_y = eg.add_neg(left_node.children[1])
                let new_id = eg.merge(class_id, neg_y)
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
/// x / -1 = -x (signed division)
fn rule_sdiv_neg_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sdiv && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(-1L) {
            let neg_x = eg.add_neg(node.children[0])
            let new_id = eg.merge(class_id, neg_x)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x % -1 = 0 (signed remainder)
fn rule_srem_neg_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Srem && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(-1L) {
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
/// x / 1 = x (signed and unsigned)
fn rule_div_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Sdiv | Udiv =>
            if node.children.length() == 2 {
              if eg.find_const(node.children[1]) is Some(1L) {
                let new_id = eg.merge(class_id, node.children[0])
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

///|
/// x % 1 = 0 (signed and unsigned)
fn rule_rem_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Srem | Urem =>
            if node.children.length() == 2 {
              if eg.find_const(node.children[1]) is Some(1L) {
                let zero = eg.add_const(0L)
                let new_id = eg.merge(class_id, zero)
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

///|
/// (!x) + 1 = -x (two's complement negation)
fn rule_bnot_add_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          // Check (!x) + 1
          if eg.find_const(node.children[1]) is Some(1L) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Bnot && inner.children.length() == 1 {
                let neg = eg.add_neg(inner.children[0])
                let new_id = eg.merge(class_id, neg)
                changed = new_id != class_id || changed
              }
            }
          }
          // Check 1 + (!x)
          if eg.find_const(node.children[0]) is Some(1L) {
            for inner in eg.get_nodes(node.children[1]) {
              if inner.op is Bnot && inner.children.length() == 1 {
                let neg = eg.add_neg(inner.children[0])
                let new_id = eg.merge(class_id, neg)
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
/// !(x - 1) = -x
fn rule_bnot_sub_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Bnot && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Sub && inner.children.length() == 2 {
              if eg.find_const(inner.children[1]) is Some(1L) {
                let neg = eg.add_neg(inner.children[0])
                let new_id = eg.merge(class_id, neg)
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
/// !(x + (-1)) = -x
fn rule_bnot_add_neg_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Bnot && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Add && inner.children.length() == 2 {
              if eg.find_const(inner.children[1]) is Some(-1L) {
                let neg = eg.add_neg(inner.children[0])
                let new_id = eg.merge(class_id, neg)
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
/// or(x, C) + (-C) = and(x, ~C)
fn rule_or_add_neg() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(m) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Or && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(n) {
                  if m == -n {
                    // or(x, C) + (-C) = and(x, ~C)
                    let not_c = eg.add_const(n.lnot())
                    let result = eg.add_and(inner.children[0], not_c)
                    let new_id = eg.merge(class_id, result)
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
/// (x + y) - (x | y) = x & y
fn rule_add_sub_or_to_and() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          for add_node in eg.get_nodes(node.children[0]) {
            if add_node.op is Add && add_node.children.length() == 2 {
              for or_node in eg.get_nodes(node.children[1]) {
                if or_node.op is Or && or_node.children.length() == 2 {
                  let add_x = eg.find(add_node.children[0])
                  let add_y = eg.find(add_node.children[1])
                  let or_x = eg.find(or_node.children[0])
                  let or_y = eg.find(or_node.children[1])
                  // Check if (x+y) - (x|y) or (x+y) - (y|x)
                  if (add_x == or_x && add_y == or_y) ||
                    (add_x == or_y && add_y == or_x) {
                    let result = eg.add_and(add_x, add_y)
                    let new_id = eg.merge(class_id, result)
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
/// x * (1 << y) = x << y
fn rule_mul_shl_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          // Check right operand for (1 << y) pattern
          for right_node in eg.get_nodes(node.children[1]) {
            if right_node.op is Shl && right_node.children.length() == 2 {
              if eg.find_const(right_node.children[0]) is Some(1L) {
                // x * (1 << y) = x << y
                let new_shl = eg.add_shl(
                  node.children[0],
                  right_node.children[1],
                )
                let new_id = eg.merge(class_id, new_shl)
                changed = new_id != class_id || changed
              }
            }
          }
          // Check left operand for (1 << y) pattern (commutative)
          for left_node in eg.get_nodes(node.children[0]) {
            if left_node.op is Shl && left_node.children.length() == 2 {
              if eg.find_const(left_node.children[0]) is Some(1L) {
                // (1 << y) * x = x << y
                let new_shl = eg.add_shl(
                  node.children[1],
                  left_node.children[1],
                )
                let new_id = eg.merge(class_id, new_shl)
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
/// (x << k) * c = x * (c << k)  (mod 2^bits)
/// Enables constant reassociation even after strength-reducing `x * 2^k` to `shl`.
fn rule_mul_shl_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      let bits = eg.get_bits(class_id).unwrap_or(64)
      let mask = ty_umax(bits)
      let shift_mask = if bits == 32 { 31L } else { 63L }
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          // Match (shl(x, k)) * c
          if eg.find_const(node.children[1]) is Some(c) {
            for left in eg.get_nodes(node.children[0]) {
              if left.op is Shl && left.children.length() == 2 {
                if eg.find_const(left.children[1]) is Some(k) {
                  let amt = (k & shift_mask).to_int()
                  let new_c = ((c & mask) << amt) & mask
                  let new_mul = eg.add_mul(
                    left.children[0],
                    eg.add_const(new_c),
                  )
                  let new_id = eg.merge(class_id, new_mul)
                  changed = new_id != class_id || changed
                }
              }
            }
          }

          // Match c * (shl(x, k))  (commutative)
          if eg.find_const(node.children[0]) is Some(c) {
            for right in eg.get_nodes(node.children[1]) {
              if right.op is Shl && right.children.length() == 2 {
                if eg.find_const(right.children[1]) is Some(k) {
                  let amt = (k & shift_mask).to_int()
                  let new_c = ((c & mask) << amt) & mask
                  let new_mul = eg.add_mul(
                    right.children[0],
                    eg.add_const(new_c),
                  )
                  let new_id = eg.merge(class_id, new_mul)
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
/// ineg(isub(y, x)) = isub(x, y)
fn rule_neg_sub_swap() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Neg && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Sub && inner.children.length() == 2 {
              // ineg(isub(y, x)) = isub(x, y)
              let new_sub = eg.add_sub(inner.children[1], inner.children[0])
              let new_id = eg.subsume(class_id, new_sub)
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
/// Tree rebalancing for iadd: (a + (b + (c + d))) => ((a + b) + (c + d))
/// Uses subsume to avoid infinite loops with commutativity rules
