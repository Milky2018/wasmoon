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

  // Comparison placeholder (simplified - just track the condition code as int)
  Cmp(Int) // Stores IntCC ordinal

  // Variable reference (leaf node representing an IR value)
  Var(Int) // IR Value id
} derive(Eq, Hash, Show)

///|
/// E-node: an expression node in the e-graph
/// Children are EClassIds, not direct node references
pub(all) struct ENode {
  op : EOpcode
  children : Array[EClassId]
} derive(Eq, Hash, Show)

///|
/// E-class: an equivalence class of e-nodes
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
}

///|
pub fn EGraph::new() -> EGraph {
  {
    uf: UnionFind::new(),
    classes: {},
    hashcons: {},
    worklist: [],
    dirty: false,
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
  class_id
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

// ============================================================================
// Standard rewrite rules
// ============================================================================

///|
/// Helper to check if an e-class contains a specific constant
fn EGraph::find_const(self : EGraph, id : EClassId) -> Int64? {
  for node in self.get_nodes(id) {
    if node.op is Const(v) {
      return Some(v)
    }
  }
  None
}

///|
/// x + 0 = x
fn rule_add_zero() -> RewriteRule {
  {
    name: "add_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          // Check if either child is 0
          if eg.find_const(node.children[1]) is Some(0L) {
            // x + 0 = x
            let new_id = eg.merge(class_id, node.children[0])
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(0L) {
            // 0 + x = x
            let new_id = eg.merge(class_id, node.children[1])
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x - 0 = x
fn rule_sub_zero() -> RewriteRule {
  {
    name: "sub_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(0L) {
            // x - 0 = x
            let new_id = eg.merge(class_id, node.children[0])
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x * 1 = x
fn rule_mul_one() -> RewriteRule {
  {
    name: "mul_one",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(1L) {
            let new_id = eg.merge(class_id, node.children[0])
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(1L) {
            let new_id = eg.merge(class_id, node.children[1])
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x * 0 = 0
fn rule_mul_zero() -> RewriteRule {
  {
    name: "mul_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(0L) ||
            eg.find_const(node.children[0]) is Some(0L) {
            let zero = eg.add_const(0L)
            let new_id = eg.merge(class_id, zero)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x & x = x, x | x = x
fn rule_idempotent() -> RewriteRule {
  {
    name: "idempotent",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is And || node.op is Or) && node.children.length() == 2 {
          if eg.equiv(node.children[0], node.children[1]) {
            let new_id = eg.merge(class_id, node.children[0])
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x ^ x = 0
fn rule_xor_self() -> RewriteRule {
  {
    name: "xor_self",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          if eg.equiv(node.children[0], node.children[1]) {
            let zero = eg.add_const(0L)
            let new_id = eg.merge(class_id, zero)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x - x = 0
fn rule_sub_self() -> RewriteRule {
  {
    name: "sub_self",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          if eg.equiv(node.children[0], node.children[1]) {
            let zero = eg.add_const(0L)
            let new_id = eg.merge(class_id, zero)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// Helper: check if n is a power of 2 and return log2(n)
fn log2_if_pow2(n : Int64) -> Int? {
  if n <= 0L {
    return None
  }
  // Check if n is power of 2: n & (n-1) == 0
  if (n & (n - 1L)) != 0L {
    return None
  }
  // Count trailing zeros to get log2
  let mut count = 0
  let mut val = n
  while (val & 1L) == 0L {
    count = count + 1
    val = val.lsr(1)
  }
  Some(count)
}

///|
/// x * 2^n = x << n (strength reduction)
fn rule_mul_pow2() -> RewriteRule {
  {
    name: "mul_pow2",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          // Check if right operand is power of 2
          if eg.find_const(node.children[1]) is Some(c) {
            if log2_if_pow2(c) is Some(shift) {
              let shift_const = eg.add_const(shift.to_int64())
              let new_node = eg.add_shl(node.children[0], shift_const)
              let new_id = eg.merge(class_id, new_node)
              changed = new_id != class_id || changed
            }
          }
          // Check if left operand is power of 2
          if eg.find_const(node.children[0]) is Some(c) {
            if log2_if_pow2(c) is Some(shift) {
              let shift_const = eg.add_const(shift.to_int64())
              let new_node = eg.add_shl(node.children[1], shift_const)
              let new_id = eg.merge(class_id, new_node)
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
/// x + x = x * 2 = x << 1
fn rule_double() -> RewriteRule {
  {
    name: "double",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          if eg.equiv(node.children[0], node.children[1]) {
            // x + x = x << 1
            let one = eg.add_const(1L)
            let shift = eg.add_shl(node.children[0], one)
            let new_id = eg.merge(class_id, shift)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// Constant folding for binary operations
fn rule_const_fold() -> RewriteRule {
  {
    name: "const_fold",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(lhs) {
            if eg.find_const(node.children[1]) is Some(rhs) {
              let result : Int64? = match node.op {
                Add => Some(lhs + rhs)
                Sub => Some(lhs - rhs)
                Mul => Some(lhs * rhs)
                And => Some(lhs & rhs)
                Or => Some(lhs | rhs)
                Xor => Some(lhs ^ rhs)
                Shl =>
                  if rhs >= 0L && rhs < 64L {
                    Some(lhs.lsl(rhs.to_int()))
                  } else {
                    None
                  }
                Sshr =>
                  if rhs >= 0L && rhs < 64L {
                    Some(lhs.asr(rhs.to_int()))
                  } else {
                    None
                  }
                Ushr =>
                  if rhs >= 0L && rhs < 64L {
                    Some(lhs.lsr(rhs.to_int()))
                  } else {
                    None
                  }
                Sdiv => if rhs != 0L { Some(lhs / rhs) } else { None }
                Udiv =>
                  if rhs != 0L {
                    // For unsigned division, we need to handle this carefully
                    // For now, just use signed division (correct for positive values)
                    Some(lhs / rhs)
                  } else {
                    None
                  }
                _ => None
              }
              if result is Some(r) {
                let result_node = eg.add_const(r)
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
/// (a + c1) + c2 = a + (c1 + c2) - reassociate constants
fn rule_reassoc_add_const() -> RewriteRule {
  {
    name: "reassoc_add_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        // Pattern: (? + c2) where ? is an Add
        if node.op is Add && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c2) {
            // Check if left child is also an Add with a constant
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Add && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(c1) {
                  // (a + c1) + c2 = a + (c1 + c2)
                  let combined = eg.add_const(c1 + c2)
                  let new_add = eg.add_add(inner.children[0], combined)
                  let new_id = eg.merge(class_id, new_add)
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
/// Get all standard rewrite rules
pub fn standard_rules() -> Array[RewriteRule] {
  [
    rule_add_zero(),
    rule_sub_zero(),
    rule_mul_one(),
    rule_mul_zero(),
    rule_idempotent(),
    rule_xor_self(),
    rule_sub_self(),
    rule_mul_pow2(),
    rule_double(),
    rule_const_fold(),
    rule_reassoc_add_const(),
  ]
}
