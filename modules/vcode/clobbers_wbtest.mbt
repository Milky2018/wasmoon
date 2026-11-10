///|
test "repeated call clobbers grow storage geometrically and preserve instruction slices" {
  for unconstrained in [false, true] {
    let builder : Builder[Int32] = Builder::new("calls", [])
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

///|
test "clobber duplicate detection agrees with ordered equality for every register class" {
  fn reference(registers : Array[PhysicalReg]) -> PhysicalReg? {
    for index, reg in registers {
      for earlier in 0..<index {
        if registers[earlier] == reg {
          return Some(reg)
        }
      }
    }
    None
  }
  let classes = [RegClass::Int, Float, Vector, FpVector]
  let ids = [-1, 0, 1, 31, 63, 64, 2147483647]
  let unique : Array[PhysicalReg] = []
  for class in classes {
    for id in ids {
      unique.push(PhysicalReg::new(id, class))
    }
  }
  for class in classes {
    for id in ids {
      assert_eq(first_duplicate_clobber(unique[:]), None)
      for position in 0..<=unique.length() {
        let registers = unique.copy()
        registers.insert(position, PhysicalReg::new(id, class))
        assert_eq(first_duplicate_clobber(registers[:]), reference(registers))
      }
    }
  }
  let second = PhysicalReg::new(0, Float)
  let first = PhysicalReg::new(0, FpVector)
  assert_eq(
    first_duplicate_clobber([first, second, second, first][:]),
    Some(second),
  )
}
