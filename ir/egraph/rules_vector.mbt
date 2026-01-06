// SIMD vector optimization rules

///|
/// Helper to create splat8 pattern: replicate byte 16 times
/// TODO: Use when type info available for lane width detection
#warnings("-unused_value")
fn splat8(n : UInt64) -> Bytes {
  let byte = (n & 0xFFUL).to_byte()
  Bytes::make(16, byte)
}

///|
/// Helper to create splat16 pattern: replicate 16-bit value 8 times
/// TODO: Use when type info available for lane width detection
#warnings("-unused_value")
fn splat16(n : UInt64) -> Bytes {
  let val = (n & 0xFFFFUL).to_int()
  Bytes::makei(16, fn(i) {
    let lane = i / 2
    let byte_idx = i % 2
    guard lane < 8 else { b'\x00' }
    ((val >> (byte_idx * 8)) & 0xFF).to_byte()
  })
}

///|
/// Helper to create splat32 pattern: replicate 32-bit value 4 times
/// TODO: Use when type info available for lane width detection
#warnings("-unused_value")
fn splat32(n : UInt64) -> Bytes {
  let val = (n & 0xFFFFFFFFUL).reinterpret_as_int64()
  Bytes::makei(16, fn(i) {
    let lane = i / 4
    let byte_idx = i % 4
    guard lane < 4 else { b'\x00' }
    ((val >> (byte_idx * 8)) & 0xFFL).to_byte()
  })
}

///|
/// Helper to create splat64 pattern: replicate 64-bit value 2 times
fn splat64(n : UInt64) -> Bytes {
  let val = n.reinterpret_as_int64()
  Bytes::makei(16, fn(i) {
    let lane = i / 8
    let byte_idx = i % 8
    guard lane < 2 else { b'\x00' }
    ((val >> (byte_idx * 8)) & 0xFFL).to_byte()
  })
}

///|
/// splat(iconst) -> vconst
/// Converts splat of constant to vector constant
fn rule_splat_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Splat && node.children.length() == 1 {
          if eg.find_const(node.children[0]) is Some(c) {
            // Default to 64-bit splat (most common case)
            // In a real implementation, we'd need type information
            // to determine the lane width
            let pattern = splat64(c.reinterpret_as_uint64())
            let vconst_node = eg.add_vconst(pattern)
            let new_id = eg.merge(class_id, vconst_node)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

// ============================================================================
// Lift splat outside of binary operations
// op(splat(x), splat(y)) -> splat(op(x, y))
// ============================================================================

///|
/// Helper to check if a node is a Splat and get its child
fn find_splat_child(eg : EGraph, class_id : EClassId) -> EClassId? {
  for node in eg.get_nodes(class_id) {
    if node.op is Splat && node.children.length() == 1 {
      return Some(node.children[0])
    }
  }
  None
}

///|
/// band(splat(x), splat(y)) -> splat(band(x, y))
fn rule_band_splat_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) &&
            find_splat_child(eg, node.children[1]) is Some(y) {
            // band(splat(x), splat(y)) -> splat(band(x, y))
            let inner_and = eg.add_and(x, y)
            let new_node = eg.add({ op: Splat, children: [inner_and] })
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
/// bor(splat(x), splat(y)) -> splat(bor(x, y))
fn rule_bor_splat_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) &&
            find_splat_child(eg, node.children[1]) is Some(y) {
            let inner_or = eg.add_or(x, y)
            let new_node = eg.add({ op: Splat, children: [inner_or] })
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
/// bxor(splat(x), splat(y)) -> splat(bxor(x, y))
fn rule_bxor_splat_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) &&
            find_splat_child(eg, node.children[1]) is Some(y) {
            let inner_xor = eg.add_xor(x, y)
            let new_node = eg.add({ op: Splat, children: [inner_xor] })
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
/// bnot(splat(x)) -> splat(bnot(x))
fn rule_bnot_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Bnot && node.children.length() == 1 {
          if find_splat_child(eg, node.children[0]) is Some(x) {
            let inner_bnot = eg.add({ op: Bnot, children: [x] })
            let new_node = eg.add({ op: Splat, children: [inner_bnot] })
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
/// iadd(splat(x), splat(y)) -> splat(iadd(x, y))
fn rule_iadd_splat_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) &&
            find_splat_child(eg, node.children[1]) is Some(y) {
            let inner_add = eg.add_add(x, y)
            let new_node = eg.add({ op: Splat, children: [inner_add] })
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
/// isub(splat(x), splat(y)) -> splat(isub(x, y))
fn rule_isub_splat_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) &&
            find_splat_child(eg, node.children[1]) is Some(y) {
            let inner_sub = eg.add_sub(x, y)
            let new_node = eg.add({ op: Splat, children: [inner_sub] })
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
/// imul(splat(x), splat(y)) -> splat(imul(x, y))
fn rule_imul_splat_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) &&
            find_splat_child(eg, node.children[1]) is Some(y) {
            let inner_mul = eg.add_mul(x, y)
            let new_node = eg.add({ op: Splat, children: [inner_mul] })
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
/// ineg(splat(x)) -> splat(ineg(x))
fn rule_ineg_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Neg && node.children.length() == 1 {
          if find_splat_child(eg, node.children[0]) is Some(x) {
            let inner_neg = eg.add({ op: Neg, children: [x] })
            let new_node = eg.add({ op: Splat, children: [inner_neg] })
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
/// iabs(splat(x)) -> splat(iabs(x))
fn rule_iabs_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Iabs && node.children.length() == 1 {
          if find_splat_child(eg, node.children[0]) is Some(x) {
            let inner_iabs = eg.add({ op: Iabs, children: [x] })
            let new_node = eg.add({ op: Splat, children: [inner_iabs] })
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
/// popcnt(splat(x)) -> splat(popcnt(x))
fn rule_popcnt_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Popcnt && node.children.length() == 1 {
          if find_splat_child(eg, node.children[0]) is Some(x) {
            let inner_popcnt = eg.add({ op: Popcnt, children: [x] })
            let new_node = eg.add({ op: Splat, children: [inner_popcnt] })
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
/// smin(splat(x), splat(y)) -> splat(smin(x, y))
fn rule_smin_splat_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Smin && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) &&
            find_splat_child(eg, node.children[1]) is Some(y) {
            let inner_smin = eg.add({ op: Smin, children: [x, y] })
            let new_node = eg.add({ op: Splat, children: [inner_smin] })
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
/// umin(splat(x), splat(y)) -> splat(umin(x, y))
fn rule_umin_splat_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Umin && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) &&
            find_splat_child(eg, node.children[1]) is Some(y) {
            let inner_umin = eg.add({ op: Umin, children: [x, y] })
            let new_node = eg.add({ op: Splat, children: [inner_umin] })
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
/// smax(splat(x), splat(y)) -> splat(smax(x, y))
fn rule_smax_splat_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Smax && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) &&
            find_splat_child(eg, node.children[1]) is Some(y) {
            let inner_smax = eg.add({ op: Smax, children: [x, y] })
            let new_node = eg.add({ op: Splat, children: [inner_smax] })
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
/// umax(splat(x), splat(y)) -> splat(umax(x, y))
fn rule_umax_splat_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Umax && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) &&
            find_splat_child(eg, node.children[1]) is Some(y) {
            let inner_umax = eg.add({ op: Umax, children: [x, y] })
            let new_node = eg.add({ op: Splat, children: [inner_umax] })
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

// ============================================================================
// Shift/rotate operations: only first operand is splatted
// op(splat(x), y) -> splat(op(x, y))
// ============================================================================

///|
/// rotl(splat(x), y) -> splat(rotl(x, y))
fn rule_rotl_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Rotl && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) {
            let y = node.children[1]
            let inner_rotl = eg.add({ op: Rotl, children: [x, y] })
            let new_node = eg.add({ op: Splat, children: [inner_rotl] })
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
/// rotr(splat(x), y) -> splat(rotr(x, y))
fn rule_rotr_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Rotr && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) {
            let y = node.children[1]
            let inner_rotr = eg.add({ op: Rotr, children: [x, y] })
            let new_node = eg.add({ op: Splat, children: [inner_rotr] })
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
/// ishl(splat(x), y) -> splat(ishl(x, y))
fn rule_ishl_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Shl && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) {
            let y = node.children[1]
            let inner_shl = eg.add_shl(x, y)
            let new_node = eg.add({ op: Splat, children: [inner_shl] })
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
/// ushr(splat(x), y) -> splat(ushr(x, y))
fn rule_ushr_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ushr && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) {
            let y = node.children[1]
            let inner_ushr = eg.add({ op: Ushr, children: [x, y] })
            let new_node = eg.add({ op: Splat, children: [inner_ushr] })
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
/// sshr(splat(x), y) -> splat(sshr(x, y))
fn rule_sshr_splat() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sshr && node.children.length() == 2 {
          if find_splat_child(eg, node.children[0]) is Some(x) {
            let y = node.children[1]
            let inner_sshr = eg.add({ op: Sshr, children: [x, y] })
            let new_node = eg.add({ op: Splat, children: [inner_sshr] })
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
/// Collect all vector rules
pub fn vector_rules() -> Array[RewriteRule] {
  [
    rule_splat_const(),
    // Binary ops with splat on both sides
    rule_band_splat_splat(),
    rule_bor_splat_splat(),
    rule_bxor_splat_splat(),
    rule_iadd_splat_splat(),
    rule_isub_splat_splat(),
    rule_imul_splat_splat(),
    rule_smin_splat_splat(),
    rule_umin_splat_splat(),
    rule_smax_splat_splat(),
    rule_umax_splat_splat(),
    // Unary ops with splat
    rule_bnot_splat(),
    rule_ineg_splat(),
    rule_iabs_splat(),
    rule_popcnt_splat(),
    // Shift/rotate with splat on first operand only
    rule_rotl_splat(),
    rule_rotr_splat(),
    rule_ishl_splat(),
    rule_ushr_splat(),
    rule_sshr_splat(),
  ]
}
