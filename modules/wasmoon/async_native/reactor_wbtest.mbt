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
test "kqueue reactor delivers readable and writable events" {
  if !NativeReactor::supported() {
    return
  }
  let runtime = @wasmoon_async.Runtime()
  let read_task = runtime.spawn()
  runtime.next_ready() |> ignore
  guard test_pipe() is Some((read_fd, write_fd)) else {
    fail("failed to create reactor test pipe")
  }
  defer {
    c_test_close(read_fd)
    c_test_close(write_fd)
  }
  let reactor = NativeReactor::try_new()
  let read_registration = reactor.register_read(read_fd, read_task.waker())
  c_test_write(write_fd) |> ignore
  debug_inspect(
    (
      reactor.wait(Some(1000000000L)),
      runtime.next_ready(),
      read_registration.is_active(),
      reactor,
    ),
    content=(
      #|(
      #|  1,
      #|  Some({ slot: 0, generation: 0 }),
      #|  false,
      #|  NativeReactor(registrations=0),
      #|)
    ),
  )
  let write_task = runtime.spawn()
  runtime.next_ready() |> ignore
  let write_registration = reactor.register_write(write_fd, write_task.waker())
  debug_inspect(
    (
      reactor.wait(Some(1000000000L)),
      runtime.next_ready(),
      write_registration.is_active(),
      reactor,
    ),
    content=(
      #|(
      #|  1,
      #|  Some({ slot: 1, generation: 0 }),
      #|  false,
      #|  NativeReactor(registrations=0),
      #|)
    ),
  )
}

///|
test "kqueue reactor delivers timers and explicit wakeups" {
  if !NativeReactor::supported() {
    return
  }
  let runtime = @wasmoon_async.Runtime()
  let task = runtime.spawn()
  runtime.next_ready() |> ignore
  let reactor = NativeReactor::try_new()
  let timer = reactor.register_timer(1000000L, task.waker())
  debug_inspect(
    (reactor.wait(Some(1000000000L)), runtime.next_ready(), timer.is_active()),
    content="(1, Some({ slot: 0, generation: 0 }), false)",
  )
  reactor.wake()
  debug_inspect(
    (reactor.wait(Some(1000000000L)), reactor),
    content="(0, NativeReactor(registrations=0))",
  )
}

///|
test "cancelled kqueue registration ignores stale readiness" {
  if !NativeReactor::supported() {
    return
  }
  let runtime = @wasmoon_async.Runtime()
  let task = runtime.spawn()
  runtime.next_ready() |> ignore
  guard test_pipe() is Some((read_fd, write_fd)) else {
    fail("failed to create reactor test pipe")
  }
  defer {
    c_test_close(read_fd)
    c_test_close(write_fd)
  }
  let reactor = NativeReactor::try_new()
  let cancelled = reactor.register_read(read_fd, task.waker())
  let stale = cancelled.operation_id()
  cancelled.cancel()
  cancelled.cancel()
  c_test_write(write_fd) |> ignore
  debug_inspect(
    (
      reactor.wait(Some(0L)),
      runtime.complete_operation(stale),
      runtime.next_ready(),
      cancelled.is_active(),
      reactor,
    ),
    content="(0, false, None, false, NativeReactor(registrations=0))",
  )
}

///|
test "kqueue registration tokens are never reused" {
  if !NativeReactor::supported() {
    return
  }
  let runtime = @wasmoon_async.Runtime()
  let task = runtime.spawn()
  runtime.next_ready() |> ignore
  guard test_pipe() is Some((read_fd, write_fd)) else {
    fail("failed to create reactor test pipe")
  }
  defer {
    c_test_close(read_fd)
    c_test_close(write_fd)
  }
  let reactor = NativeReactor::try_new()
  let first = reactor.register_read(read_fd, task.waker())
  let first_operation = first.operation_id()
  first.cancel()
  let second = reactor.register_read(read_fd, task.waker())
  c_test_write(write_fd) |> ignore
  debug_inspect(
    (
      reactor.wait(Some(1000000000L)),
      first_operation == second.operation_id(),
      runtime.next_ready(),
      reactor,
    ),
    content=(
      #|(
      #|  1,
      #|  false,
      #|  Some({ slot: 0, generation: 0 }),
      #|  NativeReactor(registrations=0),
      #|)
    ),
  )
}
