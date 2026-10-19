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
