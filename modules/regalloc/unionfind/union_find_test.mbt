///|
test "directional union find preserves groups and target representatives" {
  let uf = @unionfind.UnionFind::UnionFind(5)
  fn roots() -> Array[Int32] {
    Array::makei(5, i => uf.find(i))
  }
  debug_inspect(roots(), content="[0, 1, 2, 3, 4]")
  inspect(Set(roots()).length(), content="5")
  inspect(uf.union_into(0, 1), content="true")
  inspect(uf.union_into(1, 2), content="true")
  inspect(uf.union_into(0, 2), content="false")
  inspect(uf.find(0) == uf.find(2), content="true")
  inspect(uf.find(0) == uf.find(3), content="false")
  debug_inspect(
    Array::makei(5, i => i).filter(i => uf.find(i) == uf.find(0)),
    content="[0, 1, 2]",
  )
  inspect(Set(roots()).length(), content="3")
  inspect(uf.find(0), content="2")
}
