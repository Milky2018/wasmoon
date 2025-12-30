// Constant folding and strength reduction rules

///|
fn rule_mul_pow2() -> RewriteRule {
  {
    name: "mul_pow2",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          // Check if right operand is power of 2
          if eg.find_const(node.children[1]) is Some(c) {
            if log2_if_pow2(c) is Some(shift) {
              let shift_const = eg.add_const(shift.to_int64())
              let new_node = eg.add_shl(node.children[0], shift_const)
              let new_id = eg.merge(class_id, new_node)
              changed = new_id != class_id || changed
            }
          }
          // Check if left operand is power of 2
          if eg.find_const(node.children[0]) is Some(c) {
            if log2_if_pow2(c) is Some(shift) {
              let shift_const = eg.add_const(shift.to_int64())
              let new_node = eg.add_shl(node.children[1], shift_const)
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
/// x + x = x * 2 = x << 1
fn rule_double() -> RewriteRule {
  {
    name: "double",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          if eg.equiv(node.children[0], node.children[1]) {
            // x + x = x << 1
            let one = eg.add_const(1L)
            let shift = eg.add_shl(node.children[0], one)
            let new_id = eg.merge(class_id, shift)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// Constant folding for binary operations
fn rule_const_fold() -> RewriteRule {
  {
    name: "const_fold",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(lhs) {
            if eg.find_const(node.children[1]) is Some(rhs) {
              let result : Int64? = match node.op {
                Add => Some(lhs + rhs)
                Sub => Some(lhs - rhs)
                Mul => Some(lhs * rhs)
                And => Some(lhs & rhs)
                Or => Some(lhs | rhs)
                Xor => Some(lhs ^ rhs)
                Shl =>
                  if rhs >= 0L && rhs < 64L {
                    Some(lhs << rhs.to_int())
                  } else {
                    None
                  }
                Sshr =>
                  if rhs >= 0L && rhs < 64L {
                    Some(lhs >> rhs.to_int())
                  } else {
                    None
                  }
                Ushr => {
                  let lhs = lhs.reinterpret_as_uint64()
                  if rhs >= 0L && rhs < 64L {
                    Some((lhs >> rhs.to_int()).reinterpret_as_int64())
                  } else {
                    None
                  }
                }
                Sdiv => if rhs != 0L { Some(lhs / rhs) } else { None }
                Udiv =>
                  if rhs != 0L {
                    // For unsigned division, we need to handle this carefully
                    // For now, just use signed division (correct for positive values)
                    Some(lhs / rhs)
                  } else {
                    None
                  }
                _ => None
              }
              if result is Some(r) {
                let result_node = eg.add_const(r)
                let new_id = eg.merge(class_id, result_node)
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
/// (a | c1) | c2 = a | (c1 | c2) - reassociate or constants
fn rule_reassoc_or_const() -> RewriteRule {
  {
    name: "reassoc_or_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c2) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Or && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(c1) {
                  // (a | c1) | c2 = a | (c1 | c2)
                  let combined = eg.add_const(c1 | c2)
                  let new_or = eg.add_or(inner.children[0], combined)
                  let new_id = eg.merge(class_id, new_or)
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
/// (a & c1) & c2 = a & (c1 & c2) - reassociate and constants
fn rule_reassoc_and_const() -> RewriteRule {
  {
    name: "reassoc_and_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c2) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is And && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(c1) {
                  // (a & c1) & c2 = a & (c1 & c2)
                  let combined = eg.add_const(c1 & c2)
                  let new_and = eg.add_and(inner.children[0], combined)
                  let new_id = eg.merge(class_id, new_and)
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
/// (a ^ c1) ^ c2 = a ^ (c1 ^ c2) - reassociate xor constants
fn rule_reassoc_xor_const() -> RewriteRule {
  {
    name: "reassoc_xor_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c2) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Xor && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(c1) {
                  // (a ^ c1) ^ c2 = a ^ (c1 ^ c2)
                  let combined = eg.add_const(c1 ^ c2)
                  let new_xor = eg.add_xor(inner.children[0], combined)
                  let new_id = eg.merge(class_id, new_xor)
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
/// (a + c1) + c2 = a + (c1 + c2) - reassociate constants
fn rule_reassoc_add_const() -> RewriteRule {
  {
    name: "reassoc_add_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        // Pattern: (? + c2) where ? is an Add
        if node.op is Add && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c2) {
            // Check if left child is also an Add with a constant
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Add && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(c1) {
                  // (a + c1) + c2 = a + (c1 + c2)
                  let combined = eg.add_const(c1 + c2)
                  let new_add = eg.add_add(inner.children[0], combined)
                  let new_id = eg.merge(class_id, new_add)
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
/// (sub (add x k1) k2) = sub x (k2 - k1) when k2 >= k1
/// (sub (add x k1) k2) = add x (k1 - k2) when k1 > k2
fn rule_reassoc_sub_add_const() -> RewriteRule {
  {
    name: "reassoc_sub_add_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c2) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Add && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(c1) {
                  // (add x k1) - k2 = x + (k1 - k2) or x - (k2 - k1)
                  let combined = eg.add_const(c1 - c2)
                  let new_add = eg.add_add(inner.children[0], combined)
                  let new_id = eg.merge(class_id, new_add)
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
/// (add (sub x k1) k2) = add x (k2 - k1)
fn rule_reassoc_add_sub_const() -> RewriteRule {
  {
    name: "reassoc_add_sub_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c2) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Sub && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(c1) {
                  // (sub x k1) + k2 = x + (k2 - k1)
                  let combined = eg.add_const(c2 - c1)
                  let new_add = eg.add_add(inner.children[0], combined)
                  let new_id = eg.merge(class_id, new_add)
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
/// (sub (sub k1 x) k2) = sub (k1 - k2) x
fn rule_reassoc_sub_sub_const_left() -> RewriteRule {
  {
    name: "reassoc_sub_sub_const_left",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c2) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Sub && inner.children.length() == 2 {
                if eg.find_const(inner.children[0]) is Some(c1) {
                  // (sub k1 x) - k2 = (k1 - k2) - x
                  let combined = eg.add_const(c1 - c2)
                  let new_sub = eg.add_sub(combined, inner.children[1])
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
/// (add (sub k1 x) k2) = sub (k1 + k2) x
fn rule_reassoc_add_sub_const_left() -> RewriteRule {
  {
    name: "reassoc_add_sub_const_left",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c2) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Sub && inner.children.length() == 2 {
                if eg.find_const(inner.children[0]) is Some(c1) {
                  // (sub k1 x) + k2 = (k1 + k2) - x
                  let combined = eg.add_const(c1 + c2)
                  let new_sub = eg.add_sub(combined, inner.children[1])
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
/// Shift reassociation: ((A shl b) shl C) => ((A shl C) shl b) when A is const
fn rule_reassoc_shl_const() -> RewriteRule {
  {
    name: "reassoc_shl_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Shl && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(_) {
            // outer shift amount is constant
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Shl && inner.children.length() == 2 {
                if eg.find_const(inner.children[0]) is Some(_) {
                  // ((A shl b) shl C) => ((A shl C) shl b)
                  let inner_shift = eg.add_shl(
                    inner.children[0],
                    node.children[1],
                  )
                  let new_shift = eg.add_shl(inner_shift, inner.children[1])
                  let new_id = eg.merge(class_id, new_shift)
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
/// Shift reassociation: ((A ushr b) ushr C) => ((A ushr C) ushr b) when A is const
fn rule_reassoc_ushr_const() -> RewriteRule {
  {
    name: "reassoc_ushr_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ushr && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(_) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Ushr && inner.children.length() == 2 {
                if eg.find_const(inner.children[0]) is Some(_) {
                  let inner_shift = eg.add({
                    op: Ushr,
                    children: [inner.children[0], node.children[1]],
                  })
                  let new_shift = eg.add({
                    op: Ushr,
                    children: [inner_shift, inner.children[1]],
                  })
                  let new_id = eg.merge(class_id, new_shift)
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
/// Shift reassociation: ((A sshr b) sshr C) => ((A sshr C) sshr b) when A is const
fn rule_reassoc_sshr_const() -> RewriteRule {
  {
    name: "reassoc_sshr_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sshr && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(_) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Sshr && inner.children.length() == 2 {
                if eg.find_const(inner.children[0]) is Some(_) {
                  let inner_shift = eg.add({
                    op: Sshr,
                    children: [inner.children[0], node.children[1]],
                  })
                  let new_shift = eg.add({
                    op: Sshr,
                    children: [inner_shift, inner.children[1]],
                  })
                  let new_id = eg.merge(class_id, new_shift)
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
