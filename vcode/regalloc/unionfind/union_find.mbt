// Union-Find (Disjoint Set) Data Structure
// Used for bundle merging in the Ion-style register allocator.
// Implements path compression and union by rank for efficiency.

///|
/// Union-Find data structure for grouping LiveRanges into Bundles
struct UnionFind {
  parent : Array[Int] // Parent pointer (or self if root)
  rank : Array[Int] // Rank for union by rank heuristic
}

///|
/// Create a new UnionFind with n elements (0..n-1)
pub fn UnionFind::new(n : Int) -> UnionFind {
  let parent : Array[Int] = []
  let rank : Array[Int] = []
  for i in 0..<n {
    parent.push(i) // Each element is its own parent initially
    rank.push(0)
  }
  { parent, rank }
}

///|
/// Find the root of the set containing x
/// Uses path compression for amortized O(α(n)) time
pub fn UnionFind::find(self : UnionFind, x : Int) -> Int {
  if self.parent[x] != x {
    // Path compression: make all nodes on path point to root
    self.parent[x] = self.find(self.parent[x])
  }
  self.parent[x]
}

///|
/// Union the sets containing x and y
/// Uses union by rank for balanced trees
/// Returns true if a union was performed (sets were different)
pub fn UnionFind::union(self : UnionFind, x : Int, y : Int) -> Bool {
  let root_x = self.find(x)
  let root_y = self.find(y)
  if root_x == root_y {
    return false // Already in same set
  }

  // Union by rank: attach smaller tree under larger tree
  if self.rank[root_x] < self.rank[root_y] {
    self.parent[root_x] = root_y
  } else if self.rank[root_x] > self.rank[root_y] {
    self.parent[root_y] = root_x
  } else {
    // Same rank: choose arbitrarily and increment rank
    self.parent[root_y] = root_x
    self.rank[root_x] += 1
  }
  true
}

///|
/// Check if x and y are in the same set
pub fn UnionFind::same_set(self : UnionFind, x : Int, y : Int) -> Bool {
  self.find(x) == self.find(y)
}

///|
/// Get all elements in the same set as x
pub fn UnionFind::get_set(self : UnionFind, x : Int) -> Array[Int] {
  let root = self.find(x)
  let result : Array[Int] = []
  for i in 0..<self.parent.length() {
    if self.find(i) == root {
      result.push(i)
    }
  }
  result
}

///|
/// Get all unique sets (as arrays of their members)
pub fn UnionFind::get_all_sets(self : UnionFind) -> Array[Array[Int]] {
  let sets : Map[Int, Array[Int]] = {}
  for i in 0..<self.parent.length() {
    let root = self.find(i)
    match sets.get(root) {
      Some(arr) => arr.push(i)
      None => sets.set(root, [i])
    }
  }
  let result : Array[Array[Int]] = []
  for entry in sets {
    let (_, members) = entry
    result.push(members)
  }
  result
}

///|
/// Get the number of elements
pub fn UnionFind::length(self : UnionFind) -> Int {
  self.parent.length()
}

///|
/// Count the number of distinct sets
pub fn UnionFind::num_sets(self : UnionFind) -> Int {
  let roots : Set[Int] = Set::new()
  for i in 0..<self.parent.length() {
    roots.add(self.find(i))
  }
  roots.length()
}
