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
