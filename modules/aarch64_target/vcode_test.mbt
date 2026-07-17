///|
test "AArch64 owns a statically typed Target VCode checkpoint" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new_with_results(
    "a64_add",
    [I64, I64],
    [I64],
  )
  let entry = builder.entry_block()
  let (_, result) = builder.append_body(
    entry,
    IntBinary(W64, Add),
    [
      @vcode.Input::any(builder.parameter(0)),
      @vcode.Input::any(builder.parameter(1)),
    ],
    [@vcode.Output::any(I64)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  builder.append_body(
    entry,
    OutgoingReg(I64, @vcode.PhysicalReg::new(0, Int)),
    [@vcode.Input::any(result[0])],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  verify_vcode(function)
  inspect(
    function.summary(),
    content=(
      #|vcode a64_add(v0:i64, v1:i64) -> (i64)
      #|block0:
      #|  i0 IntBinary(W64, Add) uses=[v0:any@early, v1:any@early] defs=[v2:any@late]
      #|  i1 OutgoingReg(I64, p0:int) uses=[v2:any@early]
      #|  i2 Return
      #|
    ),
  )
}

///|
test "AArch64 verifier rejects an invalid 32-bit constant" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new("bad_const", [])
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    LoadConstant(W32, 0x100000000UL),
    [],
    [@vcode.Output::any(I32)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    entry,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  verify_vcode(builder.finish()) catch {
    error =>
      inspect(
        error,
        content=(
          #|InvalidInstruction(
          #|  instruction=i0,
          #|  message="32-bit constant has non-zero high bits",
          #|)
        ),
      )
  }
}
