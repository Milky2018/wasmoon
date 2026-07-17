///|
test "AArch64 owns a statically typed Target VCode checkpoint" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new("a64_add", [
    I64,
    I64,
  ])
  let entry = builder.entry_block()
  let (_, result) = builder.append_body(
    entry,
    Add64,
    [
      @vcode.Input::any(builder.parameter(0)),
      @vcode.Input::any(builder.parameter(1)),
    ],
    [@vcode.Output::any(I64)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  builder.set_terminator(
    entry,
    Return,
    [@vcode.Input::any(result[0])],
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
      #|vcode a64_add(v0:i64, v1:i64)
      #|block0:
      #|  i0 Add64 uses=[v0:any@early, v1:any@early] defs=[v2:any@late]
      #|  i1 Return uses=[v2:any@early]
      #|
    ),
  )
}

///|
test "AArch64 verifier rejects an unencodable shifted operand" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new("bad_shift", [
    I64,
    I64,
  ])
  let entry = builder.entry_block()
  builder.append_body(
    entry,
    AddShifted64(64),
    [
      @vcode.Input::any(builder.parameter(0)),
      @vcode.Input::any(builder.parameter(1)),
    ],
    [@vcode.Output::any(I64)],
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
        content="InvalidInstruction(instruction=i0, message=\"shift must be in 0..<64\")",
      )
  }
}
