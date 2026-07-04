///|
/// Test for uextend(const) folding with cycle detection in extract
test "rule_uextend_const_with_extract" {
  let eg = EGraph::new()

  // Create const(200) in e-graph
  let const_200 = eg.add_const(200L)

  // Create uextend(32, 64, const_200)
  let uextend_node = eg.add({ op: Uextend(32, 64), children: [const_200] })

  // Before saturation
  inspect(eg.get_nodes(uextend_node).length(), content="1")

  // Apply only the uextend_const rule
  let rules = IndexedRuleSet::new()
  rules.add_rule(rule_uextend_const(), [TUextend])
  eg.saturate_indexed(rules, 10) |> ignore

  // After saturation, uextend(const) should simplify to a constant representative.
  inspect(eg.get_nodes(uextend_node).length(), content="2")

  // Extract should return Const(200) because it has lower cost
  // and the cyclic Uextend node should be skipped
  let (cost, best) = eg.extract(uextend_node)
  inspect(cost, content="0")
  inspect(best.op, content="Const(200)")
}

///|
/// Test that typed nodes participate in rewrite_to_fixpoint
test "rule_uextend_const_typed_rewrite" {
  let eg = EGraph::new()
  let rules = standard_rules_indexed()
  let const_200 = eg.add_typed({ op: Const(200L), children: [] }, 32)
  let uextend_node = eg.add_typed(
    { op: Uextend(32, 64), children: [const_200] },
    64,
  )
  eg.saturate_indexed(rules, 10) |> ignore
  let (cost, best) = eg.extract(uextend_node)
  inspect(cost, content="0")
  inspect(best.op, content="Const(200)")
}
