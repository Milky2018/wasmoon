// Spaceship (three-way comparison) optimization rules
// Implements C++20's <=> operator / Rust's Ord::cmp
// Canonicalizes various implementations to: (x > y) - (x < y)

// Helper to check if a constant is -1

///|
fn is_neg_one(v : Int64) -> Bool {
  v == -1L
}

///|
/// Simplify (a <=> b) == 0 → a == b
/// Three-way comparison equals zero means the operands are equal
fn rule_spaceship_eq_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Eq || node.op is Icmp(CC_EQ)) &&
          node.children.length() == 2 {
          // Check if one operand is spaceship and other is zero
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipS ||
              spaceship_node.op is SpaceshipU {
              if eg.find_const(node.children[1]) is Some(0L) {
                // (spaceship(x, y) == 0) → (x == y)
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Eq, children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
                changed = new_id != class_id || changed
              }
            }
          }
          // Check the other way around
          for spaceship_node in eg.get_nodes(node.children[1]) {
            if spaceship_node.op is SpaceshipS ||
              spaceship_node.op is SpaceshipU {
              if eg.find_const(node.children[0]) is Some(0L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Eq, children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=> b) != 0 → a != b
/// Three-way comparison not equals zero means the operands are not equal
fn rule_spaceship_ne_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Ne || node.op is Icmp(CC_NE)) &&
          node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipS ||
              spaceship_node.op is SpaceshipU {
              if eg.find_const(node.children[1]) is Some(0L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Ne, children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
                changed = new_id != class_id || changed
              }
            }
          }
          for spaceship_node in eg.get_nodes(node.children[1]) {
            if spaceship_node.op is SpaceshipS ||
              spaceship_node.op is SpaceshipU {
              if eg.find_const(node.children[0]) is Some(0L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Ne, children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_s b) < 0 → a <_s b
/// Signed spaceship less than zero means first operand is less
fn rule_spaceship_s_lt_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Icmp(CC_SLT) && node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipS {
              if eg.find_const(node.children[1]) is Some(0L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_SLT), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_u b) < 0 → a <_u b
/// Unsigned spaceship less than zero means first operand is less
fn rule_spaceship_u_lt_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Icmp(CC_SLT) && node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipU {
              if eg.find_const(node.children[1]) is Some(0L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_ULT), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_s b) <= 0 → a <=_s b
fn rule_spaceship_s_le_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Icmp(CC_SLE) && node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipS {
              if eg.find_const(node.children[1]) is Some(0L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_SLE), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_u b) <= 0 → a <=_u b
fn rule_spaceship_u_le_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Icmp(CC_SLE) && node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipU {
              if eg.find_const(node.children[1]) is Some(0L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_ULE), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_s b) > 0 → a >_s b
fn rule_spaceship_s_gt_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Icmp(CC_SGT) && node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipS {
              if eg.find_const(node.children[1]) is Some(0L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_SGT), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_u b) > 0 → a >_u b
fn rule_spaceship_u_gt_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Icmp(CC_SGT) && node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipU {
              if eg.find_const(node.children[1]) is Some(0L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_UGT), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_s b) >= 0 → a >=_s b
fn rule_spaceship_s_ge_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Icmp(CC_SGE) && node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipS {
              if eg.find_const(node.children[1]) is Some(0L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_SGE), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_u b) >= 0 → a >=_u b
fn rule_spaceship_u_ge_zero() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Icmp(CC_SGE) && node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipU {
              if eg.find_const(node.children[1]) is Some(0L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_UGE), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_s b) == -1 → a <_s b
fn rule_spaceship_s_eq_neg_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Eq || node.op is Icmp(CC_EQ)) &&
          node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipS {
              if eg.find_const(node.children[1]) is Some(v) && is_neg_one(v) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_SLT), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_u b) == -1 → a <_u b
fn rule_spaceship_u_eq_neg_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Eq || node.op is Icmp(CC_EQ)) &&
          node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipU {
              if eg.find_const(node.children[1]) is Some(v) && is_neg_one(v) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_ULT), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_s b) != -1 → a >=_s b
fn rule_spaceship_s_ne_neg_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Ne || node.op is Icmp(CC_NE)) &&
          node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipS {
              if eg.find_const(node.children[1]) is Some(v) && is_neg_one(v) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_SGE), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_u b) != -1 → a >=_u b
fn rule_spaceship_u_ne_neg_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Ne || node.op is Icmp(CC_NE)) &&
          node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipU {
              if eg.find_const(node.children[1]) is Some(v) && is_neg_one(v) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_UGE), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_s b) == 1 → a >_s b
fn rule_spaceship_s_eq_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Eq || node.op is Icmp(CC_EQ)) &&
          node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipS {
              if eg.find_const(node.children[1]) is Some(1L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_SGT), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_u b) == 1 → a >_u b
fn rule_spaceship_u_eq_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Eq || node.op is Icmp(CC_EQ)) &&
          node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipU {
              if eg.find_const(node.children[1]) is Some(1L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_UGT), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_s b) != 1 → a <=_s b
fn rule_spaceship_s_ne_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Ne || node.op is Icmp(CC_NE)) &&
          node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipS {
              if eg.find_const(node.children[1]) is Some(1L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_SLE), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Simplify (a <=>_u b) != 1 → a <=_u b
fn rule_spaceship_u_ne_one() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Ne || node.op is Icmp(CC_NE)) &&
          node.children.length() == 2 {
          for spaceship_node in eg.get_nodes(node.children[0]) {
            if spaceship_node.op is SpaceshipU {
              if eg.find_const(node.children[1]) is Some(1L) {
                let x = spaceship_node.children[0]
                let y = spaceship_node.children[1]
                let new_node = eg.add({ op: Icmp(CC_ULE), children: [x, y] })
                let new_id = eg.subsume(class_id, new_node)
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
/// Collect all spaceship rules
pub fn spaceship_rules() -> Array[RewriteRule] {
  [
    rule_spaceship_eq_zero(),
    rule_spaceship_ne_zero(),
    rule_spaceship_s_lt_zero(),
    rule_spaceship_u_lt_zero(),
    rule_spaceship_s_le_zero(),
    rule_spaceship_u_le_zero(),
    rule_spaceship_s_gt_zero(),
    rule_spaceship_u_gt_zero(),
    rule_spaceship_s_ge_zero(),
    rule_spaceship_u_ge_zero(),
    rule_spaceship_s_eq_neg_one(),
    rule_spaceship_u_eq_neg_one(),
    rule_spaceship_s_ne_neg_one(),
    rule_spaceship_u_ne_neg_one(),
    rule_spaceship_s_eq_one(),
    rule_spaceship_u_eq_one(),
    rule_spaceship_s_ne_one(),
    rule_spaceship_u_ne_one(),
  ]
}
