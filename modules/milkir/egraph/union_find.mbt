// Union-find over e-class ids, and the e-class record it groups.
//
// Split out because it is the one piece with no e-graph knowledge at all:
// it merges integers and nothing else. `EGraph` in `egraph.mbt` owns an
// instance and layers congruence on top.

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
