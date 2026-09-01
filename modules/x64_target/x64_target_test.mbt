///|
test "x64 trusted direct selection skips redundant VCode validation" {
  let abi = InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
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
