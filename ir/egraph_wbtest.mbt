///|
test "egraph: basic add and find" {
  let eg = EGraph::new()

  // Add a constant
  let c1 = eg.add_const(42L)
  let c2 = eg.add_const(42L)

  // Same constant should return same class
  inspect(eg.equiv(c1, c2), content="true")

  // Different constants should be different classes
  let c3 = eg.add_const(100L)
  inspect(eg.equiv(c1, c3), content="false")
}

///|
test "egraph: variable nodes" {
  let eg = EGraph::new()
  let v1 = eg.add_var(0)
  let v2 = eg.add_var(0)
  let v3 = eg.add_var(1)

  // Same var id should be same class
  inspect(eg.equiv(v1, v2), content="true")
  // Different var ids should be different
  inspect(eg.equiv(v1, v3), content="false")
}

///|
test "egraph: add operations" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let sum1 = eg.add_add(x, y)
  let sum2 = eg.add_add(x, y)

  // Same expression should be same class
  inspect(eg.equiv(sum1, sum2), content="true")

  // Adding is not commutative by default
  let sum3 = eg.add_add(y, x)
  inspect(eg.equiv(sum1, sum3), content="false")
}

///|
test "egraph: merge" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)

  // Initially different
  inspect(eg.equiv(x, y), content="false")

  // After merge, they should be equivalent
  eg.merge(x, y) |> ignore
  inspect(eg.equiv(x, y), content="true")
}

///|
test "egraph: x + 0 = x rule" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let x_plus_zero = eg.add_add(x, zero)

  // Before saturation, x + 0 is different from x
  inspect(eg.equiv(x_plus_zero, x), content="false")

  // Apply rules
  eg.saturate(standard_rules(), 10) |> ignore

  // After saturation, x + 0 should equal x
  inspect(eg.equiv(x_plus_zero, x), content="true")
}

///|
test "egraph: x * 1 = x rule" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let one = eg.add_const(1L)
  let x_times_one = eg.add_mul(x, one)
  inspect(eg.equiv(x_times_one, x), content="false")
  eg.saturate(standard_rules(), 10) |> ignore
  inspect(eg.equiv(x_times_one, x), content="true")
}

///|
test "egraph: x * 0 = 0 rule" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let x_times_zero = eg.add_mul(x, zero)
  eg.saturate(standard_rules(), 10) |> ignore
  inspect(eg.equiv(x_times_zero, zero), content="true")
}

///|
test "egraph: x - x = 0 rule" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let x_minus_x = eg.add_sub(x, x)
  let zero = eg.add_const(0L)
  eg.saturate(standard_rules(), 10) |> ignore
  inspect(eg.equiv(x_minus_x, zero), content="true")
}

///|
test "egraph: x ^ x = 0 rule" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let x_xor_x = eg.add_xor(x, x)
  let zero = eg.add_const(0L)
  eg.saturate(standard_rules(), 10) |> ignore
  inspect(eg.equiv(x_xor_x, zero), content="true")
}

///|
test "egraph: x & x = x rule" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let x_and_x = eg.add_and(x, x)
  eg.saturate(standard_rules(), 10) |> ignore
  inspect(eg.equiv(x_and_x, x), content="true")
}

///|
test "egraph: x | x = x rule" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let x_or_x = eg.add_or(x, x)
  eg.saturate(standard_rules(), 10) |> ignore
  inspect(eg.equiv(x_or_x, x), content="true")
}

///|
test "egraph: x * 2 = x << 1 strength reduction" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let two = eg.add_const(2L)
  let one = eg.add_const(1L)
  let x_times_2 = eg.add_mul(x, two)
  let x_shl_1 = eg.add_shl(x, one)
  inspect(eg.equiv(x_times_2, x_shl_1), content="false")
  eg.saturate(standard_rules(), 10) |> ignore
  inspect(eg.equiv(x_times_2, x_shl_1), content="true")
}

///|
test "egraph: x * 8 = x << 3 strength reduction" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let eight = eg.add_const(8L)
  let three = eg.add_const(3L)
  let x_times_8 = eg.add_mul(x, eight)
  let x_shl_3 = eg.add_shl(x, three)
  eg.saturate(standard_rules(), 10) |> ignore
  inspect(eg.equiv(x_times_8, x_shl_3), content="true")
}

///|
test "egraph: x + x = x << 1" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let one = eg.add_const(1L)
  let x_plus_x = eg.add_add(x, x)
  let x_shl_1 = eg.add_shl(x, one)
  eg.saturate(standard_rules(), 10) |> ignore
  inspect(eg.equiv(x_plus_x, x_shl_1), content="true")
}

///|
test "egraph: constant folding" {
  let eg = EGraph::new()
  let a = eg.add_const(3L)
  let b = eg.add_const(4L)
  let sum = eg.add_add(a, b)
  let seven = eg.add_const(7L)
  eg.saturate(standard_rules(), 10) |> ignore
  inspect(eg.equiv(sum, seven), content="true")
}

///|
test "egraph: constant folding mul" {
  let eg = EGraph::new()
  let a = eg.add_const(5L)
  let b = eg.add_const(6L)
  let product = eg.add_mul(a, b)
  let thirty = eg.add_const(30L)
  eg.saturate(standard_rules(), 10) |> ignore
  inspect(eg.equiv(product, thirty), content="true")
}

///|
test "egraph: extraction prefers shifts over muls" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let two = eg.add_const(2L)
  let x_times_2 = eg.add_mul(x, two)
  eg.saturate(standard_rules(), 10) |> ignore

  // Extract best - should prefer shift
  let (cost, node) = eg.extract(x_times_2)
  inspect(node.op, content="Shl")
  // Cost should be low (shift cost 1 + const cost 0 + var cost 0 = 1)
  inspect(cost, content="1")
}

///|
test "egraph: (x + 1) + 2 = x + 3 reassociation" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let one = eg.add_const(1L)
  let two = eg.add_const(2L)
  let three = eg.add_const(3L)
  let x_plus_1 = eg.add_add(x, one)
  let x_plus_1_plus_2 = eg.add_add(x_plus_1, two)
  let x_plus_3 = eg.add_add(x, three)
  eg.saturate(standard_rules(), 10) |> ignore
  inspect(eg.equiv(x_plus_1_plus_2, x_plus_3), content="true")
}

///|
test "egraph: num_classes and num_nodes" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let sum = eg.add_add(x, y)

  // Before any merges
  inspect(eg.num_classes(), content="3")
  inspect(eg.num_nodes(), content="3")

  // After saturation (might add more equivalent nodes)
  eg.saturate(standard_rules(), 5) |> ignore
  // Classes should still be separate (no identity rules apply)
  inspect(eg.num_classes(), content="3")
}
