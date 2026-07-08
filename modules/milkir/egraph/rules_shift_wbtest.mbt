// Shift optimization rules tests

///|
test "shift: rotl(rotl(x, y), z) = rotl(x, y + z)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k3 = eg.add_const(3L)
  let k5 = eg.add_const(5L)
  let rotl_inner = eg.add({ op: Rotl, children: [x, k3] })
  let rotl_outer = eg.add({ op: Rotl, children: [rotl_inner, k5] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should combine to rotl(x, 8)
  let k8 = eg.add_const(8L)
  let expected = eg.add({ op: Rotl, children: [x, k8] })
  inspect(eg.equiv(rotl_outer, expected), content="true")
}

///|
test "shift: rotr(rotr(x, y), z) = rotr(x, y + z)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k2 = eg.add_const(2L)
  let k4 = eg.add_const(4L)
  let rotr_inner = eg.add({ op: Rotr, children: [x, k2] })
  let rotr_outer = eg.add({ op: Rotr, children: [rotr_inner, k4] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should combine to rotr(x, 6)
  let k6 = eg.add_const(6L)
  let expected = eg.add({ op: Rotr, children: [x, k6] })
  inspect(eg.equiv(rotr_outer, expected), content="true")
}

///|
test "shift: rotr(rotl(x, y), z) = rotl(x, y - z)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k10 = eg.add_const(10L)
  let k3 = eg.add_const(3L)
  let rotl_inner = eg.add({ op: Rotl, children: [x, k10] })
  let rotr_outer = eg.add({ op: Rotr, children: [rotl_inner, k3] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should combine to rotl(x, 7) or rotr(x, -7) which wraps
  let k7 = eg.add_const(7L)
  let expected = eg.add({ op: Rotl, children: [x, k7] })
  inspect(eg.equiv(rotr_outer, expected), content="true")
}

///|
test "shift: rotl(rotr(x, y), z) = rotr(x, y - z)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let k8 = eg.add_const(8L)
  let k5 = eg.add_const(5L)
  let rotr_inner = eg.add({ op: Rotr, children: [x, k8] })
  let rotl_outer = eg.add({ op: Rotl, children: [rotr_inner, k5] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should combine to rotr(x, 3)
  let k3 = eg.add_const(3L)
  let expected = eg.add({ op: Rotr, children: [x, k3] })
  inspect(eg.equiv(rotl_outer, expected), content="true")
}

///|
test "shift: ishl(x, uextend(y)) = ishl(x, y)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let y_extended = eg.add({ op: Uextend(32, 64), children: [y] })
  let shift = eg.add_shl(x, y_extended)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should simplify to ishl(x, y)
  let expected = eg.add_shl(x, y)
  inspect(eg.equiv(shift, expected), content="true")
}

///|
test "shift: ishl(x, sextend(y)) = ishl(x, y)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let y_extended = eg.add({ op: Sextend(32, 64), children: [y] })
  let shift = eg.add_shl(x, y_extended)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should simplify to ishl(x, y)
  let expected = eg.add_shl(x, y)
  inspect(eg.equiv(shift, expected), content="true")
}

///|
test "shift: ishl(x, ireduce(y)) = ishl(x, y)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let y_reduced = eg.add({ op: Ireduce(64, 32), children: [y] })
  let shift = eg.add_shl(x, y_reduced)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should simplify to ishl(x, y)
  let expected = eg.add_shl(x, y)
  inspect(eg.equiv(shift, expected), content="true")
}

///|
test "shift: ushr(x, uextend(y)) = ushr(x, y)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let y_extended = eg.add({ op: Uextend(32, 64), children: [y] })
  let shift = eg.add({ op: Ushr, children: [x, y_extended] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should simplify to ushr(x, y)
  let expected = eg.add({ op: Ushr, children: [x, y] })
  inspect(eg.equiv(shift, expected), content="true")
}

///|
test "shift: sshr(x, uextend(y)) = sshr(x, y)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let y_extended = eg.add({ op: Uextend(32, 64), children: [y] })
  let shift = eg.add({ op: Sshr, children: [x, y_extended] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should simplify to sshr(x, y)
  let expected = eg.add({ op: Sshr, children: [x, y] })
  inspect(eg.equiv(shift, expected), content="true")
}

///|
test "shift: rotl(x, uextend(y)) = rotl(x, y)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let y_extended = eg.add({ op: Uextend(32, 64), children: [y] })
  let rot = eg.add({ op: Rotl, children: [x, y_extended] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should simplify to rotl(x, y)
  let expected = eg.add({ op: Rotl, children: [x, y] })
  inspect(eg.equiv(rot, expected), content="true")
}

///|
test "shift: rotr(x, uextend(y)) = rotr(x, y)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let y_extended = eg.add({ op: Uextend(32, 64), children: [y] })
  let rot = eg.add({ op: Rotr, children: [x, y_extended] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should simplify to rotr(x, y)
  let expected = eg.add({ op: Rotr, children: [x, y] })
  inspect(eg.equiv(rot, expected), content="true")
}
