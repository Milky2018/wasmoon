// Rematerialization optimization rules
//
// Rematerialization marks expressions that are cheap to recompute at each use
// site rather than being spilled to memory when register pressure is high.
// These patterns are:
// - ALU ops with immediate operand (iadd, isub, band, bor, bxor with iconst)
// - bnot (very cheap unary op)
// - iconst, f32const, f64const (constants are free to rematerialize)
//
// In the e-graph context, we track rematerializable expressions and adjust
// the cost model to prefer them during extraction.

// ============================================================================
// Rematerialization checking
// ============================================================================

///|
/// Check if a node is rematerializable
/// Returns true if the node matches any rematerialization pattern
pub fn EGraph::is_rematerializable(self : EGraph, class_id : EClassId) -> Bool {
  for node in self.get_nodes(class_id) {
    if self.node_is_rematerializable(node) {
      return true
    }
  }
  false
}

///|
/// Check if a specific node is rematerializable
fn EGraph::node_is_rematerializable(self : EGraph, node : ENode) -> Bool {
  match node.op {
    // Constants are always rematerializable
    Const(_) => true
    Fconst(_) => true
    // bnot is always rematerializable (cheap unary op)
    Bnot => true
    // Binary ops with constant operand are rematerializable
    Add =>
      if node.children.length() == 2 {
        self.has_const_child(node)
      } else {
        false
      }
    Sub =>
      if node.children.length() == 2 {
        self.has_const_child(node)
      } else {
        false
      }
    And =>
      if node.children.length() == 2 {
        self.has_const_child(node)
      } else {
        false
      }
    Or =>
      if node.children.length() == 2 {
        self.has_const_child(node)
      } else {
        false
      }
    Xor =>
      if node.children.length() == 2 {
        self.has_const_child(node)
      } else {
        false
      }
    _ => false
  }
}

///|
/// Check if a node has at least one constant child
fn EGraph::has_const_child(self : EGraph, node : ENode) -> Bool {
  for child in node.children {
    if self.find_const(child) is Some(_) {
      return true
    }
  }
  false
}

// ============================================================================
// Rematerialization rules
// These rules mark classes as rematerializable when patterns are detected
// ============================================================================

///|
/// Mark iadd(iconst, x) as rematerializable
fn rule_remat_iadd_iconst_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(_) {
            if eg.mark_rematerializable(class_id) {
              changed = true
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// Mark iadd(x, iconst) as rematerializable
fn rule_remat_iadd_iconst_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(_) {
            if eg.mark_rematerializable(class_id) {
              changed = true
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// Mark isub(iconst, x) as rematerializable
fn rule_remat_isub_iconst_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(_) {
            if eg.mark_rematerializable(class_id) {
              changed = true
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// Mark isub(x, iconst) as rematerializable
fn rule_remat_isub_iconst_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(_) {
            if eg.mark_rematerializable(class_id) {
              changed = true
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// Mark band(iconst, x) as rematerializable
fn rule_remat_band_iconst_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(_) {
            if eg.mark_rematerializable(class_id) {
              changed = true
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// Mark band(x, iconst) as rematerializable
fn rule_remat_band_iconst_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(_) {
            if eg.mark_rematerializable(class_id) {
              changed = true
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// Mark bor(iconst, x) as rematerializable
fn rule_remat_bor_iconst_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(_) {
            if eg.mark_rematerializable(class_id) {
              changed = true
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// Mark bor(x, iconst) as rematerializable
fn rule_remat_bor_iconst_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(_) {
            if eg.mark_rematerializable(class_id) {
              changed = true
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// Mark bxor(iconst, x) as rematerializable
fn rule_remat_bxor_iconst_left() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(_) {
            if eg.mark_rematerializable(class_id) {
              changed = true
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// Mark bxor(x, iconst) as rematerializable
fn rule_remat_bxor_iconst_right() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(_) {
            if eg.mark_rematerializable(class_id) {
              changed = true
            }
          }
        }
      }
      changed
    },
  }
}

///|
/// Mark bnot(x) as rematerializable
fn rule_remat_bnot() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Bnot {
          if eg.mark_rematerializable(class_id) {
            changed = true
          }
        }
      }
      changed
    },
  }
}

///|
/// Mark iconst as rematerializable
fn rule_remat_iconst() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Const(_) {
          if eg.mark_rematerializable(class_id) {
            changed = true
          }
        }
      }
      changed
    },
  }
}

///|
/// Mark f32const/f64const as rematerializable
fn rule_remat_fconst() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Fconst(_) {
          if eg.mark_rematerializable(class_id) {
            changed = true
          }
        }
      }
      changed
    },
  }
}

// ============================================================================
// Get all rematerialization rules
// ============================================================================

///|
/// Get all rematerialization rules
pub fn remat_rules() -> Array[RewriteRule] {
  [
    rule_remat_iadd_iconst_left(),
    rule_remat_iadd_iconst_right(),
    rule_remat_isub_iconst_left(),
    rule_remat_isub_iconst_right(),
    rule_remat_band_iconst_left(),
    rule_remat_band_iconst_right(),
    rule_remat_bor_iconst_left(),
    rule_remat_bor_iconst_right(),
    rule_remat_bxor_iconst_left(),
    rule_remat_bxor_iconst_right(),
    rule_remat_bnot(),
    rule_remat_iconst(),
    rule_remat_fconst(),
  ]
}
