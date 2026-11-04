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

///|
test "pre-marked native graphs seed exactly the next precise collection" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  defer heap.clear_root_visitor()
  let pointer = heap.get_ptr()
  let child = heap.alloc_struct(0, [I32(42)])
  let child_word = @wasmoon_jit.encode_heap_ref(child)
  assert_true(pointer.define_layout(7, [-8], false))
  let reference = pointer.allocate_typed(7, 7, [child_word, 0L], 1, false)
  assert_true(reference > 0)
  let graph = pointer.begin_trace()
  assert_eq(graph.expand(reference), [0L, child_word, 1L])
  graph.mark()
  heap.bind_root_visitor(fn(_, roots) {
    for word in roots {
      if word == reference.to_int64() << 1 {
        // The native graph leaves this untyped child to the embedding visitor.
        return [child_word]
      }
    }
    roots
  })
  assert_eq(heap.collect([]), 0)
  assert_true(heap.is_valid(reference - 1))
  assert_true(heap.is_valid(child))
  assert_eq(heap.collect([]), 2)
  assert_false(heap.is_valid(reference - 1))
  assert_false(heap.is_valid(child))
  assert_true(heap.verify())
}

///|
test "completion and abort callbacks preserve marks for the next collection" {
  for abort in [false, true] {
    for rollback in [false, true] {
      let heap = @wasmoon_jit.CHeap()
      defer heap.free()
      defer heap.clear_root_visitor()
      let pointer = heap.get_ptr()
      assert_true(pointer.define_layout(7, [-8], false))
      let undo = heap.make_allocation_rollback(fn() { [] })
      let child = Ref(-1)
      let created = Ref(0)
      let expanded = Ref(false)
      heap.bind_root_visitor(fn(phase, roots) {
        if phase == 0 && abort && created.val == 0 {
          return [-2L]
        }
        if phase == (if abort { 2 } else { 1 }) && created.val == 0 {
          child.val = heap.alloc_struct(0, [I32(42)]) catch { _ => -1 }
          let word = @wasmoon_jit.encode_heap_ref(child.val)
          let reference = pointer.allocate_typed(7, 7, [word, 0L], 1, false)
          created.val = reference
          let graph = pointer.begin_trace()
          expanded.val = graph.expand(reference) == [0L, word, 1L]
          graph.mark()
        }
        if phase == 0 {
          for word in roots {
            if word == created.val.to_int64() << 1 {
              return [@wasmoon_jit.encode_heap_ref(child.val)]
            }
          }
        }
        roots
      })
      if rollback {
        undo()
      } else {
        assert_eq(heap.collect([]), if abort { -1 } else { 0 })
      }
      assert_true(created.val > 0)
      assert_true(expanded.val)
      assert_eq(heap.collect([]), 0)
      assert_true(heap.is_valid(created.val - 1))
      assert_true(heap.is_valid(child.val))
      assert_eq(heap.collect([]), 2)
      assert_false(heap.is_valid(created.val - 1))
      assert_false(heap.is_valid(child.val))
      assert_true(heap.verify())
    }
  }
}

///|
test "collection preserves sparse page survivors without recycling identities" {
  for precise in [false, true] {
    let heap = @wasmoon_jit.CHeap()
    defer heap.free()
    defer heap.clear_root_visitor()
    if precise {
      heap.bind_root_visitor(fn(_, roots) { roots })
    }
    let selected = [0, 1023, 1024, 2048, 4096]
    let previous : Array[Int32] = []
    for round in 0..<3 {
      let objects : Array[Int32] = []
      for index in 0..<4097 {
        let identity = round * 4097 + index
        // Odd scalar words cannot resemble conservative heap roots.
        let object = heap.alloc_struct(0, [I32(identity * 2 + 1)])
        assert_eq(object, identity)
        objects.push(object)
      }
      let roots : Array[@types.Value] = []
      for index in selected {
        roots.push(StructRef(objects[index]))
      }
      assert_eq(
        heap.collect(roots),
        4097 + previous.length() - selected.length(),
      )
      assert_eq(heap.get_object_count(), (round + 1) * 4097)
      for object in previous {
        assert_false(heap.is_valid(object))
      }
      previous.clear()
      for index in 0..<objects.length() {
        let object = objects[index]
        assert_eq(heap.is_valid(object), selected.contains(index))
        if selected.contains(index) {
          assert_eq(heap.struct_get(object, 0, I32), I32(object * 2 + 1))
          previous.push(object)
        }
      }
      assert_true(heap.verify())
    }
    assert_eq(heap.collect([]), selected.length())
    for object in previous {
      assert_false(heap.is_valid(object))
    }
    let fresh = heap.alloc_struct(0, [I32(42)])
    assert_eq(fresh, 3 * 4097)
    assert_eq(heap.struct_get(fresh, 0, I32), I32(42))
    assert_true(heap.verify())
  }
}
