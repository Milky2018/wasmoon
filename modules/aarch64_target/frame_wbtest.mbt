///|
test "AArch64 frame rejects conflicting target stack-object descriptors" {
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new(
    "overlapping_stack_objects",
    [],
  )
  let block = builder.entry_block()
  builder.append_body(
    block,
    StackAddress(AArch64StackObject::new(0, 16, 8)),
    [],
    [@vcode.Output::any(Ptr64)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.append_body(
    block,
    StackAddress(AArch64StackObject::new(0, 8, 8)),
    [],
    [@vcode.Output::any(Ptr64)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  builder.set_terminator(
    block,
    Return,
    [],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  verify_vcode(function)
  let allocation = allocate(function)
  try plan_frame(function, allocation) |> ignore catch {
    error =>
      inspect(
        error,
        content="InvalidStackObjectArea(message=\"stack-object id has conflicting size or alignment\")",
      )
  } noraise {
    _ => fail("expected conflicting target stack objects to be rejected")
  }
}
