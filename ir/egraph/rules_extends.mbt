// Sign/zero extension optimization rules

///|
/// uextend(uextend(x)) → uextend(x)
/// Chained unsigned extends can be collapsed
fn rule_uextend_uextend() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Uextend(_, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Uextend(from_bits, _) =>
                    if inner.children.length() == 1 {
                      // uextend(uextend(x)) = uextend(x) with updated type info
                      let new_node = eg.add({
                        op: Uextend(from_bits, to_bits),
                        children: [inner.children[0]],
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
      changed
    },
  }
}

///|
/// sextend(sextend(x)) → sextend(x)
/// Chained signed extends can be collapsed
fn rule_sextend_sextend() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Sextend(_, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Sextend(from_bits, _) =>
                    if inner.children.length() == 1 {
                      // sextend(sextend(x)) = sextend(x) with updated type info
                      let new_node = eg.add({
                        op: Sextend(from_bits, to_bits),
                        children: [inner.children[0]],
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
      changed
    },
  }
}

///|
/// sextend(uextend(x)) → uextend(x)
/// Once unsigned extended, sign-extending is the same as zero-extending
fn rule_sextend_uextend() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Sextend(_, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Uextend(from_bits, _) =>
                    if inner.children.length() == 1 {
                      // sextend(uextend(x)) = uextend(x) with updated type info
                      let new_node = eg.add({
                        op: Uextend(from_bits, to_bits),
                        children: [inner.children[0]],
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
      changed
    },
  }
}

///|
/// sextend(icmp(...)) → uextend(icmp(...))
/// icmp results are 0 or 1, so sign-extending is the same as zero-extending
fn rule_sextend_icmp() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Sextend(from_bits, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Icmp(_) | Eq | Ne => {
                    // sextend(icmp/eq/ne) = uextend(icmp/eq/ne) with same type info
                    let new_node = eg.add({
                      op: Uextend(from_bits, to_bits),
                      children: [node.children[0]],
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
      changed
    },
  }
}

///|
/// ireduce(uextend(x)) → x when final type equals original type
/// Reduction of an extend back to original type is identity
fn rule_ireduce_uextend() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(_, reduce_to) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Uextend(extend_from, _) =>
                    if inner.children.length() == 1 {
                      // ireduce(uextend(x)) = x when reduce_to == extend_from
                      if reduce_to == extend_from {
                        let new_id = eg.merge(class_id, inner.children[0])
                        changed = new_id != class_id || changed
                      }
                      // If reduce_to < extend_from, we still need ireduce(x)
                      // If reduce_to > extend_from, result is uextend with new types
                    }
                  _ => ()
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
/// ireduce(sextend(x)) → x when final type equals original type
/// Reduction of an extend back to original type is identity
fn rule_ireduce_sextend() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(_, reduce_to) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Sextend(extend_from, _) =>
                    if inner.children.length() == 1 {
                      // ireduce(sextend(x)) = x when reduce_to == extend_from
                      if reduce_to == extend_from {
                        let new_id = eg.merge(class_id, inner.children[0])
                        changed = new_id != class_id || changed
                      }
                      // If reduce_to < extend_from, we need ireduce(x) directly
                    }
                  _ => ()
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
/// band(uextend(x), uextend(y)) → uextend(band(x, y))
/// Bitwise AND can be pushed inside uextends
fn rule_band_uextend() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Uextend(from_bits, to_bits) =>
                if left.children.length() == 1 {
                  for right in eg.get_nodes(node.children[1]) {
                    match right.op {
                      Uextend(_, _) =>
                        if right.children.length() == 1 {
                          // band(uextend(x), uextend(y)) = uextend(band(x, y))
                          let inner_and = eg.add({
                            op: And,
                            children: [left.children[0], right.children[0]],
                          })
                          let new_node = eg.add({
                            op: Uextend(from_bits, to_bits),
                            children: [inner_and],
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
      changed
    },
  }
}

///|
/// bor(uextend(x), uextend(y)) → uextend(bor(x, y))
/// Bitwise OR can be pushed inside uextends
fn rule_bor_uextend() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Uextend(from_bits, to_bits) =>
                if left.children.length() == 1 {
                  for right in eg.get_nodes(node.children[1]) {
                    match right.op {
                      Uextend(_, _) =>
                        if right.children.length() == 1 {
                          // bor(uextend(x), uextend(y)) = uextend(bor(x, y))
                          let inner_or = eg.add({
                            op: Or,
                            children: [left.children[0], right.children[0]],
                          })
                          let new_node = eg.add({
                            op: Uextend(from_bits, to_bits),
                            children: [inner_or],
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
      changed
    },
  }
}

///|
/// bxor(uextend(x), uextend(y)) → uextend(bxor(x, y))
/// Bitwise XOR can be pushed inside uextends
fn rule_bxor_uextend() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Uextend(from_bits, to_bits) =>
                if left.children.length() == 1 {
                  for right in eg.get_nodes(node.children[1]) {
                    match right.op {
                      Uextend(_, _) =>
                        if right.children.length() == 1 {
                          // bxor(uextend(x), uextend(y)) = uextend(bxor(x, y))
                          let inner_xor = eg.add({
                            op: Xor,
                            children: [left.children[0], right.children[0]],
                          })
                          let new_node = eg.add({
                            op: Uextend(from_bits, to_bits),
                            children: [inner_xor],
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
      changed
    },
  }
}

///|
/// ireduce(ineg(x)) → ineg(ireduce(x))
/// Reduction can be pushed inside negation
fn rule_ireduce_ineg() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(from_bits, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                if inner.op is Neg && inner.children.length() == 1 {
                  // ireduce(neg(x)) = neg(ireduce(x))
                  let inner_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[0]],
                  })
                  let new_node = eg.add({ op: Neg, children: [inner_reduce] })
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
/// ireduce(bnot(x)) → bnot(ireduce(x))
/// Reduction can be pushed inside bitwise NOT
fn rule_ireduce_bnot() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(from_bits, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                if inner.op is Bnot && inner.children.length() == 1 {
                  // ireduce(bnot(x)) = bnot(ireduce(x))
                  let inner_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[0]],
                  })
                  let new_node = eg.add({ op: Bnot, children: [inner_reduce] })
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
/// ireduce(iadd(x, y)) → iadd(ireduce(x), ireduce(y))
/// Reduction can be pushed inside addition
fn rule_ireduce_iadd() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(from_bits, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                if inner.op is Add && inner.children.length() == 2 {
                  // ireduce(add(x, y)) = add(ireduce(x), ireduce(y))
                  let left_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[0]],
                  })
                  let right_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[1]],
                  })
                  let new_node = eg.add({
                    op: Add,
                    children: [left_reduce, right_reduce],
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
/// ireduce(isub(x, y)) → isub(ireduce(x), ireduce(y))
/// Reduction can be pushed inside subtraction
fn rule_ireduce_isub() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(from_bits, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                if inner.op is Sub && inner.children.length() == 2 {
                  // ireduce(sub(x, y)) = sub(ireduce(x), ireduce(y))
                  let left_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[0]],
                  })
                  let right_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[1]],
                  })
                  let new_node = eg.add({
                    op: Sub,
                    children: [left_reduce, right_reduce],
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
/// ireduce(imul(x, y)) → imul(ireduce(x), ireduce(y))
/// Reduction can be pushed inside multiplication
fn rule_ireduce_imul() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(from_bits, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                if inner.op is Mul && inner.children.length() == 2 {
                  // ireduce(mul(x, y)) = mul(ireduce(x), ireduce(y))
                  let left_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[0]],
                  })
                  let right_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[1]],
                  })
                  let new_node = eg.add({
                    op: Mul,
                    children: [left_reduce, right_reduce],
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
/// ireduce(band(x, y)) → band(ireduce(x), ireduce(y))
/// Reduction can be pushed inside bitwise AND
fn rule_ireduce_band() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(from_bits, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                if inner.op is And && inner.children.length() == 2 {
                  // ireduce(and(x, y)) = and(ireduce(x), ireduce(y))
                  let left_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[0]],
                  })
                  let right_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[1]],
                  })
                  let new_node = eg.add({
                    op: And,
                    children: [left_reduce, right_reduce],
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
/// ireduce(bor(x, y)) → bor(ireduce(x), ireduce(y))
/// Reduction can be pushed inside bitwise OR
fn rule_ireduce_bor() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(from_bits, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                if inner.op is Or && inner.children.length() == 2 {
                  // ireduce(or(x, y)) = or(ireduce(x), ireduce(y))
                  let left_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[0]],
                  })
                  let right_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[1]],
                  })
                  let new_node = eg.add({
                    op: Or,
                    children: [left_reduce, right_reduce],
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
/// ireduce(bxor(x, y)) → bxor(ireduce(x), ireduce(y))
/// Reduction can be pushed inside bitwise XOR
fn rule_ireduce_bxor() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(from_bits, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                if inner.op is Xor && inner.children.length() == 2 {
                  // ireduce(xor(x, y)) = xor(ireduce(x), ireduce(y))
                  let left_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[0]],
                  })
                  let right_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[1]],
                  })
                  let new_node = eg.add({
                    op: Xor,
                    children: [left_reduce, right_reduce],
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
/// eq(sextend(x), 0) → eq(x, 0)
/// Sign-extending can't change whether a number is zero
fn rule_eq_sextend_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Eq && node.children.length() == 2 {
          // Check if left is sextend and right is zero
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Sextend(_, _) =>
                if left.children.length() == 1 {
                  for right in eg.get_nodes(node.children[1]) {
                    if right.op == Const(0L) {
                      // eq(sextend(x), 0) = eq(x, 0)
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
              _ => ()
            }
          }
          // Also check symmetric case: eq(0, sextend(x))
          for left in eg.get_nodes(node.children[0]) {
            if left.op == Const(0L) {
              for right in eg.get_nodes(node.children[1]) {
                match right.op {
                  Sextend(_, _) =>
                    if right.children.length() == 1 {
                      let zero = eg.add_const(0L)
                      let new_node = eg.add({
                        op: Eq,
                        children: [right.children[0], zero],
                      })
                      let new_id = eg.merge(class_id, new_node)
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
/// ne(sextend(x), 0) → ne(x, 0)
/// Sign-extending can't change whether a number is zero
fn rule_ne_sextend_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ne && node.children.length() == 2 {
          // Check if left is sextend and right is zero
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Sextend(_, _) =>
                if left.children.length() == 1 {
                  for right in eg.get_nodes(node.children[1]) {
                    if right.op == Const(0L) {
                      // ne(sextend(x), 0) = ne(x, 0)
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
              _ => ()
            }
          }
          // Also check symmetric case
          for left in eg.get_nodes(node.children[0]) {
            if left.op == Const(0L) {
              for right in eg.get_nodes(node.children[1]) {
                match right.op {
                  Sextend(_, _) =>
                    if right.children.length() == 1 {
                      let zero = eg.add_const(0L)
                      let new_node = eg.add({
                        op: Ne,
                        children: [right.children[0], zero],
                      })
                      let new_id = eg.merge(class_id, new_node)
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
/// Helper: check if IntCC is a signed comparison
fn is_signed_cc(cc : Int) -> Bool {
  // IntCC: 0=eq, 1=ne, 2=slt, 3=sle, 4=sgt, 5=sge, 6=ult, 7=ule, 8=ugt, 9=uge
  cc >= 2 && cc <= 5 // slt, sle, sgt, sge
}

///|
/// icmp(signed_cc, sextend(x), 0) → icmp(signed_cc, x, 0)
/// Sign-extending doesn't change signed comparisons with zero
fn rule_icmp_sextend_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if is_signed_cc(cc) && node.children.length() == 2 {
              for left in eg.get_nodes(node.children[0]) {
                match left.op {
                  Sextend(_, _) =>
                    if left.children.length() == 1 {
                      for right in eg.get_nodes(node.children[1]) {
                        if right.op == Const(0L) {
                          // icmp(cc, sextend(x), 0) = icmp(cc, x, 0)
                          let zero = eg.add_const(0L)
                          let new_node = eg.add({
                            op: Icmp(cc),
                            children: [left.children[0], zero],
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
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// ireduce(ireduce(x)) → ireduce(x)
/// Chained reduces can be collapsed (use outermost from_bits and innermost to_bits)
fn rule_ireduce_ireduce() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(_, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Ireduce(from_bits, _) =>
                    if inner.children.length() == 1 {
                      // ireduce(ireduce(x)) = ireduce(x) with updated type info
                      let new_node = eg.add({
                        op: Ireduce(from_bits, to_bits),
                        children: [inner.children[0]],
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
      changed
    },
  }
}

///|
/// iadd(uextend(x), uextend(y)) → uextend(iadd(x, y))
/// Addition can be pushed inside uextends when there's no overflow concern
/// Note: This is only valid when the result type is large enough to not overflow
fn rule_iadd_uextend() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Uextend(from_bits, to_bits) =>
                if left.children.length() == 1 {
                  for right in eg.get_nodes(node.children[1]) {
                    match right.op {
                      Uextend(_, _) =>
                        if right.children.length() == 1 {
                          // iadd(uextend(x), uextend(y)) = uextend(iadd(x, y))
                          let inner_add = eg.add({
                            op: Add,
                            children: [left.children[0], right.children[0]],
                          })
                          let new_node = eg.add({
                            op: Uextend(from_bits, to_bits),
                            children: [inner_add],
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
      changed
    },
  }
}

///|
/// isub(uextend(x), uextend(y)) → sextend(isub(x, y))
/// Subtraction of uextended values produces a signed result
fn rule_isub_uextend() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Uextend(from_bits, to_bits) =>
                if left.children.length() == 1 {
                  for right in eg.get_nodes(node.children[1]) {
                    match right.op {
                      Uextend(_, _) =>
                        if right.children.length() == 1 {
                          // isub(uextend(x), uextend(y)) = sextend(isub(x, y))
                          let inner_sub = eg.add({
                            op: Sub,
                            children: [left.children[0], right.children[0]],
                          })
                          let new_node = eg.add({
                            op: Sextend(from_bits, to_bits),
                            children: [inner_sub],
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
      changed
    },
  }
}

///|
/// ireduce(ishl(x, y)) → ishl(ireduce(x), y)
/// Shift amount doesn't need to be reduced, only the value being shifted
fn rule_ireduce_ishl() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(from_bits, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                if inner.op is Shl && inner.children.length() == 2 {
                  // ireduce(shl(x, y)) = shl(ireduce(x), y)
                  let value_reduce = eg.add({
                    op: Ireduce(from_bits, to_bits),
                    children: [inner.children[0]],
                  })
                  let new_node = eg.add({
                    op: Shl,
                    children: [value_reduce, inner.children[1]],
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
/// slt(uextend(x), 0) → 0
/// Zero-extended values are always non-negative, so slt with 0 is always false
fn rule_slt_uextend_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_SLT && node.children.length() == 2 {
              // Check if left is uextend and right is zero
              for left in eg.get_nodes(node.children[0]) {
                match left.op {
                  Uextend(_, _) =>
                    for right in eg.get_nodes(node.children[1]) {
                      if right.op == Const(0L) {
                        // slt(uextend(x), 0) = 0 (always false)
                        let false_const = eg.add_const(0L)
                        let new_id = eg.merge(class_id, false_const)
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
      changed
    },
  }
}

///|
/// sge(uextend(x), 0) → 1
/// Zero-extended values are always non-negative, so sge with 0 is always true
fn rule_sge_uextend_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Icmp(cc) =>
            if cc == CC_SGE && node.children.length() == 2 {
              // Check if left is uextend and right is zero
              for left in eg.get_nodes(node.children[0]) {
                match left.op {
                  Uextend(_, _) =>
                    for right in eg.get_nodes(node.children[1]) {
                      if right.op == Const(0L) {
                        // sge(uextend(x), 0) = 1 (always true)
                        let true_const = eg.add_const(1L)
                        let new_id = eg.merge(class_id, true_const)
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
      changed
    },
  }
}

///|
/// Helper: check if a constant is a type mask (0xFF, 0xFFFF, 0xFFFFFFFF)
fn is_type_mask(c : Int64) -> Bool {
  c == 0xFFL || c == 0xFFFFL || c == 0xFFFFFFFFL
}

///|
/// band(uextend(x), mask) → uextend(x) when mask covers all bits of narrow type
/// If masking with 0xFF/0xFFFF/0xFFFFFFFF and value is uextended, mask is no-op
fn rule_band_uextend_mask() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          // Check band(uextend(x), mask)
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Uextend(_, _) =>
                if left.children.length() == 1 {
                  for right in eg.get_nodes(node.children[1]) {
                    match right.op {
                      Const(mask) =>
                        if is_type_mask(mask) {
                          // band(uextend(x), mask) = uextend(x) when mask covers narrow type
                          // This is safe because uextend already zeroes high bits
                          let new_id = eg.merge(class_id, node.children[0])
                          changed = new_id != class_id || changed
                        }
                      _ => ()
                    }
                  }
                }
              _ => ()
            }
          }
          // Also check band(mask, uextend(x)) - symmetric case
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Const(mask) =>
                if is_type_mask(mask) {
                  for right in eg.get_nodes(node.children[1]) {
                    match right.op {
                      Uextend(_, _) =>
                        if right.children.length() == 1 {
                          let new_id = eg.merge(class_id, node.children[1])
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
/// band(sextend(x), mask) → uextend(x) when mask is narrow type mask
/// Masking out the sign-extended bits turns sextend into uextend
fn rule_band_sextend_mask() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          // Check band(sextend(x), mask)
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Sextend(from_bits, to_bits) =>
                if left.children.length() == 1 {
                  for right in eg.get_nodes(node.children[1]) {
                    match right.op {
                      Const(mask) =>
                        if is_type_mask(mask) {
                          // band(sextend(x), mask) = uextend(x)
                          // Masking clears the sign-extended bits
                          let new_node = eg.add({
                            op: Uextend(from_bits, to_bits),
                            children: [left.children[0]],
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
          // Symmetric case
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Const(mask) =>
                if is_type_mask(mask) {
                  for right in eg.get_nodes(node.children[1]) {
                    match right.op {
                      Sextend(from_bits, to_bits) =>
                        if right.children.length() == 1 {
                          let new_node = eg.add({
                            op: Uextend(from_bits, to_bits),
                            children: [right.children[0]],
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
      changed
    },
  }
}

///|
/// Helper: get mask for a given bit width
fn mask_for_bits(bits : Int) -> Int64 {
  match bits {
    8 => 0xFFL
    16 => 0xFFFFL
    32 => 0xFFFFFFFFL
    64 => -1L // All ones
    _ => -1L
  }
}

///|
/// ireduce(const(c)) → const(c & mask)
/// Constant folding through integer reduction - truncate constant to target width
fn rule_ireduce_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(_, to_bits) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Const(c) => {
                    // ireduce(const(c)) = const(c & mask)
                    let mask = mask_for_bits(to_bits)
                    let truncated = c & mask
                    let new_const = eg.add_const(truncated)
                    let new_id = eg.merge(class_id, new_const)
                    changed = new_id != class_id || changed
                  }
                  _ => ()
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
/// uextend with from_bits == to_bits → identity
/// Extending to the same width is a no-op
fn rule_uextend_identity() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Uextend(from_bits, to_bits) =>
            if from_bits == to_bits && node.children.length() == 1 {
              // uextend(x) where widths match = x
              let new_id = eg.merge(class_id, node.children[0])
              changed = new_id != class_id || changed
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// sextend with from_bits == to_bits → identity
/// Extending to the same width is a no-op
fn rule_sextend_identity() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Sextend(from_bits, to_bits) =>
            if from_bits == to_bits && node.children.length() == 1 {
              // sextend(x) where widths match = x
              let new_id = eg.merge(class_id, node.children[0])
              changed = new_id != class_id || changed
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// ireduce with from_bits == to_bits → identity
/// Reducing to the same width is a no-op
fn rule_ireduce_identity() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(from_bits, to_bits) =>
            if from_bits == to_bits && node.children.length() == 1 {
              // ireduce(x) where widths match = x
              let new_id = eg.merge(class_id, node.children[0])
              changed = new_id != class_id || changed
            }
          _ => ()
        }
      }
      changed
    },
  }
}

///|
/// band(uextend(x), mask) → uextend(x) when mask >= type_mask(from_bits)
/// More precise version that uses actual bit width information
fn rule_band_uextend_mask_precise() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          // Check band(uextend(x), mask)
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Uextend(from_bits, _) =>
                if left.children.length() == 1 {
                  let type_mask = mask_for_bits(from_bits)
                  for right in eg.get_nodes(node.children[1]) {
                    match right.op {
                      Const(mask) =>
                        // If the mask covers all bits of the narrow type, the AND is a no-op
                        if (mask & type_mask) == type_mask {
                          let new_id = eg.merge(class_id, node.children[0])
                          changed = new_id != class_id || changed
                        }
                      _ => ()
                    }
                  }
                }
              _ => ()
            }
          }
          // Symmetric case: band(mask, uextend(x))
          for left in eg.get_nodes(node.children[0]) {
            match left.op {
              Const(mask) =>
                for right in eg.get_nodes(node.children[1]) {
                  match right.op {
                    Uextend(from_bits, _) =>
                      if right.children.length() == 1 {
                        let type_mask = mask_for_bits(from_bits)
                        if (mask & type_mask) == type_mask {
                          let new_id = eg.merge(class_id, node.children[1])
                          changed = new_id != class_id || changed
                        }
                      }
                    _ => ()
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
/// ireduce(uextend(x)) → ireduce(x) when reduce_to < extend_from
/// If we're reducing to a size smaller than the original, skip the extend
fn rule_ireduce_uextend_skip() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(_, reduce_to) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Uextend(extend_from, _) =>
                    if inner.children.length() == 1 && reduce_to < extend_from {
                      // ireduce(uextend(x)) where reduce_to < extend_from
                      // = ireduce(x) directly (skip the extend)
                      let new_node = eg.add({
                        op: Ireduce(extend_from, reduce_to),
                        children: [inner.children[0]],
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
      changed
    },
  }
}

///|
/// ireduce(sextend(x)) → ireduce(x) when reduce_to < extend_from
/// If we're reducing to a size smaller than the original, skip the extend
fn rule_ireduce_sextend_skip() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(_, reduce_to) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Sextend(extend_from, _) =>
                    if inner.children.length() == 1 && reduce_to < extend_from {
                      // ireduce(sextend(x)) where reduce_to < extend_from
                      // = ireduce(x) directly (skip the extend)
                      let new_node = eg.add({
                        op: Ireduce(extend_from, reduce_to),
                        children: [inner.children[0]],
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
      changed
    },
  }
}

///|
/// ireduce(uextend(x)) → uextend(x) when reduce_to > extend_from
/// If we're "reducing" to a larger size than the original, it's actually an extend
fn rule_ireduce_uextend_to_extend() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(_, reduce_to) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Uextend(extend_from, _) =>
                    if inner.children.length() == 1 && reduce_to > extend_from {
                      // ireduce(uextend(x)) where reduce_to > extend_from
                      // = uextend(x) from extend_from to reduce_to
                      let new_node = eg.add({
                        op: Uextend(extend_from, reduce_to),
                        children: [inner.children[0]],
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
      changed
    },
  }
}

///|
/// ireduce(sextend(x)) → sextend(x) when reduce_to > extend_from
/// If we're "reducing" to a larger size than the original, it's actually a sign extend
fn rule_ireduce_sextend_to_extend() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Ireduce(_, reduce_to) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Sextend(extend_from, _) =>
                    if inner.children.length() == 1 && reduce_to > extend_from {
                      // ireduce(sextend(x)) where reduce_to > extend_from
                      // = sextend(x) from extend_from to reduce_to
                      let new_node = eg.add({
                        op: Sextend(extend_from, reduce_to),
                        children: [inner.children[0]],
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
      changed
    },
  }
}

///|
/// uextend(const(c)) → const(c & mask)
/// Zero-extending a constant requires masking to from_bits width
/// (IR stores constants as Int64, so we must clear any sign-extended bits)
fn rule_uextend_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Uextend(from_bits, _) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Const(c) => {
                    // uextend(const(c)) = const(c & mask)
                    // Must mask to from_bits width for proper zero-extension
                    let mask = mask_for_bits(from_bits)
                    let masked_c = c & mask
                    let new_const = eg.add_const(masked_c)
                    let new_id = eg.merge(class_id, new_const)
                    changed = new_id != class_id || changed
                  }
                  _ => ()
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
/// sextend(const(c)) → const(sign_extended_c)
/// Sign-extending a constant produces the sign-extended value
fn rule_sextend_const() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        match node.op {
          Sextend(from_bits, _) =>
            if node.children.length() == 1 {
              for inner in eg.get_nodes(node.children[0]) {
                match inner.op {
                  Const(c) => {
                    // sextend(const(c)) = const(sign_extended_c)
                    // Sign-extend the constant from from_bits to 64 bits
                    let sign_bit = 1L << (from_bits - 1)
                    let mask = mask_for_bits(from_bits)
                    let masked = c & mask
                    let extended = if (masked & sign_bit) != 0L {
                      // Negative: set all high bits
                      masked | (-1L ^ mask)
                    } else {
                      // Positive: keep as is
                      masked
                    }
                    let new_const = eg.add_const(extended)
                    let new_id = eg.merge(class_id, new_const)
                    changed = new_id != class_id || changed
                  }
                  _ => ()
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
