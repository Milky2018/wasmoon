///|
test "dense live-set reads retain missing-word and negative-id behavior" {
  let set = SparseVRegSet::dense(65)
  set.set(0, true)
  set.set(64, true)
  inspect(set.word(-1), content="0")
  inspect(set.word(0), content="1")
  inspect(set.word(1), content="1")
  inspect(set.word(2), content="0")
  inspect(set.contains(-1), content="false")
  inspect(set.contains(128), content="false")
}
