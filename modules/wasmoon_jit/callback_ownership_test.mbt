///|
fn cancellation_callback_with_capture() -> () -> Bool {
  let capture = @native_test_support.callback_capture()
  fn() {
    capture.touch()
    false
  }
}

///|
fn stdin_callback_with_capture() -> () -> Bytes {
  let capture = @native_test_support.callback_capture()
  fn() {
    capture.touch()
    b""
  }
}

///|
test "owned callback setters release transferred captures exactly once" {
  @native_test_support.reset_callback_capture()
  guard NativeJITContext::try_alloc(1) is Some(context) else {
    fail("failed to allocate native JIT context")
  }
  let releases = []

  context.set_cancellation_callback(cancellation_callback_with_capture())
  releases.push(@native_test_support.callback_capture_release_count())
  context.set_cancellation_callback(cancellation_callback_with_capture())
  releases.push(@native_test_support.callback_capture_release_count())
  context.clear_cancellation_callback()
  releases.push(@native_test_support.callback_capture_release_count())

  set_wasi_stdin_callback(context.ptr(), stdin_callback_with_capture())
  releases.push(@native_test_support.callback_capture_release_count())
  set_wasi_stdin_callback(context.ptr(), stdin_callback_with_capture())
  releases.push(@native_test_support.callback_capture_release_count())
  clear_wasi_stdin_callback(context.ptr())
  releases.push(@native_test_support.callback_capture_release_count())
  context.clear_gc_heap()

  @native_test_support.transfer_cancellation_callback_to_null_context(
    cancellation_callback_with_capture(),
  )
  releases.push(@native_test_support.callback_capture_release_count())
  set_wasi_stdin_callback(0L, stdin_callback_with_capture())
  releases.push(@native_test_support.callback_capture_release_count())
  debug_inspect(releases, content="[0, 1, 2, 2, 3, 4, 5, 6]")
}
