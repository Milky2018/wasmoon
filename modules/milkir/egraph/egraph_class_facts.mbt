// Per-class facts the e-graph caches alongside the classes themselves:
// integer width and the bounds derived from it.
//
// These ride along with merging rather than driving it -- a merge has to
// reconcile them, which is why `note_type_conflict` lives here and is
// called from the merge path in `egraph.mbt`.

///|
/// Add an e-node with type information
/// bits: the bit width of the value (8, 16, 32, 64, 128)
pub fn EGraph::add_typed(self : EGraph, node : ENode, bits : Int) -> EClassId {
  let class_id = self.add(node)
  self.set_type(class_id, bits)
  class_id
}

///|
/// Poison a class's width information: drop the entry, remember the class,
/// and record the observation. Idempotent per class root.
fn EGraph::note_type_conflict(self : EGraph, root : Int) -> Unit {
  self.type_map.remove(root)
  if !self.type_conflicts.contains(root) {
    self.type_conflicts.add(root)
    self.type_conflict_hits = self.type_conflict_hits + 1
  }
}

///|
/// Set the type (bit width) for an equivalence class.
/// A conflicting assignment poisons the class: it reports no width from
/// then on, so width-dependent rules skip it rather than rewriting with
/// whichever width happened to be recorded first.
pub fn EGraph::set_type(self : EGraph, id : EClassId, bits : Int) -> Unit {
  let canonical = self.find(id).0
  match self.type_map.get(canonical) {
    None =>
      if !self.type_conflicts.contains(canonical) {
        self.type_map.set(canonical, bits)
      }
    Some(existing) => if existing != bits { self.note_type_conflict(canonical) }
  }
}

///|
/// Number of width-conflict observations so far (diagnostic).
pub fn EGraph::type_conflict_count(self : EGraph) -> Int {
  self.type_conflict_hits
}

///|
/// Number of constant-cache conflict observations so far (diagnostic).
/// A nonzero value means some rule merged classes carrying different
/// constants — an unsound union whose constant is deliberately not
/// harvested.
pub fn EGraph::const_conflict_count(self : EGraph) -> Int {
  self.const_conflict_hits
}

///|
/// Get the type (bit width) for an equivalence class
/// Returns None if no type information is available
pub fn EGraph::get_bits(self : EGraph, id : EClassId) -> Int? {
  let canonical = self.find(id).0
  self.type_map.get(canonical)
}

///|
/// Get the maximum unsigned value for a given bit width
pub fn ty_umax(bits : Int) -> Int64 {
  match bits {
    8 => 0xFFL
    16 => 0xFFFFL
    32 => 0xFFFF_FFFFL
    64 => -1L // 0xFFFF_FFFF_FFFF_FFFF
    _ => -1L
  }
}

///|
const I32_SMIN_I64 : Int64 = -2147483648L

///|
const I32_SMAX_I64 : Int64 = 2147483647L

///|
/// Get the minimum signed value for a given bit width
pub fn ty_smin(bits : Int) -> Int64 {
  match bits {
    8 => -128L
    16 => -32768L
    32 => I32_SMIN_I64
    64 => -9223372036854775808L
    _ => -9223372036854775808L
  }
}

///|
/// Get the maximum signed value for a given bit width
pub fn ty_smax(bits : Int) -> Int64 {
  match bits {
    8 => 127L
    16 => 32767L
    32 => I32_SMAX_I64
    64 => 9223372036854775807L
    _ => 9223372036854775807L
  }
}
