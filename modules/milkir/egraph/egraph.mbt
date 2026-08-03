// E-graph (Equality Graph) Implementation
//
// An e-graph is a data structure that compactly represents many equivalent
// expressions. It consists of e-classes (equivalence classes) containing
// e-nodes (expression nodes). This enables equality saturation optimization.
//
// Key concepts:
// - EClassId: Identifies an equivalence class
// - ENode: An expression node with an opcode and children (which are EClassIds)
// - EClass: A set of equivalent ENodes
// - EGraph: The main data structure containing all e-classes

///|
/// E-class identifier (index into the e-graph's class array)
pub(all) struct EClassId(Int) derive(Eq, Hash, Debug, Compare)

///|
/// E-node opcode for e-graph expressions
/// Standard IR opcodes for optimization
pub(all) enum EOpcode {
  // Constants
  Const(Int64) // Integer constant
  // Float constants (bits stored as UInt64, type indicated by context)
  // F32 uses lower 32 bits, F64 uses all 64 bits
  Fconst(UInt64) // Float constant (bit pattern)

  // Integer arithmetic (binary)
  Add
  Sub
  Mul
  Sdiv
  Udiv
  Srem
  Urem

  // Bitwise operations (binary)
  And
  Or
  Xor
  Shl
  Sshr
  Ushr
  Rotl // Rotate left
  Rotr // Rotate right

  // Unary arithmetic
  Neg // Integer negation (-x)
  Bnot // Bitwise NOT (~x)

  // Bit counting/manipulation (unary)
  Clz // Count leading zeros
  Ctz // Count trailing zeros
  Popcnt // Population count (count 1 bits)
  Bswap // Byte swap
  Bitrev // Bit reverse

  // Comparison (binary, returns i1)
  // IntCC: 0=eq, 1=ne, 2=slt, 3=sle, 4=sgt, 5=sge, 6=ult, 7=ule, 8=ugt, 9=uge
  Icmp(Int) // Integer compare with condition code
  Eq // Equal (shorthand for Icmp(0))
  Ne // Not equal (shorthand for Icmp(1))

  // Conditional
  Select // select(cond, a, b) = cond ? a : b
  Bmask // Boolean mask: 0 -> 0, nonzero -> -1

  // Integer min/max (binary)
  Smin // Signed minimum
  Smax // Signed maximum
  Umin // Unsigned minimum
  Umax // Unsigned maximum

  // Integer absolute value (unary)
  Iabs // Integer absolute value

  // Three-way comparison (spaceship operator, returns -1, 0, or 1)
  SpaceshipS // Signed three-way comparison: (x > y) - (x < y)
  SpaceshipU // Unsigned three-way comparison: (x > y) - (x < y)

  // Type conversions (integer) - with bit width info for type-aware optimizations
  // (from_bits, to_bits): e.g., Ireduce(64, 32) means i64 -> i32
  Ireduce(Int, Int) // Integer reduce (truncate to smaller type)
  Uextend(Int, Int) // Unsigned extend to larger type
  Sextend(Int, Int) // Signed extend to larger type

  // Floating point arithmetic (binary)
  Fadd // Float add
  Fsub // Float subtract
  Fmul // Float multiply
  Fdiv // Float divide
  Fmin // Float minimum
  Fmax // Float maximum
  Fcopysign // Copy sign from second operand to first

  // Floating point unary
  Fneg // Float negate
  Fabs // Float absolute value
  Fsqrt // Float square root
  Fceil // Float ceiling
  Ffloor // Float floor
  Ftrunc // Float truncate toward zero
  Fnearest // Float round to nearest

  // Floating point comparison
  // FloatCC: 0=ord, 1=uno, 2=eq, 3=ne, 4=lt, 5=le, 6=gt, 7=ge
  Fcmp(Int) // Float compare with condition code

  // Float-integer conversions
  Fpromote // Promote f32 to f64
  Fdemote // Demote f64 to f32
  FcvtToSint // Float to signed int
  FcvtToUint // Float to unsigned int
  SintToFcvt // Signed int to float
  UintToFcvt // Unsigned int to float

  // Vector operations
  Splat // Broadcast scalar to vector
  Vconst(Bytes) // Vector constant (128-bit)

  // Variable reference (leaf node representing an IR value)
  Var(Int) // IR Value id
} derive(Eq, Hash, Debug, Compare)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for EClassId with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
pub impl Show for EOpcode with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
/// E-opcode tag for indexing (ignores parameters like Const value)
enum EOpcodeTag {
  TConst
  TFconst
  // Arithmetic
  TAdd
  TSub
  TMul
  TSdiv
  TUdiv
  TSrem
  TUrem
  // Bitwise
  TAnd
  TOr
  TXor
  TShl
  TSshr
  TUshr
  TRotl
  TRotr
  // Unary
  TNeg
  TBnot
  // Bit manipulation
  TClz
  TCtz
  TPopcnt
  TBswap
  TBitrev
  // Comparison
  TIcmp
  TEq
  TNe
  // Conditional
  TSelect
  TBmask
  // Integer min/max
  TSmin
  TSmax
  TUmin
  TUmax
  // Integer absolute value
  TIabs
  // Three-way comparison
  TSpaceshipS
  TSpaceshipU
  // Type conversion (integer)
  TIreduce
  TUextend
  TSextend
  // Float arithmetic
  TFadd
  TFsub
  TFmul
  TFdiv
  TFmin
  TFmax
  TFcopysign
  // Float unary
  TFneg
  TFabs
  TFsqrt
  TFceil
  TFfloor
  TFtrunc
  TFnearest
  // Float comparison
  TFcmp
  // Float-integer conversion
  TFpromote
  TFdemote
  TFcvtToSint
  TFcvtToUint
  TSintToFcvt
  TUintToFcvt
  // Vector
  TSplat
  TVconst
  // Variable
  TVar
} derive(Eq, Hash, Debug)

///|
/// Get the tag of an opcode (for indexing)
pub fn EOpcode::tag(self : EOpcode) -> EOpcodeTag {
  match self {
    Const(_) => TConst
    Fconst(_) => TFconst
    // Arithmetic
    Add => TAdd
    Sub => TSub
    Mul => TMul
    Sdiv => TSdiv
    Udiv => TUdiv
    Srem => TSrem
    Urem => TUrem
    // Bitwise
    And => TAnd
    Or => TOr
    Xor => TXor
    Shl => TShl
    Sshr => TSshr
    Ushr => TUshr
    Rotl => TRotl
    Rotr => TRotr
    // Unary
    Neg => TNeg
    Bnot => TBnot
    // Bit manipulation
    Clz => TClz
    Ctz => TCtz
    Popcnt => TPopcnt
    Bswap => TBswap
    Bitrev => TBitrev
    // Comparison
    Icmp(_) => TIcmp
    Eq => TEq
    Ne => TNe
    // Conditional
    Select => TSelect
    Bmask => TBmask
    // Integer min/max
    Smin => TSmin
    Smax => TSmax
    Umin => TUmin
    Umax => TUmax
    // Integer absolute value
    Iabs => TIabs
    // Three-way comparison
    SpaceshipS => TSpaceshipS
    SpaceshipU => TSpaceshipU
    // Type conversion (integer) - ignore bit width parameters for tagging
    Ireduce(_, _) => TIreduce
    Uextend(_, _) => TUextend
    Sextend(_, _) => TSextend
    // Float arithmetic
    Fadd => TFadd
    Fsub => TFsub
    Fmul => TFmul
    Fdiv => TFdiv
    Fmin => TFmin
    Fmax => TFmax
    Fcopysign => TFcopysign
    // Float unary
    Fneg => TFneg
    Fabs => TFabs
    Fsqrt => TFsqrt
    Fceil => TFceil
    Ffloor => TFfloor
    Ftrunc => TFtrunc
    Fnearest => TFnearest
    // Float comparison
    Fcmp(_) => TFcmp
    // Float-integer conversion
    Fpromote => TFpromote
    Fdemote => TFdemote
    FcvtToSint => TFcvtToSint
    FcvtToUint => TFcvtToUint
    SintToFcvt => TSintToFcvt
    UintToFcvt => TUintToFcvt
    // Vector
    Splat => TSplat
    Vconst(_) => TVconst
    // Variable
    Var(_) => TVar
  }
}

///|
/// E-node: an expression node in the e-graph
/// Children are EClassIds, not direct node references
pub(all) struct ENode {
  op : EOpcode
  children : Array[EClassId]
} derive(Eq, Hash, Debug, Compare)

///|
/// E-class: an equivalence class of e-nodes
priv struct EClass {
  mut nodes : Array[ENode] // All equivalent nodes in this class
  // Cached constant values for O(1) lookup (instead of O(n) scan)
  mut const_value : Int64?
  mut fconst_value : UInt64?
}

///|
/// Union-Find data structure for e-class merging
priv struct UnionFind {
  // parent[i] = parent of i, or i if i is a root
  parent : Array[Int]
  // size[i] = number of elements in i's tree when i is a root
  size : Array[Int]
}

///|
fn UnionFind::UnionFind() -> UnionFind {
  { parent: [], size: [] }
}

///|
fn UnionFind::make_set(self : UnionFind) -> Int {
  let id = self.parent.length()
  self.parent.push(id)
  self.size.push(1)
  id
}

///|
fn UnionFind::find(self : UnionFind, x : Int) -> Int {
  // Path compression
  let mut cur = x
  while self.parent[cur] != cur {
    let grandparent = self.parent[self.parent[cur]]
    self.parent[cur] = grandparent
    cur = grandparent
  }
  cur
}

///|
/// Union two sets by size, returning the surviving root.
/// Callers must not assume which side wins; use `union_keep` when the
/// survivor matters (as `subsume` does).
fn UnionFind::union(self : UnionFind, a : Int, b : Int) -> Int {
  let root_a = self.find(a)
  let root_b = self.find(b)
  if root_a == root_b {
    return root_a
  }
  // Attach the smaller tree under the larger one; ties break on the lower
  // id so the result stays deterministic.
  let (keep, other) = if self.size[root_a] > self.size[root_b] {
    (root_a, root_b)
  } else if self.size[root_b] > self.size[root_a] {
    (root_b, root_a)
  } else if root_a < root_b {
    (root_a, root_b)
  } else {
    (root_b, root_a)
  }
  self.parent[other] = keep
  self.size[keep] = self.size[keep] + self.size[other]
  keep
}

///|
/// Union two sets, forcing `keep` to remain the root.
/// Returns the root id (always the root of `keep`).
fn UnionFind::union_keep(self : UnionFind, keep : Int, other : Int) -> Int {
  let root_keep = self.find(keep)
  let root_other = self.find(other)
  if root_keep == root_other {
    return root_keep
  }
  self.parent[root_other] = root_keep
  self.size[root_keep] = self.size[root_keep] + self.size[root_other]
  root_keep
}

///|
/// The main E-graph data structure
struct EGraph {
  // Union-find for equivalence classes
  uf : UnionFind
  // All e-classes (indexed by canonical id)
  classes : Map[Int, EClass]
  // Hash-cons map: ENode -> EClassId (for deduplication)
  hashcons : Map[ENode, EClassId]
  // Dirty flag: true if there are pending merges
  mut dirty : Bool
  // Parent edges: child class root -> ids of classes holding a node that
  // references it. Consumed by `rebuild` to repair only what a union
  // disturbed instead of rewalking the whole graph.
  parents : Map[Int, @hashset.HashSet[Int]]
  // Classes whose contents changed since the last rebuild.
  pending : Array[Int]
  // Classes repaired by the most recent rebuild (diagnostic).
  mut last_rebuild_repairs : Int
  // Opcode index: maps opcode tag to set of class ids containing that opcode
  opcode_index : Map[EOpcodeTag, @hashset.HashSet[Int]]
  // Type information: maps canonical class id to bit width (8, 16, 32, 64, 128)
  type_map : Map[Int, Int]
  // Classes whose width information conflicted (e.g., a constant shared by
  // i32 and i64 uses). Poisoned classes report no width so width-dependent
  // rules skip them instead of rewriting with a first-seen width (ISS-379).
  type_conflicts : @hashset.HashSet[Int]
  // Diagnostic counters: conflict observations, monotonically increasing.
  mut type_conflict_hits : Int
  mut const_conflict_hits : Int
  // Rematerialization set: classes that are cheap to recompute
  remat_set : @hashset.HashSet[Int]
  // Number of successful rule applications in the most recent saturate call.
  mut last_rule_applications : Int
  // Number of times rewrite candidates were truncated by matches limit.
  mut last_matches_limit_hits : Int
  // Number of times rule application was skipped due to eclass size limit.
  mut last_eclass_size_limit_hits : Int
}

///|
pub fn EGraph::EGraph() -> EGraph {
  {
    uf: UnionFind(),
    classes: Map([]),
    hashcons: Map([]),
    dirty: false,
    parents: Map([]),
    pending: [],
    last_rebuild_repairs: 0,
    opcode_index: Map([]),
    type_map: Map([]),
    type_conflicts: HashSet([]),
    type_conflict_hits: 0,
    const_conflict_hits: 0,
    remat_set: HashSet([]),
    last_rule_applications: 0,
    last_matches_limit_hits: 0,
    last_eclass_size_limit_hits: 0,
  }
}

///|
/// Add a class to the opcode index
fn EGraph::index_add(self : EGraph, tag : EOpcodeTag, class_id : Int) -> Unit {
  match self.opcode_index.get(tag) {
    Some(set) => set.add(class_id)
    None => {
      let set : @hashset.HashSet[Int] = HashSet([])
      set.add(class_id)
      self.opcode_index.set(tag, set)
    }
  }
}

///|
/// Find the canonical EClassId for a given id
pub fn EGraph::find(self : EGraph, id : EClassId) -> EClassId {
  EClassId(self.uf.find(id.0))
}

///|
/// Canonicalize an ENode by finding canonical ids for all children and
/// normalizing commutative operand order.
fn EGraph::canonicalize(self : EGraph, node : ENode) -> ENode {
  let new_children : Array[EClassId] = []
  for child in node.children {
    new_children.push(self.find(child))
  }

  // Normalize commutative binary ops:
  // - Prefer putting constants on the right (enables simpler pattern matching).
  // - Otherwise, order operands by canonical class id for determinism.
  if new_children.length() == 2 {
    let op = node.op
    let is_commutative = match op {
      Add | Mul | And | Or | Xor | Eq | Ne | Smin | Smax | Umin | Umax => true
      Fadd | Fmul | Fmin | Fmax => true
      _ => false
    }
    if is_commutative {
      let a = new_children[0]
      let b = new_children[1]
      let a_is_const = self.get_const(a) is Some(_) ||
        self.get_fconst(a) is Some(_)
      let b_is_const = self.get_const(b) is Some(_) ||
        self.get_fconst(b) is Some(_)
      if a_is_const && !b_is_const {
        return { op, children: [b, a] }
      }
      if !a_is_const && b_is_const {
        return { op, children: [a, b] }
      }
      if a.0 <= b.0 {
        return { op, children: [a, b] }
      } else {
        return { op, children: [b, a] }
      }
    }
  }
  { op: node.op, children: new_children }
}

///|
/// Add an e-node to the e-graph, returning its e-class id.
/// If an equivalent node already exists, returns the existing class id.
/// Rewriting happens later, in `saturate_indexed`.
pub fn EGraph::add(self : EGraph, node : ENode) -> EClassId {
  // Canonicalize the node first
  let node = self.canonicalize(node)

  // Check if this node already exists (hash-consing)
  if self.hashcons.get(node) is Some(existing_id) {
    return self.find(existing_id)
  }

  // Create a new e-class with cached constant values
  let id = self.uf.make_set()
  let class_id = EClassId(id)
  // Extract constant value if this is a constant node
  let const_val : Int64? = match node.op {
    Const(v) => Some(v)
    _ => None
  }
  let fconst_val : UInt64? = match node.op {
    Fconst(bits) => Some(bits)
    _ => None
  }
  let eclass : EClass = {
    nodes: [node],
    const_value: const_val,
    fconst_value: fconst_val,
  }
  self.classes.set(id, eclass)
  self.hashcons.set(node, class_id)
  // Update opcode index
  let tag = node.op.tag()
  self.index_add(tag, id)
  self.record_parent_edges(node, id)
  class_id
}

///|
/// Record that class `owner` holds a node referencing each of its children.
fn EGraph::record_parent_edges(
  self : EGraph,
  node : ENode,
  owner : Int,
) -> Unit {
  for child in node.children {
    let child_root = self.find(child).0
    match self.parents.get(child_root) {
      Some(owners) => owners.add(owner)
      None => {
        let owners : @hashset.HashSet[Int] = HashSet([])
        owners.add(owner)
        self.parents.set(child_root, owners)
      }
    }
  }
}

///|
/// Mark a class as needing repair on the next rebuild.
fn EGraph::mark_pending(self : EGraph, class_id : Int) -> Unit {
  self.pending.push(class_id)
  self.dirty = true
}

///|
/// Number of classes repaired by the most recent `rebuild` (diagnostic).
pub fn EGraph::last_rebuild_repairs(self : EGraph) -> Int {
  self.last_rebuild_repairs
}

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

// ============================================================================
// Rematerialization support
// ============================================================================

///|
/// Mark an equivalence class as rematerializable
/// Rematerializable expressions are cheap to recompute at each use site
pub fn EGraph::mark_rematerializable(self : EGraph, id : EClassId) -> Bool {
  let canonical = self.find(id).0
  if self.remat_set.contains(canonical) {
    false
  } else {
    self.remat_set.add(canonical)
    true
  }
}

///|
/// Check if an equivalence class is marked as rematerializable
pub fn EGraph::is_marked_rematerializable(self : EGraph, id : EClassId) -> Bool {
  let canonical = self.find(id).0
  self.remat_set.contains(canonical)
}

///|
/// Get the rematerialization bonus for cost calculation
/// Returns a negative value (cost reduction) if the class is rematerializable
pub fn EGraph::remat_cost_bonus(self : EGraph, id : EClassId) -> Int {
  if self.is_marked_rematerializable(id) {
    -1 // Small bonus for rematerializable expressions
  } else {
    0
  }
}

///|
/// Remove a class from the opcode index
fn EGraph::index_remove(
  self : EGraph,
  class_id : Int,
  nodes : Array[ENode],
) -> Unit {
  for node in nodes {
    let tag = node.op.tag()
    if self.opcode_index.get(tag) is Some(set) {
      set.remove(class_id)
    }
  }
}

///|
/// Subsume: replace node in class `a` with node from class `b`
/// Unlike merge, this doesn't add the original node to the equivalence class.
/// Used to avoid infinite loops in associativity/commutativity rules.
/// Returns the canonical id of the result (same as b).
pub fn EGraph::subsume(self : EGraph, a : EClassId, b : EClassId) -> EClassId {
  let a = self.find(a)
  let b = self.find(b)
  if a == b {
    return a
  }

  // Redirect `a` to `b` without merging nodes: we prefer `b`'s representation.
  // Important: force `b` to remain the root so we never delete the root class.
  let keep_root = self.uf.union_keep(b.0, a.0)
  let b = EClassId(keep_root)

  // Transfer type information from a to b; conflicting widths poison b.
  if self.type_conflicts.contains(a.0) {
    self.note_type_conflict(b.0)
  }
  match (self.type_map.get(b.0), self.type_map.get(a.0)) {
    (None, Some(bits)) =>
      if !self.type_conflicts.contains(b.0) {
        self.type_map.set(b.0, bits)
      }
    (Some(existing), Some(bits)) =>
      if existing != bits {
        self.note_type_conflict(b.0)
      }
    _ => ()
  }
  // Remove type entries for the subsumed class
  self.type_map.remove(a.0)
  self.type_conflicts.remove(a.0)

  // Transfer rematerialization flag: if either was rematerializable, result is
  if self.remat_set.contains(a.0) {
    self.remat_set.add(b.0)
  }
  self.remat_set.remove(a.0)

  // Remove the old class from opcode index before removing it
  if self.classes.get(a.0) is Some(old_class) {
    self.index_remove(a.0, old_class.nodes)
  }

  // Remove the old class entirely - its nodes are "subsumed"
  self.classes.remove(a.0)
  self.absorb_parent_edges(a.0, b.0)
  self.mark_pending(b.0)
  b
}

///|
/// Update opcode index when a class is merged into another
fn EGraph::index_merge(
  self : EGraph,
  old_id : Int,
  new_id : Int,
  nodes : Array[ENode],
) -> Unit {
  // For each node, remove old_id from index and add new_id
  for node in nodes {
    let tag = node.op.tag()
    if self.opcode_index.get(tag) is Some(set) {
      set.remove(old_id)
      set.add(new_id)
    }
  }
}

///|
/// Merge two e-classes, returning the canonical id of the merged class
pub fn EGraph::merge(self : EGraph, a : EClassId, b : EClassId) -> EClassId {
  let a = self.find(a)
  let b = self.find(b)
  if a == b {
    return a
  }

  // Rules report progress explicitly via `merge_changed`, so the union-find
  // is free to pick whichever root keeps its trees shallow.
  let keep_root = self.uf.union(a.0, b.0)
  let new_id = EClassId(keep_root)
  let other_id = if keep_root == a.0 { b } else { a }

  // Merge type information; conflicting widths poison the merged class.
  if self.type_conflicts.contains(other_id.0) {
    self.note_type_conflict(new_id.0)
  }
  match (self.type_map.get(new_id.0), self.type_map.get(other_id.0)) {
    (None, Some(bits)) =>
      if !self.type_conflicts.contains(new_id.0) {
        self.type_map.set(new_id.0, bits)
      }
    (Some(existing), Some(bits)) =>
      if existing != bits {
        self.note_type_conflict(new_id.0)
      }
    _ => ()
  }
  // Remove old type entries
  self.type_map.remove(other_id.0)
  self.type_conflicts.remove(other_id.0)

  // Merge rematerialization flag: if either was rematerializable, result is
  if self.remat_set.contains(other_id.0) {
    self.remat_set.add(new_id.0)
  }
  self.remat_set.remove(other_id.0)

  // Merge the e-class contents
  if self.classes.get(other_id.0) is Some(other_class) {
    // Update opcode index: redirect old class entries to new class
    self.index_merge(other_id.0, new_id.0, other_class.nodes)
    if self.classes.get(new_id.0) is Some(root_class) {
      // Merge all nodes: this preserves equivalences needed for congruence
      // closure (e.g., when children are later merged). Membership is
      // hashed, not scanned: e-classes can hold many nodes once the
      // per-class node budget is raised.
      let present : @hashset.HashSet[ENode] = HashSet([])
      for existing in root_class.nodes {
        present.add(existing)
      }
      for node in other_class.nodes {
        let canonical_node = self.canonicalize(node)
        if !present.contains(canonical_node) {
          present.add(canonical_node)
          root_class.nodes.push(canonical_node)
          // Keep hashcons aware of the merged node so it isn't re-created.
          self.hashcons.set(canonical_node, new_id)
          self.record_parent_edges(canonical_node, new_id.0)
        }
      }
      // Merge constant caches. Two classes carrying *different* constants
      // is proof of an unsound union: record it and refuse to harvest
      // either constant rather than silently keeping the root's.
      match (root_class.const_value, other_class.const_value) {
        (Some(a_val), Some(b_val)) =>
          if a_val != b_val {
            root_class.const_value = None
            self.const_conflict_hits = self.const_conflict_hits + 1
          }
        (None, Some(_)) => root_class.const_value = other_class.const_value
        _ => ()
      }
      match (root_class.fconst_value, other_class.fconst_value) {
        (Some(a_bits), Some(b_bits)) =>
          if a_bits != b_bits {
            root_class.fconst_value = None
            self.const_conflict_hits = self.const_conflict_hits + 1
          }
        (None, Some(_)) => root_class.fconst_value = other_class.fconst_value
        _ => ()
      }
    }
    // Remove the merged class
    self.classes.remove(other_id.0)
  }

  // Inherit the subsumed class's parent edges, then schedule repair: every
  // class holding a node that referenced either side now has a stale child
  // id in that node.
  self.absorb_parent_edges(other_id.0, new_id.0)
  self.mark_pending(new_id.0)
  new_id
}

///|
/// Merge two e-classes, reporting whether they were distinct beforehand.
///
/// Rewrite rules use this to answer "did I make progress?" directly, rather
/// than inferring it from which id `merge` returned. Keeping progress
/// explicit lets the union-find choose roots freely.
pub fn EGraph::merge_changed(self : EGraph, a : EClassId, b : EClassId) -> Bool {
  if self.find(a) == self.find(b) {
    return false
  }
  self.merge(a, b) |> ignore
  true
}

///|
/// Subsume `a` into `b`, reporting whether they were distinct beforehand.
pub fn EGraph::subsume_changed(
  self : EGraph,
  a : EClassId,
  b : EClassId,
) -> Bool {
  if self.find(a) == self.find(b) {
    return false
  }
  self.subsume(a, b) |> ignore
  true
}

///|
/// Move parent edges recorded against `old_root` onto `new_root`.
fn EGraph::absorb_parent_edges(
  self : EGraph,
  old_root : Int,
  new_root : Int,
) -> Unit {
  guard self.parents.get(old_root) is Some(old_owners) else { return }
  self.parents.remove(old_root)
  match self.parents.get(new_root) {
    Some(owners) =>
      for owner in old_owners {
        owners.add(owner)
      }
    None => self.parents.set(new_root, old_owners)
  }
}

///|
/// Restore e-graph invariants after unions.
///
/// Repair is driven by a worklist of classes whose contents changed, not by
/// a walk of the whole graph: when a union moves a class, only the nodes
/// that reference it hold a stale child id, and `parents` names exactly the
/// classes holding those nodes. Repairing a class can expose new congruences,
/// whose merges enqueue more work, so the loop runs until the worklist
/// drains.
pub fn EGraph::rebuild(self : EGraph) -> Unit {
  self.last_rebuild_repairs = 0
  if !self.dirty {
    return
  }
  while !self.pending.is_empty() {
    let batch = self.pending.copy()
    self.pending.clear()
    // Deduplicate against current roots: a batch often names the same class
    // several times, and some entries have since been merged away.
    let todo : @hashset.HashSet[Int] = HashSet([])
    for class_id in batch {
      todo.add(self.uf.find(class_id))
    }
    for class_id in todo {
      self.repair_class(class_id)
    }
  }
  self.dirty = false
}

///|
/// Repair one class and every class holding a node that references it.
fn EGraph::repair_class(self : EGraph, class_id : Int) -> Unit {
  let root = self.uf.find(class_id)
  guard self.classes.get(root) is Some(_) else { return }
  self.last_rebuild_repairs = self.last_rebuild_repairs + 1
  // The class's own nodes may carry stale children too (its members were
  // merged in from elsewhere), so recanonicalize it alongside its parents.
  self.recanonicalize_class(root)
  guard self.parents.get(root) is Some(owners) else { return }
  let owner_roots : @hashset.HashSet[Int] = HashSet([])
  for owner in owners {
    owner_roots.add(self.uf.find(owner))
  }
  // Parent edges are re-recorded against current roots as we go.
  self.parents.remove(root)
  for owner in owner_roots {
    self.recanonicalize_class(owner)
  }
}

///|
/// Recanonicalize one class's nodes in place: refresh the hashcons and
/// opcode-index entries they own, re-record their parent edges, refresh the
/// constant caches, and merge any class that turns out to be congruent.
fn EGraph::recanonicalize_class(self : EGraph, class_id : Int) -> Unit {
  let root = self.uf.find(class_id)
  guard self.classes.get(root) is Some(eclass) else { return }
  let canonical_nodes : Array[ENode] = []
  let seen : @hashset.HashSet[ENode] = HashSet([])
  let mut const_value : Int64? = None
  let mut fconst_value : UInt64? = None
  let mut const_conflicted = false
  let mut fconst_conflicted = false
  let congruent : Array[Int] = []
  for node in eclass.nodes {
    // Drop the pre-canonicalization entry; a stale key would otherwise keep
    // resolving to this class forever.
    self.hashcons.remove(node)
    let canonical_node = self.canonicalize(node)
    if seen.contains(canonical_node) {
      continue
    }
    seen.add(canonical_node)
    canonical_nodes.push(canonical_node)
    match canonical_node.op {
      Const(v) =>
        match const_value {
          None => const_value = Some(v)
          Some(existing) => if existing != v { const_conflicted = true }
        }
      Fconst(bits) =>
        match fconst_value {
          None => fconst_value = Some(bits)
          Some(existing) => if existing != bits { fconst_conflicted = true }
        }
      _ => ()
    }
    self.index_add(canonical_node.op.tag(), root)
    self.record_parent_edges(canonical_node, root)
    // Congruence closure: an identical canonical node elsewhere means the
    // two classes are equal.
    match self.hashcons.get(canonical_node) {
      Some(existing_id) => {
        let existing_root = self.uf.find(existing_id.0)
        if existing_root != root {
          congruent.push(existing_root)
        }
      }
      None => self.hashcons.set(canonical_node, EClassId(root))
    }
  }
  eclass.nodes = canonical_nodes
  if const_conflicted {
    self.const_conflict_hits = self.const_conflict_hits + 1
    eclass.const_value = None
  } else {
    eclass.const_value = const_value
  }
  if fconst_conflicted {
    self.const_conflict_hits = self.const_conflict_hits + 1
    eclass.fconst_value = None
  } else {
    eclass.fconst_value = fconst_value
  }
  // Merge after the scan so the loop above is not walking a class that is
  // being rewritten underneath it. `merge` re-enqueues the survivor.
  for other in congruent {
    self.merge(EClassId(other), EClassId(self.uf.find(root))) |> ignore
  }
}

///|
/// Get all nodes in an e-class
pub fn EGraph::get_nodes(self : EGraph, id : EClassId) -> Array[ENode] {
  let canonical = self.find(id)
  if self.classes.get(canonical.0) is Some(eclass) {
    eclass.nodes
  } else {
    []
  }
}

///|
/// Get cached constant value for an e-class (O(1) lookup)
pub fn EGraph::get_const(self : EGraph, id : EClassId) -> Int64? {
  let canonical = self.find(id)
  if self.classes.get(canonical.0) is Some(eclass) {
    eclass.const_value
  } else {
    None
  }
}

///|
/// Get cached float constant value for an e-class (O(1) lookup)
pub fn EGraph::get_fconst(self : EGraph, id : EClassId) -> UInt64? {
  let canonical = self.find(id)
  if self.classes.get(canonical.0) is Some(eclass) {
    eclass.fconst_value
  } else {
    None
  }
}

///|
/// Check if two e-class ids are equivalent
pub fn EGraph::equiv(self : EGraph, a : EClassId, b : EClassId) -> Bool {
  self.find(a) == self.find(b)
}

///|
/// Get the number of e-classes
pub fn EGraph::num_classes(self : EGraph) -> Int {
  self.classes.length()
}

///|
/// Get the total number of e-nodes
pub fn EGraph::num_nodes(self : EGraph) -> Int {
  let mut count = 0
  for _, eclass in self.classes {
    count = count + eclass.nodes.length()
  }
  count
}

///|
/// Number of successful rewrite rule applications in the most recent
/// `saturate` / `saturate_indexed` invocation.
pub fn EGraph::last_rule_applications(self : EGraph) -> Int {
  self.last_rule_applications
}

///|
/// Number of classes/rule streams truncated by the rewrite matches limit in the
/// most recent `saturate` / `saturate_indexed*` invocation.
pub fn EGraph::last_matches_limit_hits(self : EGraph) -> Int {
  self.last_matches_limit_hits
}

///|
/// Number of classes skipped/truncated due to eclass size limit in the most
/// recent `saturate` / `saturate_indexed*` invocation.
pub fn EGraph::last_eclass_size_limit_hits(self : EGraph) -> Int {
  self.last_eclass_size_limit_hits
}

// ============================================================================
// Helper constructors for common e-nodes
// ============================================================================

///|
pub fn EGraph::add_const(self : EGraph, value : Int64) -> EClassId {
  self.add({ op: Const(value), children: [] })
}

///|
pub fn EGraph::add_var(self : EGraph, var_id : Int) -> EClassId {
  self.add({ op: Var(var_id), children: [] })
}

///|
pub fn EGraph::add_binop(
  self : EGraph,
  op : EOpcode,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add({ op, children: [lhs, rhs] })
}

///|
pub fn EGraph::add_add(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Add, lhs, rhs)
}

///|
pub fn EGraph::add_sub(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Sub, lhs, rhs)
}

///|
pub fn EGraph::add_mul(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Mul, lhs, rhs)
}

///|
pub fn EGraph::add_shl(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Shl, lhs, rhs)
}

///|
pub fn EGraph::add_and(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(And, lhs, rhs)
}

///|
pub fn EGraph::add_or(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Or, lhs, rhs)
}

///|
pub fn EGraph::add_xor(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Xor, lhs, rhs)
}

///|
/// Add a negation node: -x
pub fn EGraph::add_neg(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Neg, children: [operand] })
}

///|
/// Add a bitwise NOT node: ~x
pub fn EGraph::add_bnot(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Bnot, children: [operand] })
}

///|
pub fn EGraph::add_sdiv(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Sdiv, lhs, rhs)
}

///|
pub fn EGraph::add_udiv(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Udiv, lhs, rhs)
}

///|
pub fn EGraph::add_srem(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Srem, lhs, rhs)
}

///|
pub fn EGraph::add_urem(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Urem, lhs, rhs)
}

///|
pub fn EGraph::add_ushr(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Ushr, lhs, rhs)
}

///|
pub fn EGraph::add_sshr(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Sshr, lhs, rhs)
}

///|
pub fn EGraph::add_rotl(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Rotl, lhs, rhs)
}

///|
pub fn EGraph::add_rotr(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Rotr, lhs, rhs)
}

///|
/// Add a count leading zeros node
pub fn EGraph::add_clz(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Clz, children: [operand] })
}

///|
/// Add a count trailing zeros node
pub fn EGraph::add_ctz(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Ctz, children: [operand] })
}

///|
/// Add a population count node
pub fn EGraph::add_popcnt(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Popcnt, children: [operand] })
}

///|
/// Add a byte swap node
pub fn EGraph::add_bswap(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Bswap, children: [operand] })
}

///|
/// Add a bit reverse node
pub fn EGraph::add_bitrev(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Bitrev, children: [operand] })
}

///|
/// Add an integer compare node with condition code
pub fn EGraph::add_icmp(
  self : EGraph,
  cc : Int,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add({ op: Icmp(cc), children: [lhs, rhs] })
}

///|
/// Add an equality comparison node
pub fn EGraph::add_eq(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Eq, lhs, rhs)
}

///|
/// Add a not-equal comparison node
pub fn EGraph::add_ne(
  self : EGraph,
  lhs : EClassId,
  rhs : EClassId,
) -> EClassId {
  self.add_binop(Ne, lhs, rhs)
}

///|
/// Add a select node: select(cond, a, b) = cond ? a : b
pub fn EGraph::add_select(
  self : EGraph,
  cond : EClassId,
  a : EClassId,
  b : EClassId,
) -> EClassId {
  self.add({ op: Select, children: [cond, a, b] })
}

///|
/// Add a boolean mask node: 0 -> 0, nonzero -> -1
pub fn EGraph::add_bmask(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Bmask, children: [operand] })
}

///|
/// Add an integer reduce (truncate) node with type info
pub fn EGraph::add_ireduce(
  self : EGraph,
  operand : EClassId,
  from_bits? : Int = 64,
  to_bits? : Int = 32,
) -> EClassId {
  self.add({ op: Ireduce(from_bits, to_bits), children: [operand] })
}

///|
/// Add an unsigned extend node with type info
pub fn EGraph::add_uextend(
  self : EGraph,
  operand : EClassId,
  from_bits? : Int = 32,
  to_bits? : Int = 64,
) -> EClassId {
  self.add({ op: Uextend(from_bits, to_bits), children: [operand] })
}

///|
/// Add a signed extend node with type info
pub fn EGraph::add_sextend(
  self : EGraph,
  operand : EClassId,
  from_bits? : Int = 32,
  to_bits? : Int = 64,
) -> EClassId {
  self.add({ op: Sextend(from_bits, to_bits), children: [operand] })
}

// ============================================================================
// Floating point helper constructors
// ============================================================================

///|
/// Add a float constant node (bits stored as UInt64)
pub fn EGraph::add_fconst(self : EGraph, bits : UInt64) -> EClassId {
  self.add({ op: Fconst(bits), children: [] })
}

///|
/// Add a float add node
pub fn EGraph::add_fadd(
  self : EGraph,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fadd, children: [left, right] })
}

///|
/// Add a float subtract node
pub fn EGraph::add_fsub(
  self : EGraph,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fsub, children: [left, right] })
}

///|
/// Add a float multiply node
pub fn EGraph::add_fmul(
  self : EGraph,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fmul, children: [left, right] })
}

///|
/// Add a float divide node
pub fn EGraph::add_fdiv(
  self : EGraph,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fdiv, children: [left, right] })
}

///|
/// Add a float min node
pub fn EGraph::add_fmin(
  self : EGraph,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fmin, children: [left, right] })
}

///|
/// Add a float max node
pub fn EGraph::add_fmax(
  self : EGraph,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fmax, children: [left, right] })
}

///|
/// Add a float copysign node
pub fn EGraph::add_fcopysign(
  self : EGraph,
  mag : EClassId,
  sign : EClassId,
) -> EClassId {
  self.add({ op: Fcopysign, children: [mag, sign] })
}

///|
/// Add a float negate node
pub fn EGraph::add_fneg(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fneg, children: [operand] })
}

///|
/// Add a float absolute value node
pub fn EGraph::add_fabs(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fabs, children: [operand] })
}

///|
/// Add a float square root node
pub fn EGraph::add_fsqrt(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fsqrt, children: [operand] })
}

///|
/// Add a float ceiling node
pub fn EGraph::add_fceil(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fceil, children: [operand] })
}

///|
/// Add a float floor node
pub fn EGraph::add_ffloor(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Ffloor, children: [operand] })
}

///|
/// Add a float truncate node
pub fn EGraph::add_ftrunc(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Ftrunc, children: [operand] })
}

///|
/// Add a float round to nearest node
pub fn EGraph::add_fnearest(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fnearest, children: [operand] })
}

///|
/// Add a float compare node
pub fn EGraph::add_fcmp(
  self : EGraph,
  cc : Int,
  left : EClassId,
  right : EClassId,
) -> EClassId {
  self.add({ op: Fcmp(cc), children: [left, right] })
}

///|
/// Add a float promote (f32 -> f64) node
pub fn EGraph::add_fpromote(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fpromote, children: [operand] })
}

///|
/// Add a float demote (f64 -> f32) node
pub fn EGraph::add_fdemote(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: Fdemote, children: [operand] })
}

///|
/// Add a float to signed int conversion node
pub fn EGraph::add_fcvt_to_sint(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: FcvtToSint, children: [operand] })
}

///|
/// Add a float to unsigned int conversion node
pub fn EGraph::add_fcvt_to_uint(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: FcvtToUint, children: [operand] })
}

///|
/// Add a signed int to float conversion node
pub fn EGraph::add_sint_to_fcvt(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: SintToFcvt, children: [operand] })
}

///|
/// Add an unsigned int to float conversion node
pub fn EGraph::add_uint_to_fcvt(self : EGraph, operand : EClassId) -> EClassId {
  self.add({ op: UintToFcvt, children: [operand] })
}

// ============================================================================
// Vector helper constructors
// ============================================================================

///|
/// Add a vector splat node (broadcast scalar to all lanes)
pub fn EGraph::add_splat(self : EGraph, scalar : EClassId) -> EClassId {
  self.add({ op: Splat, children: [scalar] })
}

///|
/// Add a vector constant node
pub fn EGraph::add_vconst(self : EGraph, bits : Bytes) -> EClassId {
  self.add({ op: Vconst(bits), children: [] })
}

// ============================================================================
// Cost model for extraction
// ============================================================================

///|
/// Cost of an e-node (lower is better)
fn node_cost(node : ENode) -> Int {
  match node.op {
    Const(_) => 0 // Constants are free
    Fconst(_) => 0 // Float constants are free
    Var(_) => 0 // Variables are free (already in registers)
    // Simple ALU ops
    Add | Sub => 1
    And | Or | Xor => 1
    Shl | Sshr | Ushr => 1
    Rotl | Rotr => 1
    Neg | Bnot => 1
    // Bit manipulation (usually single instruction)
    Clz | Ctz => 2
    Popcnt => 2
    Bswap => 2
    Bitrev => 3 // Bit reverse is more expensive on some architectures
    // Comparison
    Icmp(_) | Eq | Ne => 1
    // Conditional
    Select => 2
    Bmask => 1
    // Integer min/max (same cost as select - typically implemented with compare+select)
    Smin | Smax | Umin | Umax => 2
    // Integer absolute value
    Iabs => 2
    // Three-way comparison (two compares + subtract)
    SpaceshipS | SpaceshipU => 3
    // Type conversion (integer) - ignore bit width parameters for cost
    Ireduce(_, _) | Uextend(_, _) | Sextend(_, _) => 1
    // Expensive integer ops
    Mul => 3
    Sdiv | Udiv => 10
    Srem | Urem => 10
    // Float arithmetic (similar to integer on modern CPUs)
    Fadd | Fsub => 2
    Fmul => 3
    Fdiv => 10
    Fmin | Fmax => 2
    Fcopysign => 1
    // Float unary
    Fneg | Fabs => 1
    Fsqrt => 15 // Square root is expensive
    Fceil | Ffloor | Ftrunc | Fnearest => 2
    // Float comparison
    Fcmp(_) => 2
    // Float-integer conversion
    Fpromote | Fdemote => 2
    FcvtToSint | FcvtToUint => 3
    SintToFcvt | UintToFcvt => 3
    // Vector ops
    Splat => 2
    Vconst(_) => 0 // Vector constants are free
  }
}

///|
/// Extraction cost uses Cranelift-style ordering:
/// 1) lower op_cost is always better
/// 2) tie-break with shallower depth
/// Arithmetic is saturating and reserves an infinity sentinel.
priv struct ExtractCost {
  op_cost : Int
  depth : Int
  infinite : Bool
}

///|
fn extract_cost_max_finite() -> Int {
  @int.MAX_VALUE - 1
}

///|
const EXTRACT_INFINITY_DEPTH : Int = 255

///|
fn extract_cost_finite(op_cost : Int, depth : Int) -> ExtractCost {
  if op_cost >= extract_cost_max_finite() {
    extract_cost_infinity()
  } else {
    { op_cost, depth, infinite: false }
  }
}

///|
fn extract_cost_infinity() -> ExtractCost {
  {
    op_cost: extract_cost_max_finite(),
    depth: EXTRACT_INFINITY_DEPTH,
    infinite: true,
  }
}

///|
fn extract_cost_is_better(lhs : ExtractCost, rhs : ExtractCost) -> Bool {
  if lhs.infinite {
    false
  } else if rhs.infinite {
    true
  } else if lhs.op_cost < rhs.op_cost {
    true
  } else if lhs.op_cost > rhs.op_cost {
    false
  } else {
    lhs.depth < rhs.depth
  }
}

///|
fn extract_cost_add(lhs : ExtractCost, rhs : ExtractCost) -> ExtractCost {
  if lhs.infinite || rhs.infinite {
    return extract_cost_infinity()
  }
  let max_finite = extract_cost_max_finite()
  let op_cost = if lhs.op_cost > max_finite - rhs.op_cost {
    return extract_cost_infinity()
  } else {
    lhs.op_cost + rhs.op_cost
  }
  let depth = if lhs.depth >= rhs.depth { lhs.depth } else { rhs.depth }
  extract_cost_finite(op_cost, depth)
}

///|
fn extract_cost_increment_depth(cost : ExtractCost) -> ExtractCost {
  if cost.infinite {
    return cost
  }
  let depth = if cost.depth >= EXTRACT_INFINITY_DEPTH {
    EXTRACT_INFINITY_DEPTH
  } else {
    cost.depth + 1
  }
  extract_cost_finite(cost.op_cost, depth)
}

///|
fn extract_cost_equal(lhs : ExtractCost, rhs : ExtractCost) -> Bool {
  lhs.infinite == rhs.infinite &&
  lhs.op_cost == rhs.op_cost &&
  lhs.depth == rhs.depth
}

///|
fn extract_node_tiebreak_less(lhs : ENode, rhs : ENode) -> Bool {
  lhs.compare(rhs) < 0
}

///|
fn extract_cost_apply_bonus(cost : ExtractCost, bonus : Int) -> ExtractCost {
  if cost.infinite || bonus == 0 {
    return cost
  }
  let max_finite = extract_cost_max_finite()
  if bonus > 0 {
    let op_cost = if cost.op_cost > max_finite - bonus {
      max_finite
    } else {
      cost.op_cost + bonus
    }
    extract_cost_finite(op_cost, cost.depth)
  } else {
    let bonus_abs = 0 - bonus
    let op_cost = if cost.op_cost <= bonus_abs {
      0
    } else {
      cost.op_cost - bonus_abs
    }
    extract_cost_finite(op_cost, cost.depth)
  }
}

///|
/// Extract the best (lowest cost) expression from an e-class
/// Returns the total cost and the best e-node
///
/// Costs are computed with a bottom-up fixpoint over the whole e-graph
/// (egg-style relaxation) rather than a memoized DFS: a DFS that prices
/// re-entered classes as infinite while an ancestor is on the stack can
/// memoize that context-dependent infinity and poison later queries that
/// reach the class through a cycle-free route. The fixpoint has no
/// evaluation context, so every class settles to its true best cost.
pub fn EGraph::extract(self : EGraph, id : EClassId) -> (Int, ENode) {
  let canonical = self.find(id)
  let table = self.compute_extraction_table()
  match table.get(canonical.0) {
    Some((cost, node)) =>
      if cost.infinite {
        (@int.MAX_VALUE, node)
      } else {
        (cost.op_cost, node)
      }
    // No finite extraction exists (every node participates in a cycle).
    None => (@int.MAX_VALUE, { op: Var(-1), children: [] })
  }
}

///|
/// Best node per class root, computed once for the whole e-graph.
///
/// Elaboration needs every class's chosen node, not one class's, so it pays
/// for the shared fixpoint once instead of re-running extraction per value.
/// Classes with no finite extraction (every node cyclic) are absent.
pub fn EGraph::best_nodes(self : EGraph) -> Map[Int, ENode] {
  let best : Map[Int, ENode] = Map([])
  for class_id, entry in self.compute_extraction_table() {
    let (_, node) = entry
    best.set(class_id, node)
  }
  best
}

///|
/// Relax per-class best costs to a fixpoint. A node becomes priceable once
/// all of its children have finite entries; each update either strictly
/// lowers a class's (op_cost, depth) or moves to a tie-break-smaller node
/// at equal cost, so the loop terminates and the result is independent of
/// visit order.
fn EGraph::compute_extraction_table(
  self : EGraph,
) -> Map[Int, (ExtractCost, ENode)] {
  let table : Map[Int, (ExtractCost, ENode)] = Map([])
  let mut changed = true
  while changed {
    changed = false
    for class_id, eclass in self.classes {
      for node in eclass.nodes {
        let mut total_cost = extract_cost_finite(node_cost(node), 0)
        let mut priceable = true
        for child in node.children {
          let child_root = self.find(child).0
          match table.get(child_root) {
            Some((child_cost, _)) =>
              total_cost = extract_cost_add(total_cost, child_cost)
            None => {
              priceable = false
              break
            }
          }
        }
        if !priceable {
          continue
        }
        total_cost = extract_cost_apply_bonus(
          total_cost,
          self.remat_cost_bonus(EClassId(class_id)),
        )
        total_cost = extract_cost_increment_depth(total_cost)
        match table.get(class_id) {
          Some((best_cost, best_node)) =>
            if extract_cost_is_better(total_cost, best_cost) ||
              (
                extract_cost_equal(total_cost, best_cost) &&
                extract_node_tiebreak_less(node, best_node)
              ) {
              table.set(class_id, (total_cost, node))
              changed = true
            }
          None => {
            table.set(class_id, (total_cost, node))
            changed = true
          }
        }
      }
    }
  }
  table
}

// ============================================================================
// Rewrite rules
// ============================================================================

///|
/// Saturation bounds (Cranelift-style):
/// - matches_limit: max successful rewrites to keep per class per pass
/// - eclass_enode_limit: max eclass node budget before skipping further rewrites
pub struct SaturationLimits {
  matches_limit : Int
  eclass_enode_limit : Int
} derive(Debug)

///|
pub fn SaturationLimits::SaturationLimits(
  matches_limit : Int,
  eclass_enode_limit : Int,
) -> SaturationLimits {
  { matches_limit, eclass_enode_limit }
}

///|
pub fn SaturationLimits::cranelift_default() -> SaturationLimits {
  // Cranelift uses small hard caps for predictability.
  { matches_limit: 5, eclass_enode_limit: 5 }
}

///|
pub fn SaturationLimits::matches_limit(self : SaturationLimits) -> Int {
  self.matches_limit
}

///|
pub fn SaturationLimits::eclass_enode_limit(self : SaturationLimits) -> Int {
  self.eclass_enode_limit
}

///|
/// A rewrite rule matches a pattern and produces equivalent expressions
priv struct RewriteRule {
  apply : (EGraph, EClassId) -> Bool // Returns true if any changes were made
}

///|
/// An indexed rule with its RewriteRule
priv struct IndexedRule {
  rule : RewriteRule
}

///|
/// An indexed rule set for efficient rule application
struct IndexedRuleSet {
  // Rules indexed by the opcode they match
  by_opcode : Map[EOpcodeTag, Array[IndexedRule]]
  // Rules that match any opcode (e.g., constant folding)
  universal : Array[IndexedRule]
}

///|
fn IndexedRuleSet::IndexedRuleSet() -> IndexedRuleSet {
  { by_opcode: Map([]), universal: [] }
}

///|
/// Add a rule that matches specific opcodes
fn IndexedRuleSet::add_rule(
  self : IndexedRuleSet,
  rule : RewriteRule,
  tags : Array[EOpcodeTag],
) -> Unit {
  let indexed = { rule, }
  if tags.is_empty() {
    self.universal.push(indexed)
  } else {
    for tag in tags {
      match self.by_opcode.get(tag) {
        Some(rules) => rules.push(indexed)
        None => self.by_opcode.set(tag, [indexed])
      }
    }
  }
}

///|
/// Apply rules using opcode index for efficiency
pub fn EGraph::saturate_indexed(
  self : EGraph,
  ruleset : IndexedRuleSet,
  max_iterations : Int,
) -> Int {
  self.saturate_indexed_with_limits(
    ruleset,
    max_iterations,
    SaturationLimits::cranelift_default(),
  )
}

///|
/// Apply rules using opcode index for efficiency with explicit rewrite caps.
pub fn EGraph::saturate_indexed_with_limits(
  self : EGraph,
  ruleset : IndexedRuleSet,
  max_iterations : Int,
  limits : SaturationLimits,
) -> Int {
  self.last_rule_applications = 0
  self.last_matches_limit_hits = 0
  self.last_eclass_size_limit_hits = 0
  if max_iterations <= 0 {
    return 0
  }
  let mut iters = 0
  while iters < max_iterations {
    let (changed, applied) = self.apply_indexed_rules_once(ruleset, limits)
    self.last_rule_applications = self.last_rule_applications + applied
    iters = iters + 1
    if !changed {
      break
    }
  }
  iters
}

///|
/// Apply the indexed ruleset once over the current e-graph snapshot.
/// Returns true if any rule reported changes.
fn EGraph::apply_indexed_rules_once(
  self : EGraph,
  ruleset : IndexedRuleSet,
  limits : SaturationLimits,
) -> (Bool, Int) {
  let mut changed = false
  let mut applied = 0

  // Snapshot the current class ids in deterministic order.
  let uf_len = self.uf.parent.length()
  let ids : Array[EClassId] = []
  let mut i = 0
  while i < uf_len {
    if self.classes.get(i) is Some(_) {
      ids.push(EClassId(i))
    }
    i = i + 1
  }
  for id in ids {
    let canonical = self.find(id).0
    guard self.classes.get(canonical) is Some(_) else { continue }
    let class_id = EClassId(canonical)
    let nodes = self.get_nodes(class_id)
    guard !nodes.is_empty() else { continue }
    if limits.eclass_enode_limit <= 0 ||
      nodes.length() >= limits.eclass_enode_limit {
      self.last_eclass_size_limit_hits = self.last_eclass_size_limit_hits + 1
      continue
    }
    if limits.matches_limit <= 0 {
      self.last_matches_limit_hits = self.last_matches_limit_hits + 1
      continue
    }
    let mut class_matches = 0
    let mut class_capped = false

    // Apply opcode-indexed rules for any opcode present in the class.
    let tags : Array[EOpcodeTag] = []
    for node in nodes {
      let tag = node.op.tag()
      let mut exists = false
      for t in tags {
        if t == tag {
          exists = true
          break
        }
      }
      if !exists {
        tags.push(tag)
      }
    }
    for tag in tags {
      if class_capped {
        break
      }
      if ruleset.by_opcode.get(tag) is Some(rules) {
        for indexed_rule in rules {
          if class_matches >= limits.matches_limit {
            self.last_matches_limit_hits = self.last_matches_limit_hits + 1
            class_capped = true
            break
          }
          if (indexed_rule.rule.apply)(self, class_id) {
            changed = true
            applied = applied + 1
            class_matches = class_matches + 1
            let current_nodes = self.get_nodes(class_id).length()
            if current_nodes >= limits.eclass_enode_limit {
              self.last_eclass_size_limit_hits = self.last_eclass_size_limit_hits +
                1
              class_capped = true
              break
            }
          }
        }
      }
    }
    if class_capped {
      continue
    }
    for indexed_rule in ruleset.universal {
      if class_matches >= limits.matches_limit {
        self.last_matches_limit_hits = self.last_matches_limit_hits + 1
        break
      }
      if (indexed_rule.rule.apply)(self, class_id) {
        changed = true
        applied = applied + 1
        class_matches = class_matches + 1
        let current_nodes = self.get_nodes(class_id).length()
        if current_nodes >= limits.eclass_enode_limit {
          self.last_eclass_size_limit_hits = self.last_eclass_size_limit_hits +
            1
          break
        }
      }
    }
  }
  if changed {
    self.rebuild()
  }
  (changed, applied)
}
