///|
test "standalone heap close releases capacity without allowing stale revival" {
  let budget = @runtime.ResourceBudget::new(gc_bytes=32L, gc_objects=1L)
  for attempt in 0..<3 {
    let heap = if attempt == 0 {
      @runtime.MarkSweepHeap::with_threshold(1, resource_budget=Some(budget))
    } else {
      MarkSweepHeap(resource_budget=Some(budget))
    }
    defer heap.close()
    let retained = heap
    let index = heap.alloc_struct(0, [I32(42)])
    assert_eq(heap.collect([]), 1)
    assert_eq(budget.used(GcBytes), 0L)
    // Empty slots remain reusable capacity until the heap is closed.
    assert_eq(budget.used(GcObjects), 1L)
    assert_eq(heap.alloc_struct(0, []), index)
    heap.close()
    retained.close()
    assert_false(retained.is_alive(index))
    assert_eq(retained.length(), 0)
    assert_eq(budget.used(GcBytes), 0L)
    assert_eq(budget.used(GcObjects), 0L)
    try retained.alloc_struct(0, []) catch {
      InvalidHandle => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("closed heap admitted a struct")
    }
    try retained.alloc_array(0, []) catch {
      InvalidHandle => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("closed heap admitted an array")
    }
  }
  let unbudgeted = @runtime.MarkSweepHeap()
  unbudgeted.close()
  try unbudgeted.alloc_struct(0, []) catch {
    InvalidHandle => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("unbudgeted closed heap reopened")
  }
}
