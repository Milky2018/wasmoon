// Skeleton optimization rules tests

///|
test "skeleton: udiv(y, select(cond, 4, 8)) = ushr(y, select(cond, 2, 3))" {
  let eg = EGraph::new()
  let y = eg.add_var(0)
  let cond = eg.add_var(1)
  let k4 = eg.add_const(4L) // 2^2
  let k8 = eg.add_const(8L) // 2^3
  let divisor = eg.add({ op: Select, children: [cond, k4, k8] })
  let udiv = eg.add({ op: Udiv, children: [y, divisor] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to ushr(y, select(cond, 2, 3))
  let k2 = eg.add_const(2L)
  let k3 = eg.add_const(3L)
  let shift_amount = eg.add({ op: Select, children: [cond, k2, k3] })
  let ushr = eg.add({ op: Ushr, children: [y, shift_amount] })
  inspect(eg.equiv(udiv, ushr), content="true")
}

///|
test "skeleton: udiv(y, select(cond, 2, 16)) = ushr(y, select(cond, 1, 4))" {
  let eg = EGraph::new()
  let y = eg.add_var(0)
  let cond = eg.add_var(1)
  let k2 = eg.add_const(2L) // 2^1
  let k16 = eg.add_const(16L) // 2^4
  let divisor = eg.add({ op: Select, children: [cond, k2, k16] })
  let udiv = eg.add({ op: Udiv, children: [y, divisor] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to ushr(y, select(cond, 1, 4))
  let k1 = eg.add_const(1L)
  let k4 = eg.add_const(4L)
  let shift_amount = eg.add({ op: Select, children: [cond, k1, k4] })
  let ushr = eg.add({ op: Ushr, children: [y, shift_amount] })
  inspect(eg.equiv(udiv, ushr), content="true")
}

///|
test "skeleton: udiv(y, select(cond, 1, 32)) = ushr(y, select(cond, 0, 5))" {
  let eg = EGraph::new()
  let y = eg.add_var(0)
  let cond = eg.add_var(1)
  let k1 = eg.add_const(1L) // 2^0
  let k32 = eg.add_const(32L) // 2^5
  let divisor = eg.add({ op: Select, children: [cond, k1, k32] })
  let udiv = eg.add({ op: Udiv, children: [y, divisor] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to ushr(y, select(cond, 0, 5))
  let k0 = eg.add_const(0L)
  let k5 = eg.add_const(5L)
  let shift_amount = eg.add({ op: Select, children: [cond, k0, k5] })
  let ushr = eg.add({ op: Ushr, children: [y, shift_amount] })
  inspect(eg.equiv(udiv, ushr), content="true")
}
