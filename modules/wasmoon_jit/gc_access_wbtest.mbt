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

///|
test "array metadata projections preserve exact width opaque layouts and retirement" {
  let heap = CHeap()
  defer heap.free()
  let objects : Array[(Int32, Int32)] = []
  for identity, width in [1, 2, 4, 8, 16] {
    assert_true(heap.get_ptr().define_layout(identity, [width], true))
    let initial : @types.Value = if width == 16 {
      V128(Bytes::make(16, 0))
    } else {
      I64(42L)
    }
    objects.push(
      (heap.alloc_array(identity, 3, initial, runtime_type=identity), width),
    )
  }
  assert_true(heap.get_ptr().define_layout(5, [-8], true))
  objects.push((heap.alloc_array(5, 3, Null, runtime_type=5), 0))
  objects.push((heap.alloc_array(0, 3, I64(17L)), 0))
  for _ in 0..<2 {
    for (object, compact_width) in objects {
      let reference = (object + 1).to_int64() << 1
      let view = gc_word_access(heap.get_ptr(), 5, reference, 0, 0L)
      let payload = view & -16L
      // Verification mode declines a projection and leaves checked access active.
      let tag = if view == 0L {
        0L
      } else {
        match compact_width {
          1 => 1L
          2 => 2L
          4 => 3L
          8 => 4L
          _ => 0L
        }
      }
      assert_eq(view & 15L, tag)
      for requested in [1, 2, 4, 8, 16] {
        assert_eq(
          gc_word_access(heap.get_ptr(), 5, reference, requested, 0L),
          if requested == compact_width {
            payload
          } else {
            0L
          },
        )
      }
      assert_eq(gc_word_access(heap.get_ptr(), 5, reference, 0, 0L), view)
      assert_true(heap.verify())
    }
  }
  heap.collect([]) |> ignore
  for (object, _) in objects {
    assert_false(heap.is_valid(object))
    assert_eq(
      gc_word_access(heap.get_ptr(), 5, (object + 1).to_int64() << 1, 0, 0L),
      0L,
    )
  }
  assert_true(heap.verify())
}

///|
test "native heap preserves live objects across growth and reuse" {
  let heap = CHeap()
  defer heap.free()
  let dead = heap.alloc_struct(0, [I64(17L), I64(18L)])
  let retained = heap.alloc_struct(0, [I64(42L)])
  let base = heap.get_base()
  let offset = heap.get_offset(retained)
  let dead_offset = heap.get_offset(dead)
  let large = heap.alloc_array(0, 100_000, I64(0L))
  assert_true(large >= 0)
  assert_eq(heap.collect([StructRef(retained)]), 2)
  assert_false(heap.is_valid(dead))
  assert_false(heap.is_valid(large))
  assert_eq(heap.struct_get(retained, 0, I64), I64(42L))

  let replacement = heap.alloc_struct(0, [I64(99L)])
  assert_true(replacement > large)
  assert_eq(heap.struct_get(replacement, 0, I64), I64(99L))
  assert_false(heap.is_valid(dead))
  if @env.get_env_var("WASMOON_EXPERIMENT_STABLE_HEAP") is Some("1") {
    assert_eq(heap.get_base(), base)
    assert_eq(heap.get_offset(retained), offset)
    assert_eq(heap.get_offset(replacement), dead_offset)
  }
  assert_true(heap.verify(verbose=true))
}

///|
test "offset references preserve roots and reject interior or recycled slots" {
  if @env.get_env_var("WASMOON_EXPERIMENT_OFFSET_REFS") is Some("1") &&
    @env.get_env_var("WASMOON_EXPERIMENT_STABLE_HEAP") is Some("1") {
    let heap = CHeap()
    defer heap.free()
    assert_true(heap.get_ptr().define_layout(0, [1], true))
    let first = heap.alloc_array(0, 32, I32(37), runtime_type=0)
    let offset = heap.get_offset(first)
    let word = heap.encode_ref_word(first)
    assert_eq(
      word,
      0x0800000000000000L |
      (offset.to_int64() >> 4 << 32) |
      ((first.to_int64() + 1L) << 1),
    )
    assert_eq(gc_word_access(heap.get_ptr(), 2, word, 31, 0L), 37L)
    assert_eq(gc_word_access(heap.get_ptr(), 5, word + (1L << 32), 0, 0L), 0L)
    assert_eq(heap.collect_raw([word]), 0)
    assert_eq(heap.get_offset(first), offset)
    assert_eq(heap.collect([]), 1)
    let next = heap.alloc_array(0, 32, I32(99), runtime_type=0)
    assert_eq(heap.get_offset(next), offset)
    assert_eq(gc_word_access(heap.get_ptr(), 5, word, 0, 0L), 0L)
    assert_eq(heap.collect_raw([word]), 1)
    assert_false(heap.is_valid(next))
    assert_true(heap.verify(verbose=true))
  }
}

///|
test "offset hints resolve moved references through their original identity" {
  if @env.get_env_var("WASMOON_EXPERIMENT_OFFSET_REFS") is Some("1") &&
    @env.get_env_var("WASMOON_EXPERIMENT_STABLE_HEAP") is None {
    let heap = CHeap()
    defer heap.free()
    assert_true(heap.get_ptr().define_layout(0, [1], true))
    let dead = heap.alloc_array(0, 32, I32(6), runtime_type=0)
    let live = heap.alloc_array(0, 32, I32(37), runtime_type=0)
    let offset = heap.get_offset(live)
    let word = heap.encode_ref_word(live)
    assert_eq(
      word,
      0x0800000000000000L |
      (offset.to_int64() >> 4 << 32) |
      ((live.to_int64() + 1L) << 1),
    )
    assert_eq(heap.collect_raw([word]), 1)
    assert_false(heap.is_valid(dead))
    assert_true(heap.get_offset(live) < offset)
    let next = heap.alloc_array(0, 32, I32(99), runtime_type=0)
    assert_eq(heap.get_offset(next), offset)
    assert_eq(gc_word_access(heap.get_ptr(), 2, word, 31, 0L), 37L)
    assert_eq(heap.collect_raw([word]), 1)
    assert_false(heap.is_valid(next))
    assert_true(heap.verify(verbose=true))
  }
}
