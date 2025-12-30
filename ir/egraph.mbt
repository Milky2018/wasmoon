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
    val = val >> 1
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
                    Some(lhs << rhs.to_int())
                  } else {
                    None
                  }
                Sshr =>
                  if rhs >= 0L && rhs < 64L {
                    Some(lhs >> rhs.to_int())
                  } else {
                    None
                  }
                Ushr => {
                  let lhs = lhs.reinterpret_as_uint64()
                  if rhs >= 0L && rhs < 64L {
                    Some((lhs >> rhs.to_int()).reinterpret_as_int64())
                  } else {
                    None
                  }
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

// ============================================================================
// Commutativity rules
// ============================================================================

///|
/// x + y = y + x (commutativity of addition)
fn rule_add_comm() -> RewriteRule {
  {
    name: "add_comm",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          let swapped = eg.add_add(node.children[1], node.children[0])
          let new_id = eg.merge(class_id, swapped)
          changed = new_id != class_id || changed
        }
      }
      changed
    },
  }
}

///|
/// x * y = y * x (commutativity of multiplication)
fn rule_mul_comm() -> RewriteRule {
  {
    name: "mul_comm",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          let swapped = eg.add_mul(node.children[1], node.children[0])
          let new_id = eg.merge(class_id, swapped)
          changed = new_id != class_id || changed
        }
      }
      changed
    },
  }
}

///|
/// x & y = y & x (commutativity of and)
fn rule_and_comm() -> RewriteRule {
  {
    name: "and_comm",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          let swapped = eg.add_and(node.children[1], node.children[0])
          let new_id = eg.merge(class_id, swapped)
          changed = new_id != class_id || changed
        }
      }
      changed
    },
  }
}

///|
/// x | y = y | x (commutativity of or)
fn rule_or_comm() -> RewriteRule {
  {
    name: "or_comm",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          let swapped = eg.add_or(node.children[1], node.children[0])
          let new_id = eg.merge(class_id, swapped)
          changed = new_id != class_id || changed
        }
      }
      changed
    },
  }
}

///|
/// x ^ y = y ^ x (commutativity of xor)
fn rule_xor_comm() -> RewriteRule {
  {
    name: "xor_comm",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          let swapped = eg.add_xor(node.children[1], node.children[0])
          let new_id = eg.merge(class_id, swapped)
          changed = new_id != class_id || changed
        }
      }
      changed
    },
  }
}

// ============================================================================
// Bitwise identity rules
// ============================================================================

///|
/// x & 0 = 0
fn rule_and_zero() -> RewriteRule {
  {
    name: "and_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(0L) ||
            eg.find_const(node.children[1]) is Some(0L) {
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
/// x | 0 = x
fn rule_or_zero() -> RewriteRule {
  {
    name: "or_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(0L) {
            let new_id = eg.merge(class_id, node.children[0])
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(0L) {
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
/// x ^ 0 = x
fn rule_xor_zero() -> RewriteRule {
  {
    name: "xor_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Xor && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(0L) {
            let new_id = eg.merge(class_id, node.children[0])
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(0L) {
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
/// x & -1 = x (all bits set)
fn rule_and_all_ones() -> RewriteRule {
  {
    name: "and_all_ones",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is And && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(-1L) {
            let new_id = eg.merge(class_id, node.children[0])
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(-1L) {
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
/// x | -1 = -1
fn rule_or_all_ones() -> RewriteRule {
  {
    name: "or_all_ones",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Or && node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(-1L) ||
            eg.find_const(node.children[1]) is Some(-1L) {
            let all_ones = eg.add_const(-1L)
            let new_id = eg.merge(class_id, all_ones)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

// ============================================================================
// More strength reduction rules
// ============================================================================

///|
/// x / 2^n = x >> n (for unsigned, or when x >= 0)
/// Note: This is only valid for unsigned division
fn rule_udiv_pow2() -> RewriteRule {
  {
    name: "udiv_pow2",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Udiv && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c) {
            if log2_if_pow2(c) is Some(shift) {
              let shift_const = eg.add_const(shift.to_int64())
              let new_node = eg.add_binop(Ushr, node.children[0], shift_const)
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
/// x % 2^n = x & (2^n - 1) (for unsigned)
fn rule_urem_pow2() -> RewriteRule {
  {
    name: "urem_pow2",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Urem && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c) {
            if log2_if_pow2(c) is Some(_) {
              let mask = eg.add_const(c - 1L)
              let new_node = eg.add_and(node.children[0], mask)
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
/// x * 3 = (x << 1) + x
fn rule_mul_3() -> RewriteRule {
  {
    name: "mul_3",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(3L) {
            let one = eg.add_const(1L)
            let shifted = eg.add_shl(node.children[0], one)
            let new_node = eg.add_add(shifted, node.children[0])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(3L) {
            let one = eg.add_const(1L)
            let shifted = eg.add_shl(node.children[1], one)
            let new_node = eg.add_add(shifted, node.children[1])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x * 5 = (x << 2) + x
fn rule_mul_5() -> RewriteRule {
  {
    name: "mul_5",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(5L) {
            let two = eg.add_const(2L)
            let shifted = eg.add_shl(node.children[0], two)
            let new_node = eg.add_add(shifted, node.children[0])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(5L) {
            let two = eg.add_const(2L)
            let shifted = eg.add_shl(node.children[1], two)
            let new_node = eg.add_add(shifted, node.children[1])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x * 7 = (x << 3) - x
fn rule_mul_7() -> RewriteRule {
  {
    name: "mul_7",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(7L) {
            let three = eg.add_const(3L)
            let shifted = eg.add_shl(node.children[0], three)
            let new_node = eg.add_sub(shifted, node.children[0])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(7L) {
            let three = eg.add_const(3L)
            let shifted = eg.add_shl(node.children[1], three)
            let new_node = eg.add_sub(shifted, node.children[1])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x * 9 = (x << 3) + x
fn rule_mul_9() -> RewriteRule {
  {
    name: "mul_9",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(9L) {
            let three = eg.add_const(3L)
            let shifted = eg.add_shl(node.children[0], three)
            let new_node = eg.add_add(shifted, node.children[0])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          } else if eg.find_const(node.children[0]) is Some(9L) {
            let three = eg.add_const(3L)
            let shifted = eg.add_shl(node.children[1], three)
            let new_node = eg.add_add(shifted, node.children[1])
            let new_id = eg.merge(class_id, new_node)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

// ============================================================================
// Shift rules
// ============================================================================

///|
/// x << 0 = x
fn rule_shl_zero() -> RewriteRule {
  {
    name: "shl_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Shl && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(0L) {
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
/// x >> 0 = x (both arithmetic and logical)
fn rule_shr_zero() -> RewriteRule {
  {
    name: "shr_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Sshr || node.op is Ushr) && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(0L) {
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
/// 0 << x = 0, 0 >> x = 0
fn rule_shift_of_zero() -> RewriteRule {
  {
    name: "shift_of_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if (node.op is Shl || node.op is Sshr || node.op is Ushr) &&
          node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(0L) {
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
/// (x << a) << b = x << (a + b) when a + b < 64
fn rule_shl_shl() -> RewriteRule {
  {
    name: "shl_shl",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Shl && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(b) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Shl && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(a) {
                  let total = a + b
                  if total >= 0L && total < 64L {
                    let total_const = eg.add_const(total)
                    let new_node = eg.add_shl(inner.children[0], total_const)
                    let new_id = eg.merge(class_id, new_node)
                    changed = new_id != class_id || changed
                  }
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

// ============================================================================
// Subtraction rules
// ============================================================================

///|
/// 0 - x = neg(x) - but since we don't have neg yet, create sub(0, x)
/// This helps recognize negation patterns
fn rule_neg_zero() -> RewriteRule {
  {
    name: "neg_zero",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          if eg.find_const(node.children[0]) is Some(0L) {
            // 0 - x is already in canonical form for negation
            // Add the Neg node as equivalent
            let neg_node = eg.add({ op: Neg, children: [node.children[1]] })
            let new_id = eg.merge(class_id, neg_node)
            changed = new_id != class_id || changed
          }
        }
      }
      changed
    },
  }
}

///|
/// x - (0 - y) = x + y
fn rule_sub_neg() -> RewriteRule {
  {
    name: "sub_neg",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          for inner in eg.get_nodes(node.children[1]) {
            if inner.op is Sub && inner.children.length() == 2 {
              if eg.find_const(inner.children[0]) is Some(0L) {
                // x - (0 - y) = x + y
                let new_node = eg.add_add(node.children[0], inner.children[1])
                let new_id = eg.merge(class_id, new_node)
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
/// x + (0 - y) = x - y
fn rule_add_neg() -> RewriteRule {
  {
    name: "add_neg",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Add && node.children.length() == 2 {
          for inner in eg.get_nodes(node.children[1]) {
            if inner.op is Sub && inner.children.length() == 2 {
              if eg.find_const(inner.children[0]) is Some(0L) {
                // x + (0 - y) = x - y
                let new_node = eg.add_sub(node.children[0], inner.children[1])
                let new_id = eg.merge(class_id, new_node)
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

// ============================================================================
// Constant reassociation rules
// ============================================================================

///|
/// (a * c1) * c2 = a * (c1 * c2) - reassociate multiplication constants
fn rule_reassoc_mul_const() -> RewriteRule {
  {
    name: "reassoc_mul_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Mul && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c2) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Mul && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(c1) {
                  // (a * c1) * c2 = a * (c1 * c2)
                  let combined = eg.add_const(c1 * c2)
                  let new_mul = eg.add_mul(inner.children[0], combined)
                  let new_id = eg.merge(class_id, new_mul)
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
/// (a - c1) - c2 = a - (c1 + c2)
fn rule_reassoc_sub_const() -> RewriteRule {
  {
    name: "reassoc_sub_const",
    apply: fn(eg, class_id) {
      let mut changed = false
      for node in eg.get_nodes(class_id) {
        if node.op is Sub && node.children.length() == 2 {
          if eg.find_const(node.children[1]) is Some(c2) {
            for inner in eg.get_nodes(node.children[0]) {
              if inner.op is Sub && inner.children.length() == 2 {
                if eg.find_const(inner.children[1]) is Some(c1) {
                  // (a - c1) - c2 = a - (c1 + c2)
                  let combined = eg.add_const(c1 + c2)
                  let new_sub = eg.add_sub(inner.children[0], combined)
                  let new_id = eg.merge(class_id, new_sub)
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
    // Identity rules
    rule_add_zero(),
    rule_sub_zero(),
    rule_mul_one(),
    rule_mul_zero(),
    rule_idempotent(),
    rule_xor_self(),
    rule_sub_self(),
    // Bitwise identity
    rule_and_zero(),
    rule_or_zero(),
    rule_xor_zero(),
    rule_and_all_ones(),
    rule_or_all_ones(),
    // Shift identity
    rule_shl_zero(),
    rule_shr_zero(),
    rule_shift_of_zero(),
    rule_shl_shl(),
    // Strength reduction
    rule_mul_pow2(),
    rule_double(),
    rule_udiv_pow2(),
    rule_urem_pow2(),
    rule_mul_3(),
    rule_mul_5(),
    rule_mul_7(),
    rule_mul_9(),
    // Negation patterns
    rule_neg_zero(),
    rule_sub_neg(),
    rule_add_neg(),
    // Constant folding and reassociation
    rule_const_fold(),
    rule_reassoc_add_const(),
    rule_reassoc_mul_const(),
    rule_reassoc_sub_const(),
    // Commutativity (put last as they can cause explosion)
    rule_add_comm(),
    rule_mul_comm(),
    rule_and_comm(),
    rule_or_comm(),
    rule_xor_comm(),
  ]
}

// ============================================================================
// IR Integration - Convert IR instructions to/from EGraph
// ============================================================================

///|
/// Builder for constructing an EGraph from IR instructions
pub(all) struct EGraphBuilder {
  egraph : EGraph
  // Map from IR Value id to EClassId
  value_map : Map[Int, EClassId]
  // Map from IR Value id to its defining instruction
  def_map : Map[Int, Inst]
}

///|
pub fn EGraphBuilder::new() -> EGraphBuilder {
  { egraph: EGraph::new(), value_map: {}, def_map: {} }
}

///|
/// Register an instruction's definition
pub fn EGraphBuilder::register_def(self : EGraphBuilder, inst : Inst) -> Unit {
  match inst.result {
    Some(v) => self.def_map.set(v.id, inst)
    None => ()
  }
}

///|
/// Convert IntCC to an ordinal value
fn intcc_to_ordinal(cc : IntCC) -> Int {
  match cc {
    Eq => 0
    Ne => 1
    Slt => 2
    Sle => 3
    Sgt => 4
    Sge => 5
    Ult => 6
    Ule => 7
    Ugt => 8
    Uge => 9
  }
}

///|
/// Convert an IR Opcode to an EOpcode (if optimizable)
fn opcode_to_eopcode(opcode : Opcode) -> EOpcode? {
  match opcode {
    Iconst(c) => Some(Const(c))
    Iadd => Some(Add)
    Isub => Some(Sub)
    Imul => Some(Mul)
    Sdiv => Some(Sdiv)
    Udiv => Some(Udiv)
    Srem => Some(Srem)
    Urem => Some(Urem)
    Band => Some(And)
    Bor => Some(Or)
    Bxor => Some(Xor)
    Ishl => Some(Shl)
    Sshr => Some(Sshr)
    Ushr => Some(Ushr)
    Icmp(cc) => Some(Cmp(intcc_to_ordinal(cc)))
    _ => None // Not optimizable via e-graph
  }
}

///|
/// Add an IR value to the e-graph, recursively adding its definition
pub fn EGraphBuilder::add_value(
  self : EGraphBuilder,
  value : Value,
) -> EClassId {
  // Check if already converted
  match self.value_map.get(value.id) {
    Some(id) => return id
    None => ()
  }

  // Look up the defining instruction
  let class_id = match self.def_map.get(value.id) {
    None =>
      // No definition found - treat as a variable (parameter or external)
      self.egraph.add_var(value.id)
    Some(inst) =>
      // Try to convert the opcode
      match opcode_to_eopcode(inst.opcode) {
        None =>
          // Not an optimizable opcode - treat as variable
          self.egraph.add_var(value.id)
        Some(eop) =>
          match eop {
            Const(c) => self.egraph.add_const(c)
            _ => {
              // Recursively add operands
              let children : Array[EClassId] = []
              for operand in inst.operands {
                children.push(self.add_value(operand))
              }
              // Add the node to e-graph
              self.egraph.add({ op: eop, children })
            }
          }
      }
  }
  self.value_map.set(value.id, class_id)
  class_id
}

///|
/// Run optimization on the e-graph
pub fn EGraphBuilder::optimize(self : EGraphBuilder) -> Unit {
  self.egraph.saturate(standard_rules(), 10) |> ignore
}

///|
/// Get the optimized e-graph
pub fn EGraphBuilder::get_egraph(self : EGraphBuilder) -> EGraph {
  self.egraph
}

///|
/// Extract the best expression for a given IR value
pub fn EGraphBuilder::extract(
  self : EGraphBuilder,
  value : Value,
) -> (Int, ENode)? {
  match self.value_map.get(value.id) {
    Some(class_id) => Some(self.egraph.extract(class_id))
    None => None
  }
}

///|
/// Optimize a single basic block's arithmetic expressions
/// Returns a map from original Value id to optimized ENode
pub fn optimize_block(block : Block) -> Map[Int, (Int, ENode)] {
  let builder = EGraphBuilder::new()

  // First pass: register all definitions
  for inst in block.instructions {
    builder.register_def(inst)
  }

  // Second pass: add all arithmetic values to e-graph
  for inst in block.instructions {
    match inst.result {
      Some(v) =>
        // Only add if it's an optimizable operation
        match opcode_to_eopcode(inst.opcode) {
          Some(_) => builder.add_value(v) |> ignore
          None => ()
        }
      None => ()
    }
  }

  // Run saturation
  builder.optimize()

  // Extract optimized results
  let results : Map[Int, (Int, ENode)] = {}
  for inst in block.instructions {
    match inst.result {
      Some(v) =>
        match builder.extract(v) {
          Some(result) => results.set(v.id, result)
          None => ()
        }
      None => ()
    }
  }
  results
}

///|
/// Convert EOpcode back to IR Opcode
fn eopcode_to_opcode(eop : EOpcode) -> Opcode? {
  match eop {
    Const(c) => Some(Iconst(c))
    Add => Some(Iadd)
    Sub => Some(Isub)
    Mul => Some(Imul)
    Sdiv => Some(Sdiv)
    Udiv => Some(Udiv)
    Srem => Some(Srem)
    Urem => Some(Urem)
    And => Some(Band)
    Or => Some(Bor)
    Xor => Some(Bxor)
    Shl => Some(Ishl)
    Sshr => Some(Sshr)
    Ushr => Some(Ushr)
    Neg => None // Neg is synthetic, not in IR
    Cmp(_) => None // Would need to reconstruct IntCC
    Var(_) => None // Variable reference, not an instruction
  }
}

///|
/// Check if the extracted expression is simpler than the original
/// Returns Some(simplified_opcode) if optimization found, None otherwise
pub fn EGraphBuilder::get_simplified_opcode(
  self : EGraphBuilder,
  value : Value,
) -> Opcode? {
  match self.value_map.get(value.id) {
    None => None
    Some(class_id) => {
      let (_, best_node) = self.egraph.extract(class_id)
      // Check if it's a constant folding result
      match best_node.op {
        Const(c) => Some(Iconst(c))
        _ =>
          // Check if the opcode changed
          match self.def_map.get(value.id) {
            None => None
            Some(orig_inst) => {
              let orig_eop = opcode_to_eopcode(orig_inst.opcode)
              match orig_eop {
                None => None
                Some(orig) =>
                  if orig != best_node.op {
                    eopcode_to_opcode(best_node.op)
                  } else {
                    None
                  }
              }
            }
          }
      }
    }
  }
}

///|
/// Apply e-graph optimization to a function
/// Returns true if any optimization was applied
pub fn optimize_function(func : Function) -> Bool {
  let mut changed = false
  for block in func.blocks {
    let builder = EGraphBuilder::new()

    // Register all definitions in this block
    for inst in block.instructions {
      builder.register_def(inst)
    }

    // Add all values to e-graph
    for inst in block.instructions {
      match inst.result {
        Some(v) =>
          match opcode_to_eopcode(inst.opcode) {
            Some(_) => builder.add_value(v) |> ignore
            None => ()
          }
        None => ()
      }
    }

    // Run saturation
    builder.optimize()

    // Apply optimizations - for now, just constant folding
    for inst in block.instructions {
      match inst.result {
        Some(v) =>
          match builder.get_simplified_opcode(v) {
            Some(Iconst(c)) => {
              // Replace with constant
              inst.opcode = Iconst(c)
              inst.operands.clear()
              changed = true
            }
            Some(_) =>
              // Other optimizations would require operand rewriting
              // For now, skip these
              ()
            None => ()
          }
        None => ()
      }
    }
  }
  changed
}
