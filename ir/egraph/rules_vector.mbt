// Vector splat rules for EGraph optimization
// Implements Cranelift cprop.isle vector optimization rules

///|
/// Helper to create splat8 pattern: replicate byte 16 times
/// TODO: Use when type info available for lane width detection
#warnings("-unused_value")
fn splat8(n : UInt64) -> Bytes {
  let byte = (n & 0xFFUL).to_byte()
  Bytes::make(16, byte)
}

///|
/// Helper to create splat16 pattern: replicate 16-bit value 8 times
/// TODO: Use when type info available for lane width detection
#warnings("-unused_value")
fn splat16(n : UInt64) -> Bytes {
  let val = (n & 0xFFFFUL).to_int()
  Bytes::makei(16, fn(i) {
    let lane = i / 2
    let byte_idx = i % 2
    guard lane < 8 else { b'\x00' }
    ((val >> (byte_idx * 8)) & 0xFF).to_byte()
  })
}

///|
/// Helper to create splat32 pattern: replicate 32-bit value 4 times
/// TODO: Use when type info available for lane width detection
#warnings("-unused_value")
fn splat32(n : UInt64) -> Bytes {
  let val = (n & 0xFFFFFFFFUL).reinterpret_as_int64()
  Bytes::makei(16, fn(i) {
    let lane = i / 4
    let byte_idx = i % 4
    guard lane < 4 else { b'\x00' }
    ((val >> (byte_idx * 8)) & 0xFFL).to_byte()
  })
}

///|
/// Helper to create splat64 pattern: replicate 64-bit value 2 times
fn splat64(n : UInt64) -> Bytes {
  let val = n.reinterpret_as_int64()
  Bytes::makei(16, fn(i) {
    let lane = i / 8
    let byte_idx = i % 8
    guard lane < 2 else { b'\x00' }
    ((val >> (byte_idx * 8)) & 0xFFL).to_byte()
  })
}

///|
/// splat(iconst) -> vconst
/// Converts splat of constant to vector constant
fn rule_splat_const() -> RewriteRule {
  {
    name: "splat_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Splat && node.children.length() == 1 {
          if eg.find_const(node.children[0]) is Some(c) {
            // Default to 64-bit splat (most common case)
            // In a real implementation, we'd need type information
            // to determine the lane width
            let pattern = splat64(c.reinterpret_as_uint64())
            let vconst_node = eg.add_vconst(pattern)
            let new_id = eg.merge(class_id, vconst_node)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}
