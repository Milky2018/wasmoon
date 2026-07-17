///|
test "AArch64 lowering selects scalar SSA and preserves source metadata" {
  let builder = @semantic.FunctionBuilder::new(
    "selected_add",
    Internal,
    [I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let sum = builder.emit_with_metadata(
      IntBinary(Add),
      parameters,
      [I64],
      @semantic.InstructionMetadata::new(
        Some(@semantic.SourceLocation::new("selected.wat", 3, 9)),
        [],
      ),
    )[0]
  builder.return_([sum])
  let selected = lower(builder.finish())
  inspect(
    selected.summary(),
    content=(
      #|vcode selected_add(v0:i64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IncomingReg(I64, p0:int) uses=[v0:fixed(p0:int)@early] defs=[v2:any@late]
      #|  i1 IncomingReg(I64, p1:int) uses=[v1:fixed(p1:int)@early] defs=[v3:any@late]
      #|  i2 IntBinary(W64, Add) uses=[v2:any@early, v3:any@early] defs=[v4:any@late] source={ file: "selected.wat", line: 3, column: 9 }
      #|  i3 OutgoingReg(I64, p0:int) uses=[v4:any@early]
      #|  i4 Return
      #|
    ),
  )
}

///|
test "AArch64 lowering rejects unsupported valid operations structurally" {
  let builder = @semantic.FunctionBuilder::new(
    "unsupported_float",
    Internal,
    [],
    [F32],
  )
  let value = builder.emit(F32Const(0x3F800000U), [], [F32])[0]
  builder.return_([value])
  try lower(builder.finish()) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(
          #|  block_index=0,
          #|  instruction_index=0,
          #|  operation=F32Const(1065353216),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected unsupported float selection to fail")
  }
}

///|
test "AArch64 lowering does not silently select non-trapping hardware divide" {
  let builder = @semantic.FunctionBuilder::new(
    "checked_divide",
    Internal,
    [I64, I64],
    [I64],
  )
  let value = builder.emit(IntBinary(SignedDiv), builder.parameters(), [I64])[0]
  builder.return_([value])
  try lower(builder.finish()) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(
          #|  block_index=0,
          #|  instruction_index=0,
          #|  operation=IntBinary(SignedDiv),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected unchecked hardware division selection to fail")
  }
}
