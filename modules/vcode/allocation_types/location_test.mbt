///|
test "packed allocation locations preserve register identity" {
  for
    reg in [
      PhysicalReg::new(-7, Int),
      PhysicalReg::new(3, Float),
      PhysicalReg::new(11, Vector),
      PhysicalReg::new(31, FpVector),
    ] {
    let location = AllocationLocation::reg(reg)
    assert_true(location.is_register())
    assert_false(location.is_spill())
    assert_eq(location.register(), Some(reg))
    assert_eq(location.spill_index(), None)
  }
}

///|
test "packed allocation locations preserve spill identity and diagnostics" {
  let location = AllocationLocation::spill(42)
  assert_false(location.is_register())
  assert_true(location.is_spill())
  assert_eq(location.register(), None)
  assert_eq(location.spill_index(), Some(42))
  inspect(Repr(location).to_string(), content="Spill(42)")
  inspect(
    Repr(AllocationLocation::reg(PhysicalReg::new(5, Int))).to_string(),
    content="Reg(p5:int)",
  )
}
