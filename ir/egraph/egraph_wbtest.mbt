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

  // Commutative ops are canonicalized at construction time.
  let sum3 = eg.add_add(y, x)
  inspect(eg.equiv(sum1, sum3), content="true")
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
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore

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
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_times_one, x), content="true")
}

///|
test "egraph: x * 0 = 0 rule" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let x_times_zero = eg.add_mul(x, zero)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_times_zero, zero), content="true")
}

///|
test "egraph: x - x = 0 rule" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let x_minus_x = eg.add_sub(x, x)
  let zero = eg.add_const(0L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_minus_x, zero), content="true")
}

///|
test "egraph: x ^ x = 0 rule" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let x_xor_x = eg.add_xor(x, x)
  let zero = eg.add_const(0L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_xor_x, zero), content="true")
}

///|
test "egraph: x & x = x rule" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let x_and_x = eg.add_and(x, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_and_x, x), content="true")
}

///|
test "egraph: x | x = x rule" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let x_or_x = eg.add_or(x, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
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
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
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
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_times_8, x_shl_3), content="true")
}

///|
test "egraph: x + x = x << 1" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let one = eg.add_const(1L)
  let x_plus_x = eg.add_add(x, x)
  let x_shl_1 = eg.add_shl(x, one)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_plus_x, x_shl_1), content="true")
}

///|
test "egraph: constant folding" {
  let eg = EGraph::new()
  let a = eg.add_const(3L)
  let b = eg.add_const(4L)
  let sum = eg.add_add(a, b)
  let seven = eg.add_const(7L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(sum, seven), content="true")
}

///|
test "egraph: constant folding mul" {
  let eg = EGraph::new()
  let a = eg.add_const(5L)
  let b = eg.add_const(6L)
  let product = eg.add_mul(a, b)
  let thirty = eg.add_const(30L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(product, thirty), content="true")
}

///|
test "egraph: extraction prefers shifts over muls" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let two = eg.add_const(2L)
  let x_times_2 = eg.add_mul(x, two)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore

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
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_plus_1_plus_2, x_plus_3), content="true")
}

///|
test "egraph: num_classes and num_nodes" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let _ = eg.add_add(x, y)

  // Before any merges
  inspect(eg.num_classes(), content="3")
  inspect(eg.num_nodes(), content="3")
}

// ============================================================================
// New rule tests
// ============================================================================

///|
test "egraph: x & 0 = 0" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let x_and_zero = eg.add_and(x, zero)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_and_zero, zero), content="true")
}

///|
test "egraph: x | 0 = x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let x_or_zero = eg.add_or(x, zero)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_or_zero, x), content="true")
}

///|
test "egraph: x ^ 0 = x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let x_xor_zero = eg.add_xor(x, zero)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_xor_zero, x), content="true")
}

///|
test "egraph: x & -1 = x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let all_ones = eg.add_const(-1L)
  let result = eg.add_and(x, all_ones)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x), content="true")
}

///|
test "egraph: x | -1 = -1" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let all_ones = eg.add_const(-1L)
  let result = eg.add_or(x, all_ones)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, all_ones), content="true")
}

///|
test "egraph: x << 0 = x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let result = eg.add_shl(x, zero)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x), content="true")
}

///|
test "egraph: 0 << x = 0" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let result = eg.add_shl(zero, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, zero), content="true")
}

///|
test "egraph: (x << 2) << 3 = x << 5" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let two = eg.add_const(2L)
  let three = eg.add_const(3L)
  let five = eg.add_const(5L)
  let inner = eg.add_shl(x, two)
  let outer = eg.add_shl(inner, three)
  let direct = eg.add_shl(x, five)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(outer, direct), content="true")
}

///|
test "egraph: x * 3 = (x << 1) + x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let three = eg.add_const(3L)
  let one = eg.add_const(1L)
  let mul3 = eg.add_mul(x, three)
  let shifted = eg.add_shl(x, one)
  let add_form = eg.add_add(shifted, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(mul3, add_form), content="true")
}

///|
test "egraph: x * 5 = (x << 2) + x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let five = eg.add_const(5L)
  let two = eg.add_const(2L)
  let mul5 = eg.add_mul(x, five)
  let shifted = eg.add_shl(x, two)
  let add_form = eg.add_add(shifted, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(mul5, add_form), content="true")
}

///|
test "egraph: x * 7 = (x << 3) - x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let seven = eg.add_const(7L)
  let three = eg.add_const(3L)
  let mul7 = eg.add_mul(x, seven)
  let shifted = eg.add_shl(x, three)
  let sub_form = eg.add_sub(shifted, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(mul7, sub_form), content="true")
}

///|
test "egraph: x * 9 = (x << 3) + x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let nine = eg.add_const(9L)
  let three = eg.add_const(3L)
  let mul9 = eg.add_mul(x, nine)
  let shifted = eg.add_shl(x, three)
  let add_form = eg.add_add(shifted, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(mul9, add_form), content="true")
}

///|
test "egraph: x % 8 = x & 7 (urem)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let eight = eg.add_const(8L)
  let seven = eg.add_const(7L)
  let rem = eg.add_binop(Urem, x, eight)
  let and_form = eg.add_and(x, seven)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(rem, and_form), content="true")
}

///|
test "egraph: x / 4 = x >> 2 (udiv)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let four = eg.add_const(4L)
  let two = eg.add_const(2L)
  let div = eg.add_binop(Udiv, x, four)
  let shr = eg.add_binop(Ushr, x, two)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(div, shr), content="true")
}

///|
test "egraph: 0 - x creates Neg node" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let neg_x = eg.add_sub(zero, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore

  // Check that Neg node exists in the class
  let mut has_neg = false
  for node in eg.get_nodes(neg_x) {
    if node.op is Neg {
      has_neg = true
    }
  }
  inspect(has_neg, content="true")
}

///|
test "egraph: x - (0 - y) = x + y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let zero = eg.add_const(0L)
  let neg_y = eg.add_sub(zero, y)
  let x_sub_neg_y = eg.add_sub(x, neg_y)
  let x_add_y = eg.add_add(x, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_sub_neg_y, x_add_y), content="true")
}

///|
test "egraph: x + (0 - y) = x - y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let zero = eg.add_const(0L)
  let neg_y = eg.add_sub(zero, y)
  let x_add_neg_y = eg.add_add(x, neg_y)
  let x_sub_y = eg.add_sub(x, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_add_neg_y, x_sub_y), content="true")
}

///|
test "egraph: (a * 2) * 3 = a * 6" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let two = eg.add_const(2L)
  let three = eg.add_const(3L)
  let six = eg.add_const(6L)
  let a_times_2 = eg.add_mul(a, two)
  let result = eg.add_mul(a_times_2, three)
  let direct = eg.add_mul(a, six)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, direct), content="true")
}

///|
test "egraph: (a - 1) - 2 = a - 3" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let one = eg.add_const(1L)
  let two = eg.add_const(2L)
  let three = eg.add_const(3L)
  let a_sub_1 = eg.add_sub(a, one)
  let result = eg.add_sub(a_sub_1, two)
  let direct = eg.add_sub(a, three)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, direct), content="true")
}

///|
test "egraph: commutativity canonicalizes add" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let xy = eg.add_add(x, y)
  let yx = eg.add_add(y, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(xy, yx), content="true")
}

///|
test "egraph: commutativity canonicalizes mul" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let xy = eg.add_mul(x, y)
  let yx = eg.add_mul(y, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(xy, yx), content="true")
}

///|
test "egraph: extraction prefers add over mul for x*3" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let three = eg.add_const(3L)
  let mul3 = eg.add_mul(x, three)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore

  // Should prefer (x << 1) + x (cost 2) over x * 3 (cost 3)
  let (cost, _) = eg.extract(mul3)
  // Cost should be: shl(1) + add(1) = 2
  inspect(cost, content="2")
}

///|
test "egraph: x * -1 = -x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let neg_one = eg.add_const(-1L)
  let mul_neg_one = eg.add_mul(x, neg_one)
  let neg_x = eg.add_neg(x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(mul_neg_one, neg_x), content="true")
}

///|
test "egraph: -x * -y = x * y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let neg_x = eg.add_neg(x)
  let neg_y = eg.add_neg(y)
  let neg_mul = eg.add_mul(neg_x, neg_y)
  let pos_mul = eg.add_mul(x, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(neg_mul, pos_mul), content="true")
}

///|
test "egraph: (x - y) + y = x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_sub_y = eg.add_sub(x, y)
  let result = eg.add_add(x_sub_y, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x), content="true")
}

///|
test "egraph: (x + y) - y = x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_add_y = eg.add_add(x, y)
  let result = eg.add_sub(x_add_y, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x), content="true")
}

///|
test "egraph: (x + y) - x = y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_add_y = eg.add_add(x, y)
  let result = eg.add_sub(x_add_y, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, y), content="true")
}

///|
test "egraph: (x - y) - x = -y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_sub_y = eg.add_sub(x, y)
  let result = eg.add_sub(x_sub_y, x)
  let neg_y = eg.add_neg(y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, neg_y), content="true")
}

///|
test "egraph: x / -1 = -x (sdiv)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let neg_one = eg.add_const(-1L)
  let div = eg.add({ op: Sdiv, children: [x, neg_one] })
  let neg_x = eg.add_neg(x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(div, neg_x), content="true")
}

///|
test "egraph: x % -1 = 0 (srem)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let neg_one = eg.add_const(-1L)
  let rem = eg.add({ op: Srem, children: [x, neg_one] })
  let zero = eg.add_const(0L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(rem, zero), content="true")
}

///|
test "egraph: x * (1 << y) = x << y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let one = eg.add_const(1L)
  let shl_one = eg.add_shl(one, y)
  let mul = eg.add_mul(x, shl_one)
  let shl_x = eg.add_shl(x, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(mul, shl_x), content="true")
}

///|
test "egraph: x | x = x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let x_or_x = eg.add_or(x, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(x_or_x, x), content="true")
}

///|
test "egraph: x ^ ~x = -1" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let not_x = eg.add_bnot(x)
  let result = eg.add_xor(x, not_x)
  let all_ones = eg.add_const(-1L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, all_ones), content="true")
}

///|
test "egraph: x | ~x = -1" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let not_x = eg.add_bnot(x)
  let result = eg.add_or(x, not_x)
  let all_ones = eg.add_const(-1L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, all_ones), content="true")
}

///|
test "egraph: x & ~x = 0" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let not_x = eg.add_bnot(x)
  let result = eg.add_and(x, not_x)
  let zero = eg.add_const(0L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, zero), content="true")
}

///|
test "egraph: ~~x = x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let not_x = eg.add_bnot(x)
  let not_not_x = eg.add_bnot(not_x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(not_not_x, x), content="true")
}

///|
test "egraph: DeMorgan ~(x | y) = ~x & ~y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_or_y = eg.add_or(x, y)
  let not_or = eg.add_bnot(x_or_y)
  let not_x = eg.add_bnot(x)
  let not_y = eg.add_bnot(y)
  let not_and = eg.add_and(not_x, not_y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(not_or, not_and), content="true")
}

///|
test "egraph: DeMorgan ~(x & y) = ~x | ~y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_and_y = eg.add_and(x, y)
  let not_and = eg.add_bnot(x_and_y)
  let not_x = eg.add_bnot(x)
  let not_y = eg.add_bnot(y)
  let not_or = eg.add_or(not_x, not_y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(not_and, not_or), content="true")
}

///|
test "egraph: x ^ -1 = ~x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let all_ones = eg.add_const(-1L)
  let result = eg.add_xor(x, all_ones)
  let not_x = eg.add_bnot(x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, not_x), content="true")
}

///|
test "egraph: (x & y) ^ (x ^ y) = x | y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_and_y = eg.add_and(x, y)
  let x_xor_y = eg.add_xor(x, y)
  let result = eg.add_xor(x_and_y, x_xor_y)
  let x_or_y = eg.add_or(x, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x_or_y), content="true")
}

///|
test "egraph: (x | y) ^ (x & y) = x ^ y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_or_y = eg.add_or(x, y)
  let x_and_y = eg.add_and(x, y)
  let result = eg.add_xor(x_or_y, x_and_y)
  let x_xor_y = eg.add_xor(x, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x_xor_y), content="true")
}

///|
test "egraph: (x & y) | x = x (absorption)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_and_y = eg.add_and(x, y)
  let result = eg.add_or(x_and_y, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x), content="true")
}

///|
test "egraph: (x ^ y) ^ y = x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_xor_y = eg.add_xor(x, y)
  let result = eg.add_xor(x_xor_y, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x), content="true")
}

///|
test "egraph: (z & x) ^ (z & y) = z & (x ^ y)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let z = eg.add_var(2)
  let z_and_x = eg.add_and(z, x)
  let z_and_y = eg.add_and(z, y)
  let result = eg.add_xor(z_and_x, z_and_y)
  let x_xor_y = eg.add_xor(x, y)
  let expected = eg.add_and(z, x_xor_y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: (x & y) + (x ^ y) = x | y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_and_y = eg.add_and(x, y)
  let x_xor_y = eg.add_xor(x, y)
  let result = eg.add_add(x_and_y, x_xor_y)
  let x_or_y = eg.add_or(x, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x_or_y), content="true")
}

///|
test "egraph: (x | y) + (x & y) = x + y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_or_y = eg.add_or(x, y)
  let x_and_y = eg.add_and(x, y)
  let result = eg.add_add(x_or_y, x_and_y)
  let x_add_y = eg.add_add(x, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x_add_y), content="true")
}

///|
test "egraph: (x & y) | ~y = x | ~y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_and_y = eg.add_and(x, y)
  let not_y = eg.add_bnot(y)
  let result = eg.add_or(x_and_y, not_y)
  let expected = eg.add_or(x, not_y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: (x | y) | x = x | y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_or_y = eg.add_or(x, y)
  let result = eg.add_or(x_or_y, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x_or_y), content="true")
}

///|
test "egraph: (x & y) & x = x & y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_and_y = eg.add_and(x, y)
  let result = eg.add_and(x_and_y, x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x_and_y), content="true")
}

///|
test "egraph: (x ^ ~y) & x = x & y" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let not_y = eg.add_bnot(y)
  let x_xor_not_y = eg.add_xor(x, not_y)
  let result = eg.add_and(x_xor_not_y, x)
  let expected = eg.add_and(x, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: (x & y) | ~x = y | ~x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let x_and_y = eg.add_and(x, y)
  let not_x = eg.add_bnot(x)
  let result = eg.add_or(x_and_y, not_x)
  let expected = eg.add_or(y, not_x)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: (x | 3) | 5 = x | 7 (or reassociation)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let c3 = eg.add_const(3L)
  let c5 = eg.add_const(5L)
  let x_or_3 = eg.add_or(x, c3)
  let result = eg.add_or(x_or_3, c5)
  let c7 = eg.add_const(7L)
  let expected = eg.add_or(x, c7)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: (x & 7) & 3 = x & 3 (and reassociation)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let c7 = eg.add_const(7L)
  let c3 = eg.add_const(3L)
  let x_and_7 = eg.add_and(x, c7)
  let result = eg.add_and(x_and_7, c3)
  let expected = eg.add_and(x, c3)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: (x ^ 3) ^ 5 = x ^ 6 (xor reassociation)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let c3 = eg.add_const(3L)
  let c5 = eg.add_const(5L)
  let x_xor_3 = eg.add_xor(x, c3)
  let result = eg.add_xor(x_xor_3, c5)
  let c6 = eg.add_const(6L)
  let expected = eg.add_xor(x, c6)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: (x + 3) - 5 = x - 2 (sub-add reassociation)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let c3 = eg.add_const(3L)
  let c5 = eg.add_const(5L)
  let x_add_3 = eg.add_add(x, c3)
  let result = eg.add_sub(x_add_3, c5)
  let c_neg2 = eg.add_const(-2L)
  let expected = eg.add_add(x, c_neg2)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: (x - 3) + 5 = x + 2 (add-sub reassociation)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let c3 = eg.add_const(3L)
  let c5 = eg.add_const(5L)
  let x_sub_3 = eg.add_sub(x, c3)
  let result = eg.add_add(x_sub_3, c5)
  let c2 = eg.add_const(2L)
  let expected = eg.add_add(x, c2)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

// ============================================================================
// New select rules tests
// ============================================================================

///|
test "egraph: select(cond, x, x) = x" {
  let eg = EGraph::new()
  let cond = eg.add_var(0)
  let x = eg.add_var(1)
  let select = eg.add({ op: Select, children: [cond, x, x] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(select, x), content="true")
}

///|
test "egraph: select(icmp, 1, 0) = icmp" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let one = eg.add_const(1L)
  let zero = eg.add_const(0L)
  // icmp(slt, x, y)
  let cmp = eg.add({ op: Icmp(2), children: [x, y] })
  let select = eg.add({ op: Select, children: [cmp, one, zero] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(select, cmp), content="true")
}

///|
test "egraph: select(d, a, select(d, _, y)) = select(d, a, y)" {
  let eg = EGraph::new()
  let d = eg.add_var(0)
  let a = eg.add_var(1)
  let b = eg.add_var(2)
  let y = eg.add_var(3)
  // inner: select(d, b, y)
  let inner = eg.add({ op: Select, children: [d, b, y] })
  // outer: select(d, a, inner)
  let outer = eg.add({ op: Select, children: [d, a, inner] })
  // expected: select(d, a, y)
  let expected = eg.add({ op: Select, children: [d, a, y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(outer, expected), content="true")
}

///|
test "egraph: select(d, select(d, x, _), a) = select(d, x, a)" {
  let eg = EGraph::new()
  let d = eg.add_var(0)
  let x = eg.add_var(1)
  let b = eg.add_var(2)
  let a = eg.add_var(3)
  // inner: select(d, x, b)
  let inner = eg.add({ op: Select, children: [d, x, b] })
  // outer: select(d, inner, a)
  let outer = eg.add({ op: Select, children: [d, inner, a] })
  // expected: select(d, x, a)
  let expected = eg.add({ op: Select, children: [d, x, a] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(outer, expected), content="true")
}

// ============================================================================
// New shift rules tests
// ============================================================================

///|
test "egraph: x rotl 0 = x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let result = eg.add({ op: Rotl, children: [x, zero] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x), content="true")
}

///|
test "egraph: x rotr 0 = x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let result = eg.add({ op: Rotr, children: [x, zero] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x), content="true")
}

///|
test "egraph: (x >> 3) >> 2 = x >> 5 (ushr)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let two = eg.add_const(2L)
  let three = eg.add_const(3L)
  let five = eg.add_const(5L)
  let inner = eg.add({ op: Ushr, children: [x, three] })
  let outer = eg.add({ op: Ushr, children: [inner, two] })
  let direct = eg.add({ op: Ushr, children: [x, five] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(outer, direct), content="true")
}

///|
test "egraph: (x >> 3) >> 2 = x >> 5 (sshr)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let two = eg.add_const(2L)
  let three = eg.add_const(3L)
  let five = eg.add_const(5L)
  let inner = eg.add({ op: Sshr, children: [x, three] })
  let outer = eg.add({ op: Sshr, children: [inner, two] })
  let direct = eg.add({ op: Sshr, children: [x, five] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(outer, direct), content="true")
}

///|
test "egraph: rotl(rotr(x, y), y) = x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let rotr_x = eg.add({ op: Rotr, children: [x, y] })
  let result = eg.add({ op: Rotl, children: [rotr_x, y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x), content="true")
}

///|
test "egraph: rotr(rotl(x, y), y) = x" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let rotl_x = eg.add({ op: Rotl, children: [x, y] })
  let result = eg.add({ op: Rotr, children: [rotl_x, y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, x), content="true")
}

///|
test "egraph: (x >> k) << k = x & mask (ushr/shl)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k = eg.add_const(4L)
  let ushr_x = eg.add({ op: Ushr, children: [x, k] })
  let result = eg.add_shl(ushr_x, k)
  // mask = ~((1 << 4) - 1) = ~15 = 0xFFFFFFFFFFFFFFF0
  let mask = eg.add_const(-16L) // 0xFFFFFFFFFFFFFFF0
  let expected = eg.add_and(x, mask)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: band(ishl(x, z), ishl(y, z)) = ishl(band(x, y), z)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let z = eg.add_var(2)
  let shl_x = eg.add_shl(x, z)
  let shl_y = eg.add_shl(y, z)
  let result = eg.add_and(shl_x, shl_y)
  let x_and_y = eg.add_and(x, y)
  let expected = eg.add_shl(x_and_y, z)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: iadd(ishl(x, z), ishl(y, z)) = ishl(iadd(x, y), z)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let z = eg.add_var(2)
  let shl_x = eg.add_shl(x, z)
  let shl_y = eg.add_shl(y, z)
  let result = eg.add_add(shl_x, shl_y)
  let x_add_y = eg.add_add(x, y)
  let expected = eg.add_shl(x_add_y, z)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: isub(ishl(x, z), ishl(y, z)) = ishl(isub(x, y), z)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let z = eg.add_var(2)
  let shl_x = eg.add_shl(x, z)
  let shl_y = eg.add_shl(y, z)
  let result = eg.add_sub(shl_x, shl_y)
  let x_sub_y = eg.add_sub(x, y)
  let expected = eg.add_shl(x_sub_y, z)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: (x << 32) | (x >> 32) = rotl(x, 32)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k = eg.add_const(32L)
  let shl_x = eg.add_shl(x, k)
  let ushr_x = eg.add({ op: Ushr, children: [x, k] })
  let result = eg.add_or(shl_x, ushr_x)
  let rotl_x = eg.add({ op: Rotl, children: [x, k] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, rotl_x), content="true")
}

// ============================================================================
// Comparison reassociation tests
// ============================================================================

///|
test "egraph: eq(x + 3, 10) = eq(x, 7)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let c3 = eg.add_const(3L)
  let c10 = eg.add_const(10L)
  let c7 = eg.add_const(7L)
  let x_add_3 = eg.add_add(x, c3)
  let result = eg.add({ op: Eq, children: [x_add_3, c10] })
  let expected = eg.add({ op: Eq, children: [x, c7] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: ne(x + 3, 10) = ne(x, 7)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let c3 = eg.add_const(3L)
  let c10 = eg.add_const(10L)
  let c7 = eg.add_const(7L)
  let x_add_3 = eg.add_add(x, c3)
  let result = eg.add({ op: Ne, children: [x_add_3, c10] })
  let expected = eg.add({ op: Ne, children: [x, c7] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: eq(x - 3, 10) = eq(x, 13)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let c3 = eg.add_const(3L)
  let c10 = eg.add_const(10L)
  let c13 = eg.add_const(13L)
  let x_sub_3 = eg.add_sub(x, c3)
  let result = eg.add({ op: Eq, children: [x_sub_3, c10] })
  let expected = eg.add({ op: Eq, children: [x, c13] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: ne(x - 3, 10) = ne(x, 13)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let c3 = eg.add_const(3L)
  let c10 = eg.add_const(10L)
  let c13 = eg.add_const(13L)
  let x_sub_3 = eg.add_sub(x, c3)
  let result = eg.add({ op: Ne, children: [x_sub_3, c10] })
  let expected = eg.add({ op: Ne, children: [x, c13] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

// ============================================================================
// Additional optimization rules tests
// ============================================================================

///|
test "egraph: ineg(isub(y, x)) = isub(x, y)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let sub_yx = eg.add_sub(y, x)
  let neg_sub = eg.add({ op: Neg, children: [sub_yx] })
  let expected = eg.add_sub(x, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(neg_sub, expected), content="true")
}

///|
test "egraph: ineg(ushr(x, 63)) = sshr(x, 63)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k63 = eg.add_const(63L)
  let ushr_x = eg.add({ op: Ushr, children: [x, k63] })
  let neg_ushr = eg.add({ op: Neg, children: [ushr_x] })
  let expected = eg.add({ op: Sshr, children: [x, k63] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(neg_ushr, expected), content="true")
}

///|
test "egraph: (ishl (ishl x 40) 30) = 0 (shift overflow)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k40 = eg.add_const(40L)
  let k30 = eg.add_const(30L)
  let shl1 = eg.add_shl(x, k40)
  let shl2 = eg.add_shl(shl1, k30)
  let zero = eg.add_const(0L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(shl2, zero), content="true")
}

///|
test "egraph: (ushr (ushr x 40) 30) = 0 (shift overflow)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k40 = eg.add_const(40L)
  let k30 = eg.add_const(30L)
  let ushr1 = eg.add({ op: Ushr, children: [x, k40] })
  let ushr2 = eg.add({ op: Ushr, children: [ushr1, k30] })
  let zero = eg.add_const(0L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(ushr2, zero), content="true")
}

///|
test "egraph: iadd(select(c, 1, 2), 5) = select(c, 6, 7)" {
  let eg = EGraph::new()
  let c = eg.add_var(0)
  let k1 = eg.add_const(1L)
  let k2 = eg.add_const(2L)
  let k5 = eg.add_const(5L)
  let k6 = eg.add_const(6L)
  let k7 = eg.add_const(7L)
  let sel = eg.add({ op: Select, children: [c, k1, k2] })
  let result = eg.add_add(sel, k5)
  let expected = eg.add({ op: Select, children: [c, k6, k7] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: icmp(slt, 5, x) = icmp(sgt, x, 5) (swap const to right)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k5 = eg.add_const(5L)
  let cc_slt = 2
  let cc_sgt = 4
  let result = eg.add({ op: Icmp(cc_slt), children: [k5, x] })
  let expected = eg.add({ op: Icmp(cc_sgt), children: [x, k5] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: eq(5, x) = eq(x, 5) (swap const to right)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k5 = eg.add_const(5L)
  let result = eg.add({ op: Eq, children: [k5, x] })
  let expected = eg.add({ op: Eq, children: [x, k5] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: eq(x + 3, y + 5) = eq(x, y + 2)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let k3 = eg.add_const(3L)
  let k5 = eg.add_const(5L)
  let k2 = eg.add_const(2L)
  let x_add_3 = eg.add_add(x, k3)
  let y_add_5 = eg.add_add(y, k5)
  let result = eg.add({ op: Eq, children: [x_add_3, y_add_5] })
  let y_add_2 = eg.add_add(y, k2)
  let expected = eg.add({ op: Eq, children: [x, y_add_2] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

///|
test "egraph: ne(x + 3, y + 5) = ne(x, y + 2)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let k3 = eg.add_const(3L)
  let k5 = eg.add_const(5L)
  let k2 = eg.add_const(2L)
  let x_add_3 = eg.add_add(x, k3)
  let y_add_5 = eg.add_add(y, k5)
  let result = eg.add({ op: Ne, children: [x_add_3, y_add_5] })
  let y_add_2 = eg.add_add(y, k2)
  let expected = eg.add({ op: Ne, children: [x, y_add_2] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}

// ============================================================================
// Type-aware comparison rules tests
// ============================================================================

///|
test "egraph: ugt(x, UMAX_32) = false with type info" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  eg.set_type(x, 32) // Mark x as 32-bit
  let umax32 = eg.add_const(0xFFFF_FFFFL)
  let cc_ugt = 8
  let result = eg.add({ op: Icmp(cc_ugt), children: [x, umax32] })
  let zero = eg.add_const(0L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, zero), content="true")
}

///|
test "egraph: ule(x, UMAX_32) = true with type info" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  eg.set_type(x, 32) // Mark x as 32-bit
  let umax32 = eg.add_const(0xFFFF_FFFFL)
  let cc_ule = 7
  let result = eg.add({ op: Icmp(cc_ule), children: [x, umax32] })
  let one = eg.add_const(1L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, one), content="true")
}

///|
test "egraph: sgt(x, SMAX_32) = false with type info" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  eg.set_type(x, 32) // Mark x as 32-bit
  let smax32 = eg.add_const(2147483647L) // 0x7FFF_FFFF
  let cc_sgt = 4
  let result = eg.add({ op: Icmp(cc_sgt), children: [x, smax32] })
  let zero = eg.add_const(0L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, zero), content="true")
}

///|
test "egraph: slt(x, SMIN_32) = false with type info" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  eg.set_type(x, 32) // Mark x as 32-bit
  let smin32 = eg.add_const(-2147483648L) // 0x8000_0000
  let cc_slt = 2
  let result = eg.add({ op: Icmp(cc_slt), children: [x, smin32] })
  let zero = eg.add_const(0L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, zero), content="true")
}

///|
test "egraph: sge(x, SMIN_32) = true with type info" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  eg.set_type(x, 32) // Mark x as 32-bit
  let smin32 = eg.add_const(-2147483648L)
  let cc_sge = 5
  let result = eg.add({ op: Icmp(cc_sge), children: [x, smin32] })
  let one = eg.add_const(1L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, one), content="true")
}

///|
test "egraph: sle(x, SMAX_32) = true with type info" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  eg.set_type(x, 32) // Mark x as 32-bit
  let smax32 = eg.add_const(2147483647L)
  let cc_sle = 3
  let result = eg.add({ op: Icmp(cc_sle), children: [x, smax32] })
  let one = eg.add_const(1L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, one), content="true")
}

///|
test "egraph: type info is preserved through merge" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  eg.set_type(x, 32)
  // Merge x and y
  eg.merge(x, y) |> ignore
  eg.rebuild()
  // Type should be preserved in merged class
  inspect(eg.get_bits(y), content="Some(32)")
}

///|
test "egraph: add_typed sets type correctly" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k5 = eg.add_const(5L)
  let result = eg.add_typed({ op: Add, children: [x, k5] }, 32)
  inspect(eg.get_bits(result), content="Some(32)")
}

///|
/// Test that x + 0 = x extraction returns Var, not Const(0)
test "egraph: x + 0 extract returns Var not Const" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let x_plus_zero = eg.add_add(x, zero)

  // Before saturation
  inspect(eg.equiv(x_plus_zero, x), content="false")

  // Apply only add_zero rule
  let rules = IndexedRuleSet::new()
  rules.add_rule(rule_add_zero(), [TAdd])
  eg.saturate_indexed(rules, 10) |> ignore

  // After saturation, x + 0 should equal x
  inspect(eg.equiv(x_plus_zero, x), content="true")

  // Verify we kept both `Add` and `Var` forms in the e-class.
  let nodes = eg.get_nodes(x_plus_zero)
  inspect(nodes.length(), content="2")

  // Extract should return Var(0), not Const(0)
  let (cost, node) = eg.extract(x_plus_zero)
  inspect(node.op, content="Var(0)")
  inspect(cost, content="0")
}

///|
/// Test that rebuild preserves all nodes when unions happen mid-rebuild.
/// This tests the bug where nodes can be lost if:
/// 1. Class A (lower ID) has single node that will collide
/// 2. Class B (higher ID) has multiple nodes [N1, N2] where N1 collides with A
/// 3. During rebuild, when processing B, N1 causes collision and union
/// 4. N2 is then added to canonical_nodes[B] using stale canonical_id
/// 5. In the second pass, B is non-canonical, so nodes from canonical_nodes[B] are lost
test "rebuild: nodes preserved after intra-rebuild union" {
  let eg = EGraph::new()

  // Create two variables - x will be the "winner" after merge
  let x = eg.add_var(0) // class 0
  let y = eg.add_var(1) // class 1

  // Create Add(x, x) FIRST - this will be in class 2 (lower ID)
  // This is the collision source that will be processed first during rebuild
  let add_xx = eg.add_add(x, x)

  // Create Add(y, y) - this will be in class 3 (higher ID)
  let add_yy = eg.add_add(y, y)

  // Create Sub(y, y) and Mul(y, y) to ensure we have multiple nodes
  let sub_yy = eg.add_sub(y, y)
  let mul_yy = eg.add_mul(y, y)

  // Merge all y-based ops into one class
  // After this, the class containing add_yy has nodes: [Add(y,y), Sub(y,y), Mul(y,y)]
  eg.merge(add_yy, sub_yy) |> ignore
  eg.merge(add_yy, mul_yy) |> ignore
  eg.rebuild()

  // Verify the class has 3 nodes.
  let nodes_before = eg.get_nodes(add_yy)
  inspect(nodes_before.length(), content="3")

  // Now merge x and y
  // After rebuild, Add(y,y) will canonicalize to Add(x,x) and collide
  eg.merge(x, y) |> ignore
  eg.rebuild()

  // All should be in the same class now
  inspect(eg.equiv(add_xx, add_yy), content="true")
  inspect(eg.equiv(add_xx, sub_yy), content="true")
  inspect(eg.equiv(add_xx, mul_yy), content="true")

  // The merged class should have Add, Sub, AND Mul nodes
  let nodes_after = eg.get_nodes(add_xx)
  let mut has_add = false
  let mut has_sub = false
  let mut has_mul = false
  for node in nodes_after {
    match node.op {
      Add => has_add = true
      Sub => has_sub = true
      Mul => has_mul = true
      _ => ()
    }
  }
  inspect(has_add, content="true")
  inspect(has_sub, content="true")
  inspect(has_mul, content="true")
}

///|
/// Test that rebuild re-canonicalizes nodes after applying unions.
/// This tests the bug where nodes with children that get merged during rebuild
/// are left with stale child class IDs.
///
/// Scenario:
/// - Class 0: Var(0), Class 1: Var(1)
/// - Class 2: Add(0, 0), Class 3: Add(1, 1)
/// - Class 4: Mul(0, 2), Class 5: Mul(1, 3)
/// - merge(0, 1) triggers rebuild
///
/// During rebuild:
/// - Add(0,0) and Add(1,1) both canonicalize to Add(0,0), causing union(2,3)
/// - Before the union is applied, Mul(1,3) canonicalizes to Mul(0,3)
/// - After union(2,3), find(3)=2, so Mul(0,3) should become Mul(0,2)
/// - But without re-canonicalization, Mul(0,3) has stale child reference
test "rebuild: re-canonicalize nodes after unions" {
  let eg = EGraph::new()

  // Create two variables
  let x = eg.add_var(0) // class 0
  let y = eg.add_var(1) // class 1

  // Create Add(x, x) and Add(y, y)
  let add_xx = eg.add_add(x, x) // class 2
  let add_yy = eg.add_add(y, y) // class 3

  // Create Mul(x, Add(x,x)) and Mul(y, Add(y,y))
  let mul_x_addxx = eg.add_mul(x, add_xx) // class 4
  let mul_y_addyy = eg.add_mul(y, add_yy) // class 5

  // Verify initial state - all are different
  inspect(eg.equiv(add_xx, add_yy), content="false")
  inspect(eg.equiv(mul_x_addxx, mul_y_addyy), content="false")

  // Merge x and y - this will trigger a cascade:
  // 1. Add(x,x) and Add(y,y) will canonicalize to same node
  // 2. Thus Add classes should merge
  // 3. Mul(x, Add(x,x)) and Mul(y, Add(y,y)) should also merge
  eg.merge(x, y) |> ignore
  eg.rebuild()

  // After rebuild, Add(x,x) and Add(y,y) should be equivalent
  inspect(eg.equiv(add_xx, add_yy), content="true")

  // The Mul nodes should ALSO be equivalent because:
  // - Their first child (x/y) are now equivalent
  // - Their second child (Add(x,x)/Add(y,y)) are now equivalent
  // This will FAIL if nodes aren't re-canonicalized after unions
  inspect(eg.equiv(mul_x_addxx, mul_y_addyy), content="true")

  // Verify hashcons consistency: looking up the canonical form should work
  let mul_canonical = eg.canonicalize({
    op: Mul,
    children: [eg.find(x), eg.find(add_xx)],
  })
  let lookup_result = eg.hashcons.get(mul_canonical)
  inspect(lookup_result is None, content="false")
}
