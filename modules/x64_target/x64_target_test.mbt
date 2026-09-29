///|
test "x64 trusted direct selection skips redundant VCode validation" {
  let abi = @x64_target.InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let saw_validation = Ref(false)
  let session = @x64_target.DirectLoweringSession::new(
    "trusted",
    Internal,
    [Ptr64],
    [],
    @x64_target.LoweringContext::new(abi),
    on_event=fn(event) {
      if event is TargetValidationStarted {
        saw_validation.val = true
      }
    },
  )
  let sink = session.sink()
  inspect(sink.folds_unsigned_index_into_memory(), content="false")
  let builder = @lowering.DirectBuilder::new([Ptr64], sink)
  builder.return_([])
  builder.finish()
  session.finish_selected(verify_selected=false) |> ignore
  inspect(saw_validation.val, content="false")
}

///|
test "x64 direct selection erases raw-word pointer bitcasts" {
  let abi = @x64_target.InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let session = @x64_target.DirectLoweringSession::new(
    "raw_word_alias",
    Internal,
    [Ptr64, I64],
    [I64],
    @x64_target.LoweringContext::new(abi),
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

///|
test "x64 explicit immediate comparison retains semantic fallback" {
  let abi = @x64_target.InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )

  let session = @x64_target.DirectLoweringSession::new(
    "compare_fallback",
    Internal,
    [Ptr64, I64],
    [I32],
    @x64_target.LoweringContext::new(abi),
  )
  let sink = session.sink()
  inspect(sink.supports_int_compare_immediate(I64, 42UL), content="false")
  let builder = @lowering.DirectBuilder::new([Ptr64, I64], sink)
  let result = builder.emit_with_metadata(
      IntCompareImmediate(Equal, 42UL),
      [builder.parameters()[1]],
      [I32],
      @lowering.InstructionMetadata::empty(),
    )[0]
  builder.return_([result])
  builder.finish()
  let diagnostics = @x64_target.diagnose_selected(session.finish_selected())
  inspect(diagnostics.target_vcode.contains("LoadConstant"), content="true")
  inspect(diagnostics.target_vcode.contains("CompareSet"), content="true")
}
