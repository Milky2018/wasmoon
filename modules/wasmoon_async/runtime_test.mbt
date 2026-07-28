///|
test "ready queue deduplicates wakeups and preserves task order" {
  let runtime = @wasmoon_async.Runtime()
  let first = runtime.spawn()
  let second = runtime.spawn()
  first.waker().wake() |> ignore
  second.waker().wake() |> ignore
  debug_inspect(
    [runtime.next_ready(), runtime.next_ready(), runtime.next_ready()],
    content=(
      #|[
      #|  Some({ slot: 0, generation: 0 }),
      #|  Some({ slot: 1, generation: 0 }),
      #|  None,
      #|]
    ),
  )
  first.waker().wake() |> ignore
  first.waker().wake() |> ignore
  debug_inspect(
    [runtime.next_ready(), runtime.next_ready()],
    content=(
      #|[Some({ slot: 0, generation: 0 }), None]
    ),
  )
}

///|
test "operation completion wakes its task and stale events are rejected" {
  let runtime = @wasmoon_async.Runtime()
  let task = runtime.spawn()
  runtime.next_ready() |> ignore
  guard task.waker().register() is Some(first) else {
    fail("failed to register operation")
  }
  let stale = first.id()
  first.complete() |> ignore
  debug_inspect(
    (runtime, runtime.next_ready()),
    content=(
      #|(
      #|  Runtime(now=0, tasks=1, operations=0, ready=0),
      #|  Some({ slot: 0, generation: 0 }),
      #|)
    ),
  )
  guard task.waker().register() is Some(second) else {
    fail("failed to reuse operation slot")
  }
  debug_inspect(
    (
      stale == second.id(),
      runtime.complete_operation(stale),
      second.complete(),
      runtime,
    ),
    content=(
      #|(false, false, true, Runtime(now=0, tasks=1, operations=0, ready=1))
    ),
  )
}

///|
test "deterministic timers wake at their deadlines" {
  let runtime = @wasmoon_async.Runtime()
  let first = runtime.spawn()
  let second = runtime.spawn()
  runtime.next_ready() |> ignore
  runtime.next_ready() |> ignore
  guard first.waker().register_timer(20L) is Some(_) else {
    fail("failed to register first timer")
  }
  guard second.waker().register_timer(10L) is Some(_) else {
    fail("failed to register second timer")
  }
  debug_inspect(
    runtime.next_deadline(),
    content=(
      #|Some(10)
    ),
  )
  debug_inspect(
    (runtime.advance_to(9L), runtime.next_ready()),
    content=(
      #|(0, None)
    ),
  )
  debug_inspect(
    (runtime.advance_to(10L), runtime.next_ready(), runtime.next_deadline()),
    content=(
      #|(1, Some({ slot: 1, generation: 0 }), Some(20))
    ),
  )
  debug_inspect(
    (runtime.advance_to(20L), runtime.next_ready(), runtime.next_deadline()),
    content=(
      #|(1, Some({ slot: 0, generation: 0 }), None)
    ),
  )
}

///|
test "task cancellation releases operations and invalidates wakers" {
  let runtime = @wasmoon_async.Runtime()
  let task = runtime.spawn()
  let waker = task.waker()
  runtime.next_ready() |> ignore
  guard waker.register() is Some(operation) else {
    fail("failed to register operation")
  }
  task.cancel()
  task.cancel()
  let stale_wake = waker.wake()
  let stale_completion = operation.complete()
  debug_inspect(
    (
      task.id(),
      operation.id(),
      task.is_active(),
      stale_wake,
      stale_completion,
      runtime.next_ready(),
      runtime.next_deadline(),
      runtime,
    ),
    content=(
      #|(
      #|  { slot: 0, generation: 0 },
      #|  { slot: 0, generation: 0 },
      #|  false,
      #|  false,
      #|  false,
      #|  None,
      #|  None,
      #|  Runtime(now=0, tasks=0, operations=0, ready=0),
      #|)
    ),
  )
}

///|
test "expired timer registration is immediately ready" {
  let runtime = @wasmoon_async.Runtime()
  let task = runtime.spawn()
  runtime.next_ready() |> ignore
  runtime.advance_to(10L) |> ignore
  guard task.waker().register_timer(5L) is Some(operation) else {
    fail("failed to register expired timer")
  }
  debug_inspect(
    (operation.id(), runtime.next_ready(), runtime),
    content=(
      #|(
      #|  { slot: 0, generation: 0 },
      #|  Some({ slot: 0, generation: 0 }),
      #|  Runtime(now=10, tasks=1, operations=0, ready=0),
      #|)
    ),
  )
}

///|
test "time cannot move backwards" {
  let runtime = @wasmoon_async.Runtime()
  runtime.advance_to(5L) |> ignore
  try runtime.advance_to(4L) |> ignore catch {
    error =>
      debug_inspect(
        error,
        content=(
          #|TimeWentBackwards(previous=5, requested=4)
        ),
      )
  }
}
