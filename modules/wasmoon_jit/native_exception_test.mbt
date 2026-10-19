///|
test "native exception arena retains only reference payload words until seal" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  let state = @wasmoon_jit.NativeExecutionState()
  defer state.seal()
  let arena = state.exceptions()
  let live = heap.alloc_struct(0, [I32(42)])
  let dead = heap.alloc_struct(0, [I32(99)])
  assert_true(arena.define_tag(7, [RefNullStruct(0), I64]))
  let reference = arena.insert(heap.get_ptr(), 7, [
    @wasmoon_jit.encode_heap_ref(live),
    @wasmoon_jit.encode_heap_ref(dead),
  ])
  assert_true(reference != 0L)
  inspect(heap.collect([]), content="1")
  assert_true(heap.is_valid(live))
  assert_false(heap.is_valid(dead))
  guard arena.snapshot(reference) is Some((tag, values)) else {
    fail("missing exception")
  }
  inspect(tag, content="7")
  assert_eq(values[0], @wasmoon_jit.encode_heap_ref(live))
  state.seal()
  inspect(heap.collect([]), content="1")
  assert_true(arena.snapshot(reference) is None)
}

///|
test "empty native snapshots preserve budgets across growth and root modes" {
  for traced in [false, true] {
    for with_heap in [false, true] {
      let heap = @wasmoon_jit.CHeap()
      defer heap.free()
      let arena = @jit_ffi.NativeExceptionArena::new()
      defer arena.clear()
      if traced {
        arena.enable_reclamation()
      }
      assert_true(arena.define_tag(7, []))
      let bytes = @jit_ffi.Quota::new(1024L)
      let objects = @jit_ffi.Quota::new(40L)
      assert_true(arena.bind_quotas(bytes, objects))
      let pointer = if with_heap {
        heap.get_ptr()
      } else {
        @jit_ffi.GCHeapHandle::null()
      }
      let references = Array::makei(40, _ => arena.insert(pointer, 7, []))
      for i in 0..<references.length() {
        assert_true(references[i] > 0L)
        if i > 0 {
          assert_true(references[i] > references[i - 1])
        }
        assert_eq(arena.snapshot(references[i]), Some((7, [])))
      }
      assert_eq(arena.insert(pointer, 7, []), 0L)
      assert_eq(arena.quota_denied(), 26)
      assert_eq(bytes.used(), 640L)
      assert_eq(objects.used(), 40L)
      for i in 0..<references.length() {
        arena.release_snapshot(references[i])
        arena.release_snapshot(references[i])
        assert_true(arena.snapshot(references[i]) is None)
        assert_eq(bytes.used(), (39 - i).to_int64() * 16L)
        assert_eq(objects.used(), (39 - i).to_int64())
      }
      let next = arena.insert(pointer, 7, [])
      assert_true(next > references[39])
      assert_eq(bytes.used(), 16L)
      assert_eq(objects.used(), 1L)
      arena.clear()
      arena.clear()
      assert_eq(bytes.used(), 0L)
      assert_eq(objects.used(), 0L)
    }
  }
}
