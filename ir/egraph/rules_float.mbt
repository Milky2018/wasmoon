// Floating-point optimization rules

///|
/// Float constant folding for binary operations
/// Only folds when the result is not NaN (except fneg/fabs/fcopysign)
fn rule_fconst_fold_binary() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.children.length() == 2 {
          if eg.find_fconst(node.children[0]) is Some(lhs_bits) {
            if eg.find_fconst(node.children[1]) is Some(rhs_bits) {
              // Interpret as f64 (assumes 64-bit floats)
              let lhs = lhs_bits.reinterpret_as_double()
              let rhs = rhs_bits.reinterpret_as_double()
              let result : Double? = match node.op {
                Fadd => {
                  let r = lhs + rhs
                  if r.is_nan() {
                    None
                  } else {
                    Some(r)
                  }
                }
                Fsub => {
                  let r = lhs - rhs
                  if r.is_nan() {
                    None
                  } else {
                    Some(r)
                  }
                }
                Fmul => {
                  let r = lhs * rhs
                  if r.is_nan() {
                    None
                  } else {
                    Some(r)
                  }
                }
                Fdiv => {
                  let r = lhs / rhs
                  if r.is_nan() {
                    None
                  } else {
                    Some(r)
                  }
                }
                Fmin => {
                  let r = if lhs < rhs { lhs } else { rhs }
                  if r.is_nan() {
                    None
                  } else {
                    Some(r)
                  }
                }
                Fmax => {
                  let r = if lhs > rhs { lhs } else { rhs }
                  if r.is_nan() {
                    None
                  } else {
                    Some(r)
                  }
                }
                Fcopysign =>
                  // copysign always produces a valid result
                  Some(lhs.abs() * (if rhs < 0.0 { -1.0 } else { 1.0 }))
                _ => None
              }
              if result is Some(r) {
                let result_bits = r.reinterpret_as_uint64()
                let result_node = eg.add_fconst(result_bits)
                let new_id = eg.merge(class_id, result_node)
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
/// Float constant folding for unary operations
fn rule_fconst_fold_unary() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.children.length() == 1 {
          if eg.find_fconst(node.children[0]) is Some(x_bits) {
            let x = x_bits.reinterpret_as_double()
            let result : Double? = match node.op {
              Fneg => Some(-x) // fneg always works
              Fabs => Some(x.abs()) // fabs always works
              Fsqrt => {
                let r = x.sqrt()
                if r.is_nan() {
                  None
                } else {
                  Some(r)
                }
              }
              Fceil => {
                let r = x.ceil()
                if r.is_nan() {
                  None
                } else {
                  Some(r)
                }
              }
              Ffloor => {
                let r = x.floor()
                if r.is_nan() {
                  None
                } else {
                  Some(r)
                }
              }
              Ftrunc => {
                let r = x.trunc()
                if r.is_nan() {
                  None
                } else {
                  Some(r)
                }
              }
              Fnearest => {
                let r = x.round()
                if r.is_nan() {
                  None
                } else {
                  Some(r)
                }
              }
              _ => None
            }
            if result is Some(r) {
              let result_bits = r.reinterpret_as_uint64()
              let result_node = eg.add_fconst(result_bits)
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
/// fneg(fneg(x)) = x (double negation)
fn rule_fneg_fneg() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Fneg && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Fneg && inner.children.length() == 1 {
              // fneg(fneg(x)) = x
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
/// fabs(fneg(x)) = fabs(x)
fn rule_fabs_fneg() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Fabs && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Fneg && inner.children.length() == 1 {
              // fabs(fneg(x)) = fabs(x)
              let new_abs = eg.add_fabs(inner.children[0])
              let new_id = eg.merge(class_id, new_abs)
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
/// fabs(fabs(x)) = fabs(x) (idempotent)
fn rule_fabs_fabs() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Fabs && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Fabs && inner.children.length() == 1 {
              // fabs(fabs(x)) = fabs(x)
              let new_id = eg.merge(class_id, node.children[0])
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
/// fneg(fabs(x)) = fneg(fabs(x)) but fabs(fneg(x)) = fabs(x)
/// This is the reverse direction
fn rule_fneg_fabs() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Fneg && node.children.length() == 1 {
          for inner in eg.get_nodes(node.children[0]) {
            if inner.op is Fabs && inner.children.length() == 1 {
              // This is already in canonical form
              // But we can add fneg(fabs(fneg(x))) = fneg(fabs(x))
              for innermost in eg.get_nodes(inner.children[0]) {
                if innermost.op is Fneg && innermost.children.length() == 1 {
                  let new_fabs = eg.add_fabs(innermost.children[0])
                  let new_fneg = eg.add_fneg(new_fabs)
                  let new_id = eg.merge(class_id, new_fneg)
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
