///|
test "guest continuation ownership: stale cancellation cannot release a new owner" {
  let store = Store()
  let releases = Ref(0)
  let successor = Ref(-1L)
  let handle = store.put_guest_continuation({
    run: fn(_) raise {
      successor.val = store.put_guest_continuation({
        run: fn(_) { [] },
        cancel: fn() { releases.val += 1 },
      })
      []
    },
    cancel: fn() { releases.val += 100 },
  })
  let consumed = store.take_guest_continuation(handle)
  assert_true((consumed.run)(Values([])).is_empty())
  (consumed.cancel)()
  inspect(releases.val, content="0")
  try store.take_guest_continuation(handle) catch {
    error => inspect(error.to_string(), content="continuation already consumed")
  } noraise {
    _ => fail("a consumed handle remained usable")
  }
  assert_true(successor.val > handle)
  store.close()
  store.close()
  inspect(releases.val, content="1")
}

///|
test "guest continuation ownership: terminal failure releases the consumed body" {
  let store = Store()
  defer store.close()
  let releases = Ref(0)
  let handle = store.put_guest_continuation({
    run: fn(_) raise { raise RuntimeError::Unreachable },
    cancel: fn() { releases.val += 1 },
  })
  let body = store.take_guest_continuation(handle)
  try (body.run)(Values([])) catch {
    error => assert_true(RuntimeError::from_error(error) is Some(Unreachable))
  } noraise {
    _ => fail("expected the continuation to trap")
  }
  (body.cancel)()
  inspect(releases.val, content="1")
}
