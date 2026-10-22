///|
#borrow(heap)
extern "c" fn gc_word_access(
  heap : GCHeapHandle,
  operation : Int32,
  reference : Int64,
  index : Int32,
  value : Int64,
) -> Int64 = "wasmoon_test_gc_word_access"

///|
test "explicit heap helpers preserve wide objects dynamic layouts and tombstones" {
  let first = CHeap()
  defer first.free()
  let second = CHeap()
  defer second.free()
  assert_true(first.get_ptr().define_layout(0, [1, 8], false))
  assert_true(first.get_ptr().define_layout(1, [1], true))
  let compact = first.alloc_struct(0, [I32(7), I64(42L)], runtime_type=0)
  let wide = second.alloc_struct(0, [I32(8), I64(43L)])
  for (heap, index, expected) in [(first, compact, 42L), (second, wide, 43L)] {
    let reference = (index + 1).to_int64() << 1
    assert_eq(gc_word_access(heap.get_ptr(), 0, reference, 1, 0L), expected)
    gc_word_access(heap.get_ptr(), 1, reference, 1, 99L) |> ignore
    assert_eq(heap.struct_get(index, 1, I64), I64(99L))
  }
  let compact_array = first.alloc_array(1, 3, I32(7), runtime_type=1)
  let wide_array = second.alloc_array(1, 3, I32(7))
  for
    (heap, index, expected) in [
      (first, compact_array, 255L),
      (second, wide_array, 511L),
    ] {
    let reference = (index + 1).to_int64() << 1
    assert_eq(gc_word_access(heap.get_ptr(), 4, reference, 0, 0L), 3L)
    gc_word_access(heap.get_ptr(), 3, reference, 2, 511L) |> ignore
    assert_eq(gc_word_access(heap.get_ptr(), 2, reference, 2, 0L), expected)
    heap.collect([]) |> ignore
    assert_eq(gc_word_access(heap.get_ptr(), 4, reference, 0, 0L), 0L)
    assert_eq(gc_word_access(heap.get_ptr(), 0, 2L, 1, 0L), 0L)
  }
}
