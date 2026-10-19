///|
test "collection finishes the captured visitor after it clears its binding" {
  for rollback in [false, true] {
    let heap = @wasmoon_jit.CHeap()
    defer heap.free()
    let undo = heap.make_allocation_rollback(fn() { [] })
    let object = heap.alloc_struct(0, [I32(7)])
    let phases : Array[Int32] = []
    heap.bind_root_visitor(fn(phase, roots) {
      phases.push(phase)
      if phase == 0 {
        heap.clear_root_visitor()
      }
      roots
    })
    if rollback {
      undo()
    } else {
      assert_eq(heap.collect([]), 1)
    }
    assert_eq(phases, [0, 1])
    assert_false(heap.is_valid(object))
    assert_true(heap.verify())
  }
}

///|
test "collection aborts the captured visitor before using its replacement" {
  for rollback in [false, true] {
    let heap = @wasmoon_jit.CHeap()
    defer heap.free()
    let undo = heap.make_allocation_rollback(fn() { [] })
    let object = heap.alloc_struct(0, [I32(7)])
    let original : Array[Int32] = []
    let replacement : Array[Int32] = []
    heap.bind_root_visitor(fn(phase, _) {
      original.push(phase)
      if phase == 0 {
        heap.bind_root_visitor(fn(next_phase, roots) {
          replacement.push(next_phase)
          roots
        })
        [-2L]
      } else {
        []
      }
    })
    if rollback {
      undo()
    } else {
      assert_eq(heap.collect([]), -1)
    }
    assert_eq(original, [0, 2])
    assert_eq(replacement, [])
    assert_true(heap.is_valid(object))
    assert_true(heap.verify())
    assert_eq(heap.collect([]), 1)
    assert_eq(replacement, [0, 1])
    assert_false(heap.is_valid(object))
  }
}

///|
test "collection rejects same-heap reentry without touching the outer roots" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  let object = heap.alloc_struct(0, [I32(7)])
  let nested = Ref(0)
  let entered = Ref(false)
  let phases : Array[Int32] = []
  heap.bind_root_visitor(fn(phase, roots) {
    phases.push(phase)
    if phase == 0 && !entered.val {
      entered.val = true
      nested.val = heap.collect([])
    }
    roots
  })
  assert_eq(heap.collect([StructRef(object)]), 0)
  assert_eq(nested.val, -1)
  assert_eq(phases, [0, 1])
  assert_true(heap.is_valid(object))
  assert_true(heap.verify())
}

///|
test "collection retains its heap and captured visitor after the owner closes" {
  for rollback in [false, true] {
    let heap = @wasmoon_jit.CHeap()
    defer heap.free()
    let undo = heap.make_allocation_rollback(fn() { [] })
    heap.alloc_struct(0, [I32(7)]) |> ignore
    let phases : Array[Int32] = []
    heap.bind_root_visitor(fn(phase, roots) {
      phases.push(phase)
      if phase == 0 {
        heap.free()
      }
      roots
    })
    if rollback {
      undo()
    } else {
      assert_eq(heap.collect([]), 1)
    }
    assert_eq(phases, [0, 1])
    assert_true(heap.get_ptr().is_null())
  }
}

///|
test "collection permits a different heap to collect during its visitor" {
  let first = @wasmoon_jit.CHeap()
  let second = @wasmoon_jit.CHeap()
  defer first.free()
  defer second.free()
  let object = first.alloc_struct(0, [I32(7)])
  let other = second.alloc_struct(0, [I32(8)])
  let phases : Array[Int32] = []
  let nested = Ref(-1)
  first.bind_root_visitor(fn(phase, roots) {
    phases.push(phase)
    if phase == 0 {
      nested.val = second.collect([StructRef(other)])
    }
    roots
  })
  assert_eq(first.collect([StructRef(object)]), 0)
  assert_eq(phases, [0, 1])
  assert_eq(nested.val, 0)
  assert_true(first.is_valid(object))
  assert_true(second.is_valid(other))
}

///|
test "clearing a visitor does not change the current precise marking mode" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  let unrooted = heap.alloc_struct(0, [I32(7)])
  // This integer resembles a heap reference but is not a typed edge. The
  // captured visitor returns the complete typed roots for this collection.
  let carrier = heap.alloc_struct(0, [I64((unrooted + 1).to_int64() << 1)])
  let phases : Array[Int32] = []
  heap.bind_root_visitor(fn(phase, roots) {
    phases.push(phase)
    if phase == 0 {
      heap.clear_root_visitor()
    }
    roots
  })
  assert_eq(heap.collect([StructRef(carrier)]), 1)
  assert_eq(phases, [0, 1])
  assert_true(heap.is_valid(carrier))
  assert_false(heap.is_valid(unrooted))
  assert_true(heap.verify())
}
