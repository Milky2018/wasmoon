///|
test "component entry tracks nested activity independently of poison" {
  let entry = ComponentInstanceEntryState::new()
  inspect(entry.may_start_async(), content="true")
  entry.enter()
  entry.enter()
  inspect(entry.active_depth.val, content="2")
  inspect(entry.may_start_async(), content="false")
  entry.leave()
  inspect(entry.active_depth.val, content="1")
  inspect(entry.may_start_async(), content="false")
  entry.leave()
  inspect(entry.may_start_async(), content="true")
  entry.enter()
  entry.poison()
  entry.leave()
  inspect(entry.active_depth.val, content="0")
  inspect(entry.may_start_async(), content="true")
  inspect(entry.poisoned.val, content="true")
  entry.enter()
  inspect(entry.active_depth.val, content="1")
  entry.leave()
}

///|
test "cancelling a suspended call does not release a different activation" {
  let entry = ComponentInstanceEntryState::new()
  entry.enter()
  let cancelled = Ref(false)
  let suspended = guard_core_outcome(
    Suspended(
      Yield,
      CoreContinuation(fn() { Returned([]) }, fn() { cancelled.val = true }),
    ),
    entry,
  )
  inspect(entry.active_depth.val, content="0")
  entry.enter()
  guard suspended is Suspended(_, continuation) else {
    fail("expected suspension")
  }
  continuation.cancel()
  inspect(cancelled.val, content="true")
  inspect(entry.active_depth.val, content="1")
  inspect(entry.may_start_async(), content="false")
  entry.leave()
  inspect(entry.may_start_async(), content="true")
}
