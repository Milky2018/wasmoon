// Skeleton rules - Side-effectful instruction simplifications
// These are pure simplifications extracted from Cranelift's skeleton.isle

///|
/// Check if a value is a power of two and return its log2
fn is_power_of_two(n : Int64) -> Int64? {
  if n <= 0L {
    return None
  }
  // Check if n is a power of 2 (only one bit set)
  if (n & (n - 1L)) != 0L {
    return None
  }
  // Count trailing zeros to get log2
  let mut count = 0L
  let mut v = n.reinterpret_as_uint64()
  while (v & 1UL) == 0UL {
    count = count + 1L
    v = v >> 1
  }
  Some(count)
}

///|
/// udiv(y, select(cond, 2^n, 2^m)) = ushr(y, select(cond, n, m))
/// Convert division by power-of-two select to shift by select
fn rule_udiv_select_pow2() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Udiv && node.children.length() == 2 {
          let y = node.children[0]
          // Check if divisor is a select
          for divisor_node in eg.get_nodes(node.children[1]) {
            if divisor_node.op is Select && divisor_node.children.length() == 3 {
              let cond = divisor_node.children[0]
              // Check if both branches are power of 2 constants
              if eg.find_const(divisor_node.children[1]) is Some(n_val) &&
                eg.find_const(divisor_node.children[2]) is Some(m_val) {
                if is_power_of_two(n_val) is Some(n_log) &&
                  is_power_of_two(m_val) is Some(m_log) {
                  // Create select(cond, n_log, m_log)
                  let n_const = eg.add_const(n_log)
                  let m_const = eg.add_const(m_log)
                  let shift_select = eg.add({
                    op: Select,
                    children: [cond, n_const, m_const],
                  })
                  // Create ushr(y, select(...))
                  let new_node = eg.add({
                    op: Ushr,
                    children: [y, shift_select],
                  })
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
/// uadd_overflow optimization: (a:uextend) + (b:uextend) cannot overflow
/// If both operands are zero-extended from smaller types, their sum won't overflow
/// This rule recognizes Add of two uextend values and marks them as safe
/// (In a full implementation, this would be used to remove overflow traps)
fn rule_add_uextend_no_overflow() -> RewriteRule {
  {
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let mut left_is_uextend = false
          let mut right_is_uextend = false
          // Check if left operand is uextend
          for left in eg.get_nodes(node.children[0]) {
            if left.op is Uextend(_, _) {
              left_is_uextend = true
              break
            }
          }
          // Check if right operand is uextend
          for right in eg.get_nodes(node.children[1]) {
            if right.op is Uextend(_, _) {
              right_is_uextend = true
              break
            }
          }
          // If both are uextends, the sum cannot overflow the extended type.
          // This is pattern recognition for potential future optimizations.
          // Transformation would require e-graph node annotations (not yet supported).
          // Example uses: nsw/nuw flags for LLVM-style optimizations,
          // or marking additions as safe for strength reduction.
          if left_is_uextend && right_is_uextend {
            // Pattern recognized but no transformation currently.
            // Future: add AddNoOverflow(a, b) equivalent to egraph
            changed = changed
          }
        }
      }
      changed
    },
  }
}

///|
/// Collect all skeleton rules
pub fn skeleton_rules() -> Array[RewriteRule] {
  [rule_udiv_select_pow2(), rule_add_uextend_no_overflow()]
}
