// Select optimization rules tests

///|
test "select: select(_, x, x) = x" {
  let eg = EGraph::new()
  let cond = eg.add_var(0)
  let x = eg.add_var(1)
  let select = eg.add({ op: Select, children: [cond, x, x] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(select, x), content="true")
}

///|
test "select: select(icmp, 1, 0) = icmp" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let one = eg.add_const(1L)
  let zero = eg.add_const(0L)
  let cmp = eg.add({ op: Icmp(CC_SLT), children: [x, y] })
  let select = eg.add({ op: Select, children: [cmp, one, zero] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(select, cmp), content="true")
}

///|
test "select: select(sgt(x, y), x, y) = smax(x, y)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let cmp = eg.add({ op: Icmp(CC_SGT), children: [x, y] })
  let select = eg.add({ op: Select, children: [cmp, x, y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Check that Smax node exists in the class
  let mut has_smax = false
  for node in eg.get_nodes(select) {
    if node.op is Smax {
      has_smax = true
    }
  }
  inspect(has_smax, content="true")
}

///|
test "select: select(slt(x, y), x, y) = smin(x, y)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let cmp = eg.add({ op: Icmp(CC_SLT), children: [x, y] })
  let select = eg.add({ op: Select, children: [cmp, x, y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Check that Smin node exists in the class
  let mut has_smin = false
  for node in eg.get_nodes(select) {
    if node.op is Smin {
      has_smin = true
    }
  }
  inspect(has_smin, content="true")
}

///|
test "select: select(ugt(x, y), x, y) = umax(x, y)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let cmp = eg.add({ op: Icmp(CC_UGT), children: [x, y] })
  let select = eg.add({ op: Select, children: [cmp, x, y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Check that Umax node exists in the class
  let mut has_umax = false
  for node in eg.get_nodes(select) {
    if node.op is Umax {
      has_umax = true
    }
  }
  inspect(has_umax, content="true")
}

///|
test "select: select(ult(x, y), x, y) = umin(x, y)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let cmp = eg.add({ op: Icmp(CC_ULT), children: [x, y] })
  let select = eg.add({ op: Select, children: [cmp, x, y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Check that Umin node exists in the class
  let mut has_umin = false
  for node in eg.get_nodes(select) {
    if node.op is Umin {
      has_umin = true
    }
  }
  inspect(has_umin, content="true")
}

///|
test "select: select(slt(x, y), y, x) = smax(x, y) (swapped)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let cmp = eg.add({ op: Icmp(CC_SLT), children: [x, y] })
  // Note: select branches are swapped: (cond, y, x) instead of (cond, x, y)
  let select = eg.add({ op: Select, children: [cmp, y, x] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Check that Smax node exists in the class
  let mut has_smax = false
  for node in eg.get_nodes(select) {
    if node.op is Smax {
      has_smax = true
    }
  }
  inspect(has_smax, content="true")
}

///|
test "select: select(sgt(x, y), y, x) = smin(x, y) (swapped)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let cmp = eg.add({ op: Icmp(CC_SGT), children: [x, y] })
  // Note: select branches are swapped: (cond, y, x) instead of (cond, x, y)
  let select = eg.add({ op: Select, children: [cmp, y, x] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Check that Smin node exists in the class
  let mut has_smin = false
  for node in eg.get_nodes(select) {
    if node.op is Smin {
      has_smin = true
    }
  }
  inspect(has_smin, content="true")
}

///|
test "select: select(sgt(x, 0), x, -x) = iabs(x)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let neg_x = eg.add({ op: Neg, children: [x] })
  let cmp = eg.add({ op: Icmp(CC_SGT), children: [x, zero] })
  let select = eg.add({ op: Select, children: [cmp, x, neg_x] })
  let iabs = eg.add({ op: Iabs, children: [x] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(select, iabs), content="true")
}

///|
test "select: select(slt(x, 0), -x, x) = iabs(x)" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let zero = eg.add_const(0L)
  let neg_x = eg.add({ op: Neg, children: [x] })
  let cmp = eg.add({ op: Icmp(CC_SLT), children: [x, zero] })
  let select = eg.add({ op: Select, children: [cmp, neg_x, x] })
  let iabs = eg.add({ op: Iabs, children: [x] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(select, iabs), content="true")
}

///|
test "select: sgt(smin(x, y), x) = 0" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let smin = eg.add({ op: Smin, children: [x, y] })
  let cmp = eg.add({ op: Icmp(CC_SGT), children: [smin, x] })
  let zero = eg.add_const(0L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(cmp, zero), content="true")
}

///|
test "select: slt(x, smin(x, y)) = 0" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let smin = eg.add({ op: Smin, children: [x, y] })
  let cmp = eg.add({ op: Icmp(CC_SLT), children: [x, smin] })
  let zero = eg.add_const(0L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(cmp, zero), content="true")
}

///|
test "select: ugt(umin(x, y), x) = 0" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let umin = eg.add({ op: Umin, children: [x, y] })
  let cmp = eg.add({ op: Icmp(CC_UGT), children: [umin, x] })
  let zero = eg.add_const(0L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(cmp, zero), content="true")
}

///|
test "select: ult(x, umin(x, y)) = 0" {
  let eg = EGraph::new()
  let x = eg.add_var(0)
  let y = eg.add_var(1)
  let umin = eg.add({ op: Umin, children: [x, y] })
  let cmp = eg.add({ op: Icmp(CC_ULT), children: [x, umin] })
  let zero = eg.add_const(0L)
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(cmp, zero), content="true")
}

///|
test "select: select(d, a, select(d, _, y)) = select(d, a, y)" {
  let eg = EGraph::new()
  let d = eg.add_var(0)
  let a = eg.add_var(1)
  let b = eg.add_var(2)
  let y = eg.add_var(3)
  let inner = eg.add({ op: Select, children: [d, b, y] })
  let outer = eg.add({ op: Select, children: [d, a, inner] })
  let expected = eg.add({ op: Select, children: [d, a, y] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(outer, expected), content="true")
}

///|
test "select: select(d, select(d, x, _), a) = select(d, x, a)" {
  let eg = EGraph::new()
  let d = eg.add_var(0)
  let x = eg.add_var(1)
  let b = eg.add_var(2)
  let a = eg.add_var(3)
  let inner = eg.add({ op: Select, children: [d, x, b] })
  let outer = eg.add({ op: Select, children: [d, inner, a] })
  let expected = eg.add({ op: Select, children: [d, x, a] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(outer, expected), content="true")
}

///|
test "select: iadd(select(c, 1, 2), 5) = select(c, 6, 7)" {
  let eg = EGraph::new()
  let c = eg.add_var(0)
  let k1 = eg.add_const(1L)
  let k2 = eg.add_const(2L)
  let k5 = eg.add_const(5L)
  let k6 = eg.add_const(6L)
  let k7 = eg.add_const(7L)
  let sel = eg.add({ op: Select, children: [c, k1, k2] })
  let result = eg.add({ op: Add, children: [sel, k5] })
  let expected = eg.add({ op: Select, children: [c, k6, k7] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  inspect(eg.equiv(result, expected), content="true")
}
