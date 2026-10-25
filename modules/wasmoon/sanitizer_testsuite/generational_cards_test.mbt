///|
#borrow(heap)
extern "c" fn generation_unknown_write(
  heap : @wasmoon_jit.GCHeapHandle,
  reference : Int32,
  field : Int32,
  word : Int64,
) -> Bool = "wasmoon_test_heap_unknown_reference_write"

///|
test "young reference cards cover distant words fill copy and overlap boundaries" {
  let length = 32769
  for operation in 0..<4 {
    let heap = @wasmoon_jit.CHeap()
    defer heap.free()
    defer heap.clear_root_visitor()
    let pointer = heap.get_ptr()
    assert_true(pointer.define_layout(7, [-8], true))
    assert_true(pointer.define_layout(8, [4], false))
    let owner = pointer.allocate_typed(7, 7, [0L, 0L], length, true)
    bind_generation_roots(heap)
    assert_eq(heap.collect([ArrayRef(owner - 1)]), 0)
    assert_eq(generation_dirty_cards(pointer, owner), 0)
    let a = pointer.allocate_typed(8, 8, [41L, 0L], 1, false)
    let b = pointer.allocate_typed(8, 8, [42L, 0L], 1, false)
    let unused = pointer.allocate_typed(8, 8, [99L, 0L], 1, false)
    let source = pointer.allocate_typed(
      7,
      7,
      FixedArray::makei(length * 2, fn(i) {
        if i % 2 == 1 {
          0L
        } else {
          (if i % 4 == 0 { a } else { b }).to_int64() << 1
        }
      }),
      length,
      false,
    )
    let expected : Array[(Int32, Int32)] = match operation {
      0 => {
        heap.array_set(owner - 1, 0, StructRef(a - 1))
        heap.array_set(owner - 1, 16384, StructRef(b - 1))
        heap.array_set(owner - 1, length - 1, StructRef(a - 1))
        assert_eq(generation_dirty_cards(pointer, owner), 3)
        [(0, a), (16384, b), (length - 1, a)]
      }
      1 => {
        heap.array_fill(owner - 1, 255, StructRef(a - 1), 4)
        heap.array_fill(owner - 1, 16383, StructRef(b - 1), 3)
        assert_eq(generation_dirty_cards(pointer, owner), 4)
        [(255, a), (258, a), (16383, b), (16385, b)]
      }
      2 => {
        heap.array_copy(owner - 1, 255, source - 1, 0, 600)
        assert_eq(generation_dirty_cards(pointer, owner), 4)
        [(255, a), (256, b), (853, a), (854, b)]
      }
      _ => {
        for i in 0..<4 {
          heap.array_set(
            owner - 1,
            254 + i,
            StructRef((if i % 2 == 0 { a } else { b }) - 1),
          )
        }
        heap.array_copy(owner - 1, 255, owner - 1, 254, 4)
        heap.array_copy(owner - 1, 253, owner - 1, 255, 4)
        heap.array_copy(owner - 1, length - 3, owner - 1, 253, 3)
        assert_eq(generation_dirty_cards(pointer, owner), 4)
        [
          (253, a),
          (254, b),
          (255, a),
          (256, b),
          (length - 3, a),
          (length - 2, b),
          (length - 1, a),
        ]
      }
    }
    assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 2)
    assert_eq(generation_minor_count(pointer), 1)
    assert_eq(generation_dirty_cards(pointer, owner), 0)
    assert_false(heap.is_valid(source - 1))
    assert_false(heap.is_valid(unused - 1))
    for (field, child) in expected {
      assert_eq(
        heap.array_get(owner - 1, field, StructRef),
        StructRef(child - 1),
      )
    }
    assert_eq(heap.struct_get(a - 1, 0, I32), I32(41))
    assert_eq(heap.struct_get(b - 1, 0, I32), I32(42))
    assert_true(heap.verify())
    assert_eq(heap.collect([]), 3)
    assert_true(heap.verify())
  }
}

///|
test "mixed large struct cards retain references without rooting numeric lookalikes" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  let fields = 16385
  assert_true(
    pointer.define_layout(
      7,
      FixedArray::makei(fields, i => {
        if i == 0 || i == 8192 || i == fields - 1 {
          -8
        } else {
          8
        }
      }),
      false,
    ),
  )
  assert_true(pointer.define_layout(8, [4], false))
  let owner = pointer.allocate_typed(
    7,
    7,
    FixedArray::make(fields * 2, 0L),
    fields,
    false,
  )
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(owner - 1)]), 0)
  assert_eq(generation_dirty_cards(pointer, owner), 0)
  let a = pointer.allocate_typed(8, 8, [41L, 0L], 1, false)
  let b = pointer.allocate_typed(8, 8, [42L, 0L], 1, false)
  let unused = pointer.allocate_typed(8, 8, [99L, 0L], 1, false)
  heap.struct_set(owner - 1, 1, I64(unused.to_int64() << 1))
  heap.struct_set(owner - 1, 0, StructRef(a - 1))
  heap.struct_set(owner - 1, 8192, StructRef(b - 1))
  heap.struct_set(owner - 1, fields - 1, StructRef(a - 1))
  assert_eq(generation_dirty_cards(pointer, owner), 3)
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 1)
  assert_eq(generation_minor_count(pointer), 1)
  assert_false(heap.is_valid(unused - 1))
  assert_eq(heap.struct_get(owner - 1, 8192, StructRef), StructRef(b - 1))
  assert_eq(heap.struct_get(a - 1, 0, I32), I32(41))
  assert_eq(heap.struct_get(b - 1, 0, I32), I32(42))
  assert_eq(generation_dirty_cards(pointer, owner), 0)
  assert_true(heap.verify())
  assert_eq(heap.collect([]), 3)
}

///|
test "unknown reference writes retain whole-object scanning fallback" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], true))
  assert_true(pointer.define_layout(8, [4], false))
  let owner = pointer.allocate_typed(7, 7, [0L, 0L], 8193, true)
  bind_generation_roots(heap)
  assert_eq(heap.collect([ArrayRef(owner - 1)]), 0)
  assert_eq(generation_dirty_cards(pointer, owner), 0)
  let child = pointer.allocate_typed(8, 8, [42L, 0L], 1, false)
  assert_true(
    generation_unknown_write(pointer, owner, 8192, child.to_int64() << 1),
  )
  assert_eq(generation_dirty_cards(pointer, owner), -1)
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  assert_eq(generation_minor_count(pointer), 1)
  assert_eq(heap.struct_get(child - 1, 0, I32), I32(42))
  assert_eq(generation_dirty_cards(pointer, owner), 0)
  assert_true(heap.verify())
  assert_eq(heap.collect([]), 2)
}

///|
test "card metadata retires with objects across rollback and identity reuse" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], true))
  assert_true(pointer.define_layout(8, [4], false))
  let anchor = pointer.allocate_typed(8, 8, [7L, 0L], 1, false)
  bind_generation_roots(heap)
  assert_eq(heap.collect([StructRef(anchor - 1)]), 0)
  let baseline = generation_identity_bytes(pointer)
  let rollback = heap.make_allocation_rollback(fn() { [StructRef(anchor - 1)] })
  let owner = pointer.allocate_typed(7, 7, [0L, 0L], 8193, true)
  assert_eq(heap.collect([StructRef(anchor - 1), ArrayRef(owner - 1)]), 0)
  assert_eq(generation_dirty_cards(pointer, owner), 0)
  assert_true(generation_identity_bytes(pointer) > baseline + 8192L)
  let child = pointer.allocate_typed(8, 8, [42L, 0L], 1, false)
  heap.array_set(owner - 1, 8192, StructRef(child - 1))
  assert_eq(generation_dirty_cards(pointer, owner), 1)
  rollback()
  assert_false(heap.is_valid(owner - 1))
  assert_false(heap.is_valid(child - 1))
  assert_eq(generation_identity_bytes(pointer), baseline)
  assert_true(heap.verify())
  let replacement = pointer.allocate_typed(7, 7, [0L, 0L], 8193, true)
  assert_eq(replacement, owner)
  assert_eq(generation_dirty_cards(pointer, replacement), -2)
  assert_eq(heap.collect([StructRef(anchor - 1), ArrayRef(replacement - 1)]), 0)
  assert_eq(generation_dirty_cards(pointer, replacement), 0)
  assert_eq(heap.collect([StructRef(anchor - 1)]), 1)
  assert_eq(generation_identity_bytes(pointer), baseline)
  assert_true(heap.verify())
}

///|
test "aborted young discovery preserves distant reference cards for retry" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], true))
  assert_true(pointer.define_layout(8, [4], false))
  let owner = pointer.allocate_typed(7, 7, [0L, 0L], 8193, true)
  bind_generation_roots(heap)
  assert_eq(heap.collect([ArrayRef(owner - 1)]), 0)
  assert_eq(generation_dirty_cards(pointer, owner), 0)
  let child = pointer.allocate_typed(8, 8, [42L, 0L], 1, false)
  heap.array_set(owner - 1, 8192, StructRef(child - 1))
  heap.bind_generational_root_visitor(
    fn(phase, roots) {
      if phase == 0 {
        generation_roots(pointer, roots, false)
      } else {
        []
      }
    },
    fn(_roots) { Some([-2L]) },
  )
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), -1)
  assert_true(heap.is_valid(child - 1))
  bind_generation_roots(heap)
  assert_eq(generation_collection(pointer, [owner.to_int64() << 1]), 0)
  assert_eq(generation_minor_count(pointer), 1)
  assert_eq(heap.struct_get(child - 1, 0, I32), I32(42))
  assert_eq(generation_dirty_cards(pointer, owner), 0)
  assert_true(heap.verify())
  assert_eq(heap.collect([]), 2)
}

///|
test "optional card preparation preserves native allocation failure controls" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  assert_true(pointer.define_layout(7, [-8], true))
  let owner = pointer.allocate_typed(7, 7, [0L, 0L], 8193, true)
  // All fields are null, so this seed alone is a complete root graph without
  // allocating a native worklist that would consume the controlled failure.
  heap.bind_generational_root_visitor(fn(_phase, roots) { roots }, fn(_roots) {
    None
  })
  defer runtime_fail_native_allocation(0)
  runtime_fail_native_allocation(1)
  assert_eq(heap.collect([ArrayRef(owner - 1)]), 0)
  assert_eq(generation_dirty_cards(pointer, owner), -2)
  assert_eq(pointer.begin_trace().expand(owner), [-2L])
  runtime_fail_native_allocation(0)
  assert_eq(heap.collect([ArrayRef(owner - 1)]), 0)
  assert_eq(generation_dirty_cards(pointer, owner), 0)
  assert_true(heap.verify())
  assert_eq(heap.collect([]), 1)
}
