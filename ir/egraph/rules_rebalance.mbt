// Tree rebalancing rules for associative operations

///|
fn rule_rebalance_add_right() -> RewriteRule {
  {
    name: "rebalance_add_right",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let a = node.children[0]
          for mid in eg.get_nodes(node.children[1]) {
            if mid.op is Add && mid.children.length() == 2 {
              let b = mid.children[0]
              for inner in eg.get_nodes(mid.children[1]) {
                if inner.op is Add && inner.children.length() == 2 {
                  let c = inner.children[0]
                  let d = inner.children[1]
                  let ab = eg.add_add(a, b)
                  let cd = eg.add_add(c, d)
                  let balanced = eg.add_add(ab, cd)
                  // Use subsume instead of merge to avoid infinite loops
                  let new_id = eg.subsume(class_id, balanced)
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
/// Tree rebalancing for iadd: (((a + b) + c) + d) => ((a + b) + (c + d))
fn rule_rebalance_add_left() -> RewriteRule {
  {
    name: "rebalance_add_left",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let d = node.children[1]
          for mid in eg.get_nodes(node.children[0]) {
            if mid.op is Add && mid.children.length() == 2 {
              let c = mid.children[1]
              for inner in eg.get_nodes(mid.children[0]) {
                if inner.op is Add && inner.children.length() == 2 {
                  let a = inner.children[0]
                  let b = inner.children[1]
                  let ab = eg.add_add(a, b)
                  let cd = eg.add_add(c, d)
                  let balanced = eg.add_add(ab, cd)
                  let new_id = eg.subsume(class_id, balanced)
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
/// Tree rebalancing for imul: (a * (b * (c * d))) => ((a * b) * (c * d))
fn rule_rebalance_mul_right() -> RewriteRule {
  {
    name: "rebalance_mul_right",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          let a = node.children[0]
          for mid in eg.get_nodes(node.children[1]) {
            if mid.op is Mul && mid.children.length() == 2 {
              let b = mid.children[0]
              for inner in eg.get_nodes(mid.children[1]) {
                if inner.op is Mul && inner.children.length() == 2 {
                  let c = inner.children[0]
                  let d = inner.children[1]
                  let ab = eg.add_mul(a, b)
                  let cd = eg.add_mul(c, d)
                  let balanced = eg.add_mul(ab, cd)
                  let new_id = eg.subsume(class_id, balanced)
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
/// Tree rebalancing for imul: (((a * b) * c) * d) => ((a * b) * (c * d))
fn rule_rebalance_mul_left() -> RewriteRule {
  {
    name: "rebalance_mul_left",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          let d = node.children[1]
          for mid in eg.get_nodes(node.children[0]) {
            if mid.op is Mul && mid.children.length() == 2 {
              let c = mid.children[1]
              for inner in eg.get_nodes(mid.children[0]) {
                if inner.op is Mul && inner.children.length() == 2 {
                  let a = inner.children[0]
                  let b = inner.children[1]
                  let ab = eg.add_mul(a, b)
                  let cd = eg.add_mul(c, d)
                  let balanced = eg.add_mul(ab, cd)
                  let new_id = eg.subsume(class_id, balanced)
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
/// Tree rebalancing for band: (a & (b & (c & d))) => ((a & b) & (c & d))
fn rule_rebalance_and_right() -> RewriteRule {
  {
    name: "rebalance_and_right",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          let a = node.children[0]
          for mid in eg.get_nodes(node.children[1]) {
            if mid.op is And && mid.children.length() == 2 {
              let b = mid.children[0]
              for inner in eg.get_nodes(mid.children[1]) {
                if inner.op is And && inner.children.length() == 2 {
                  let c = inner.children[0]
                  let d = inner.children[1]
                  let ab = eg.add_and(a, b)
                  let cd = eg.add_and(c, d)
                  let balanced = eg.add_and(ab, cd)
                  let new_id = eg.subsume(class_id, balanced)
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
/// Tree rebalancing for band: (((a & b) & c) & d) => ((a & b) & (c & d))
fn rule_rebalance_and_left() -> RewriteRule {
  {
    name: "rebalance_and_left",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          let d = node.children[1]
          for mid in eg.get_nodes(node.children[0]) {
            if mid.op is And && mid.children.length() == 2 {
              let c = mid.children[1]
              for inner in eg.get_nodes(mid.children[0]) {
                if inner.op is And && inner.children.length() == 2 {
                  let a = inner.children[0]
                  let b = inner.children[1]
                  let ab = eg.add_and(a, b)
                  let cd = eg.add_and(c, d)
                  let balanced = eg.add_and(ab, cd)
                  let new_id = eg.subsume(class_id, balanced)
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
/// Tree rebalancing for bxor: (a ^ (b ^ (c ^ d))) => ((a ^ b) ^ (c ^ d))
fn rule_rebalance_xor_right() -> RewriteRule {
  {
    name: "rebalance_xor_right",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          let a = node.children[0]
          for mid in eg.get_nodes(node.children[1]) {
            if mid.op is Xor && mid.children.length() == 2 {
              let b = mid.children[0]
              for inner in eg.get_nodes(mid.children[1]) {
                if inner.op is Xor && inner.children.length() == 2 {
                  let c = inner.children[0]
                  let d = inner.children[1]
                  let ab = eg.add_xor(a, b)
                  let cd = eg.add_xor(c, d)
                  let balanced = eg.add_xor(ab, cd)
                  let new_id = eg.subsume(class_id, balanced)
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
/// Tree rebalancing for bxor: (((a ^ b) ^ c) ^ d) => ((a ^ b) ^ (c ^ d))
fn rule_rebalance_xor_left() -> RewriteRule {
  {
    name: "rebalance_xor_left",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          let d = node.children[1]
          for mid in eg.get_nodes(node.children[0]) {
            if mid.op is Xor && mid.children.length() == 2 {
              let c = mid.children[1]
              for inner in eg.get_nodes(mid.children[0]) {
                if inner.op is Xor && inner.children.length() == 2 {
                  let a = inner.children[0]
                  let b = inner.children[1]
                  let ab = eg.add_xor(a, b)
                  let cd = eg.add_xor(c, d)
                  let balanced = eg.add_xor(ab, cd)
                  let new_id = eg.subsume(class_id, balanced)
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
