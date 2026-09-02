// SIMD vector optimization rules

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
fn rule_splat_const(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Splat &&
    node.children.length() == 1 &&
    eg.find_const(node.children[0]) is Some(c) {
    // Default to 64-bit splat (most common case)
    // In a real implementation, we'd need type information
    // to determine the lane width
    let pattern = splat64(c.reinterpret_as_uint64())
    let vconst_node = eg.add_vconst(pattern)
    changed = eg.merge_changed(class_id, vconst_node) || changed
  }
  changed
}

// ============================================================================
// Lift splat outside of binary operations
// op(splat(x), splat(y)) -> splat(op(x, y))
// ============================================================================

///|
/// Helper to check if a node is a Splat and get its child
fn find_splat_child(eg : EGraph, class_id : EClassId) -> EClassId? {
  for node in eg.get_nodes(class_id) {
    if node.op is Splat && node.children.length() == 1 {
      return Some(node.children[0])
    }
  }
  None
}

///|
/// band(splat(x), splat(y)) -> splat(band(x, y))
fn rule_band_splat_splat(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is And &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) &&
    find_splat_child(eg, node.children[1]) is Some(y) {
    // band(splat(x), splat(y)) -> splat(band(x, y))
    let inner_and = eg.add_and(x, y)
    let new_node = eg.add({ op: Splat, children: [inner_and], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// bor(splat(x), splat(y)) -> splat(bor(x, y))
fn rule_bor_splat_splat(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Or &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) &&
    find_splat_child(eg, node.children[1]) is Some(y) {
    let inner_or = eg.add_or(x, y)
    let new_node = eg.add({ op: Splat, children: [inner_or], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// bxor(splat(x), splat(y)) -> splat(bxor(x, y))
fn rule_bxor_splat_splat(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Xor &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) &&
    find_splat_child(eg, node.children[1]) is Some(y) {
    let inner_xor = eg.add_xor(x, y)
    let new_node = eg.add({ op: Splat, children: [inner_xor], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// bnot(splat(x)) -> splat(bnot(x))
fn rule_bnot_splat(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Bnot &&
    node.children.length() == 1 &&
    find_splat_child(eg, node.children[0]) is Some(x) {
    let inner_bnot = eg.add({ op: Bnot, children: [x], })
    let new_node = eg.add({ op: Splat, children: [inner_bnot], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// iadd(splat(x), splat(y)) -> splat(iadd(x, y))
fn rule_iadd_splat_splat(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Add &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) &&
    find_splat_child(eg, node.children[1]) is Some(y) {
    let inner_add = eg.add_add(x, y)
    let new_node = eg.add({ op: Splat, children: [inner_add], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// isub(splat(x), splat(y)) -> splat(isub(x, y))
fn rule_isub_splat_splat(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Sub &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) &&
    find_splat_child(eg, node.children[1]) is Some(y) {
    let inner_sub = eg.add_sub(x, y)
    let new_node = eg.add({ op: Splat, children: [inner_sub], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// imul(splat(x), splat(y)) -> splat(imul(x, y))
fn rule_imul_splat_splat(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Mul &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) &&
    find_splat_child(eg, node.children[1]) is Some(y) {
    let inner_mul = eg.add_mul(x, y)
    let new_node = eg.add({ op: Splat, children: [inner_mul], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// ineg(splat(x)) -> splat(ineg(x))
fn rule_ineg_splat(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Neg &&
    node.children.length() == 1 &&
    find_splat_child(eg, node.children[0]) is Some(x) {
    let inner_neg = eg.add({ op: Neg, children: [x], })
    let new_node = eg.add({ op: Splat, children: [inner_neg], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// iabs(splat(x)) -> splat(iabs(x))
fn rule_iabs_splat(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Iabs &&
    node.children.length() == 1 &&
    find_splat_child(eg, node.children[0]) is Some(x) {
    let inner_iabs = eg.add({ op: Iabs, children: [x], })
    let new_node = eg.add({ op: Splat, children: [inner_iabs], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// popcnt(splat(x)) -> splat(popcnt(x))
fn rule_popcnt_splat(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Popcnt &&
    node.children.length() == 1 &&
    find_splat_child(eg, node.children[0]) is Some(x) {
    let inner_popcnt = eg.add({ op: Popcnt, children: [x], })
    let new_node = eg.add({ op: Splat, children: [inner_popcnt], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// smin(splat(x), splat(y)) -> splat(smin(x, y))
fn rule_smin_splat_splat(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Smin &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) &&
    find_splat_child(eg, node.children[1]) is Some(y) {
    let inner_smin = eg.add({ op: Smin, children: [x, y], })
    let new_node = eg.add({ op: Splat, children: [inner_smin], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// umin(splat(x), splat(y)) -> splat(umin(x, y))
fn rule_umin_splat_splat(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Umin &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) &&
    find_splat_child(eg, node.children[1]) is Some(y) {
    let inner_umin = eg.add({ op: Umin, children: [x, y], })
    let new_node = eg.add({ op: Splat, children: [inner_umin], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// smax(splat(x), splat(y)) -> splat(smax(x, y))
fn rule_smax_splat_splat(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Smax &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) &&
    find_splat_child(eg, node.children[1]) is Some(y) {
    let inner_smax = eg.add({ op: Smax, children: [x, y], })
    let new_node = eg.add({ op: Splat, children: [inner_smax], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// umax(splat(x), splat(y)) -> splat(umax(x, y))
fn rule_umax_splat_splat(
  eg : EGraph,
  class_id : EClassId,
  node : ENode,
) -> Bool {
  let mut changed = false
  if node.op is Umax &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) &&
    find_splat_child(eg, node.children[1]) is Some(y) {
    let inner_umax = eg.add({ op: Umax, children: [x, y], })
    let new_node = eg.add({ op: Splat, children: [inner_umax], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

// ============================================================================
// Shift/rotate operations: only first operand is splatted
// op(splat(x), y) -> splat(op(x, y))
// ============================================================================

///|
/// rotl(splat(x), y) -> splat(rotl(x, y))
fn rule_rotl_splat(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Rotl &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) {
    let y = node.children[1]
    let inner_rotl = eg.add({ op: Rotl, children: [x, y], })
    let new_node = eg.add({ op: Splat, children: [inner_rotl], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// rotr(splat(x), y) -> splat(rotr(x, y))
fn rule_rotr_splat(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Rotr &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) {
    let y = node.children[1]
    let inner_rotr = eg.add({ op: Rotr, children: [x, y], })
    let new_node = eg.add({ op: Splat, children: [inner_rotr], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// ishl(splat(x), y) -> splat(ishl(x, y))
fn rule_ishl_splat(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Shl &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) {
    let y = node.children[1]
    let inner_shl = eg.add_shl(x, y)
    let new_node = eg.add({ op: Splat, children: [inner_shl], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// ushr(splat(x), y) -> splat(ushr(x, y))
fn rule_ushr_splat(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Ushr &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) {
    let y = node.children[1]
    let inner_ushr = eg.add({ op: Ushr, children: [x, y], })
    let new_node = eg.add({ op: Splat, children: [inner_ushr], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}

///|
/// sshr(splat(x), y) -> splat(sshr(x, y))
fn rule_sshr_splat(eg : EGraph, class_id : EClassId, node : ENode) -> Bool {
  let mut changed = false
  if node.op is Sshr &&
    node.children.length() == 2 &&
    find_splat_child(eg, node.children[0]) is Some(x) {
    let y = node.children[1]
    let inner_sshr = eg.add({ op: Sshr, children: [x, y], })
    let new_node = eg.add({ op: Splat, children: [inner_sshr], })
    changed = eg.merge_changed(class_id, new_node) || changed
  }
  changed
}
