///|
test "repeated call clobbers grow storage geometrically and preserve instruction slices" {
  for unconstrained in [false, true] {
    let builder : Builder[Int] = Builder::new("calls", [])
    let entry = builder.entry_block()
    let clobbers = [PhysicalReg::new(0, Int), PhysicalReg::new(1, Int)]
    let mut growths = 0
    for index in 0..<256 {
      let previous = builder.function.clobbers.capacity()
      if unconstrained {
        builder.commit_unconstrained_body(
          entry,
          index,
          [],
          [],
          clobbers,
          InstructionMetadata::empty(),
        )
        |> ignore
      } else {
        builder.append_body(
          entry,
          index,
          [],
          [],
          clobbers,
          InstructionMetadata::empty(),
        )
        |> ignore
      }
      if builder.function.clobbers.capacity() != previous {
        growths += 1
      }
      let data = builder.function.instructions[index]
      assert_eq(data.clobber_start, index * 2)
      assert_eq(data.clobber_count, 2)
    }
    assert_eq(builder.function.clobbers.length(), 512)
    for index, reg in builder.function.clobbers {
      assert_eq(reg, clobbers[index % 2])
    }
    // Exact-sized growth once per call copies a quadratic number of registers.
    assert_true(growths <= 16)
  }
}
