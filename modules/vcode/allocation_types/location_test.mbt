///|
test "packed allocation locations preserve register identity" {
  for
    reg in [
      @allocation_types.PhysicalReg::new(-7, Int),
      @allocation_types.PhysicalReg::new(3, Float),
      @allocation_types.PhysicalReg::new(11, Vector),
      @allocation_types.PhysicalReg::new(31, FpVector),
    ] {
    let location = @allocation_types.AllocationLocation::reg(reg)
    assert_true(location.is_register())
    assert_false(location.is_spill())
    assert_eq(location.register(), Some(reg))
    assert_eq(location.spill_index(), None)
  }
}

///|
test "packed allocation locations preserve spill identity and diagnostics" {
  let location = @allocation_types.AllocationLocation::spill(42)
  assert_false(location.is_register())
  assert_true(location.is_spill())
  assert_eq(location.register(), None)
  assert_eq(location.spill_index(), Some(42))
  inspect(Repr(location).to_string(), content="Spill(42)")
  inspect(
    Repr(
      @allocation_types.AllocationLocation::reg(
        @allocation_types.PhysicalReg::new(5, Int),
      ),
    ).to_string(),
    content="Reg(p5:int)",
  )
}
