///|
test "both target selectors verify shared sibling constants without an environment gate" {
  for bits in [42, 65537, 2147483647] {
    let builder = @milkir.FunctionBuilder::FunctionBuilder("shared_siblings")
    builder.add_param(Ptr) |> ignore
    let input = builder.add_param(I32)
    let choose = builder.add_param(I32)
    builder.add_result(I32)
    let left = builder.create_block()
    let right = builder.create_block()
    let join = builder.create_block()
    let result = builder.add_block_param(join, I32)
    let constant = builder.iconst_i32(bits)
    builder.brnz(choose, left, right)
    builder.switch_to_block(left)
    let first = builder.icmp_slt(input, constant)
    builder.jump(join, [first])
    builder.switch_to_block(right)
    let second = builder.icmp_slt(input, constant)
    builder.jump(join, [second])
    builder.switch_to_block(join)
    builder.return_([result])
    let function = builder.finalize()
    let x64 = @x64_target.DirectLoweringSession::new(
      "shared_siblings",
      Internal,
      [Ptr64, I32, I32],
      [I32],
      @x64_target.LoweringContext::new(
        @x64_target.InternalAbi::new(
          7,
          12,
          [6, 2, 1, 8, 9],
          [0, 1, 2, 3, 4, 5, 6, 7],
          [0, 2, 1, 8, 9, 6, 7, 10],
          [0, 1, 2, 3, 4, 5, 6, 7],
        ),
      ),
    )
    @milkir_native.lower_core_to_sink(function, x64.sink())
    x64.finish_selected() |> ignore
    let arm = @aarch64_target.DirectLoweringSession::new(
      "shared_siblings",
      Internal,
      [Ptr64, I32, I32],
      [I32],
      @aarch64_target.LoweringContext::new(
        @aarch64_target.InternalAbi::new(
          0,
          8,
          [1, 2, 3, 4, 5, 6, 7],
          [0, 1, 2, 3, 4, 5, 6, 7],
          [0, 1, 2, 3, 4, 5, 6, 7],
          [0, 1, 2, 3, 4, 5, 6, 7],
        ),
      ),
    )
    @milkir_native.lower_core_to_sink(function, arm.sink())
    arm.finish_selected() |> ignore
  }
}
