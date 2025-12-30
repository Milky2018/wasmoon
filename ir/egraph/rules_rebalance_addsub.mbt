// Add/Sub mixed rebalancing rules
// ============================================================================
// Add/Sub mixed rebalancing rules
// These rules balance combinations of + and - to increase ILP
// ============================================================================

///|
/// a - (b - (c - d)) = (a - b) + (c - d)
fn rule_rebalance_sub_sub_sub() -> RewriteRule {
  {
    name: "rebalance_sub_sub_sub",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let a = node.children[0]
          for mid in eg.get_nodes(node.children[1]) {
            if mid.op is Sub && mid.children.length() == 2 {
              let b = mid.children[0]
              for inner in eg.get_nodes(mid.children[1]) {
                if inner.op is Sub && inner.children.length() == 2 {
                  let c = inner.children[0]
                  let d = inner.children[1]
                  let ab = eg.add_sub(a, b)
                  let cd = eg.add_sub(c, d)
                  let result = eg.add_add(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// a - (b - (c + d)) = (a - b) + (c + d)
fn rule_rebalance_sub_sub_add() -> RewriteRule {
  {
    name: "rebalance_sub_sub_add",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let a = node.children[0]
          for mid in eg.get_nodes(node.children[1]) {
            if mid.op is Sub && mid.children.length() == 2 {
              let b = mid.children[0]
              for inner in eg.get_nodes(mid.children[1]) {
                if inner.op is Add && inner.children.length() == 2 {
                  let c = inner.children[0]
                  let d = inner.children[1]
                  let ab = eg.add_sub(a, b)
                  let cd = eg.add_add(c, d)
                  let result = eg.add_add(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// a - (b + (c - d)) = (a - b) - (c - d)
fn rule_rebalance_sub_add_sub() -> RewriteRule {
  {
    name: "rebalance_sub_add_sub",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let a = node.children[0]
          for mid in eg.get_nodes(node.children[1]) {
            if mid.op is Add && mid.children.length() == 2 {
              let b = mid.children[0]
              for inner in eg.get_nodes(mid.children[1]) {
                if inner.op is Sub && inner.children.length() == 2 {
                  let c = inner.children[0]
                  let d = inner.children[1]
                  let ab = eg.add_sub(a, b)
                  let cd = eg.add_sub(c, d)
                  let result = eg.add_sub(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// a - (b + (c + d)) = (a - b) - (c + d)
fn rule_rebalance_sub_add_add() -> RewriteRule {
  {
    name: "rebalance_sub_add_add",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let a = node.children[0]
          for mid in eg.get_nodes(node.children[1]) {
            if mid.op is Add && mid.children.length() == 2 {
              let b = mid.children[0]
              for inner in eg.get_nodes(mid.children[1]) {
                if inner.op is Add && inner.children.length() == 2 {
                  let c = inner.children[0]
                  let d = inner.children[1]
                  let ab = eg.add_sub(a, b)
                  let cd = eg.add_add(c, d)
                  let result = eg.add_sub(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// a + (b - (c - d)) = (a + b) - (c - d)
fn rule_rebalance_add_sub_sub() -> RewriteRule {
  {
    name: "rebalance_add_sub_sub",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let a = node.children[0]
          for mid in eg.get_nodes(node.children[1]) {
            if mid.op is Sub && mid.children.length() == 2 {
              let b = mid.children[0]
              for inner in eg.get_nodes(mid.children[1]) {
                if inner.op is Sub && inner.children.length() == 2 {
                  let c = inner.children[0]
                  let d = inner.children[1]
                  let ab = eg.add_add(a, b)
                  let cd = eg.add_sub(c, d)
                  let result = eg.add_sub(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// a + (b - (c + d)) = (a + b) - (c + d)
fn rule_rebalance_add_sub_add() -> RewriteRule {
  {
    name: "rebalance_add_sub_add",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let a = node.children[0]
          for mid in eg.get_nodes(node.children[1]) {
            if mid.op is Sub && mid.children.length() == 2 {
              let b = mid.children[0]
              for inner in eg.get_nodes(mid.children[1]) {
                if inner.op is Add && inner.children.length() == 2 {
                  let c = inner.children[0]
                  let d = inner.children[1]
                  let ab = eg.add_add(a, b)
                  let cd = eg.add_add(c, d)
                  let result = eg.add_sub(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// a + (b + (c - d)) = (a + b) + (c - d)
fn rule_rebalance_add_add_sub() -> RewriteRule {
  {
    name: "rebalance_add_add_sub",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let a = node.children[0]
          for mid in eg.get_nodes(node.children[1]) {
            if mid.op is Add && mid.children.length() == 2 {
              let b = mid.children[0]
              for inner in eg.get_nodes(mid.children[1]) {
                if inner.op is Sub && inner.children.length() == 2 {
                  let c = inner.children[0]
                  let d = inner.children[1]
                  let ab = eg.add_add(a, b)
                  let cd = eg.add_sub(c, d)
                  let result = eg.add_add(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// ((a - b) - c) - d = (a - b) - (c + d)
fn rule_rebalance_left_sub_sub_sub() -> RewriteRule {
  {
    name: "rebalance_left_sub_sub_sub",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let d = node.children[1]
          for mid in eg.get_nodes(node.children[0]) {
            if mid.op is Sub && mid.children.length() == 2 {
              let c = mid.children[1]
              for inner in eg.get_nodes(mid.children[0]) {
                if inner.op is Sub && inner.children.length() == 2 {
                  let a = inner.children[0]
                  let b = inner.children[1]
                  let ab = eg.add_sub(a, b)
                  let cd = eg.add_add(c, d)
                  let result = eg.add_sub(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// ((a - b) - c) + d = (a - b) - (c - d)
fn rule_rebalance_left_sub_sub_add() -> RewriteRule {
  {
    name: "rebalance_left_sub_sub_add",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let d = node.children[1]
          for mid in eg.get_nodes(node.children[0]) {
            if mid.op is Sub && mid.children.length() == 2 {
              let c = mid.children[1]
              for inner in eg.get_nodes(mid.children[0]) {
                if inner.op is Sub && inner.children.length() == 2 {
                  let a = inner.children[0]
                  let b = inner.children[1]
                  let ab = eg.add_sub(a, b)
                  let cd = eg.add_sub(c, d)
                  let result = eg.add_sub(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// ((a - b) + c) - d = (a - b) + (c - d)
fn rule_rebalance_left_sub_add_sub() -> RewriteRule {
  {
    name: "rebalance_left_sub_add_sub",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let d = node.children[1]
          for mid in eg.get_nodes(node.children[0]) {
            if mid.op is Add && mid.children.length() == 2 {
              let c = mid.children[1]
              for inner in eg.get_nodes(mid.children[0]) {
                if inner.op is Sub && inner.children.length() == 2 {
                  let a = inner.children[0]
                  let b = inner.children[1]
                  let ab = eg.add_sub(a, b)
                  let cd = eg.add_sub(c, d)
                  let result = eg.add_add(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// ((a - b) + c) + d = (a - b) + (c + d)
fn rule_rebalance_left_sub_add_add() -> RewriteRule {
  {
    name: "rebalance_left_sub_add_add",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let d = node.children[1]
          for mid in eg.get_nodes(node.children[0]) {
            if mid.op is Add && mid.children.length() == 2 {
              let c = mid.children[1]
              for inner in eg.get_nodes(mid.children[0]) {
                if inner.op is Sub && inner.children.length() == 2 {
                  let a = inner.children[0]
                  let b = inner.children[1]
                  let ab = eg.add_sub(a, b)
                  let cd = eg.add_add(c, d)
                  let result = eg.add_add(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// ((a + b) - c) - d = (a + b) - (c + d)
fn rule_rebalance_left_add_sub_sub() -> RewriteRule {
  {
    name: "rebalance_left_add_sub_sub",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let d = node.children[1]
          for mid in eg.get_nodes(node.children[0]) {
            if mid.op is Sub && mid.children.length() == 2 {
              let c = mid.children[1]
              for inner in eg.get_nodes(mid.children[0]) {
                if inner.op is Add && inner.children.length() == 2 {
                  let a = inner.children[0]
                  let b = inner.children[1]
                  let ab = eg.add_add(a, b)
                  let cd = eg.add_add(c, d)
                  let result = eg.add_sub(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// ((a + b) - c) + d = (a + b) - (c - d)
fn rule_rebalance_left_add_sub_add() -> RewriteRule {
  {
    name: "rebalance_left_add_sub_add",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let d = node.children[1]
          for mid in eg.get_nodes(node.children[0]) {
            if mid.op is Sub && mid.children.length() == 2 {
              let c = mid.children[1]
              for inner in eg.get_nodes(mid.children[0]) {
                if inner.op is Add && inner.children.length() == 2 {
                  let a = inner.children[0]
                  let b = inner.children[1]
                  let ab = eg.add_add(a, b)
                  let cd = eg.add_sub(c, d)
                  let result = eg.add_sub(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// ((a + b) + c) - d = (a + b) + (c - d)
fn rule_rebalance_left_add_add_sub() -> RewriteRule {
  {
    name: "rebalance_left_add_add_sub",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          let d = node.children[1]
          for mid in eg.get_nodes(node.children[0]) {
            if mid.op is Add && mid.children.length() == 2 {
              let c = mid.children[1]
              for inner in eg.get_nodes(mid.children[0]) {
                if inner.op is Add && inner.children.length() == 2 {
                  let a = inner.children[0]
                  let b = inner.children[1]
                  let ab = eg.add_add(a, b)
                  let cd = eg.add_sub(c, d)
                  let result = eg.add_add(ab, cd)
                  let new_id = eg.subsume(class_id, result)
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
/// Get all standard rewrite rules
