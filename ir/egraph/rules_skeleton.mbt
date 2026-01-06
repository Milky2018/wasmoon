// Skeleton rules: pure simplifications for algebraic identities

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
/// Collect all skeleton rules
pub fn skeleton_rules() -> Array[RewriteRule] {
  [rule_udiv_select_pow2()]
}
