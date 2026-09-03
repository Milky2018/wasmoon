///|
test "AArch64 rejects an internal ABI that reuses the context register" {
  try
    InternalAbi::new(0, 8, [0, 1, 2], [0, 1], [0, 1], [0, 1]) |> ignore
  catch {
    error => inspect(error, content="ContextRegisterReused(index=0)")
  } noraise {
    _ => fail("expected the internal ABI contract to be rejected")
  }
}

///|
test "AArch64 reserves the internal result-area register" {
  try InternalAbi::new(0, 1, [1, 2], [0, 1], [0, 1], [0, 1]) |> ignore catch {
    error => inspect(error, content="ResultAreaRegisterReused(index=1)")
  } noraise {
    _ => fail("expected the result-area ABI register to be reserved")
  }
}

///|
test "AArch64 trusted direct selection skips redundant VCode validation" {
  let abi = InternalAbi::new(
    0,
    8,
    [1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let saw_validation = Ref(false)
  let session = DirectLoweringSession::new(
    "trusted",
    Internal,
    [Ptr64],
    [],
    LoweringContext::new(abi),
    on_event=fn(event) {
      if event is TargetValidationStarted {
        saw_validation.val = true
      }
    },
  )
  let builder = @lowering.DirectBuilder::new([Ptr64], session.sink())
  builder.return_([])
  builder.finish()
  session.finish_selected(verify_selected=false) |> ignore
  inspect(saw_validation.val, content="false")
}

///|
test "AArch64 direct selection erases raw-word pointer bitcasts" {
  let abi = InternalAbi::new(
    0,
    8,
    [1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let session = DirectLoweringSession::new(
    "raw_word_alias",
    Internal,
    [Ptr64, I64],
    [I64],
    LoweringContext::new(abi),
  )
  let builder = @lowering.DirectBuilder::new([Ptr64, I64], session.sink())
  let pointer = builder.emit_with_metadata(
      Convert(Bitcast(I64, Ptr64)),
      [builder.parameters()[1]],
      [Ptr64],
      @lowering.InstructionMetadata::empty(),
    )[0]
  let offset = builder.emit_with_metadata(
      I64Const(8UL),
      [],
      [I64],
      @lowering.InstructionMetadata::empty(),
    )[0]
  let adjusted = builder.emit_with_metadata(
      PointerOffset,
      [pointer, offset],
      [Ptr64],
      @lowering.InstructionMetadata::empty(),
    )[0]
  let bits = builder.emit_with_metadata(
      Convert(Bitcast(Ptr64, I64)),
      [adjusted],
      [I64],
      @lowering.InstructionMetadata::empty(),
    )[0]
  builder.return_([bits])
  builder.finish()
  session.finish_selected() |> ignore
}
