///|
test "dominator walk retains recursive child and scope exit order" {
  let events : Array[Int32] = []
  @milkir.visit_dominator_tree(
    [[1, 2], [], [3, 4], [], []],
    0,
    block => {
      events.push(block)
      (block, block != 3)
    },
    block => events.push(-block - 1),
  )
  debug_inspect(events, content="[0, 1, -2, 2, 3, -4, 4, -5, -3, -1]")
}

///|
test "joint dominance construction retains independent child lists" {
  let cfg = @milkir.CFG::build(build_public_diamond())
  let (dominance, tree) = cfg.compute_dominance_and_tree()
  let reference = cfg.compute_dominance()
  debug_inspect(tree, content="[[1, 2, 3], [], [], []]")
  debug_inspect(dominance.idom, content="[0, 0, 0, 0]")
  for dominator in -1..<=4 {
    for block in -1..<=4 {
      assert_eq(
        dominance.dominates(dominator, block),
        reference.dominates(dominator, block),
      )
    }
  }
  tree[0].clear()
  dominance.idom[1] = -1
  assert_true(dominance.dominates(0, 1))
  assert_true(reference.dominates(0, 1))
  debug_inspect(reference.idom, content="[0, 0, 0, 0]")
}
