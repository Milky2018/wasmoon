// Spaceship optimization rules tests

///|
test "spaceship: (a <=>_s b) == 0 → a == b" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let b = eg.add_var(1)
  let zero = eg.add_const(0L)
  let spaceship = eg.add({ op: SpaceshipS, children: [a, b] })
  let cmp = eg.add({ op: Eq, children: [spaceship, zero] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to a == b
  let eq = eg.add({ op: Eq, children: [a, b] })
  inspect(eg.equiv(cmp, eq), content="true")
}

///|
test "spaceship: (a <=>_u b) == 0 → a == b" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let b = eg.add_var(1)
  let zero = eg.add_const(0L)
  let spaceship = eg.add({ op: SpaceshipU, children: [a, b] })
  let cmp = eg.add({ op: Eq, children: [spaceship, zero] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to a == b
  let eq = eg.add({ op: Eq, children: [a, b] })
  inspect(eg.equiv(cmp, eq), content="true")
}

///|
test "spaceship: (a <=>_s b) != 0 → a != b" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let b = eg.add_var(1)
  let zero = eg.add_const(0L)
  let spaceship = eg.add({ op: SpaceshipS, children: [a, b] })
  let cmp = eg.add({ op: Ne, children: [spaceship, zero] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to a != b
  let ne = eg.add({ op: Ne, children: [a, b] })
  inspect(eg.equiv(cmp, ne), content="true")
}

///|
test "spaceship: (a <=>_s b) <_s 0 → a <_s b" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let b = eg.add_var(1)
  let zero = eg.add_const(0L)
  let spaceship = eg.add({ op: SpaceshipS, children: [a, b] })
  let cmp = eg.add({ op: Icmp(CC_SLT), children: [spaceship, zero] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to a <_s b
  let slt = eg.add({ op: Icmp(CC_SLT), children: [a, b] })
  inspect(eg.equiv(cmp, slt), content="true")
}

///|
test "spaceship: (a <=>_u b) <_s 0 → a <_u b" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let b = eg.add_var(1)
  let zero = eg.add_const(0L)
  let spaceship = eg.add({ op: SpaceshipU, children: [a, b] })
  let cmp = eg.add({ op: Icmp(CC_SLT), children: [spaceship, zero] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to a <_u b
  let ult = eg.add({ op: Icmp(CC_ULT), children: [a, b] })
  inspect(eg.equiv(cmp, ult), content="true")
}

///|
test "spaceship: (a <=>_s b) >_s 0 → a >_s b" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let b = eg.add_var(1)
  let zero = eg.add_const(0L)
  let spaceship = eg.add({ op: SpaceshipS, children: [a, b] })
  let cmp = eg.add({ op: Icmp(CC_SGT), children: [spaceship, zero] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to a >_s b
  let sgt = eg.add({ op: Icmp(CC_SGT), children: [a, b] })
  inspect(eg.equiv(cmp, sgt), content="true")
}

///|
test "spaceship: (a <=>_u b) >_s 0 → a >_u b" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let b = eg.add_var(1)
  let zero = eg.add_const(0L)
  let spaceship = eg.add({ op: SpaceshipU, children: [a, b] })
  let cmp = eg.add({ op: Icmp(CC_SGT), children: [spaceship, zero] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to a >_u b
  let ugt = eg.add({ op: Icmp(CC_UGT), children: [a, b] })
  inspect(eg.equiv(cmp, ugt), content="true")
}

///|
test "spaceship: (a <=>_s b) <=_s 0 → a <=_s b" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let b = eg.add_var(1)
  let zero = eg.add_const(0L)
  let spaceship = eg.add({ op: SpaceshipS, children: [a, b] })
  let cmp = eg.add({ op: Icmp(CC_SLE), children: [spaceship, zero] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to a <=_s b
  let sle = eg.add({ op: Icmp(CC_SLE), children: [a, b] })
  inspect(eg.equiv(cmp, sle), content="true")
}

///|
test "spaceship: (a <=>_s b) >=_s 0 → a >=_s b" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let b = eg.add_var(1)
  let zero = eg.add_const(0L)
  let spaceship = eg.add({ op: SpaceshipS, children: [a, b] })
  let cmp = eg.add({ op: Icmp(CC_SGE), children: [spaceship, zero] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to a >=_s b
  let sge = eg.add({ op: Icmp(CC_SGE), children: [a, b] })
  inspect(eg.equiv(cmp, sge), content="true")
}

///|
test "spaceship: (a <=>_s b) == -1 → a <_s b" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let b = eg.add_var(1)
  let neg_one = eg.add_const(-1L)
  let spaceship = eg.add({ op: SpaceshipS, children: [a, b] })
  let cmp = eg.add({ op: Eq, children: [spaceship, neg_one] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to a <_s b
  let slt = eg.add({ op: Icmp(CC_SLT), children: [a, b] })
  inspect(eg.equiv(cmp, slt), content="true")
}

///|
test "spaceship: (a <=>_s b) == 1 → a >_s b" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let b = eg.add_var(1)
  let one = eg.add_const(1L)
  let spaceship = eg.add({ op: SpaceshipS, children: [a, b] })
  let cmp = eg.add({ op: Eq, children: [spaceship, one] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to a >_s b
  let sgt = eg.add({ op: Icmp(CC_SGT), children: [a, b] })
  inspect(eg.equiv(cmp, sgt), content="true")
}

///|
test "spaceship: (a <=>_s b) != -1 → a >=_s b" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let b = eg.add_var(1)
  let neg_one = eg.add_const(-1L)
  let spaceship = eg.add({ op: SpaceshipS, children: [a, b] })
  let cmp = eg.add({ op: Ne, children: [spaceship, neg_one] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to a >=_s b
  let sge = eg.add({ op: Icmp(CC_SGE), children: [a, b] })
  inspect(eg.equiv(cmp, sge), content="true")
}

///|
test "spaceship: (a <=>_s b) != 1 → a <=_s b" {
  let eg = EGraph::new()
  let a = eg.add_var(0)
  let b = eg.add_var(1)
  let one = eg.add_const(1L)
  let spaceship = eg.add({ op: SpaceshipS, children: [a, b] })
  let cmp = eg.add({ op: Ne, children: [spaceship, one] })
  eg.saturate_indexed(standard_rules_indexed(), 10) |> ignore
  // Should be equivalent to a <=_s b
  let sle = eg.add({ op: Icmp(CC_SLE), children: [a, b] })
  inspect(eg.equiv(cmp, sle), content="true")
}
