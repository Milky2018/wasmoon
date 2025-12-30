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
/// Simplified from IR Opcode to focus on optimizable operations
pub(all) enum EOpcode {
  // Constants
  Const(Int64)

  // Integer arithmetic (binary)
  Add
  Sub
  Mul
  Sdiv
  Udiv
  Srem
  Urem

  // Bitwise operations
  And
  Or
  Xor
  Shl
  Sshr
  Ushr

  // Unary
  Neg // Represented as 0 - x or -1 * x in IR, but useful for patterns
  Bnot // Bitwise NOT (~x)

  // Comparison placeholder (simplified - just track the condition code as int)
  Cmp(Int) // Stores IntCC ordinal

  // Variable reference (leaf node representing an IR value)
  Var(Int) // IR Value id
} derive(Eq, Hash, Show)

///|
/// E-opcode tag for indexing (ignores parameters like Const value)
pub(all) enum EOpcodeTag {
  TConst
  TAdd
  TSub
  TMul
  TSdiv
  TUdiv
  TSrem
  TUrem
  TAnd
  TOr
  TXor
  TShl
  TSshr
  TUshr
  TNeg
  TBnot
  TCmp
  TVar
} derive(Eq, Hash, Show)

///|
/// Get the tag of an opcode (for indexing)
fn EOpcode::tag(self : EOpcode) -> EOpcodeTag {
  match self {
    Const(_) => TConst
    Add => TAdd
    Sub => TSub
    Mul => TMul
    Sdiv => TSdiv
    Udiv => TUdiv
    Srem => TSrem
    Urem => TUrem
    And => TAnd
    Or => TOr
    Xor => TXor
    Shl => TShl
    Sshr => TSshr
    Ushr => TUshr
    Neg => TNeg
    Bnot => TBnot
    Cmp(_) => TCmp
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
struct EClass {
  id : EClassId
  mut nodes : Array[ENode] // All equivalent nodes in this class
  // For extraction: best node and its cost (lazily computed)
  mut best_node : ENode?
  mut best_cost : Int
}

///|
/// Union-Find data structure for e-class merging
struct UnionFind {
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

///|
/// The main E-graph data structure
pub(all) struct EGraph {
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
pub fn EGraph::add(self : EGraph, node : ENode) -> EClassId {
  // Canonicalize the node first
  let node = self.canonicalize(node)

  // Check if this node already exists (hash-consing)
  if self.hashcons.get(node) is Some(existing_id) {
    return self.find(existing_id)
  }

  // Create a new e-class
  let id = self.uf.make_set()
  let class_id = EClassId(id)
  let eclass : EClass = {
    id: class_id,
    nodes: [node],
    best_node: None,
    best_cost: @int.max_value,
  }
  self.classes.set(id, eclass)
  self.hashcons.set(node, class_id)
  // Update opcode index
  self.index_add(node.op.tag(), id)
  class_id
}

///|
/// Add an e-node and eagerly apply applicable rules
/// This is more efficient than iterating to fixpoint when rules are directional
/// (i.e., RHS cost >= LHS cost, so rules only simplify)
pub fn EGraph::add_eager(
  self : EGraph,
  node : ENode,
  ruleset : IndexedRuleSet,
) -> EClassId {
  let class_id = self.add(node)
  // Apply applicable rules immediately
  let tag = node.op.tag()
  if ruleset.by_opcode.get(tag) is Some(rules) {
    for indexed_rule in rules {
      (indexed_rule.rule.apply)(self, class_id) |> ignore
    }
  }
  // Also apply universal rules
  for indexed_rule in ruleset.universal {
    (indexed_rule.rule.apply)(self, class_id) |> ignore
  }
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

  // Union in the union-find
  let new_root = self.uf.union(a.0, b.0)
  let new_id = EClassId(new_root)
  let other_id = if new_root == a.0 { b } else { a }

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

  // Process all nodes in all classes to re-canonicalize
  // This is a simplified rebuild - production e-graphs use more efficient algorithms
  let new_hashcons : Map[ENode, EClassId] = {}
  for class_id, eclass in self.classes {
    let canonical_id = self.find(EClassId(class_id))
    let new_nodes : Array[ENode] = []
    for node in eclass.nodes {
      let canonical_node = self.canonicalize(node)

      // Check if this canonical node already exists in another class
      if new_hashcons.get(canonical_node) is Some(existing_id) {
        let existing_canonical = self.find(existing_id)
        if existing_canonical != canonical_id {
          // Need to merge these classes
          self.uf.union(canonical_id.0, existing_canonical.0) |> ignore
        }
      } else {
        new_nodes.push(canonical_node)
        new_hashcons.set(canonical_node, canonical_id)
      }
    }
    eclass.nodes = new_nodes
  }
  self.hashcons = new_hashcons
  self.worklist = []
  self.dirty = false
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

// ============================================================================
// Cost model for extraction
// ============================================================================

///|
/// Cost of an e-node (lower is better)
fn node_cost(node : ENode) -> Int {
  match node.op {
    Const(_) => 0 // Constants are free
    Var(_) => 0 // Variables are free (already in registers)
    Add | Sub => 1 // Simple ALU ops
    And | Or | Xor => 1
    Shl | Sshr | Ushr => 1 // Shifts are cheap
    Mul => 3 // Multiplication is more expensive
    Sdiv | Udiv => 10 // Division is very expensive
    Srem | Urem => 10
    Neg => 1
    Bnot => 1
    Cmp(_) => 1
  }
}

///|
/// Extract the best (lowest cost) expression from an e-class
/// Returns the total cost and the best e-node
pub fn EGraph::extract(self : EGraph, id : EClassId) -> (Int, ENode) {
  // Use memoization to avoid recomputing
  let memo : Map[Int, (Int, ENode)] = {}
  self.extract_impl(id, memo)
}

///|
fn EGraph::extract_impl(
  self : EGraph,
  id : EClassId,
  memo : Map[Int, (Int, ENode)],
) -> (Int, ENode) {
  let canonical = self.find(id)

  // Check memo
  if memo.get(canonical.0) is Some(result) {
    return result
  }

  // Get all nodes in this class
  let nodes = self.get_nodes(canonical)
  if nodes.is_empty() {
    // Should not happen in a well-formed e-graph
    return (@int.max_value, { op: Const(0L), children: [] })
  }

  // Find the lowest cost node
  let mut best_cost = @int.max_value
  let mut best_node = nodes[0]
  for node in nodes {
    // Compute cost: node cost + sum of children costs
    let mut total_cost = node_cost(node)
    for child in node.children {
      let (child_cost, _) = self.extract_impl(child, memo)
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
  let result = (best_cost, best_node)
  memo.set(canonical.0, result)
  result
}

// ============================================================================
// Rewrite rules
// ============================================================================

///|
/// A rewrite rule matches a pattern and produces equivalent expressions
pub(all) struct RewriteRule {
  name : String
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
struct IndexedRule {
  rule : RewriteRule
}

///|
/// An indexed rule set for efficient rule application
pub(all) struct IndexedRuleSet {
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
