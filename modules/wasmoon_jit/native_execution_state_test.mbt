///|
test "native execution state keeps parked resources distinct" {
  let state = NativeExecutionState::NativeExecutionState()
  let released : Array[Int] = []
  let first = state.begin(release=fn() { released.push(1) })
  first.park()
  let second = state.begin(release=fn() { released.push(2) })
  second.park()
  debug_inspect(
    (
      first.resource_id(),
      second.resource_id(),
      first.phase(),
      second.phase(),
      state,
    ),
    content=(
      #|(
      #|  0,
      #|  1,
      #|  Parked,
      #|  Parked,
      #|  NativeExecutionState(active_depth=0, parked_count=2, live_count=2),
      #|)
    ),
  )
  first.cancel()
  second.cancel()
  debug_inspect(
    (released, state),
    content=(
      #|(
      #|  [1, 2],
      #|  NativeExecutionState(active_depth=0, parked_count=0, live_count=0),
      #|)
    ),
  )
}

///|
test "nested native activation restores its caller" {
  let state = NativeExecutionState::NativeExecutionState()
  let outer = state.begin()
  let inner = state.begin()
  debug_inspect(
    (outer.id(), inner.id(), state.current_invocation(), state.active_depth()),
    content="(0, 1, Some(1), 2)",
  )
  inner.complete()
  debug_inspect(
    (state.current_invocation(), state.active_depth()),
    content="(Some(0), 1)",
  )
  outer.complete()
  debug_inspect(
    (state.current_invocation(), state.active_depth(), state.live_count()),
    content="(None, 0, 0)",
  )
}

///|
test "native invocation resources release exactly once" {
  let state = NativeExecutionState::NativeExecutionState()
  let releases = [0]
  let invocation = state.begin(release=fn() { releases[0] = releases[0] + 1 })
  invocation.park()
  invocation.cancel()
  let second = try invocation.cancel() catch {
    error => error.to_string()
  } noraise {
    _ => "unexpected success"
  }
  debug_inspect((releases[0], second), content="(1, \"UnknownInvocation(0)\")")
}
