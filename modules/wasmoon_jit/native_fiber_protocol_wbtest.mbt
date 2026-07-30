///|
test "native fiber state wire protocol is decoded once and totally" {
  debug_inspect(
    [
      decode_native_fiber_state_code(0),
      decode_native_fiber_state_code(1),
      decode_native_fiber_state_code(2),
      decode_native_fiber_state_code(3),
      decode_native_fiber_state_code(4),
      decode_native_fiber_state_code(-1),
      decode_native_fiber_state_code(99),
    ],
    content=(
      #|[
      #|  Ok(Ready),
      #|  Ok(Running),
      #|  Ok(Suspended),
      #|  Ok(Returned),
      #|  Ok(Cancelled),
      #|  Err(-1),
      #|  Err(99),
      #|]
    ),
  )
}

///|
test "native fiber operation wire protocol preserves typed failures" {
  debug_inspect(
    (
      [
        decode_native_fiber_advance_code(0),
        decode_native_fiber_advance_code(1),
        decode_native_fiber_advance_code(-2),
        decode_native_fiber_advance_code(-3),
        decode_native_fiber_advance_code(-4),
        decode_native_fiber_advance_code(99),
      ],
      [
        decode_native_fiber_cancel_code(0),
        decode_native_fiber_cancel_code(-2),
        decode_native_fiber_cancel_code(-3),
        decode_native_fiber_cancel_code(-1),
        decode_native_fiber_cancel_code(99),
      ],
      FiberInvalidState(7).to_error(),
    ),
    content=(
      #|(
      #|  [
      #|    FiberDidSuspend,
      #|    FiberDidReturn,
      #|    FiberAdvanceWrongThread,
      #|    FiberAdvanceInvalidTransition,
      #|    FiberAdvanceInvalidState,
      #|    FiberAdvanceNativeFailure(99),
      #|  ],
      #|  [
      #|    FiberDidCancel,
      #|    FiberCancelWrongThread,
      #|    FiberCancelInvalidTransition,
      #|    FiberCancelNativeFailure(-1),
      #|    FiberCancelNativeFailure(99),
      #|  ],
      #|  InvalidState(7),
      #|)
    ),
  )
}
