///|
test "x64 scalar fused operations retain product and addend signs" {
  let abi = @x64_target.InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let operations : Array[(@lowering.FloatTernaryOp, Byte)] = [
    (FusedMultiplyAdd, 0xA9),
    (FusedNegatedMultiplyAdd, 0xAD),
    (FusedMultiplySubtract, 0xAB),
    (FusedNegatedMultiplySubtract, 0xAF),
  ]
  let types : Array[@native.ValueType] = [F32, F64]
  for ty in types {
    for (operation, expected_opcode) in operations {
      let session = @x64_target.DirectLoweringSession::new(
        "scalar_fused_signs",
        Platform,
        [ty, ty, ty],
        [ty],
        @x64_target.LoweringContext::new(abi),
      )
      let builder = @lowering.DirectBuilder::new([ty, ty, ty], session.sink())
      let result = builder.emit_with_metadata(
        FloatTernary(operation),
        builder.parameters(),
        [ty],
        @lowering.InstructionMetadata::empty(),
      )
      builder.return_(result)
      builder.finish()
      let (object, _) = @x64_target.compile_selected(session.finish_selected())
      let code = object.code()
      let fused_opcodes : Array[Byte] = []
      for i in 0..<(code.length() - 4) {
        if code[i] == 0xC4 && (code[i + 1] & 0x1F) == 0x02 {
          fused_opcodes.push(code[i + 3])
        }
      }
      assert_eq(fused_opcodes, [expected_opcode])
    }
  }
}
