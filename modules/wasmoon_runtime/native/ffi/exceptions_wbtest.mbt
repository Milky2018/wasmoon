///|
// Historical identity counts are intentionally not exposed by the public API;
// inspect registry storage here to guard against unbounded tombstone retention.
test "exception registry storage stays bounded during long-lived retirement churn" {
  let arena = NativeExceptionArena::new()
  defer arena.clear()
  let heap = GCHeapHandle::null()
  let survivor = arena.insert(heap, 7, [42L])
  let mut previous = survivor
  for _ in 0..<10000 {
    let reference = arena.insert(heap, 7, [43L])
    assert_true(reference > previous)
    previous = reference
    arena.release_snapshot(reference)
  }
  assert_eq(arena.snapshot(survivor), Some((7, [42L])))
  assert_true(arena.state.entries.length() < 64)
  assert_true(arena.state.entries.capacity() < 128)
  assert_true(arena.state.storage.capacity() < 128)
}

///|
test "exception sweep keeps allocation headroom when all snapshots survive" {
  let arena = NativeExceptionArena::new()
  defer arena.clear()
  arena.enable_reclamation()
  let heap = GCHeapHandle::null()
  arena.state.entries.reserve_capacity(256)
  let capacity = arena.state.entries.capacity()
  let references : Array[Int64] = []
  for _ in 0..<(capacity / 2) {
    references.push(arena.insert(heap, 7, []))
  }
  for _ in 0..<4 {
    for reference in references {
      arena.state.mark(reference)
    }
    // Null-heap snapshots still exercise the same logical sweep policy.
    arena.state.sweep(0L)
    assert_eq(arena.state.entries.capacity(), capacity)
  }
}

///|
test "exception slot estimates reject retired identities after compaction and clear" {
  let arena = NativeExceptionArena::new()
  defer arena.clear()
  let heap = GCHeapHandle::null()
  let references = Array::makei(64, fn(i) {
    arena.insert(heap, 7, [i.to_int64()])
  })
  assert_eq(arena.state.lookup(references[25]), 26L)
  assert_eq(arena.state.lookup(references[25] + 1L), 0L)
  for i = 0; i < 64; i = i + 2 {
    arena.release_snapshot(references[i])
  }
  arena.release_snapshot(references[1]) // Trigger compaction with identity gaps.
  // The direct offset may name a different live entry, or exceed the length.
  assert_eq(arena.state.lookup(references[5]), 2L)
  assert_eq(arena.state.lookup(references[25]), 12L)
  assert_eq(arena.state.lookup(references[24]), 0L)
  assert_eq(arena.state.lookup(references[63]), 31L)
  for i in 3..<61 {
    arena.release_snapshot(references[i])
  }
  assert_true(arena.state.lookup(references[63]) > 0L)
  assert_eq(arena.snapshot(references[63]), Some((7, [63L])))
  let fresh = arena.insert(heap, 7, [42L])
  assert_true(arena.state.lookup(fresh) > 0L)
  arena.clear()
  assert_eq(arena.state.lookup(fresh), 0L)
}
