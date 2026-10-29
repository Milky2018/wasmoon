///|
test "AArch64 low-bit shifts independently validate fields and operand widths" {
  for width in [32, 64] {
    for
      (field_bits, amount, wrong_type) in [
        (1, 0, false),
        (1, width - 1, false),
        (width, 0, false),
        (0, 0, false),
        (-1, 0, false),
        (width + 1, 0, false),
        (1, -1, false),
        (1, width, false),
        (width, 1, false),
        (8, 1, true),
      ] {
      let rejected = wrong_type ||
        field_bits <= 0 ||
        field_bits > width ||
        amount < 0 ||
        amount > width - field_bits
      let ty : @native.ValueType = if (width == 32) != wrong_type {
        I32
      } else {
        I64
      }
      let builder : @vcode.Builder[@aarch64_target.AArch64Inst] = @vcode.Builder::new(
        "invalid_low_bit_shift",
        [ty],
      )
      builder.append_body(
        builder.entry_block(),
        IntLowBitsShiftLeft(
          if width == 32 {
            W32
          } else {
            W64
          },
          field_bits,
          amount,
        ),
        [@vcode.Input::any(builder.parameter(0))],
        [@vcode.Output::any(ty)],
        [],
        @vcode.InstructionMetadata::empty(),
      )
      |> ignore
      builder.set_terminator(
        builder.entry_block(),
        Return,
        [],
        [],
        [],
        @vcode.InstructionMetadata::empty(),
      )
      |> ignore
      try @aarch64_target.verify_vcode(builder.finish()) catch {
        InvalidInstruction(..) => assert_true(rejected)
        error => fail("unexpected target verifier failure: \{error}")
      } noraise {
        _ => assert_false(rejected)
      }
    }
  }
}
