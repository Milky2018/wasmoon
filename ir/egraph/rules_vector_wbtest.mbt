// Vector optimization rules tests

///|
test "vector: band(splat(x), splat(y)) = splat(band(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let splat_y = eg.add({ op: Splat, children: [y] })
  let band = eg.add_and(splat_x, splat_y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(band(x, y))
  let inner_and = eg.add_and(x, y)
  let expected = eg.add({ op: Splat, children: [inner_and] })
  inspect(eg.equiv(band, expected), content="true")
}

///|
test "vector: bor(splat(x), splat(y)) = splat(bor(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let splat_y = eg.add({ op: Splat, children: [y] })
  let bor = eg.add_or(splat_x, splat_y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(bor(x, y))
  let inner_or = eg.add_or(x, y)
  let expected = eg.add({ op: Splat, children: [inner_or] })
  inspect(eg.equiv(bor, expected), content="true")
}

///|
test "vector: bxor(splat(x), splat(y)) = splat(bxor(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let splat_y = eg.add({ op: Splat, children: [y] })
  let bxor = eg.add_xor(splat_x, splat_y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(bxor(x, y))
  let inner_xor = eg.add_xor(x, y)
  let expected = eg.add({ op: Splat, children: [inner_xor] })
  inspect(eg.equiv(bxor, expected), content="true")
}

///|
test "vector: bnot(splat(x)) = splat(bnot(x))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let bnot = eg.add({ op: Bnot, children: [splat_x] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(bnot(x))
  let inner_bnot = eg.add({ op: Bnot, children: [x] })
  let expected = eg.add({ op: Splat, children: [inner_bnot] })
  inspect(eg.equiv(bnot, expected), content="true")
}

///|
test "vector: iadd(splat(x), splat(y)) = splat(iadd(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let splat_y = eg.add({ op: Splat, children: [y] })
  let iadd = eg.add_add(splat_x, splat_y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(iadd(x, y))
  let inner_add = eg.add_add(x, y)
  let expected = eg.add({ op: Splat, children: [inner_add] })
  inspect(eg.equiv(iadd, expected), content="true")
}

///|
test "vector: isub(splat(x), splat(y)) = splat(isub(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let splat_y = eg.add({ op: Splat, children: [y] })
  let isub = eg.add_sub(splat_x, splat_y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(isub(x, y))
  let inner_sub = eg.add_sub(x, y)
  let expected = eg.add({ op: Splat, children: [inner_sub] })
  inspect(eg.equiv(isub, expected), content="true")
}

///|
test "vector: imul(splat(x), splat(y)) = splat(imul(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let splat_y = eg.add({ op: Splat, children: [y] })
  let imul = eg.add_mul(splat_x, splat_y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(imul(x, y))
  let inner_mul = eg.add_mul(x, y)
  let expected = eg.add({ op: Splat, children: [inner_mul] })
  inspect(eg.equiv(imul, expected), content="true")
}

///|
test "vector: ineg(splat(x)) = splat(ineg(x))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let ineg = eg.add({ op: Neg, children: [splat_x] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(ineg(x))
  let inner_neg = eg.add({ op: Neg, children: [x] })
  let expected = eg.add({ op: Splat, children: [inner_neg] })
  inspect(eg.equiv(ineg, expected), content="true")
}

///|
test "vector: iabs(splat(x)) = splat(iabs(x))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let iabs = eg.add({ op: Iabs, children: [splat_x] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(iabs(x))
  let inner_iabs = eg.add({ op: Iabs, children: [x] })
  let expected = eg.add({ op: Splat, children: [inner_iabs] })
  inspect(eg.equiv(iabs, expected), content="true")
}

///|
test "vector: popcnt(splat(x)) = splat(popcnt(x))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let popcnt = eg.add({ op: Popcnt, children: [splat_x] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(popcnt(x))
  let inner_popcnt = eg.add({ op: Popcnt, children: [x] })
  let expected = eg.add({ op: Splat, children: [inner_popcnt] })
  inspect(eg.equiv(popcnt, expected), content="true")
}

///|
test "vector: smin(splat(x), splat(y)) = splat(smin(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let splat_y = eg.add({ op: Splat, children: [y] })
  let smin = eg.add({ op: Smin, children: [splat_x, splat_y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(smin(x, y))
  let inner_smin = eg.add({ op: Smin, children: [x, y] })
  let expected = eg.add({ op: Splat, children: [inner_smin] })
  inspect(eg.equiv(smin, expected), content="true")
}

///|
test "vector: smax(splat(x), splat(y)) = splat(smax(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let splat_y = eg.add({ op: Splat, children: [y] })
  let smax = eg.add({ op: Smax, children: [splat_x, splat_y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(smax(x, y))
  let inner_smax = eg.add({ op: Smax, children: [x, y] })
  let expected = eg.add({ op: Splat, children: [inner_smax] })
  inspect(eg.equiv(smax, expected), content="true")
}

///|
test "vector: umin(splat(x), splat(y)) = splat(umin(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let splat_y = eg.add({ op: Splat, children: [y] })
  let umin = eg.add({ op: Umin, children: [splat_x, splat_y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(umin(x, y))
  let inner_umin = eg.add({ op: Umin, children: [x, y] })
  let expected = eg.add({ op: Splat, children: [inner_umin] })
  inspect(eg.equiv(umin, expected), content="true")
}

///|
test "vector: umax(splat(x), splat(y)) = splat(umax(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let splat_y = eg.add({ op: Splat, children: [y] })
  let umax = eg.add({ op: Umax, children: [splat_x, splat_y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(umax(x, y))
  let inner_umax = eg.add({ op: Umax, children: [x, y] })
  let expected = eg.add({ op: Splat, children: [inner_umax] })
  inspect(eg.equiv(umax, expected), content="true")
}

///|
test "vector: ishl(splat(x), y) = splat(ishl(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let ishl = eg.add_shl(splat_x, y)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(ishl(x, y))
  let inner_shl = eg.add_shl(x, y)
  let expected = eg.add({ op: Splat, children: [inner_shl] })
  inspect(eg.equiv(ishl, expected), content="true")
}

///|
test "vector: ushr(splat(x), y) = splat(ushr(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let ushr = eg.add({ op: Ushr, children: [splat_x, y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(ushr(x, y))
  let inner_ushr = eg.add({ op: Ushr, children: [x, y] })
  let expected = eg.add({ op: Splat, children: [inner_ushr] })
  inspect(eg.equiv(ushr, expected), content="true")
}

///|
test "vector: sshr(splat(x), y) = splat(sshr(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let sshr = eg.add({ op: Sshr, children: [splat_x, y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(sshr(x, y))
  let inner_sshr = eg.add({ op: Sshr, children: [x, y] })
  let expected = eg.add({ op: Splat, children: [inner_sshr] })
  inspect(eg.equiv(sshr, expected), content="true")
}

///|
test "vector: rotl(splat(x), y) = splat(rotl(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let rotl = eg.add({ op: Rotl, children: [splat_x, y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(rotl(x, y))
  let inner_rotl = eg.add({ op: Rotl, children: [x, y] })
  let expected = eg.add({ op: Splat, children: [inner_rotl] })
  inspect(eg.equiv(rotl, expected), content="true")
}

///|
test "vector: rotr(splat(x), y) = splat(rotr(x, y))" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let splat_x = eg.add({ op: Splat, children: [x] })
  let rotr = eg.add({ op: Rotr, children: [splat_x, y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to splat(rotr(x, y))
  let inner_rotr = eg.add({ op: Rotr, children: [x, y] })
  let expected = eg.add({ op: Splat, children: [inner_rotr] })
  inspect(eg.equiv(rotr, expected), content="true")
}
