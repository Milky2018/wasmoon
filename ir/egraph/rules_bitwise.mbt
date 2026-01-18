// Bitwise rules
// ============================================================================
// Bitwise identity rules
// ============================================================================

///|
/// x & 0 = 0
fn rule_and_zero() -> RewriteRule {
  {
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

///|
/// x | x = x (or idempotent)
fn rule_or_self() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          if eg.equiv(node.children[0], node.children[1]) {
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
/// x ^ ~x = -1, ~x ^ x = -1
fn rule_xor_not() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          let x = node.children[0]
          let y = node.children[1]
          // Check if y = ~x
          for y_node in eg.get_nodes(y) {
            if y_node.op is Bnot && y_node.children.length() == 1 {
              if eg.equiv(y_node.children[0], x) {
                let all_ones = eg.add_const(-1L)
                let new_id = eg.merge(class_id, all_ones)
                changed = new_id != class_id || changed
              }
            }
          }
          // Check if x = ~y
          for x_node in eg.get_nodes(x) {
            if x_node.op is Bnot && x_node.children.length() == 1 {
              if eg.equiv(x_node.children[0], y) {
                let all_ones = eg.add_const(-1L)
                let new_id = eg.merge(class_id, all_ones)
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
/// x | ~x = -1, ~x | x = -1
fn rule_or_not() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          let x = node.children[0]
          let y = node.children[1]
          // Check if y = ~x
          for y_node in eg.get_nodes(y) {
            if y_node.op is Bnot && y_node.children.length() == 1 {
              if eg.equiv(y_node.children[0], x) {
                let all_ones = eg.add_const(-1L)
                let new_id = eg.merge(class_id, all_ones)
                changed = new_id != class_id || changed
              }
            }
          }
          // Check if x = ~y
          for x_node in eg.get_nodes(x) {
            if x_node.op is Bnot && x_node.children.length() == 1 {
              if eg.equiv(x_node.children[0], y) {
                let all_ones = eg.add_const(-1L)
                let new_id = eg.merge(class_id, all_ones)
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
/// x & ~x = 0, ~x & x = 0
fn rule_and_not() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          let x = node.children[0]
          let y = node.children[1]
          // Check if y = ~x
          for y_node in eg.get_nodes(y) {
            if y_node.op is Bnot && y_node.children.length() == 1 {
              if eg.equiv(y_node.children[0], x) {
                let zero = eg.add_const(0L)
                let new_id = eg.merge(class_id, zero)
                changed = new_id != class_id || changed
              }
            }
          }
          // Check if x = ~y
          for x_node in eg.get_nodes(x) {
            if x_node.op is Bnot && x_node.children.length() == 1 {
              if eg.equiv(x_node.children[0], y) {
                let zero = eg.add_const(0L)
                let new_id = eg.merge(class_id, zero)
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
/// ~~x = x (double negation)
fn rule_double_bnot() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Bnot && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Bnot && inner.children.length() == 1 {
              let new_id = eg.subsume(class_id, inner.children[0])
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
/// DeMorgan: ~(x | y) = ~x & ~y
fn rule_demorgan_or() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Bnot && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Or && inner.children.length() == 2 {
              let not_x = eg.add_bnot(inner.children[0])
              let not_y = eg.add_bnot(inner.children[1])
              let result = eg.add_and(not_x, not_y)
              let new_id = eg.subsume(class_id, result)
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
/// DeMorgan: ~(x & y) = ~x | ~y
fn rule_demorgan_and() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Bnot && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is And && inner.children.length() == 2 {
              let not_x = eg.add_bnot(inner.children[0])
              let not_y = eg.add_bnot(inner.children[1])
              let result = eg.add_or(not_x, not_y)
              let new_id = eg.subsume(class_id, result)
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
/// x ^ -1 = ~x
fn rule_xor_all_ones() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(-1L) {
            let result = eg.add_bnot(node.children[0])
            let new_id = eg.merge(class_id, result)
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(-1L) {
            let result = eg.add_bnot(node.children[1])
            let new_id = eg.merge(class_id, result)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// (x & y) ^ (x ^ y) = x | y
fn rule_and_xor_xor() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          // Check if left is (x & y) and right is (x ^ y)
          for left in eg.get_nodes(node.children[0]) {
            if left.op is And && left.children.length() == 2 {
              let x = left.children[0]
              let y = left.children[1]
              for right in eg.get_nodes(node.children[1]) {
                if right.op is Xor && right.children.length() == 2 {
                  if (
                      eg.equiv(right.children[0], x) &&
                      eg.equiv(right.children[1], y)
                    ) ||
                    (
                      eg.equiv(right.children[0], y) &&
                      eg.equiv(right.children[1], x)
                    ) {
                    let result = eg.add_or(x, y)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  }
                }
              }
            }
          }
          // Check if left is (x ^ y) and right is (x & y)
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Xor && left.children.length() == 2 {
              let x = left.children[0]
              let y = left.children[1]
              for right in eg.get_nodes(node.children[1]) {
                if right.op is And && right.children.length() == 2 {
                  if (
                      eg.equiv(right.children[0], x) &&
                      eg.equiv(right.children[1], y)
                    ) ||
                    (
                      eg.equiv(right.children[0], y) &&
                      eg.equiv(right.children[1], x)
                    ) {
                    let result = eg.add_or(x, y)
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
/// (x | y) ^ (x & y) = x ^ y
fn rule_or_xor_and() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          // Check if left is (x | y) and right is (x & y)
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Or && left.children.length() == 2 {
              let x = left.children[0]
              let y = left.children[1]
              for right in eg.get_nodes(node.children[1]) {
                if right.op is And && right.children.length() == 2 {
                  if (
                      eg.equiv(right.children[0], x) &&
                      eg.equiv(right.children[1], y)
                    ) ||
                    (
                      eg.equiv(right.children[0], y) &&
                      eg.equiv(right.children[1], x)
                    ) {
                    let result = eg.add_xor(x, y)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  }
                }
              }
            }
          }
          // Check if left is (x & y) and right is (x | y)
          for left in eg.get_nodes(node.children[0]) {
            if left.op is And && left.children.length() == 2 {
              let x = left.children[0]
              let y = left.children[1]
              for right in eg.get_nodes(node.children[1]) {
                if right.op is Or && right.children.length() == 2 {
                  if (
                      eg.equiv(right.children[0], x) &&
                      eg.equiv(right.children[1], y)
                    ) ||
                    (
                      eg.equiv(right.children[0], y) &&
                      eg.equiv(right.children[1], x)
                    ) {
                    let result = eg.add_xor(x, y)
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
/// (x & y) | x = x (absorption)
fn rule_and_or_absorb() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          let a = node.children[0]
          let b = node.children[1]
          // Check if a is (x & y) and b is x or y
          for a_node in eg.get_nodes(a) {
            if a_node.op is And && a_node.children.length() == 2 {
              if eg.equiv(a_node.children[0], b) ||
                eg.equiv(a_node.children[1], b) {
                let new_id = eg.merge(class_id, b)
                changed = new_id != class_id || changed
              }
            }
          }
          // Check if b is (x & y) and a is x or y
          for b_node in eg.get_nodes(b) {
            if b_node.op is And && b_node.children.length() == 2 {
              if eg.equiv(b_node.children[0], a) ||
                eg.equiv(b_node.children[1], a) {
                let new_id = eg.merge(class_id, a)
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
/// (x ^ y) ^ y = x
fn rule_xor_xor_cancel() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          let a = node.children[0]
          let b = node.children[1]
          // Check if a is (x ^ y) and b is y
          for a_node in eg.get_nodes(a) {
            if a_node.op is Xor && a_node.children.length() == 2 {
              if eg.equiv(a_node.children[1], b) {
                let new_id = eg.merge(class_id, a_node.children[0])
                changed = new_id != class_id || changed
              } else if eg.equiv(a_node.children[0], b) {
                let new_id = eg.merge(class_id, a_node.children[1])
                changed = new_id != class_id || changed
              }
            }
          }
          // Check if b is (x ^ y) and a is y
          for b_node in eg.get_nodes(b) {
            if b_node.op is Xor && b_node.children.length() == 2 {
              if eg.equiv(b_node.children[1], a) {
                let new_id = eg.merge(class_id, b_node.children[0])
                changed = new_id != class_id || changed
              } else if eg.equiv(b_node.children[0], a) {
                let new_id = eg.merge(class_id, b_node.children[1])
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
/// (z & x) ^ (z & y) = z & (x ^ y)
fn rule_factor_and_xor() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is And && left.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op is And && right.children.length() == 2 {
                  // Check if left.children[0] == right.children[0] (common z)
                  if eg.equiv(left.children[0], right.children[0]) {
                    let z = left.children[0]
                    let x = left.children[1]
                    let y = right.children[1]
                    let x_xor_y = eg.add_xor(x, y)
                    let result = eg.add_and(z, x_xor_y)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  }
                  // Check if left.children[1] == right.children[1] (common z on right)
                  if eg.equiv(left.children[1], right.children[1]) {
                    let z = left.children[1]
                    let x = left.children[0]
                    let y = right.children[0]
                    let x_xor_y = eg.add_xor(x, y)
                    let result = eg.add_and(z, x_xor_y)
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
/// (x & y) + (x ^ y) = x | y
fn rule_and_add_xor() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          // Check if left is (x & y) and right is (x ^ y)
          for left in eg.get_nodes(node.children[0]) {
            if left.op is And && left.children.length() == 2 {
              let x = left.children[0]
              let y = left.children[1]
              for right in eg.get_nodes(node.children[1]) {
                if right.op is Xor && right.children.length() == 2 {
                  if (
                      eg.equiv(right.children[0], x) &&
                      eg.equiv(right.children[1], y)
                    ) ||
                    (
                      eg.equiv(right.children[0], y) &&
                      eg.equiv(right.children[1], x)
                    ) {
                    let result = eg.add_or(x, y)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  }
                }
              }
            }
          }
          // Check if left is (x ^ y) and right is (x & y)
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Xor && left.children.length() == 2 {
              let x = left.children[0]
              let y = left.children[1]
              for right in eg.get_nodes(node.children[1]) {
                if right.op is And && right.children.length() == 2 {
                  if (
                      eg.equiv(right.children[0], x) &&
                      eg.equiv(right.children[1], y)
                    ) ||
                    (
                      eg.equiv(right.children[0], y) &&
                      eg.equiv(right.children[1], x)
                    ) {
                    let result = eg.add_or(x, y)
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
/// (x | y) + (x & y) = x + y
fn rule_or_add_and() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          // Check if left is (x | y) and right is (x & y)
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Or && left.children.length() == 2 {
              let x = left.children[0]
              let y = left.children[1]
              for right in eg.get_nodes(node.children[1]) {
                if right.op is And && right.children.length() == 2 {
                  if (
                      eg.equiv(right.children[0], x) &&
                      eg.equiv(right.children[1], y)
                    ) ||
                    (
                      eg.equiv(right.children[0], y) &&
                      eg.equiv(right.children[1], x)
                    ) {
                    let result = eg.add_add(x, y)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  }
                }
              }
            }
          }
          // Check if left is (x & y) and right is (x | y)
          for left in eg.get_nodes(node.children[0]) {
            if left.op is And && left.children.length() == 2 {
              let x = left.children[0]
              let y = left.children[1]
              for right in eg.get_nodes(node.children[1]) {
                if right.op is Or && right.children.length() == 2 {
                  if (
                      eg.equiv(right.children[0], x) &&
                      eg.equiv(right.children[1], y)
                    ) ||
                    (
                      eg.equiv(right.children[0], y) &&
                      eg.equiv(right.children[1], x)
                    ) {
                    let result = eg.add_add(x, y)
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
/// or(and(x, y), not(y)) = or(x, not(y))
/// (x & y) | ~y = x | ~y
fn rule_or_and_not() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          let a = node.children[0]
          let b = node.children[1]
          // Check if a is (x & y) and b is ~y
          for a_node in eg.get_nodes(a) {
            if a_node.op is And && a_node.children.length() == 2 {
              let x = a_node.children[0]
              let y = a_node.children[1]
              for b_node in eg.get_nodes(b) {
                if b_node.op is Bnot && b_node.children.length() == 1 {
                  if eg.equiv(b_node.children[0], y) {
                    // (x & y) | ~y = x | ~y
                    let result = eg.add_or(x, b)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  } else if eg.equiv(b_node.children[0], x) {
                    // (x & y) | ~x = y | ~x
                    let result = eg.add_or(y, b)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  }
                }
              }
            }
          }
          // Check if b is (x & y) and a is ~y
          for b_node in eg.get_nodes(b) {
            if b_node.op is And && b_node.children.length() == 2 {
              let x = b_node.children[0]
              let y = b_node.children[1]
              for a_node in eg.get_nodes(a) {
                if a_node.op is Bnot && a_node.children.length() == 1 {
                  if eg.equiv(a_node.children[0], y) {
                    // ~y | (x & y) = x | ~y
                    let result = eg.add_or(x, a)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  } else if eg.equiv(a_node.children[0], x) {
                    // ~x | (x & y) = y | ~x
                    let result = eg.add_or(y, a)
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
/// (x | y) | x = x | y (or absorption with nested or)
fn rule_or_or_absorb() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          let a = node.children[0]
          let b = node.children[1]
          // Check if a is (x | y) and b is x or y
          for a_node in eg.get_nodes(a) {
            if a_node.op is Or && a_node.children.length() == 2 {
              if eg.equiv(a_node.children[0], b) ||
                eg.equiv(a_node.children[1], b) {
                // (x | y) | x = x | y, (x | y) | y = x | y
                let new_id = eg.subsume(class_id, a)
                changed = new_id != class_id || changed
              }
            }
          }
          // Check if b is (x | y) and a is x or y
          for b_node in eg.get_nodes(b) {
            if b_node.op is Or && b_node.children.length() == 2 {
              if eg.equiv(b_node.children[0], a) ||
                eg.equiv(b_node.children[1], a) {
                // x | (x | y) = x | y, y | (x | y) = x | y
                let new_id = eg.subsume(class_id, b)
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
/// (x & y) & x = x & y (and absorption with nested and)
fn rule_and_and_absorb() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          let a = node.children[0]
          let b = node.children[1]
          // Check if a is (x & y) and b is x or y
          for a_node in eg.get_nodes(a) {
            if a_node.op is And && a_node.children.length() == 2 {
              if eg.equiv(a_node.children[0], b) ||
                eg.equiv(a_node.children[1], b) {
                // (x & y) & x = x & y, (x & y) & y = x & y
                let new_id = eg.subsume(class_id, a)
                changed = new_id != class_id || changed
              }
            }
          }
          // Check if b is (x & y) and a is x or y
          for b_node in eg.get_nodes(b) {
            if b_node.op is And && b_node.children.length() == 2 {
              if eg.equiv(b_node.children[0], a) ||
                eg.equiv(b_node.children[1], a) {
                // x & (x & y) = x & y, y & (x & y) = x & y
                let new_id = eg.subsume(class_id, b)
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
/// (x ^ ~y) & x = x & y
fn rule_xor_not_and() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          let a = node.children[0]
          let b = node.children[1]
          // Check if a is (x ^ ~y) and b is x
          for a_node in eg.get_nodes(a) {
            if a_node.op is Xor && a_node.children.length() == 2 {
              let left = a_node.children[0]
              let right = a_node.children[1]
              // Check if right is ~y and left is x where b == x
              for right_node in eg.get_nodes(right) {
                if right_node.op is Bnot && right_node.children.length() == 1 {
                  if eg.equiv(left, b) {
                    // (x ^ ~y) & x = x & y
                    let y = right_node.children[0]
                    let result = eg.add_and(b, y)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  }
                }
              }
              // Check if left is ~y and right is x where b == x
              for left_node in eg.get_nodes(left) {
                if left_node.op is Bnot && left_node.children.length() == 1 {
                  if eg.equiv(right, b) {
                    // (~y ^ x) & x = x & y
                    let y = left_node.children[0]
                    let result = eg.add_and(b, y)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  }
                }
              }
            }
          }
          // Check if b is (x ^ ~y) and a is x
          for b_node in eg.get_nodes(b) {
            if b_node.op is Xor && b_node.children.length() == 2 {
              let left = b_node.children[0]
              let right = b_node.children[1]
              // Check if right is ~y and left is x where a == x
              for right_node in eg.get_nodes(right) {
                if right_node.op is Bnot && right_node.children.length() == 1 {
                  if eg.equiv(left, a) {
                    // x & (x ^ ~y) = x & y
                    let y = right_node.children[0]
                    let result = eg.add_and(a, y)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  }
                }
              }
              // Check if left is ~y and right is x where a == x
              for left_node in eg.get_nodes(left) {
                if left_node.op is Bnot && left_node.children.length() == 1 {
                  if eg.equiv(right, a) {
                    // x & (~y ^ x) = x & y
                    let y = left_node.children[0]
                    let result = eg.add_and(a, y)
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
/// (x & y) | ~x = y | ~x
fn rule_and_or_not() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          let a = node.children[0]
          let b = node.children[1]
          // Check if a is (x & y) and b is ~x
          for a_node in eg.get_nodes(a) {
            if a_node.op is And && a_node.children.length() == 2 {
              let x = a_node.children[0]
              let y = a_node.children[1]
              for b_node in eg.get_nodes(b) {
                if b_node.op is Bnot && b_node.children.length() == 1 {
                  if eg.equiv(b_node.children[0], x) {
                    // (x & y) | ~x = y | ~x
                    let result = eg.add_or(y, b)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  } else if eg.equiv(b_node.children[0], y) {
                    // (x & y) | ~y = x | ~y
                    let result = eg.add_or(x, b)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  }
                }
              }
            }
          }
          // Check if b is (x & y) and a is ~x
          for b_node in eg.get_nodes(b) {
            if b_node.op is And && b_node.children.length() == 2 {
              let x = b_node.children[0]
              let y = b_node.children[1]
              for a_node in eg.get_nodes(a) {
                if a_node.op is Bnot && a_node.children.length() == 1 {
                  if eg.equiv(a_node.children[0], x) {
                    // ~x | (x & y) = y | ~x
                    let result = eg.add_or(y, a)
                    let new_id = eg.merge(class_id, result)
                    changed = new_id != class_id || changed
                  } else if eg.equiv(a_node.children[0], y) {
                    // ~y | (x & y) = x | ~y
                    let result = eg.add_or(x, a)
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
