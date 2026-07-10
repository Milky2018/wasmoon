///|
test "union find groups sets" {
  let uf = UnionFind::UnionFind(5)
  inspect(uf.length(), content="5")
  inspect(uf.num_sets(), content="5")
  inspect(uf.union(0, 1), content="true")
  inspect(uf.union(1, 2), content="true")
  inspect(uf.union(0, 2), content="false")
  inspect(uf.same_set(0, 2), content="true")
  inspect(uf.same_set(0, 3), content="false")
  debug_inspect(uf.get_set(0), content="[0, 1, 2]")
  inspect(uf.num_sets(), content="3")
}
