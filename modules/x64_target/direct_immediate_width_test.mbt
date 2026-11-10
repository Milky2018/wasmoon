///|
test "x64 integer immediates wrap at their operand width" {
  let abi = @x64_target.InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  for
    operation in [
      @lowering.Operation::IntBinaryImmediate(Add, 0xFFFFFFFFFFFFFFFFUL),
      IntBinaryImmediate(And, 0xFFFFFFFFFFFFFFF0UL),
      IntBinaryImmediate(Mul, 0x100000002UL),
      IntCompareImmediate(Equal, 0xFFFFFFFFFFFFFFFFUL),
    ] {
    let session = @x64_target.DirectLoweringSession::new(
      "word_immediate",
      Internal,
      [Ptr64, I32],
      [I32],
      @x64_target.LoweringContext::new(abi),
    )
    let builder = @lowering.DirectBuilder::new([Ptr64, I32], session.sink())
    let result = builder.emit_with_metadata(
        operation,
        [builder.parameters()[1]],
        [I32],
        @lowering.InstructionMetadata::empty(),
      )[0]
    let yes = builder.create_block([])
    let no = builder.create_block([])
    builder.branch_int_compare_immediate(
      Equal,
      builder.parameters()[1],
      0xFFFFFFFFFFFFFFFFUL,
      yes,
      [],
      no,
      [],
    )
    builder.switch_to_block(yes)
    builder.return_([result])
    builder.switch_to_block(no)
    builder.return_([result])
    builder.finish()
    session.finish_selected() |> ignore
  }
}
