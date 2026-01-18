// Shift rules
// ============================================================================
// Shift rules
// ============================================================================

///|
/// x << 0 = x
fn rule_shl_zero() -> RewriteRule {
  {
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

///|
/// (x >> a) >> b = x >> (a + b) when a + b < 64 (unsigned)
fn rule_ushr_ushr() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ushr && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(b) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Ushr && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(a) {
                  let total = a + b
                  if total >= 0L && total < 64L {
                    let total_const = eg.add_const(total)
                    let new_node = eg.add({
                      op: Ushr,
                      children: [inner.children[0], total_const],
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
/// (x >> a) >> b = x >> (a + b) when a + b < 64 (signed)
fn rule_sshr_sshr() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sshr && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(b) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Sshr && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(a) {
                  let total = a + b
                  if total >= 0L && total < 64L {
                    let total_const = eg.add_const(total)
                    let new_node = eg.add({
                      op: Sshr,
                      children: [inner.children[0], total_const],
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
/// x rotl 0 = x, x rotr 0 = x
fn rule_rot_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Rotl || node.op is Rotr) && node.children.length() == 2 {
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
/// rotl(rotr(x, y), y) = x
fn rule_rotl_rotr_cancel() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Rotl && node.children.length() == 2 {
          let y = node.children[1]
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Rotr && inner.children.length() == 2 {
              if eg.equiv(inner.children[1], y) {
                let new_id = eg.subsume(class_id, inner.children[0])
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
/// rotr(rotl(x, y), y) = x
fn rule_rotr_rotl_cancel() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Rotr && node.children.length() == 2 {
          let y = node.children[1]
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Rotl && inner.children.length() == 2 {
              if eg.equiv(inner.children[1], y) {
                let new_id = eg.subsume(class_id, inner.children[0])
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
/// (x >> k) << k = x & mask (masking off bottom k bits)
fn rule_ushr_shl_mask() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Shl && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(k) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Ushr && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(k2) {
                  if k == k2 && k >= 0L && k < 64L {
                    // (x >> k) << k = x & (0xFFFFFFFFFFFFFFFF << k)
                    let mask = -1L << k.to_int()
                    let mask_const = eg.add_const(mask)
                    let new_node = eg.add_and(inner.children[0], mask_const)
                    let new_id = eg.subsume(class_id, new_node)
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
/// (x << k) >> k = x & mask (unsigned, masking off top k bits)
fn rule_shl_ushr_mask() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ushr && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(k) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Shl && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(k2) {
                  if k == k2 && k >= 0L && k < 64L {
                    // (x << k) >> k = x & (0xFFFFFFFFFFFFFFFF >> k)
                    let mask = ((-1L).reinterpret_as_uint64() >> k.to_int()).reinterpret_as_int64()
                    let mask_const = eg.add_const(mask)
                    let new_node = eg.add_and(inner.children[0], mask_const)
                    let new_id = eg.subsume(class_id, new_node)
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
/// band(ishl(x, z), ishl(y, z)) = ishl(band(x, y), z)
/// Distribute band through shifts with same amount
fn rule_band_shl_shl() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Shl && left.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op is Shl && right.children.length() == 2 {
                  if eg.equiv(left.children[1], right.children[1]) {
                    let z = left.children[1]
                    let xy_and = eg.add_and(left.children[0], right.children[0])
                    let new_node = eg.add_shl(xy_and, z)
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
/// isub(ishl(x, z), ishl(y, z)) = ishl(isub(x, y), z)
/// Distribute sub through shifts with same amount
fn rule_sub_shl_shl() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Shl && left.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op is Shl && right.children.length() == 2 {
                  if eg.equiv(left.children[1], right.children[1]) {
                    let z = left.children[1]
                    let xy_sub = eg.add_sub(left.children[0], right.children[0])
                    let new_node = eg.add_shl(xy_sub, z)
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
/// iadd(ishl(x, z), ishl(y, z)) = ishl(iadd(x, y), z)
/// Distribute add through shifts with same amount
fn rule_add_shl_shl() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Shl && left.children.length() == 2 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op is Shl && right.children.length() == 2 {
                  if eg.equiv(left.children[1], right.children[1]) {
                    let z = left.children[1]
                    let xy_add = eg.add_add(left.children[0], right.children[0])
                    let new_node = eg.add_shl(xy_add, z)
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
/// ushr(band(ishl(x, y), z), y) = band(x, ushr(z, y))
fn rule_ushr_band_shl() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ushr && node.children.length() == 2 {
          let y = node.children[1]
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is And && inner.children.length() == 2 {
              // Check if left of and is (x << y)
              for left in eg.get_nodes(inner.children[0]) {
                if left.op is Shl && left.children.length() == 2 {
                  if eg.equiv(left.children[1], y) {
                    let x = left.children[0]
                    let z = inner.children[1]
                    let z_ushr_y = eg.add({ op: Ushr, children: [z, y] })
                    let new_node = eg.add_and(x, z_ushr_y)
                    let new_id = eg.merge(class_id, new_node)
                    changed = new_id != class_id || changed
                  }
                }
              }
              // Also check if right of and is (x << y)
              for right in eg.get_nodes(inner.children[1]) {
                if right.op is Shl && right.children.length() == 2 {
                  if eg.equiv(right.children[1], y) {
                    let x = right.children[0]
                    let z = inner.children[0]
                    let z_ushr_y = eg.add({ op: Ushr, children: [z, y] })
                    let new_node = eg.add_and(x, z_ushr_y)
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
/// ineg(ushr(x, k)) = sshr(x, k) when k == bits - 1
/// Negating a logical right shift by (bits-1) equals arithmetic right shift
fn rule_neg_ushr_to_sshr() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Neg && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Ushr && inner.children.length() == 2 {
              // Check if shift amount is bits-1 (63 for 64-bit, 31 for 32-bit)
              if eg.find_const(inner.children[1]) is Some(k) {
                if k == 63L || k == 31L {
                  // ineg(ushr(x, k)) = sshr(x, k)
                  let new_node = eg.add({
                    op: Sshr,
                    children: [inner.children[0], inner.children[1]],
                  })
                  let new_id = eg.subsume(class_id, new_node)
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
/// (ishl (ishl x k1) k2) = 0 when k1 + k2 >= bits
/// Shift overflow becomes zero
fn rule_shl_shl_overflow() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Shl && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(k2) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Shl && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(k1) {
                  let total = k1 + k2
                  // Overflow for 64-bit and 32-bit
                  if total >= 64L {
                    let zero = eg.add_const(0L)
                    let new_id = eg.subsume(class_id, zero)
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
/// (ushr (ushr x k1) k2) = 0 when k1 + k2 >= bits
/// Unsigned shift overflow becomes zero
fn rule_ushr_ushr_overflow() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ushr && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(k2) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Ushr && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(k1) {
                  let total = k1 + k2
                  if total >= 64L {
                    let zero = eg.add_const(0L)
                    let new_id = eg.subsume(class_id, zero)
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
/// (rotl (rotl x y) z) = (rotl x (iadd y z))
/// Combine consecutive rotations into single rotation with added amounts
fn rule_rotl_rotl_combine() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Rotl && node.children.length() == 2 {
          let z = node.children[1]
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Rotl && inner.children.length() == 2 {
              let x = inner.children[0]
              let y = inner.children[1]
              // rotl(rotl(x, y), z) = rotl(x, y + z)
              let sum = eg.add_add(y, z)
              let new_node = eg.add({ op: Rotl, children: [x, sum] })
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
/// (rotr (rotr x y) z) = (rotr x (iadd y z))
/// Combine consecutive rotations into single rotation with added amounts
fn rule_rotr_rotr_combine() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Rotr && node.children.length() == 2 {
          let z = node.children[1]
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Rotr && inner.children.length() == 2 {
              let x = inner.children[0]
              let y = inner.children[1]
              // rotr(rotr(x, y), z) = rotr(x, y + z)
              let sum = eg.add_add(y, z)
              let new_node = eg.add({ op: Rotr, children: [x, sum] })
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
/// (rotr (rotl x y) z) = (rotl x (isub y z))
/// Convert mixed rotation to single rotation with subtracted amounts
fn rule_rotr_rotl_to_rotl() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Rotr && node.children.length() == 2 {
          let z = node.children[1]
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Rotl && inner.children.length() == 2 {
              let x = inner.children[0]
              let y = inner.children[1]
              // rotr(rotl(x, y), z) = rotl(x, y - z)
              let diff = eg.add_sub(y, z)
              let new_node = eg.add({ op: Rotl, children: [x, diff] })
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
/// (rotl (rotr x y) z) = (rotr x (isub y z))
/// Convert mixed rotation to single rotation with subtracted amounts
fn rule_rotl_rotr_to_rotr() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Rotl && node.children.length() == 2 {
          let z = node.children[1]
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Rotr && inner.children.length() == 2 {
              let x = inner.children[0]
              let y = inner.children[1]
              // rotl(rotr(x, y), z) = rotr(x, y - z)
              let diff = eg.add_sub(y, z)
              let new_node = eg.add({ op: Rotr, children: [x, diff] })
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
/// Remove uextend/sextend from shift amount: (ishl x (uextend y)) = (ishl x y)
/// Shift operations only look at lower bits of shift amount
fn rule_shift_extend_amount() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        // Match Shl, Ushr, Sshr, Rotl, Rotr with extended shift amount
        if (
            node.op is Shl ||
            node.op is Ushr ||
            node.op is Sshr ||
            node.op is Rotl ||
            node.op is Rotr
          ) &&
          node.children.length() == 2 {
          let x = node.children[0]
          for amount_node in eg.get_nodes(node.children[1]) {
            // Check if shift amount is an extend operation
            if amount_node.op is Uextend(_, _) ||
              amount_node.op is Sextend(_, _) {
              if amount_node.children.length() == 1 {
                let y = amount_node.children[0]
                let new_node = eg.add({ op: node.op, children: [x, y] })
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
/// Remove ireduce from shift amount: (ishl x (ireduce y)) = (ishl x y)
/// Shift operations only look at lower bits of shift amount
fn rule_shift_reduce_amount() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        // Match Shl, Ushr, Sshr, Rotl, Rotr with reduced shift amount
        if (
            node.op is Shl ||
            node.op is Ushr ||
            node.op is Sshr ||
            node.op is Rotl ||
            node.op is Rotr
          ) &&
          node.children.length() == 2 {
          let x = node.children[0]
          for amount_node in eg.get_nodes(node.children[1]) {
            // Check if shift amount is an ireduce operation
            if amount_node.op is Ireduce(_, _) {
              if amount_node.children.length() == 1 {
                let y = amount_node.children[0]
                let new_node = eg.add({ op: node.op, children: [x, y] })
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
/// (shl x k1) | (ushr x k2) = rotl x k1  when k2 = bits - k1
/// Convert shift pair to rotate left
fn rule_shl_ushr_to_rotl() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          // Check both orderings
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Shl && left.children.length() == 2 {
              if eg.find_const(left.children[1]) is Some(k1) {
                for right in eg.get_nodes(node.children[1]) {
                  if right.op is Ushr && right.children.length() == 2 {
                    if eg.find_const(right.children[1]) is Some(k2) {
                      // Check if they operate on the same value
                      if eg.equiv(left.children[0], right.children[0]) {
                        // Check if k1 + k2 = 64 (for 64-bit rotation)
                        if k1 + k2 == 64L && k1 > 0L && k2 > 0L {
                          let new_node = eg.add({
                            op: Rotl,
                            children: [left.children[0], left.children[1]],
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
          // Also check ushr | shl ordering
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Ushr && left.children.length() == 2 {
              if eg.find_const(left.children[1]) is Some(k2) {
                for right in eg.get_nodes(node.children[1]) {
                  if right.op is Shl && right.children.length() == 2 {
                    if eg.find_const(right.children[1]) is Some(k1) {
                      if eg.equiv(left.children[0], right.children[0]) {
                        if k1 + k2 == 64L && k1 > 0L && k2 > 0L {
                          let new_node = eg.add({
                            op: Rotl,
                            children: [right.children[0], right.children[1]],
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
        }
      }
      changed
    },
  }
}
