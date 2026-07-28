///|
test "Preview 2 output stream retains a legal short write" {
  let state : OutputStreamState = {
    write: fn(_bytes) { true },
    native_fd: Some(1),
    file_position: None,
    append: false,
    owns_fd: false,
    permit: Ref(5L),
    pending: Ref(Some((b"hello", 0))),
    failure: Ref(None),
    closed: Ref(false),
  }
  let attempts = Ref(0)
  let first = drain_output_stream_with(state, false, fn() { true }, fn(
    _bytes,
    _offset,
  ) {
    attempts.val = attempts.val + 1
    if attempts.val == 1 {
      Written(2)
    } else {
      WouldBlock
    }
  })
  guard first is Pending else {
    fail("short write followed by would-block must remain pending")
  }
  debug_inspect(
    (state.pending.val, state.closed.val, attempts.val),
    content=(
      #|(Some((<Bytes: [0x68, 0x65, 0x6c, 0x6c, 0x6f]>, 2)), false, 2)
    ),
  )
  let second = drain_output_stream_with(state, false, fn() { true }, fn(
    _bytes,
    _offset,
  ) {
    Written(3)
  })
  guard second is Drained else {
    fail("the retained suffix must drain on the next writable attempt")
  }
  debug_inspect((state.pending.val, state.closed.val), content="(None, false)")
}
