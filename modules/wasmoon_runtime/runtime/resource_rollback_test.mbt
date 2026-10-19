///|
test "exception rollback releases quota and preserves healthy admission" {
  let budget = @runtime.ResourceBudget::new(gc_bytes=16L, gc_objects=1L)
  let store = @runtime.Store::Store(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [], results: [], })
  for _ in 0..<3 {
    store.with_instantiation(fn() -> Unit raise @runtime.RuntimeError {
      store.alloc_exn(tag, []) |> ignore
      raise OutOfMemory
    }) catch {
      OutOfMemory => ()
      error => fail(error.to_string())
    }
    debug_inspect(
      (budget.used(GcBytes), budget.used(GcObjects)),
      content="(0, 0)",
    )
  }
  let exception = store.alloc_exn(tag, [])
  inspect(store.get_exn(exception).tag_addr, content="0")
  debug_inspect(
    (budget.used(GcBytes), budget.used(GcObjects)),
    content="(16, 1)",
  )
  store.close()
  debug_inspect(
    (budget.used(GcBytes), budget.used(GcObjects)),
    content="(0, 0)",
  )
}

///|
test "failed continuation preparation releases work and cancels once" {
  let budget = @runtime.ResourceBudget::new(pending_work=1L)
  let store = @runtime.Store::Store(resource_budget=Some(budget))
  defer store.close()
  let index = store.alloc_struct(0, [])
  let cancelled = Ref(0)
  for attempt in 1..<4 {
    let body = @runtime.GuestContinuationBody::new(
      fn(_) { [] },
      fn() { cancelled.val += 1 },
      roots=[StructRef(index)],
    )
    try store.put_guest_continuation(body) catch {
      ResourceLimitExceeded(PendingWork) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("expected root admission to exhaust PendingWork")
    }
    assert_eq(cancelled.val, attempt)
    inspect(budget.used(PendingWork), content="0")
  }
  inspect(store.collect_garbage(), content="1")
  let handle = store.put_guest_continuation(
    @runtime.GuestContinuationBody::new(fn(_) { [] }, fn() {
      cancelled.val += 1
    }),
  )
  assert_true(store.has_guest_continuation(handle))
  inspect(budget.used(PendingWork), content="1")
  store.close()
  store.close()
  inspect(cancelled.val, content="4")
  inspect(budget.used(PendingWork), content="0")
}
