///|
test "rules are dispatched by their actual root opcode" {
  let eg = EGraph::EGraph()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let one = eg.add_const(1L)
  let neg_one = eg.add_const(-1L)

  let sub_one = eg.add_sub(x, one)
  let bnot_sub_one = eg.add_bnot(sub_one)
  let neg_x = eg.add_neg(x)

  let add_neg_one = eg.add_add(y, neg_one)
  let bnot_add_neg_one = eg.add_bnot(add_neg_one)
  let neg_y = eg.add_neg(y)

  let sum = eg.add_add(x, y)
  let either = eg.add_or(x, y)
  let difference = eg.add_sub(sum, either)
  let both = eg.add_and(x, y)

  eg.saturate_indexed(get_global_ruleset(), 10) |> ignore
  inspect(eg.equiv(bnot_sub_one, neg_x), content="true")
  inspect(eg.equiv(bnot_add_neg_one, neg_y), content="true")
  inspect(eg.equiv(difference, both), content="true")
}

///|
test "generated matcher keeps commutative mul-shift rewrites" {
  let eg = EGraph::EGraph()
  let x = eg.add_var(0)
  let one = eg.add_const(1L)
  let three = eg.add_const(3L)
  let six = eg.add_const(6L)
  let shifted = eg.add_shl(x, one)
  let expression = eg.add_mul(three, shifted)
  let expected = eg.add_mul(x, six)

  eg.saturate_indexed(get_global_ruleset(), 10) |> ignore
  inspect(eg.equiv(expression, expected), content="true")
}

///|
test "generated matcher keeps left-nested add-sub rewrites" {
  fn make_prefix(eg : EGraph) -> (EClassId, EClassId, EClassId) {
    let a = eg.add_var(0)
    let b = eg.add_var(1)
    let c = eg.add_var(2)
    let ab = eg.add_add(a, b)
    (ab, eg.add_sub(ab, c), c)
  }

  let add_graph = EGraph::EGraph()
  let (add_ab, add_prefix, add_c) = make_prefix(add_graph)
  let add_d = add_graph.add_var(3)
  let add_expression = add_graph.add_add(add_prefix, add_d)
  let add_expected = add_graph.add_sub(add_ab, add_graph.add_sub(add_c, add_d))
  add_graph.saturate_indexed(get_global_ruleset(), 10) |> ignore
  inspect(add_graph.equiv(add_expression, add_expected), content="true")

  let sub_graph = EGraph::EGraph()
  let (sub_ab, sub_prefix, sub_c) = make_prefix(sub_graph)
  let sub_d = sub_graph.add_var(3)
  let sub_expression = sub_graph.add_sub(sub_prefix, sub_d)
  let sub_expected = sub_graph.add_sub(sub_ab, sub_graph.add_add(sub_c, sub_d))
  sub_graph.saturate_indexed(get_global_ruleset(), 10) |> ignore
  inspect(sub_graph.equiv(sub_expression, sub_expected), content="true")
}

///|
test "generated matcher rejects inapplicable rules before budget accounting" {
  let eg = EGraph::EGraph()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let sum = eg.add_add(x, y)
  let candidates = generated_rule_match_bits(eg, eg.get_nodes(sum)[0], TAdd).popcnt()
  inspect(candidates < generated_rule_bucket_size(TAdd), content="true")
  let ruleset = get_global_ruleset()
  inspect(ruleset.generated_matcher, content="true")
}
