// Extend/Reduce optimization rules
// Implements Cranelift extends.isle optimization rules

///|
/// uextend(uextend(x)) → uextend(x)
/// Chained unsigned extends can be collapsed
fn rule_uextend_uextend() -> RewriteRule {
  {
    name: "uextend_uextend",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Uextend && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Uextend && inner.children.length() == 1 {
              // uextend(uextend(x)) = uextend(x)
              let new_node = eg.add({
                op: Uextend,
                children: [inner.children[0]],
              })
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
/// sextend(sextend(x)) → sextend(x)
/// Chained signed extends can be collapsed
fn rule_sextend_sextend() -> RewriteRule {
  {
    name: "sextend_sextend",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sextend && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Sextend && inner.children.length() == 1 {
              // sextend(sextend(x)) = sextend(x)
              let new_node = eg.add({
                op: Sextend,
                children: [inner.children[0]],
              })
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
/// sextend(uextend(x)) → uextend(x)
/// Once unsigned extended, sign-extending is the same as zero-extending
fn rule_sextend_uextend() -> RewriteRule {
  {
    name: "sextend_uextend",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sextend && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Uextend && inner.children.length() == 1 {
              // sextend(uextend(x)) = uextend(x)
              let new_node = eg.add({
                op: Uextend,
                children: [inner.children[0]],
              })
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
/// sextend(icmp(...)) → uextend(icmp(...))
/// icmp results are 0 or 1, so sign-extending is the same as zero-extending
fn rule_sextend_icmp() -> RewriteRule {
  {
    name: "sextend_icmp",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sextend && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            match inner.op {
              Icmp(_) | Eq | Ne => {
                // sextend(icmp/eq/ne) = uextend(icmp/eq/ne)
                let new_node = eg.add({
                  op: Uextend,
                  children: [node.children[0]],
                })
                let new_id = eg.merge(class_id, new_node)
                changed = new_id != class_id || changed
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
/// ireduce(uextend(x)) → x when types match
/// Reduction of an extend back to original type is identity
fn rule_ireduce_uextend() -> RewriteRule {
  {
    name: "ireduce_uextend",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ireduce && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Uextend && inner.children.length() == 1 {
              // ireduce(uextend(x)) = x (assuming types match)
              let new_id = eg.merge(class_id, inner.children[0])
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
/// ireduce(sextend(x)) → x when types match
/// Reduction of an extend back to original type is identity
fn rule_ireduce_sextend() -> RewriteRule {
  {
    name: "ireduce_sextend",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ireduce && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Sextend && inner.children.length() == 1 {
              // ireduce(sextend(x)) = x (assuming types match)
              let new_id = eg.merge(class_id, inner.children[0])
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
/// band(uextend(x), uextend(y)) → uextend(band(x, y))
/// Bitwise AND can be pushed inside uextends
fn rule_band_uextend() -> RewriteRule {
  {
    name: "band_uextend",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Uextend && left.children.length() == 1 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op is Uextend && right.children.length() == 1 {
                  // band(uextend(x), uextend(y)) = uextend(band(x, y))
                  let inner_and = eg.add({
                    op: And,
                    children: [left.children[0], right.children[0]],
                  })
                  let new_node = eg.add({ op: Uextend, children: [inner_and] })
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
/// bor(uextend(x), uextend(y)) → uextend(bor(x, y))
/// Bitwise OR can be pushed inside uextends
fn rule_bor_uextend() -> RewriteRule {
  {
    name: "bor_uextend",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Uextend && left.children.length() == 1 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op is Uextend && right.children.length() == 1 {
                  // bor(uextend(x), uextend(y)) = uextend(bor(x, y))
                  let inner_or = eg.add({
                    op: Or,
                    children: [left.children[0], right.children[0]],
                  })
                  let new_node = eg.add({ op: Uextend, children: [inner_or] })
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
/// bxor(uextend(x), uextend(y)) → uextend(bxor(x, y))
/// Bitwise XOR can be pushed inside uextends
fn rule_bxor_uextend() -> RewriteRule {
  {
    name: "bxor_uextend",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Uextend && left.children.length() == 1 {
              for right in eg.get_nodes(node.children[1]) {
                if right.op is Uextend && right.children.length() == 1 {
                  // bxor(uextend(x), uextend(y)) = uextend(bxor(x, y))
                  let inner_xor = eg.add({
                    op: Xor,
                    children: [left.children[0], right.children[0]],
                  })
                  let new_node = eg.add({ op: Uextend, children: [inner_xor] })
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
/// ireduce(ineg(x)) → ineg(ireduce(x))
/// Reduction can be pushed inside negation
fn rule_ireduce_ineg() -> RewriteRule {
  {
    name: "ireduce_ineg",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ireduce && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Neg && inner.children.length() == 1 {
              // ireduce(neg(x)) = neg(ireduce(x))
              let inner_reduce = eg.add({
                op: Ireduce,
                children: [inner.children[0]],
              })
              let new_node = eg.add({ op: Neg, children: [inner_reduce] })
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
/// ireduce(bnot(x)) → bnot(ireduce(x))
/// Reduction can be pushed inside bitwise NOT
fn rule_ireduce_bnot() -> RewriteRule {
  {
    name: "ireduce_bnot",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ireduce && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Bnot && inner.children.length() == 1 {
              // ireduce(bnot(x)) = bnot(ireduce(x))
              let inner_reduce = eg.add({
                op: Ireduce,
                children: [inner.children[0]],
              })
              let new_node = eg.add({ op: Bnot, children: [inner_reduce] })
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
/// ireduce(iadd(x, y)) → iadd(ireduce(x), ireduce(y))
/// Reduction can be pushed inside addition
fn rule_ireduce_iadd() -> RewriteRule {
  {
    name: "ireduce_iadd",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ireduce && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Add && inner.children.length() == 2 {
              // ireduce(add(x, y)) = add(ireduce(x), ireduce(y))
              let left_reduce = eg.add({
                op: Ireduce,
                children: [inner.children[0]],
              })
              let right_reduce = eg.add({
                op: Ireduce,
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
    name: "ireduce_isub",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ireduce && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Sub && inner.children.length() == 2 {
              // ireduce(sub(x, y)) = sub(ireduce(x), ireduce(y))
              let left_reduce = eg.add({
                op: Ireduce,
                children: [inner.children[0]],
              })
              let right_reduce = eg.add({
                op: Ireduce,
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
    name: "ireduce_imul",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ireduce && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Mul && inner.children.length() == 2 {
              // ireduce(mul(x, y)) = mul(ireduce(x), ireduce(y))
              let left_reduce = eg.add({
                op: Ireduce,
                children: [inner.children[0]],
              })
              let right_reduce = eg.add({
                op: Ireduce,
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
    name: "ireduce_band",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ireduce && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is And && inner.children.length() == 2 {
              // ireduce(and(x, y)) = and(ireduce(x), ireduce(y))
              let left_reduce = eg.add({
                op: Ireduce,
                children: [inner.children[0]],
              })
              let right_reduce = eg.add({
                op: Ireduce,
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
    name: "ireduce_bor",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ireduce && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Or && inner.children.length() == 2 {
              // ireduce(or(x, y)) = or(ireduce(x), ireduce(y))
              let left_reduce = eg.add({
                op: Ireduce,
                children: [inner.children[0]],
              })
              let right_reduce = eg.add({
                op: Ireduce,
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
    name: "ireduce_bxor",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Ireduce && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Xor && inner.children.length() == 2 {
              // ireduce(xor(x, y)) = xor(ireduce(x), ireduce(y))
              let left_reduce = eg.add({
                op: Ireduce,
                children: [inner.children[0]],
              })
              let right_reduce = eg.add({
                op: Ireduce,
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
      }
      changed
    },
  }
}
