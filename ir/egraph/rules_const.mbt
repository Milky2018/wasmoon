// Constant folding and strength reduction rules

///|
fn sign_extend(x : Int64, bits : Int) -> Int64 {
  if bits >= 64 {
    x
  } else {
    let shift = 64 - bits
    x << shift >> shift
  }
}

///|
fn rule_mul_pow2() -> RewriteRule {
  {
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
/// Constant folding for binary and unary operations
fn rule_const_fold() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        // Binary operations
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
                Shl => {
                  // Check bit width: default to 64 if unknown
                  let bits = eg.get_bits(class_id).unwrap_or(64)
                  if bits == 32 {
                    let amt = (rhs & 31L).to_int()
                    let result = (lhs << amt) & 0xFFFFFFFFL
                    Some(result)
                  } else {
                    let amt = (rhs & 63L).to_int()
                    Some(lhs << amt)
                  }
                }
                Sshr => {
                  // Check bit width: default to 64 if unknown
                  let bits = eg.get_bits(class_id).unwrap_or(64)
                  if bits == 32 {
                    let amt = (rhs & 31L).to_int()
                    // Sign-extend 32-bit value, then shift, then mask
                    let slhs = lhs << 32 >> 32 // sign-extend low 32 bits
                    let result = (slhs >> amt) & 0xFFFFFFFFL
                    Some(result)
                  } else {
                    let amt = (rhs & 63L).to_int()
                    Some(lhs >> amt)
                  }
                }
                Ushr => {
                  // Check bit width: default to 64 if unknown
                  let bits = eg.get_bits(class_id).unwrap_or(64)
                  if bits == 32 {
                    let amt = (rhs & 31L).to_int()
                    let ulhs = (lhs & 0xFFFFFFFFL).reinterpret_as_uint64()
                    let result = (ulhs >> amt).reinterpret_as_int64()
                    Some(result)
                  } else {
                    let amt = (rhs & 63L).to_int()
                    let ulhs = lhs.reinterpret_as_uint64()
                    Some((ulhs >> amt).reinterpret_as_int64())
                  }
                }
                Rotl => {
                  // Check bit width: default to 64 if unknown
                  let bits = eg.get_bits(class_id).unwrap_or(64)
                  if bits == 32 {
                    let amt = (rhs & 31L).to_int()
                    let ulhs = (lhs & 0xFFFFFFFFL).reinterpret_as_uint64()
                    let rotated = if amt == 0 {
                      ulhs
                    } else {
                      (ulhs << amt) | (ulhs >> (32 - amt))
                    }
                    Some((rotated & 0xFFFFFFFFUL).reinterpret_as_int64())
                  } else {
                    let amt = (rhs & 63L).to_int()
                    let ulhs = lhs.reinterpret_as_uint64()
                    let rotated = if amt == 0 {
                      ulhs
                    } else {
                      (ulhs << amt) | (ulhs >> (64 - amt))
                    }
                    Some(rotated.reinterpret_as_int64())
                  }
                }
                Rotr => {
                  // Check bit width: default to 64 if unknown
                  let bits = eg.get_bits(class_id).unwrap_or(64)
                  if bits == 32 {
                    let amt = (rhs & 31L).to_int()
                    let ulhs = (lhs & 0xFFFFFFFFL).reinterpret_as_uint64()
                    let rotated = if amt == 0 {
                      ulhs
                    } else {
                      (ulhs >> amt) | (ulhs << (32 - amt))
                    }
                    Some((rotated & 0xFFFFFFFFUL).reinterpret_as_int64())
                  } else {
                    let amt = (rhs & 63L).to_int()
                    let ulhs = lhs.reinterpret_as_uint64()
                    let rotated = if amt == 0 {
                      ulhs
                    } else {
                      (ulhs >> amt) | (ulhs << (64 - amt))
                    }
                    Some(rotated.reinterpret_as_int64())
                  }
                }
                Sdiv => {
                  let bits = eg.get_bits(class_id).unwrap_or(64)
                  let slhs = sign_extend(lhs, bits)
                  let srhs = sign_extend(rhs, bits)
                  if srhs == 0L {
                    None
                  } else if slhs == ty_smin(bits) && srhs == -1L {
                    None
                  } else {
                    Some(slhs / srhs)
                  }
                }
                Udiv => {
                  let bits = eg.get_bits(class_id).unwrap_or(64)
                  let mask = ty_umax(bits)
                  let ulhs = (lhs & mask).reinterpret_as_uint64()
                  let urhs = (rhs & mask).reinterpret_as_uint64()
                  if urhs == 0UL {
                    None
                  } else {
                    Some((ulhs / urhs).reinterpret_as_int64())
                  }
                }
                Srem => {
                  let bits = eg.get_bits(class_id).unwrap_or(64)
                  let slhs = sign_extend(lhs, bits)
                  let srhs = sign_extend(rhs, bits)
                  if srhs == 0L {
                    None
                  } else {
                    Some(slhs % srhs)
                  }
                }
                Urem => {
                  let bits = eg.get_bits(class_id).unwrap_or(64)
                  let mask = ty_umax(bits)
                  let ulhs = (lhs & mask).reinterpret_as_uint64()
                  let urhs = (rhs & mask).reinterpret_as_uint64()
                  if urhs == 0UL {
                    None
                  } else {
                    Some((ulhs % urhs).reinterpret_as_int64())
                  }
                }
                // icmp constant folding
                Icmp(cc) => {
                  let bits = eg.get_bits(node.children[0]).unwrap_or(64)
                  let mask = ty_umax(bits)
                  let slhs = sign_extend(lhs, bits)
                  let srhs = sign_extend(rhs, bits)
                  let ulhs = (lhs & mask).reinterpret_as_uint64()
                  let urhs = (rhs & mask).reinterpret_as_uint64()
                  let result = match cc {
                    0 => (lhs & mask) == (rhs & mask) // eq
                    1 => (lhs & mask) != (rhs & mask) // ne
                    2 => slhs < srhs // slt
                    3 => slhs <= srhs // sle
                    4 => slhs > srhs // sgt
                    5 => slhs >= srhs // sge
                    6 => ulhs < urhs // ult
                    7 => ulhs <= urhs // ule
                    8 => ulhs > urhs // ugt
                    9 => ulhs >= urhs // uge
                    _ => false
                  }
                  Some(if result { 1L } else { 0L })
                }
                Eq => {
                  let bits = eg.get_bits(node.children[0]).unwrap_or(64)
                  let mask = ty_umax(bits)
                  Some(if (lhs & mask) == (rhs & mask) { 1L } else { 0L })
                }
                Ne => {
                  let bits = eg.get_bits(node.children[0]).unwrap_or(64)
                  let mask = ty_umax(bits)
                  Some(if (lhs & mask) != (rhs & mask) { 1L } else { 0L })
                }
                _ => None
              }
              if result is Some(r) {
                let result_node = eg.add_const(r)
                let new_id = eg.subsume(class_id, result_node)
                changed = new_id != class_id || changed
              }
            }
          }
        }
        // Unary operations
        if node.children.length() == 1 {
          if eg.find_const(node.children[0]) is Some(x) {
            let result : Int64? = match node.op {
              Neg => Some(-x)
              Bnot => Some(x.lnot())
              Clz => Some(x.clz().to_int64())
              Ctz => Some(x.ctz().to_int64())
              Popcnt => Some(x.popcnt().to_int64())
              Bswap => Some(bswap64(x))
              Bitrev => Some(bitrev64(x))
              _ => None
            }
            if result is Some(r) {
              let result_node = eg.add_const(r)
              let new_id = eg.subsume(class_id, result_node)
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
/// Byte swap for 64-bit integer
fn bswap64(x : Int64) -> Int64 {
  let u = x.reinterpret_as_uint64()
  let b0 = (u >> 56) & 0xFFUL
  let b1 = ((u >> 40) & 0xFFUL) << 8
  let b2 = ((u >> 24) & 0xFFUL) << 16
  let b3 = ((u >> 8) & 0xFFUL) << 24
  let b4 = (u & 0xFFUL) << 56
  let b5 = (u & 0xFF00UL) << 40
  let b6 = (u & 0xFF0000UL) << 24
  let b7 = (u & 0xFF000000UL) << 8
  (b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7).reinterpret_as_int64()
}

///|
/// Bit reverse for 64-bit integer
fn bitrev64(x : Int64) -> Int64 {
  let mut u = x.reinterpret_as_uint64()
  // Swap odd and even bits
  u = ((u >> 1) & 0x5555555555555555UL) | ((u & 0x5555555555555555UL) << 1)
  // Swap consecutive pairs
  u = ((u >> 2) & 0x3333333333333333UL) | ((u & 0x3333333333333333UL) << 2)
  // Swap nibbles
  u = ((u >> 4) & 0x0F0F0F0F0F0F0F0FUL) | ((u & 0x0F0F0F0F0F0F0F0FUL) << 4)
  // Now byte swap to reverse byte order
  bswap64(u.reinterpret_as_int64())
  .reinterpret_as_uint64()
  .reinterpret_as_int64()
}

///|
/// (a | c1) | c2 = a | (c1 | c2) - reassociate or constants
fn rule_reassoc_or_const() -> RewriteRule {
  {
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

///|
/// select(non_zero, x, _) -> x
/// select(0, _, y) -> y
fn rule_select_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Select && node.children.length() == 3 {
          if eg.find_const(node.children[0]) is Some(cond) {
            // select(cond, x, y): if cond != 0 -> x, else -> y
            let result = if cond != 0L {
              node.children[1]
            } else {
              node.children[2]
            }
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
/// (sub x k) -> (add x -k) when k is negative (so -k is positive)
/// This helps simplify patterns like x - (-5) -> x + 5
fn rule_sub_neg_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(k) {
            // x - k where k < 0: convert to x + (-k)
            if k < 0L {
              let neg_k = eg.add_const(-k)
              let new_add = eg.add_add(node.children[0], neg_k)
              let new_id = eg.merge(class_id, new_add)
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
/// Tree rebalancing for add: ((a + B) + (c + D)) -> ((a + c) + (B + D))
/// where B and D are constants
fn rule_rebalance_add_consts() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Add && left.children.length() == 2 {
              if eg.find_const(left.children[1]) is Some(_) {
                for right in eg.get_nodes(node.children[1]) {
                  if right.op is Add && right.children.length() == 2 {
                    if eg.find_const(right.children[1]) is Some(_) {
                      // ((a + B) + (c + D)) -> ((a + c) + (B + D))
                      let ac = eg.add_add(left.children[0], right.children[0])
                      let bd = eg.add_add(left.children[1], right.children[1])
                      let result = eg.add_add(ac, bd)
                      let new_id = eg.merge(class_id, result)
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
/// Tree rebalancing for mul: ((a * B) * (c * D)) -> ((a * c) * (B * D))
fn rule_rebalance_mul_consts() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Mul && left.children.length() == 2 {
              if eg.find_const(left.children[1]) is Some(_) {
                for right in eg.get_nodes(node.children[1]) {
                  if right.op is Mul && right.children.length() == 2 {
                    if eg.find_const(right.children[1]) is Some(_) {
                      let ac = eg.add_mul(left.children[0], right.children[0])
                      let bd = eg.add_mul(left.children[1], right.children[1])
                      let result = eg.add_mul(ac, bd)
                      let new_id = eg.merge(class_id, result)
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
/// Tree rebalancing for and: ((a & B) & (c & D)) -> ((a & c) & (B & D))
fn rule_rebalance_and_consts() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is And && left.children.length() == 2 {
              if eg.find_const(left.children[1]) is Some(_) {
                for right in eg.get_nodes(node.children[1]) {
                  if right.op is And && right.children.length() == 2 {
                    if eg.find_const(right.children[1]) is Some(_) {
                      let ac = eg.add_and(left.children[0], right.children[0])
                      let bd = eg.add_and(left.children[1], right.children[1])
                      let result = eg.add_and(ac, bd)
                      let new_id = eg.merge(class_id, result)
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
/// Tree rebalancing for or: ((a | B) | (c | D)) -> ((a | c) | (B | D))
fn rule_rebalance_or_consts() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Or && left.children.length() == 2 {
              if eg.find_const(left.children[1]) is Some(_) {
                for right in eg.get_nodes(node.children[1]) {
                  if right.op is Or && right.children.length() == 2 {
                    if eg.find_const(right.children[1]) is Some(_) {
                      let ac = eg.add_or(left.children[0], right.children[0])
                      let bd = eg.add_or(left.children[1], right.children[1])
                      let result = eg.add_or(ac, bd)
                      let new_id = eg.merge(class_id, result)
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
/// Tree rebalancing for xor: ((a ^ B) ^ (c ^ D)) -> ((a ^ c) ^ (B ^ D))
fn rule_rebalance_xor_consts() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Xor && left.children.length() == 2 {
              if eg.find_const(left.children[1]) is Some(_) {
                for right in eg.get_nodes(node.children[1]) {
                  if right.op is Xor && right.children.length() == 2 {
                    if eg.find_const(right.children[1]) is Some(_) {
                      let ac = eg.add_xor(left.children[0], right.children[0])
                      let bd = eg.add_xor(left.children[1], right.children[1])
                      let result = eg.add_xor(ac, bd)
                      let new_id = eg.merge(class_id, result)
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
