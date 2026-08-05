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
