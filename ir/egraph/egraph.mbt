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
pub(all) struct EClassId(Int) derive(Eq, Hash, Show, Compare)

///|
/// E-node opcode for e-graph expressions
/// Aligned with Cranelift IR opcodes for consistent optimization
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
} derive(Eq, Hash, Show)

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
} derive(Eq, Hash, Show)

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
} derive(Eq, Hash, Show)

///|
/// E-class: an equivalence class of e-nodes
#warnings("-unused_field")
priv struct EClass {
  id : EClassId
  mut nodes : Array[ENode] // All equivalent nodes in this class
  // For extraction: best node and its cost (lazily computed)
  mut best_node : ENode?
  mut best_cost : Int
  // Cached constant values for O(1) lookup (instead of O(n) scan)
  mut const_value : Int64?
  mut fconst_value : UInt64?
}

///|
/// Union-Find data structure for e-class merging
priv struct UnionFind {
  // parent[i] = parent of i, or i if i is a root
  parent : Array[Int]
}

///|
fn UnionFind::new() -> UnionFind {
  { parent: [] }
}

///|
fn UnionFind::make_set(self : UnionFind) -> Int {
  let id = self.parent.length()
  self.parent.push(id)
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
fn UnionFind::union(self : UnionFind, a : Int, b : Int) -> Int {
  let root_a = self.find(a)
  let root_b = self.find(b)
  if root_a == root_b {
    return root_a
  }
  // Always make the smaller id the root (deterministic)
  if root_a < root_b {
    self.parent[root_b] = root_a
    root_a
  } else {
    self.parent[root_a] = root_b
    root_b
  }
}

// Cranelift-style limits to prevent infinite rewriting

///|
/// Max nodes per e-class (prevents exponential blowup from commutativity/associativity)
let eclass_node_limit : Int = 5

///|
/// Max recursive rewrite depth (prevents rule application spiraling)
let rewrite_depth_limit : Int = 5

///|
/// Max rewrites per add_eager call
let matches_limit : Int = 5

///|
/// The main E-graph data structure
struct EGraph {
  // Union-find for equivalence classes
  uf : UnionFind
  // All e-classes (indexed by canonical id)
  classes : Map[Int, EClass]
  // Hash-cons map: ENode -> EClassId (for deduplication)
  mut hashcons : Map[ENode, EClassId]
  // Worklist for nodes that need to be re-canonicalized after merges
  mut worklist : Array[EClassId]
  // Dirty flag: true if there are pending merges
  mut dirty : Bool
  // Opcode index: maps opcode tag to set of class ids containing that opcode
  opcode_index : Map[EOpcodeTag, @hashset.HashSet[Int]]
  // Worklist of (class_id, opcode_tag) pairs pending rule application
  mut pending_rules : Array[(EClassId, EOpcodeTag)]
  // Type information: maps canonical class id to bit width (8, 16, 32, 64, 128)
  type_map : Map[Int, Int]
  // Rematerialization set: classes that are cheap to recompute
  remat_set : @hashset.HashSet[Int]
}

///|
pub fn EGraph::new() -> EGraph {
  {
    uf: UnionFind::new(),
    classes: {},
    hashcons: {},
    worklist: [],
    dirty: false,
    opcode_index: {},
    pending_rules: [],
    type_map: {},
    remat_set: @hashset.new(),
  }
}

///|
/// Add a class to the opcode index
fn EGraph::index_add(self : EGraph, tag : EOpcodeTag, class_id : Int) -> Unit {
  match self.opcode_index.get(tag) {
    Some(set) => set.add(class_id)
    None => {
      let set : @hashset.HashSet[Int] = @hashset.new()
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
/// Canonicalize an ENode by finding canonical ids for all children
fn EGraph::canonicalize(self : EGraph, node : ENode) -> ENode {
  let new_children : Array[EClassId] = []
  for child in node.children {
    new_children.push(self.find(child))
  }
  { op: node.op, children: new_children }
}

///|
/// Add an e-node to the e-graph, returning its e-class id
/// If an equivalent node already exists, returns the existing class id
/// New nodes are queued for rule application (processed by add_eager)
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
    id: class_id,
    nodes: [node],
    best_node: None,
    best_cost: @int.max_value,
    const_value: const_val,
    fconst_value: fconst_val,
  }
  self.classes.set(id, eclass)
  self.hashcons.set(node, class_id)
  // Update opcode index
  let tag = node.op.tag()
  self.index_add(tag, id)
  // Queue for rule application (will be processed by add_eager)
  self.pending_rules.push((class_id, tag))
  class_id
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
/// Set the type (bit width) for an equivalence class
pub fn EGraph::set_type(self : EGraph, id : EClassId, bits : Int) -> Unit {
  let canonical = self.find(id).0
  self.type_map.set(canonical, bits)
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
/// Get the minimum signed value for a given bit width
pub fn ty_smin(bits : Int) -> Int64 {
  match bits {
    8 => -128L
    16 => -32768L
    32 => -2147483648L
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
    32 => 2147483647L
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
pub fn EGraph::mark_rematerializable(self : EGraph, id : EClassId) -> Unit {
  let canonical = self.find(id).0
  self.remat_set.add(canonical)
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
/// Add an e-node with type information and eagerly apply applicable rules
pub fn EGraph::add_eager_typed(
  self : EGraph,
  node : ENode,
  bits : Int,
  ruleset : IndexedRuleSet,
) -> EClassId {
  let class_id = self.add_eager(node, ruleset)
  self.set_type(class_id, bits)
  class_id
}

///|
/// Add an e-node and eagerly apply applicable rules
/// Processes all pending nodes (including those created by rules) up to MATCHES_LIMIT
/// This handles chained rewrites like x*8 → x<<3 → further optimizations
pub fn EGraph::add_eager(
  self : EGraph,
  node : ENode,
  ruleset : IndexedRuleSet,
) -> EClassId {
  self.add_eager_with_depth(node, ruleset, 0)
}

///|
/// Add an e-node with depth tracking for recursive rewrites
/// Depth limit prevents rule application from spiraling out of control
fn EGraph::add_eager_with_depth(
  self : EGraph,
  node : ENode,
  ruleset : IndexedRuleSet,
  depth : Int,
) -> EClassId {
  // Check depth limit - if exceeded, just add without rule application
  if depth > rewrite_depth_limit {
    return self.add(node)
  }
  let class_id = self.add(node)
  // Process all pending nodes with rule application
  // Rules may add new nodes which also get processed
  let mut rewrites = 0
  while self.pending_rules.length() > 0 && rewrites < matches_limit {
    let (pending_id, tag) = self.pending_rules.pop().unwrap()
    let canonical_id = self.find(pending_id)
    // Apply rules matching this opcode
    if ruleset.by_opcode.get(tag) is Some(rules) {
      for indexed_rule in rules {
        if (indexed_rule.rule.apply)(self, canonical_id) {
          rewrites = rewrites + 1
        }
      }
    }
    // Apply universal rules
    for indexed_rule in ruleset.universal {
      if (indexed_rule.rule.apply)(self, canonical_id) {
        rewrites = rewrites + 1
      }
    }
  }
  // Clear any remaining pending (hit limit)
  self.pending_rules.clear()
  // Return the (possibly merged) canonical class id
  self.find(class_id)
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

  // Remove nodes from class a that match the pattern being subsumed
  // For simplicity, just redirect a to b without merging nodes
  self.uf.union(a.0, b.0) |> ignore

  // Transfer type information from a to b if b doesn't have it
  if self.type_map.get(b.0) is None {
    if self.type_map.get(a.0) is Some(bits) {
      self.type_map.set(b.0, bits)
    }
  }
  // Remove type entry for the subsumed class
  self.type_map.remove(a.0)

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
  self.dirty = true
  self.worklist.push(b)
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

  // Check combined size limit to prevent exponential blowup
  let size_a = self.classes.get(a.0).map_or(0, fn(c) { c.nodes.length() })
  let size_b = self.classes.get(b.0).map_or(0, fn(c) { c.nodes.length() })
  if size_a + size_b > eclass_node_limit {
    // Don't merge - return the "better" one (lower ID = older = likely simpler)
    return if a.0 < b.0 { a } else { b }
  }

  // Union in the union-find
  let new_root = self.uf.union(a.0, b.0)
  let new_id = EClassId(new_root)
  let other_id = if new_root == a.0 { b } else { a }

  // Merge type information: prefer existing type, or take from other class
  match (self.type_map.get(new_id.0), self.type_map.get(other_id.0)) {
    (None, Some(bits)) => self.type_map.set(new_id.0, bits)
    _ => () // Keep new_id's type or both None
  }
  // Remove old type entry
  self.type_map.remove(other_id.0)

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
      // Add all nodes from other class to root class
      for node in other_class.nodes {
        root_class.nodes.push(node)
      }
      // Invalidate best node cache
      root_class.best_node = None
      root_class.best_cost = @int.max_value
      // Merge constant caches: prefer non-None values
      if root_class.const_value is None && other_class.const_value is Some(_) {
        root_class.const_value = other_class.const_value
      }
      if root_class.fconst_value is None && other_class.fconst_value is Some(_) {
        root_class.fconst_value = other_class.fconst_value
      }
    }
    // Remove the merged class
    self.classes.remove(other_id.0)
  }

  // Mark as dirty - need to rebuild
  self.dirty = true
  self.worklist.push(new_id)
  new_id
}

///|
/// Rebuild the e-graph after merges to restore invariants
/// This re-canonicalizes all nodes and updates the hash-cons map
pub fn EGraph::rebuild(self : EGraph) -> Unit {
  if not(self.dirty) {
    return
  }

  // Iterative rebuild: keep canonicalizing and merging until fixpoint
  // This handles cascading merges where merging A and B causes C and D to collide
  while true {
    // Collect all nodes from all classes
    let all_nodes : Array[(Int, ENode)] = []
    for class_id, eclass in self.classes {
      for node in eclass.nodes {
        all_nodes.push((class_id, node))
      }
    }

    // Canonicalize all nodes and detect collisions
    let new_hashcons : Map[ENode, EClassId] = {}
    let mut had_union = false
    for i in 0..<all_nodes.length() {
      let (class_id, node) = all_nodes[i]
      let canonical_node = self.canonicalize(node)
      let canonical_id = self.find(EClassId(class_id))
      if new_hashcons.get(canonical_node) is Some(existing_id) {
        let existing_canonical = self.find(existing_id)
        if existing_canonical != canonical_id {
          // Merge the classes
          self.uf.union(canonical_id.0, existing_canonical.0) |> ignore
          had_union = true
        }
      } else {
        new_hashcons.set(canonical_node, canonical_id)
      }
    }

    // If no unions happened, we've reached fixpoint
    if not(had_union) {
      // Final pass: collect nodes by canonical class with fully canonical nodes
      let canonical_nodes : Map[Int, Array[ENode]] = {}
      let final_hashcons : Map[ENode, EClassId] = {}
      for i in 0..<all_nodes.length() {
        let (class_id, node) = all_nodes[i]
        let canonical_node = self.canonicalize(node)
        let final_canonical_id = self.find(EClassId(class_id))

        // Add to hashcons
        if final_hashcons.get(canonical_node) is None {
          final_hashcons.set(canonical_node, final_canonical_id)
        }

        // Add to canonical_nodes, avoiding duplicates
        match canonical_nodes.get(final_canonical_id.0) {
          Some(nodes) => {
            let mut found = false
            for existing in nodes {
              if existing == canonical_node {
                found = true
                break
              }
            }
            if not(found) {
              nodes.push(canonical_node)
            }
          }
          None => canonical_nodes.set(final_canonical_id.0, [canonical_node])
        }
      }

      // Update each class with its canonical nodes
      for class_id, eclass in self.classes {
        let canonical_id = self.find(EClassId(class_id))
        if class_id == canonical_id.0 {
          match canonical_nodes.get(class_id) {
            Some(nodes) => eclass.nodes = nodes
            None => eclass.nodes = []
          }
        } else {
          eclass.nodes = []
        }
      }
      self.hashcons = final_hashcons
      self.worklist = []
      self.pending_rules = []
      self.dirty = false
      break
    }
    // Otherwise, continue iterating with updated union-find
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
/// Extract the best (lowest cost) expression from an e-class
/// Returns the total cost and the best e-node
pub fn EGraph::extract(self : EGraph, id : EClassId) -> (Int, ENode) {
  // Use memoization to avoid recomputing
  let memo : Map[Int, (Int, ENode)] = {}
  // Track classes currently being processed to detect cycles
  let in_progress : @hashset.HashSet[Int] = @hashset.new()
  self.extract_impl(id, memo, in_progress)
}

///|
fn EGraph::extract_impl(
  self : EGraph,
  id : EClassId,
  memo : Map[Int, (Int, ENode)],
  in_progress : @hashset.HashSet[Int],
) -> (Int, ENode) {
  let canonical = self.find(id)

  // Check memo
  if memo.get(canonical.0) is Some(result) {
    return result
  }

  // Check for cycle - if we're already processing this class, return high cost
  // but don't return a fake Const(0) - the caller should handle this case
  // by not choosing nodes that lead to cycles
  if in_progress.contains(canonical.0) {
    // Return a sentinel value that indicates "don't use this path"
    // The caller will see the high cost and skip this node
    return (@int.max_value / 2, { op: Var(-1), children: [] })
  }

  // Mark as in progress
  in_progress.add(canonical.0)

  // Get all nodes in this class
  let nodes = self.get_nodes(canonical)
  if nodes.is_empty() {
    // Should not happen in a well-formed e-graph, but handle gracefully
    in_progress.remove(canonical.0)
    // Return a sentinel value
    return (@int.max_value, { op: Var(-1), children: [] })
  }

  // Find the lowest cost node
  let mut best_cost = @int.max_value
  let mut best_node = nodes[0]
  for node in nodes {
    // Skip nodes with cyclic children (child points to current class)
    let mut has_cycle = false
    for child in node.children {
      if self.find(child).0 == canonical.0 {
        has_cycle = true
        break
      }
    }
    if has_cycle {
      continue // Skip this node, try others
    }

    // Compute cost: node cost + sum of children costs
    let mut total_cost = node_cost(node)
    for child in node.children {
      let (child_cost, _) = self.extract_impl(child, memo, in_progress)
      total_cost = total_cost + child_cost
      if total_cost >= best_cost {
        break // Pruning: no need to continue if already worse
      }
    }
    if total_cost < best_cost {
      best_cost = total_cost
      best_node = node
    }
  }

  // Remove from in progress
  in_progress.remove(canonical.0)
  let result = (best_cost, best_node)
  memo.set(canonical.0, result)
  result
}

// ============================================================================
// Rewrite rules
// ============================================================================

///|
/// A rewrite rule matches a pattern and produces equivalent expressions
struct RewriteRule {
  apply : (EGraph, EClassId) -> Bool // Returns true if any changes were made
}

///|
/// Apply all rewrite rules until fixpoint (equality saturation)
pub fn EGraph::saturate(
  self : EGraph,
  rules : Array[RewriteRule],
  max_iterations : Int,
) -> Int {
  let mut iterations = 0
  while iterations < max_iterations {
    let mut changed = false

    // Collect all class ids (snapshot to avoid modification during iteration)
    let class_ids : Array[EClassId] = []
    for class_id, _ in self.classes {
      class_ids.push(EClassId(class_id))
    }

    // Apply each rule to each e-class
    for rule in rules {
      for class_id in class_ids {
        if (rule.apply)(self, class_id) {
          changed = true
        }
      }
    }

    // Rebuild to restore invariants
    self.rebuild()
    iterations = iterations + 1
    if not(changed) {
      break
    }
  }
  iterations
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
fn IndexedRuleSet::new() -> IndexedRuleSet {
  { by_opcode: {}, universal: [] }
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
  let mut iterations = 0
  while iterations < max_iterations {
    let mut changed = false

    // For each opcode tag in the index
    for tag, class_ids in self.opcode_index {
      // Get rules that match this opcode
      if ruleset.by_opcode.get(tag) is Some(rules) {
        // Apply rules to classes with this opcode
        for class_id in class_ids.to_array() {
          let cid = EClassId(class_id)
          for indexed_rule in rules {
            if (indexed_rule.rule.apply)(self, cid) {
              changed = true
            }
          }
        }
      }
    }

    // Apply universal rules to all classes
    if not(ruleset.universal.is_empty()) {
      let class_ids : Array[EClassId] = []
      for class_id, _ in self.classes {
        class_ids.push(EClassId(class_id))
      }
      for indexed_rule in ruleset.universal {
        for class_id in class_ids {
          if (indexed_rule.rule.apply)(self, class_id) {
            changed = true
          }
        }
      }
    }

    // Rebuild to restore invariants
    self.rebuild()
    iterations = iterations + 1
    if not(changed) {
      break
    }
  }
  iterations
}
