///|
#borrow(fds)
extern "c" fn c_test_pipe(fds : FixedArray[Int]) -> Int = "wasmoon_async_test_pipe"

///|
extern "c" fn c_test_write(fd : Int) -> Int = "wasmoon_async_test_write"

///|
extern "c" fn c_test_close(fd : Int) -> Unit = "wasmoon_async_test_close"

///|
fn test_pipe() -> (Int, Int)? {
  let fds = FixedArray::make(2, -1)
  if c_test_pipe(fds) != 0 {
    return None
  }
  Some((fds[0], fds[1]))
}

///|
test "native reactor delivers readable and writable events" {
  if !NativeReactor::supported() {
    return
  }
  guard test_pipe() is Some((read_fd, write_fd)) else {
    fail("failed to create reactor test pipe")
  }
  defer {
    c_test_close(read_fd)
    c_test_close(write_fd)
  }
  let reactor = NativeReactor::try_new()
  let read_registration = reactor.register_read(read_fd)
  c_test_write(write_fd) |> ignore
  debug_inspect(
    (
      reactor.wait(Some(1000000000L)),
      read_registration.is_ready(),
      read_registration.is_active(),
      reactor,
    ),
    content="(1, true, false, NativeReactor(registrations=0))",
  )
  let write_registration = reactor.register_write(write_fd)
  debug_inspect(
    (
      reactor.wait(Some(1000000000L)),
      write_registration.is_ready(),
      write_registration.is_active(),
      reactor,
    ),
    content="(1, true, false, NativeReactor(registrations=0))",
  )
}

///|
test "native reactor delivers timers and explicit wakeups" {
  if !NativeReactor::supported() {
    return
  }
  let reactor = NativeReactor::try_new()
  let timer = reactor.register_timer(1000000L)
  debug_inspect(
    (reactor.wait(Some(1000000000L)), timer.is_ready(), timer.is_active()),
    content="(1, true, false)",
  )
  reactor.wake()
  debug_inspect(
    (reactor.wait(Some(1000000000L)), reactor),
    content="(0, NativeReactor(registrations=0))",
  )
}

///|
test "cancelled native registration ignores stale readiness" {
  if !NativeReactor::supported() {
    return
  }
  guard test_pipe() is Some((read_fd, write_fd)) else {
    fail("failed to create reactor test pipe")
  }
  defer {
    c_test_close(read_fd)
    c_test_close(write_fd)
  }
  let reactor = NativeReactor::try_new()
  let cancelled = reactor.register_read(read_fd)
  cancelled.cancel()
  cancelled.cancel()
  c_test_write(write_fd) |> ignore
  debug_inspect(
    (
      reactor.wait(Some(0L)),
      cancelled.is_ready(),
      cancelled.is_active(),
      reactor,
    ),
    content="(0, false, false, NativeReactor(registrations=0))",
  )
}

///|
test "native registration tokens are never reused" {
  if !NativeReactor::supported() {
    return
  }
  guard test_pipe() is Some((read_fd, write_fd)) else {
    fail("failed to create reactor test pipe")
  }
  defer {
    c_test_close(read_fd)
    c_test_close(write_fd)
  }
  let reactor = NativeReactor::try_new()
  let first = reactor.register_read(read_fd)
  let first_token = first.1
  first.cancel()
  let second = reactor.register_read(read_fd)
  c_test_write(write_fd) |> ignore
  debug_inspect(
    (
      reactor.wait(Some(1000000000L)),
      first_token == second.1,
      first.is_ready(),
      second.is_ready(),
      reactor,
    ),
    content="(1, false, false, true, NativeReactor(registrations=0))",
  )
}

///|
test "native reactor cancellation stress returns to an empty baseline" {
  if !NativeReactor::supported() {
    return
  }
  guard test_pipe() is Some((read_fd, write_fd)) else {
    fail("failed to create reactor test pipe")
  }
  defer {
    c_test_close(read_fd)
    c_test_close(write_fd)
  }
  let reactor = NativeReactor::try_new()
  let first_token : Array[Int64?] = [None]
  let last_token : Array[Int64?] = [None]
  for index in 0..<512 {
    let registration = if index % 2 == 0 {
      reactor.register_read(read_fd)
    } else {
      reactor.register_timer(1000000000L)
    }
    if first_token[0] is None {
      first_token[0] = Some(registration.1)
    }
    last_token[0] = Some(registration.1)
    registration.cancel()
    registration.cancel()
  }
  c_test_write(write_fd) |> ignore
  debug_inspect(
    (
      first_token[0],
      last_token[0],
      reactor.wait(Some(0L)),
      reactor.has_pending(),
      reactor,
    ),
    content="(Some(1), Some(512), 0, false, NativeReactor(registrations=0))",
  )
}
