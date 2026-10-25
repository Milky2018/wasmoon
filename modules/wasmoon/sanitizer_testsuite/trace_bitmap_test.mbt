///|
test "independent native traces retain their own visited identities" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8, 4], false))
  let child = pointer.allocate_typed(7, 7, [0L, 0L, 42L, 0L], 2, false)
  let child_word = child.to_int64() << 1
  let parent = pointer.allocate_typed(7, 7, [child_word, 0L, 1L, 0L], 2, false)
  let first = pointer.begin_trace()
  assert_eq(first.expand(parent), [0L])
  assert_eq(first.objects(), [parent.to_int64() << 1, child_word])
  let second = pointer.begin_trace()
  assert_eq(second.expand(child), [0L])
  assert_eq(first.expand(child), [0L])
  assert_eq(first.objects(), [parent.to_int64() << 1, child_word])
  assert_eq(second.objects(), [child_word])
  assert_true(heap.verify())
}

///|
test "overlapping native trace marks form a union and clear after collection" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  heap.bind_root_visitor(fn(_, roots) { roots })
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], false))
  let child = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  let word = child.to_int64() << 1
  let left = pointer.allocate_typed(7, 7, [word, 0L], 1, false)
  let right = pointer.allocate_typed(7, 7, [word, 0L], 1, false)
  let first = pointer.begin_trace()
  let second = pointer.begin_trace()
  assert_eq(first.expand(left), [0L])
  assert_eq(second.expand(right), [0L])
  first.mark()
  second.mark()
  assert_eq(heap.collect([]), 0)
  for reference in [child, left, right] {
    assert_true(heap.is_valid(reference - 1))
  }
  // Old full graph handles resolve live identities after compaction.
  first.mark()
  second.mark()
  assert_eq(heap.collect([]), 0)
  assert_true(heap.verify())
  assert_eq(heap.collect([]), 3)
  // Discovery and a mark on a retired snapshot cannot resurrect payloads.
  first.mark()
  assert_eq(first.expand(left), [-1L])
  assert_eq(heap.collect([]), 0)
  assert_true(heap.verify())
}

///|
test "read-only native graph discovery does not retain payloads" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], false))
  let reference = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  let graph = pointer.begin_trace()
  assert_eq(graph.expand(reference), [0L])
  assert_eq(heap.collect([]), 1)
  assert_false(heap.is_valid(reference - 1))
  assert_true(heap.verify())
}

///|
test "native trace metadata failures never publish partial marks" {
  defer runtime_fail_native_allocation(0)
  for attempt in 1..<6 {
    let heap = @wasmoon_jit.CHeap()
    defer heap.free()
    let pointer = heap.get_ptr()
    assert_true(pointer.define_layout(7, [-8], false))
    let child = heap.alloc_struct(0, [I32(42)])
    let reference = pointer.allocate_typed(
      7,
      7,
      [@wasmoon_jit.encode_heap_ref(child), 0L],
      1,
      false,
    )
    let graph = pointer.begin_trace()
    runtime_fail_native_allocation(attempt)
    assert_eq(graph.expand(reference), [-2L])
    runtime_fail_native_allocation(0)
    graph.mark()
    assert_eq(heap.collect([]), 2)
    assert_false(heap.is_valid(child))
    assert_false(heap.is_valid(reference - 1))
    assert_true(heap.verify())
  }
}

///|
test "rollback invalidates trace visits before a partial page reuses identities" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], false))
  let anchor = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  let undo = heap.make_allocation_rollback(fn() { [] })
  let old = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  let graph = pointer.begin_trace()
  assert_eq(graph.expand(old), [0L])
  undo()
  assert_true(heap.is_valid(anchor - 1))
  assert_false(heap.is_valid(old - 1))
  let fresh = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  let child = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
  assert_eq(fresh, old)
  heap.struct_set(fresh - 1, 0, StructRef(child - 1))
  assert_eq(graph.expand(fresh), [0L])
  assert_eq(graph.objects(), [
    old.to_int64() << 1,
    fresh.to_int64() << 1,
    child.to_int64() << 1,
  ])
  assert_true(heap.verify())
}

///|
#borrow(heap)
extern "c" fn trace_sparse_history(heap : @wasmoon_jit.GCHeapHandle) -> Bool = "wasmoon_test_gc_sparse_trace_history"

///|
test "sparse native traces cross directory chunks and retire missing pages" {
  defer runtime_fail_native_allocation(0)
  for failure in [0, 1, 2, 3] {
    let heap = @wasmoon_jit.CHeap()
    defer heap.free()
    defer heap.clear_root_visitor()
    heap.bind_root_visitor(fn(_, roots) { roots })
    let pointer = heap.get_ptr()
    assert_true(pointer.define_layout(7, [-8], false))
    let first = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
    assert_true(trace_sparse_history(pointer))
    let second = pointer.allocate_typed(
      7,
      7,
      [first.to_int64() << 1, 0L],
      1,
      false,
    )
    assert_eq(second, 1048577)
    let graph = pointer.begin_trace()
    assert_eq(graph.expand(first), [0L])
    runtime_fail_native_allocation(failure)
    assert_eq(graph.expand(second), if failure == 0 { [0L] } else { [-2L] })
    runtime_fail_native_allocation(0)
    graph.mark()
    if failure == 0 {
      assert_eq(graph.objects(), [first.to_int64() << 1, second.to_int64() << 1])
      assert_eq(heap.collect([]), 0)
      assert_true(heap.verify())
    }
    assert_eq(heap.collect([]), 2)
    // Both trace directory entries now designate absent identity pages.
    graph.mark()
    assert_eq(heap.collect([]), 0)
    assert_true(heap.verify())
  }
}

///|
test "young trace mark union excludes mature bitmap word and page boundaries" {
  for count in [63, 64, 65, 1024] {
    let heap = @wasmoon_jit.CHeap()
    defer heap.free()
    defer heap.clear_root_visitor()
    let pointer = heap.get_ptr()
    assert_true(pointer.define_layout(7, [-8], false))
    let mut head = 0
    for _ in 0..<count {
      head = pointer.allocate_typed(7, 7, [head.to_int64() << 1, 0L], 1, false)
    }
    bind_generation_roots(heap)
    assert_eq(heap.collect([StructRef(head - 1)]), 0)
    let child = pointer.allocate_typed(7, 7, [0L, 0L], 1, false)
    heap.struct_set(0, 0, StructRef(child - 1))
    assert_eq(generation_collection(pointer, [head.to_int64() << 1]), 0)
    assert_eq(generation_minor_count(pointer), 1)
    assert_true(heap.is_valid(child - 1))
    assert_true(heap.verify())
    assert_eq(heap.collect([]), count + 1)
  }
}
