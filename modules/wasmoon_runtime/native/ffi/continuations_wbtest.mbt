///|
#borrow(state, context)
extern "c" fn test_create_continuation(
  state : ContinuationState,
  context : JITContext,
  create : FuncRef[(ContinuationState, ContinuationCreateRequest) -> Int64],
) -> Int64 = "wasmoon_test_create_continuation"

///|
#borrow(context, heap)
extern "c" fn test_bind_continuation_heap(
  context : JITContext,
  heap : GCHeapHandle,
) -> Unit = "wasmoon_jit_gc_set_heap_managed"

///|
test "unpublished continuation bodies and parked roots retire before arena close" {
  for with_heap in [false, true] {
    let arena = NativeContinuationArena::new()
    defer arena.clear()
    let context = JITContext::new(0)
    context.bind_continuation_arena(arena)
    let heap = if with_heap {
      GCHeapHandle::new(65536L)
    } else {
      GCHeapHandle::null()
    }
    test_bind_continuation_heap(context, heap)
    let quota = Quota::new(1L)
    assert_true(arena.bind_quota(quota))
    // Exhaustion happens after body/value/root allocation, inside publication.
    // Historical handle-table allocation was removed when identities moved to
    // MoonBit; generation exhaustion exercises its current recoverable exit.
    arena.state.next_reference = 0x7fffffff
    for _ in 0..<16 {
      assert_eq(
        test_create_continuation(arena.state, context, fn(state, request) {
          state.create(request)
        }),
        9L,
      )
      arena.reclaim_retired()
      assert_eq(arena.state.storage.count(), 0)
      assert_eq(arena.state.handles.length(), 0)
      assert_eq(quota.used(), 0L)
      if with_heap {
        assert_eq(heap.execution_roots().length(), 0)
      }
    }
    // A fresh identity succeeds in the same storage/heap after failed attempts.
    arena.state.next_reference = 0
    assert_eq(
      test_create_continuation(arena.state, context, fn(state, request) {
        let reference = state.create(request)
        guard reference < 0L else { return 1L }
        let body = state.take(reference)
        guard body > 0L else { return 2L }
        continuation_body_close(body)
        state.reclaim()
        reference
      }),
      -1L,
    )
    assert_eq(arena.state.storage.count(), 0)
    assert_eq(quota.used(), 0L)
  }
}
