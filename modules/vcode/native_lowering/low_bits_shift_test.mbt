///|
test "low-bit shift contracts reject invalid fields and types" {
  for width in [32, 64] {
    let ty : @native.ValueType = if width == 32 { I32 } else { I64 }
    for
      (field_bits, amount) in [
        (1, 0),
        (1, width - 1),
        (width, 0),
        (width - 1, 1),
      ] {
      assert_true(
        @native_lowering.verify_operation_contract(
          IntLowBitsShiftLeft(field_bits, amount),
          [ty],
          [ty],
        )
        is None,
      )
    }
    for
      (field_bits, amount) in [
        (0, 0),
        (-1, 0),
        (width + 1, 0),
        (1, -1),
        (1, width),
        (width, 1),
      ] {
      assert_true(
        @native_lowering.verify_operation_contract(
          IntLowBitsShiftLeft(field_bits, amount),
          [ty],
          [ty],
        )
        is Some(_),
      )
    }
  }
  let invalid_types : Array[
    (Array[@native.ValueType], Array[@native.ValueType]),
  ] = [
    ([I32], [I64]),
    ([I64], [I32]),
    ([Ptr64], [Ptr64]),
    ([F32], [F32]),
    ([I64, I64], [I64]),
    ([I64], []),
  ]
  for (inputs, outputs) in invalid_types {
    assert_true(
      @native_lowering.verify_operation_contract(
        IntLowBitsShiftLeft(8, 1),
        inputs,
        outputs,
      )
      is Some(_),
    )
  }
}
