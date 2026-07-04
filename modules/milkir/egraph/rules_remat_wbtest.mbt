// Rematerialization rules tests

///|
test "remat: iadd with iconst is rematerializable" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k5 = eg.add_const(5L)
  let result = eg.add_add(x, k5)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.is_marked_rematerializable(result), content="true")
}

///|
test "remat: isub with iconst is rematerializable" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k5 = eg.add_const(5L)
  let result = eg.add_sub(x, k5)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.is_marked_rematerializable(result), content="true")
}

///|
test "remat: band with iconst is rematerializable" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k5 = eg.add_const(5L)
  let result = eg.add_and(x, k5)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.is_marked_rematerializable(result), content="true")
}

///|
test "remat: bor with iconst is rematerializable" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k5 = eg.add_const(5L)
  let result = eg.add_or(x, k5)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.is_marked_rematerializable(result), content="true")
}

///|
test "remat: bxor with iconst is rematerializable" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k5 = eg.add_const(5L)
  let result = eg.add_xor(x, k5)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.is_marked_rematerializable(result), content="true")
}

///|
test "remat: bnot is rematerializable" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let result = eg.add_bnot(x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.is_marked_rematerializable(result), content="true")
}

///|
test "remat: iconst is rematerializable" {
  let eg = EGraph::new()
  let result = eg.add_const(42L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.is_marked_rematerializable(result), content="true")
}

///|
test "remat: fconst is rematerializable" {
  let eg = EGraph::new()
  let result = eg.add_fconst(0x3FF0000000000000UL) // 1.0 as f64
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.is_marked_rematerializable(result), content="true")
}

///|
test "remat: iadd without iconst is not rematerializable" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let result = eg.add_add(x, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.is_marked_rematerializable(result), content="false")
}

///|
test "remat: mul is not rematerializable" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k5 = eg.add_const(5L)
  let result = eg.add_mul(x, k5)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.is_marked_rematerializable(result), content="false")
}

///|
test "remat: flag preserved through merge" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k5 = eg.add_const(5L)
  let add_result = eg.add_add(x, k5)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Create another expression and merge
  let y = eg.add_var(1)
  eg.merge(add_result, y) |> ignore
  eg.rebuild()
  // Remat flag should be preserved
  inspect(eg.is_marked_rematerializable(y), content="true")
}

///|
test "remat: is_rematerializable checks node patterns" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k5 = eg.add_const(5L)
  let add_result = eg.add_add(x, k5)
  // Use the is_rematerializable method that checks node patterns
  inspect(eg.is_rematerializable(add_result), content="true")
  // Non-rematerializable: mul with const
  let mul_result = eg.add_mul(x, k5)
  inspect(eg.is_rematerializable(mul_result), content="false")
}
