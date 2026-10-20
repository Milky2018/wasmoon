///|
test "failed direct table admission preserves snapshots and quota" {
  let budget = @runtime.ResourceBudget::new(gc_objects=3L)
  let store = @runtime.Store::Store(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [], results: [], })
  let first = store.alloc_exn(tag, [])
  let second = store.alloc_exn(tag, [])
  let table = @runtime.Table::Table(ExnRef, 2, None)
  table.set(0, ExnRef(first))
  table.set(1, ExnRef(second))
  try store.alloc_table(table) catch {
    ResourceLimitExceeded(GcObjects) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("expected admission failure")
  }
  assert_eq(store.counts().tables, 0)
  assert_eq(table.get(0), ExnRef(first))
  assert_eq(table.get(1), ExnRef(second))
  let used = budget.used(GcObjects)
  let can_allocate = try {
    store.alloc_exn(tag, []) |> ignore
    true
  } catch {
    ResourceLimitExceeded(GcObjects) => false
    error => fail(error.to_string())
  }
  assert_eq((used, can_allocate), (2L, true))
}

///|
test "failed admission batch retains earlier cache entries and can be retried" {
  for cached in [false, true] {
    let budget = @runtime.ResourceBudget::new(
      gc_objects=if cached { 5L } else { 3L },
    )
    let store = @runtime.Store::Store(resource_budget=Some(budget))
    defer store.close()
    let tag = store.alloc_tag({ params: [], results: [], })
    let count = if cached { 3 } else { 2 }
    let exceptions = Array::makei(count, _ => store.alloc_exn(tag, []))
    let token = if cached {
      Some(store.encode_native_exception(exceptions[0]))
    } else {
      None
    }
    let before = (
      budget.used(GcObjects),
      budget.used(GcBytes),
      budget.used(TableElements),
    )
    let table = @runtime.Table::Table(ExnRef, count, None)
    for i, exception in exceptions {
      table.set(i, ExnRef(exception))
    }
    for _ in 0..<3 {
      try store.alloc_table(table) catch {
        ResourceLimitExceeded(GcObjects) => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("expected admission failure")
      }
      assert_eq(store.counts().tables, 0)
      assert_eq(
        (
          budget.used(GcObjects),
          budget.used(GcBytes),
          budget.used(TableElements),
        ),
        before,
      )
      for i, exception in exceptions {
        assert_eq(table.get(i), ExnRef(exception))
      }
      if token is Some(token) {
        assert_eq(store.encode_native_exception(exceptions[0]), token)
      }
    }
    // Reuse this same Table after replacing later initializers with the first.
    table.fill(0, ExnRef(exceptions[0]), count)
    store.alloc_table(table) |> ignore
    for i in 0..<count {
      assert_eq(table.get(i), ExnRef(exceptions[0]))
    }
    assert_eq(budget.used(GcObjects), before.0 + (if cached { 0L } else { 1L }))
  }
}

///|
test "failed admission undoes complete nested snapshots from earlier elements" {
  for cached_child in [false, true] {
    let budget = @runtime.ResourceBudget::new(gc_objects=5L)
    let store = @runtime.Store::Store(resource_budget=Some(budget))
    defer store.close()
    let tag = store.alloc_tag({ params: [], results: [], })
    let child = store.alloc_exn(tag, [])
    let parent_tag = store.alloc_tag({ params: [ExnRef], results: [], })
    let parent = store.alloc_exn(parent_tag, [ExnRef(child)])
    let other = store.alloc_exn(tag, [])
    let cached = if cached_child {
      Some(store.encode_native_exception(child))
    } else {
      None
    }
    let before = (budget.used(GcObjects), budget.used(GcBytes))
    let table = @runtime.Table::Table(ExnRef, 2, None)
    table.set(0, ExnRef(parent))
    table.set(1, ExnRef(other))
    try store.alloc_table(table) catch {
      ResourceLimitExceeded(GcObjects) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("expected admission rejection")
    }
    assert_eq((budget.used(GcObjects), budget.used(GcBytes)), before)
    if cached is Some(token) {
      assert_eq(store.encode_native_exception(child), token)
    }
    store.alloc_exn(tag, []) |> ignore
  }
}
