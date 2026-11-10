// Union-Find (Disjoint Set) Data Structure
// Directional bundle merging with path compression.
// The requested target representative remains the root.

///|
/// Union-Find data structure for grouping LiveRanges into Bundles
struct UnionFind {
  parent : Array[Int32] // Parent pointer (or self if root)
}

///|
/// Create a new UnionFind with n elements (0..n-1)
pub fn UnionFind::UnionFind(n : Int32) -> UnionFind {
  let parent : Array[Int32] = []
  for i in 0..<n {
    parent.push(i) // Each element is its own parent initially
  }
  { parent, }
}

///|
/// Find the root of the set containing x
/// Uses path compression for amortized O(α(n)) time
pub fn UnionFind::find(self : UnionFind, x : Int32) -> Int32 {
  let mut root = x
  while self.parent[root] != root {
    root = self.parent[root]
  }
  let mut current = x
  while self.parent[current] != current {
    let next = self.parent[current]
    self.parent[current] = root
    current = next
  }
  root
}

///|
/// Union the set containing `from` into the set containing `to`.
/// Returns true if a union was performed (sets were different).
pub fn UnionFind::union_into(
  self : UnionFind,
  from : Int32,
  to : Int32,
) -> Bool {
  let from_root = self.find(from)
  let to_root = self.find(to)
  if from_root == to_root {
    return false
  }
  self.parent[from_root] = to_root
  true
}
