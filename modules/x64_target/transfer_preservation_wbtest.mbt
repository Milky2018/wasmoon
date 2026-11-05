///|
test "frames preserve the callee-saved temporary used by late parallel moves" {
  let abi = InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  )
  let params : Array[@native.ValueType] = [Ptr64] +
    Array::make(9, F64) +
    Array::make(10, I64)
  let results : Array[@native.ValueType] = Array::make(10, I64) +
    Array::make(9, F64)
  let session = DirectLoweringSession::new(
    "reverse_mixed_results",
    Internal,
    params,
    results,
    LoweringContext::new(abi),
  )
  let builder = @lowering.DirectBuilder::new(params, session.sink())
  let args = builder.parameters()
  builder.return_(Array::makei(19, i => args[19 - i]))
  builder.finish()
  let function = session.finish_selected().constructed.function
  let allocation = allocate(function)
  let frame = plan_frame(function, allocation)
  assert_true(
    frame.saved_registers().any(saved => saved.0 == int_transfer_scratch()),
  )
  emit(function, allocation, frame) |> ignore
}
