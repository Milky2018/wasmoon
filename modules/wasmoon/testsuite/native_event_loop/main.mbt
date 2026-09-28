///|
#borrow(fds)
extern "c" fn make_pipe(fds : FixedArray[Int]) -> Int = "wasmoon_async_test_pipe"

///|
extern "c" fn write_pipe(fd : Int) -> Int = "wasmoon_async_test_write"

///|
extern "c" fn close_pipe(fd : Int) -> Unit = "wasmoon_async_test_close"

///|
async fn main {
  @async_native.install_event_loop()
  @async.with_timeout(5000, async fn() {
    let first = @async_native.NativeReactor::try_new()
    let second = @async_native.NativeReactor::try_new()
    defer second.close()
    let cancelled = first.register_timer(60000000000L)
    let timer = second.register_timer(1000000L)
    first.close()
    assert_true(!cancelled.is_active())
    assert_true(!timer.is_ready())
    while !timer.is_ready() {
      @async_native.wait_for_readiness()
    }
    assert_true(!second.has_pending())

    let pipe = FixedArray::make(2, -1)
    assert_eq(make_pipe(pipe), 0)
    defer {
      close_pipe(pipe[0])
      close_pipe(pipe[1])
    }
    let readable = second.register_read(pipe[0])
    let third = @async_native.NativeReactor::try_new()
    let dropped = third.register_read(pipe[0])
    third.close()
    @async.with_task_group(async fn(group) {
      group.spawn_bg(async fn() {
        @async.sleep(1)
        assert_eq(write_pipe(pipe[1]), 1)
      })
      while !readable.is_ready() {
        @async_native.wait_for_readiness()
      }
    })
    assert_true(!dropped.is_ready())
    assert_true(!dropped.is_active())

    // The pipe still contains data, but only the outer event loop may drain
    // the kernel reactor, which also carries async's foreign-thread wakeups.
    let next_read = second.register_read(pipe[0])
    assert_eq(second.wait(Some(0L)), 0)
    assert_true(!next_read.is_ready())
    while !next_read.is_ready() {
      @async_native.wait_for_readiness()
    }

    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    @async.with_task_group(async fn(group) {
      let serving = group.spawn(async fn() {
        let (socket, _) = server.accept()
        defer socket.close()
        // The async socket task cannot respond until native readiness wakes it.
        let timer = second.register_timer(1000000L)
        while !timer.is_ready() {
          @async_native.wait_for_readiness()
        }
        socket.write(b"ready")
      })
      let socket = @socket.Tcp::connect(server.addr)
      defer socket.close()
      assert_eq(socket.read_exactly(5), b"ready")
      serving.wait()

      let waiting = group.spawn(no_wait=true, async fn() {
        let scoped = @async_native.NativeReactor::try_new()
        defer scoped.close()
        let timer = scoped.register_timer(60000000000L)
        while !timer.is_ready() {
          @async_native.wait_for_readiness()
        }
      })
      @async.pause()
      waiting.cancel()
      try waiting.wait() catch {
        @async.WaitedTaskAlreadyCancelled => ()
        error => raise error
      } noraise {
        _ => fail("expected cancellation")
      }
    })
    // Exercise wake-before-wait: the wake token must survive until poll.
    second.wake()
    try second.wait(None) catch {
      BlockingWaitInExternalLoop => ()
      error => raise error
    } noraise {
      _ => fail("shared scopes must reject blocking waits")
    }
    let final_timer = second.register_timer(1000000L)
    while !final_timer.is_ready() {
      @async_native.wait_for_readiness()
    }
  })
}
