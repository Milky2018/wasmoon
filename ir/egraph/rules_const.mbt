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
/// Constant folding for binary and unary operations
fn rule_const_fold() -> RewriteRule {
  {
    name: "const_fold",
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
                  let ulhs = lhs.reinterpret_as_uint64()
                  if rhs >= 0L && rhs < 64L {
                    Some((ulhs >> rhs.to_int()).reinterpret_as_int64())
                  } else {
                    None
                  }
                }
                Rotl => {
                  let amt = (rhs & 63L).to_int()
                  let ulhs = lhs.reinterpret_as_uint64()
                  Some(
                    ((ulhs << amt) | (ulhs >> (64 - amt))).reinterpret_as_int64(),
                  )
                }
                Rotr => {
                  let amt = (rhs & 63L).to_int()
                  let ulhs = lhs.reinterpret_as_uint64()
                  Some(
                    ((ulhs >> amt) | (ulhs << (64 - amt))).reinterpret_as_int64(),
                  )
                }
                Sdiv => if rhs != 0L { Some(lhs / rhs) } else { None }
                Udiv => {
                  let ulhs = lhs.reinterpret_as_uint64()
                  let urhs = rhs.reinterpret_as_uint64()
                  if urhs != 0UL {
                    Some((ulhs / urhs).reinterpret_as_int64())
                  } else {
                    None
                  }
                }
                Srem => if rhs != 0L { Some(lhs % rhs) } else { None }
                Urem => {
                  let ulhs = lhs.reinterpret_as_uint64()
                  let urhs = rhs.reinterpret_as_uint64()
                  if urhs != 0UL {
                    Some((ulhs % urhs).reinterpret_as_int64())
                  } else {
                    None
                  }
                }
                // icmp constant folding
                Icmp(cc) => {
                  let result = match cc {
                    0 => lhs == rhs // eq
                    1 => lhs != rhs // ne
                    2 => lhs < rhs // slt
                    3 => lhs <= rhs // sle
                    4 => lhs > rhs // sgt
                    5 => lhs >= rhs // sge
                    6 =>
                      lhs.reinterpret_as_uint64() < rhs.reinterpret_as_uint64() // ult
                    7 =>
                      lhs.reinterpret_as_uint64() <= rhs.reinterpret_as_uint64() // ule
                    8 =>
                      lhs.reinterpret_as_uint64() > rhs.reinterpret_as_uint64() // ugt
                    9 =>
                      lhs.reinterpret_as_uint64() >= rhs.reinterpret_as_uint64() // uge
                    _ => false
                  }
                  Some(if result { 1L } else { 0L })
                }
                Eq => Some(if lhs == rhs { 1L } else { 0L })
                Ne => Some(if lhs != rhs { 1L } else { 0L })
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
              let new_id = eg.merge(class_id, result_node)
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

///|
/// select(non_zero, x, _) -> x
/// select(0, _, y) -> y
fn rule_select_const() -> RewriteRule {
  {
    name: "select_const",
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
    name: "sub_neg_const",
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
    name: "rebalance_add_consts",
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
    name: "rebalance_mul_consts",
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
    name: "rebalance_and_consts",
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
    name: "rebalance_or_consts",
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
    name: "rebalance_xor_consts",
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
