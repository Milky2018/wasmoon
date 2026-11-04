///|
test "native low-bit shifts select one AArch64 operation and a verified x64 fallback" {
  for width in [32, 64] {
    let ty : @milkir.Type = if width == 32 { I32 } else { I64 }
    for
      (commuted, shared, sparse) in [
        (false, false, false),
        (true, false, false),
        (false, true, false),
        (false, false, true),
      ] {
      let builder = @milkir.FunctionBuilder("low_bit_selection")
      builder.add_param(Ptr) |> ignore
      let input = builder.add_param(ty)
      builder.add_result(ty)
      let one = if width == 32 {
        builder.iconst_i32(1)
      } else {
        builder.iconst_i64(1L)
      }
      let mask = if sparse {
        if width == 32 {
          builder.iconst_i32(0x55555554)
        } else {
          builder.iconst_i64(0x5555555455555554L)
        }
      } else if width == 32 {
        builder.iconst_i32(16382)
      } else {
        builder.iconst_i64(8589934590L)
      }
      let shifted = builder.ishl(input, one)
      let result = if commuted {
        builder.band(mask, shifted)
      } else {
        builder.band(shifted, mask)
      }
      if shared {
        builder.add_result(ty)
        builder.return_([result, shifted])
      } else {
        builder.return_([result])
      }
      for target in [@wasmoon_jit.NativeTarget::AArch64, X64] {
        let diagnostics = @wasmoon_jit.compile_wasm_body_diagnostics_for_target(
          builder.get_function(),
          @wasm_milkir.WasmValidationContext::empty(),
          target,
        )
        if target == AArch64 {
          assert_eq(
            diagnostics.target_vcode.contains("IntLowBitsShiftLeft"),
            !shared && !sparse,
          )
        }
      }
    }
  }
}
