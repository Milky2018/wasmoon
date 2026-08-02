///|
fn[T] heap_has_error(
  body : () -> T raise RuntimeError,
  matches : (RuntimeError) -> Bool,
) -> Bool {
  try body() catch {
    err => matches(err)
  } noraise {
    _ => false
  }
}

///|
test "MarkSweepHeap: alloc and get struct" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  let idx = heap.alloc_struct(0, [I32(42), I64(100L)])
  inspect(idx, content="0")
  inspect(heap.length(), content="1")
  let s = heap.get_struct(idx)
  inspect(s.type_idx, content="0")
  inspect(s.fields.length(), content="2")
  inspect(s.fields[0], content="I32(42)")
  inspect(s.fields[1], content="I64(100)")
}

///|
test "MarkSweepHeap: alloc and get array" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  let idx = heap.alloc_array(1, [F32(1.0), F32(2.0), F32(3.0)])
  inspect(idx, content="0")
  let a = heap.get_array(idx)
  inspect(a.type_idx, content="1")
  inspect(a.elements.length(), content="3")
}

///|
test "MarkSweepHeap: struct get/set" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  let idx = heap.alloc_struct(0, [I32(10), I32(20)])

  // Get field
  let v0 = heap.struct_get(idx, 0)
  inspect(v0, content="I32(10)")

  // Set field
  heap.struct_set(idx, 0, I32(100)) |> ignore
  let v1 = heap.struct_get(idx, 0)
  inspect(v1, content="I32(100)")
}

///|
test "MarkSweepHeap: array get/set/len" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  let idx = heap.alloc_array(0, [I32(1), I32(2), I32(3)])

  // Length
  inspect(heap.array_len(idx), content="3")

  // Get element
  inspect(heap.array_get(idx, 1), content="I32(2)")

  // Set element
  heap.array_set(idx, 1, I32(100)) |> ignore
  inspect(heap.array_get(idx, 1), content="I32(100)")
}

///|
test "MarkSweepHeap: array fill" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  let idx = heap.alloc_array(0, [I32(0), I32(0), I32(0), I32(0)])
  heap.array_fill(idx, 1, I32(42), 2) |> ignore
  inspect(heap.array_get(idx, 0), content="I32(0)")
  inspect(heap.array_get(idx, 1), content="I32(42)")
  inspect(heap.array_get(idx, 2), content="I32(42)")
  inspect(heap.array_get(idx, 3), content="I32(0)")
}

///|
test "MarkSweepHeap: array copy" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  let src = heap.alloc_array(0, [I32(1), I32(2), I32(3)])
  let dst = heap.alloc_array(0, [I32(0), I32(0), I32(0)])
  heap.array_copy(dst, 0, src, 1, 2) |> ignore
  inspect(heap.array_get(dst, 0), content="I32(2)")
  inspect(heap.array_get(dst, 1), content="I32(3)")
  inspect(heap.array_get(dst, 2), content="I32(0)")
}

///|
test "MarkSweepHeap: array out of bounds" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  let idx = heap.alloc_array(0, [I32(1), I32(2)])
  inspect(
    heap_has_error(() => heap.array_get(idx, 5), err => {
      err is OutOfBoundsArrayAccess
    }),
    content="true",
  )
  inspect(
    heap_has_error(() => heap.array_set(idx, -1, I32(0)), err => {
      err is OutOfBoundsArrayAccess
    }),
    content="true",
  )
}

///|
test "MarkSweepHeap: type mismatch" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  let struct_idx = heap.alloc_struct(0, [])
  let array_idx = heap.alloc_array(1, [])

  // Try to get struct as array
  inspect(
    heap_has_error(() => heap.get_array(struct_idx), err => err is TypeMismatch),
    content="true",
  )
  // Try to get array as struct
  inspect(
    heap_has_error(() => heap.get_struct(array_idx), err => err is TypeMismatch),
    content="true",
  )
}

///|
test "MarkSweepHeap: get_type_idx" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  let s = heap.alloc_struct(5, [])
  let a = heap.alloc_array(10, [])
  inspect(heap.get_type_idx(s), content="5")
  inspect(heap.get_type_idx(a), content="10")
}

///|
test "MarkSweepHeap: multiple allocations" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  let s1 = heap.alloc_struct(0, [I32(1)])
  let a1 = heap.alloc_array(1, [I64(2L)])
  let s2 = heap.alloc_struct(2, [F32(3.0)])
  inspect(s1, content="0")
  inspect(a1, content="1")
  inspect(s2, content="2")
  inspect(heap.length(), content="3")

  // Verify each object is independent
  inspect(heap.struct_get(s1, 0), content="I32(1)")
  inspect(heap.array_get(a1, 0), content="I64(2)")
  inspect(heap.struct_get(s2, 0), content="F32(3)")
}

// ============================================================
// GC Algorithm Tests
// ============================================================

///|
test "GC: stats initial" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  let stats = heap.stats()
  inspect(stats.total_objects, content="0")
  inspect(stats.live_objects, content="0")
  inspect(stats.free_slots, content="0")
  inspect(stats.collections, content="0")
  inspect(stats.bytes_allocated, content="0")
  inspect(stats.bytes_collected, content="0")
}

///|
test "GC: stats after allocation" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  heap.alloc_struct(0, [I32(1)]) |> ignore
  heap.alloc_array(0, [I32(2)]) |> ignore
  let stats = heap.stats()
  inspect(stats.total_objects, content="2")
  inspect(stats.live_objects, content="2")
  inspect(stats.free_slots, content="0")
  inspect(stats.bytes_allocated, content="48")
  inspect(stats.bytes_collected, content="0")
}

///|
test "GC: collect unreachable objects" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  // Allocate some objects
  heap.alloc_struct(0, [I32(1)]) |> ignore
  heap.alloc_struct(0, [I32(2)]) |> ignore
  heap.alloc_struct(0, [I32(3)]) |> ignore
  inspect(heap.stats().live_objects, content="3")

  // Collect with no roots - all objects should be collected
  let collected = heap.collect([])
  inspect(collected, content="3")
  inspect(heap.stats().live_objects, content="0")
  inspect(heap.stats().free_slots, content="3")
  inspect(heap.stats().collections, content="1")
  inspect(heap.stats().bytes_collected, content="72")
}

///|
test "GC: preserve reachable objects" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  // Allocate objects
  let s1 = heap.alloc_struct(0, [I32(1)])
  heap.alloc_struct(0, [I32(2)]) |> ignore // unreachable
  let s3 = heap.alloc_struct(0, [I32(3)])

  // Collect with s1 and s3 as roots
  let roots = [@types.Value::StructRef(s1), StructRef(s3)]
  let collected = heap.collect(roots)
  inspect(collected, content="1") // Only the middle object collected
  inspect(heap.stats().live_objects, content="2")

  // Verify reachable objects still exist
  inspect(heap.struct_get(s1, 0), content="I32(1)")
  inspect(heap.struct_get(s3, 0), content="I32(3)")
}

///|
test "GC: follow references in structs" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  // Create a chain: s1 -> s2 -> s3
  let s3 = heap.alloc_struct(0, [I32(3)])
  let s2 = heap.alloc_struct(0, [StructRef(s3)])
  let s1 = heap.alloc_struct(0, [StructRef(s2)])
  heap.alloc_struct(0, [I32(999)]) |> ignore // unreachable

  // Collect with only s1 as root - s2 and s3 should be preserved via references
  let collected = heap.collect([StructRef(s1)])
  inspect(collected, content="1") // Only the unreachable object collected
  inspect(heap.stats().live_objects, content="3")

  // Verify all reachable objects still exist
  inspect(heap.is_alive(s1), content="true")
  inspect(heap.is_alive(s2), content="true")
  inspect(heap.is_alive(s3), content="true")
}

///|
test "GC: follow references in arrays" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  // Create objects
  let s1 = heap.alloc_struct(0, [I32(1)])
  let s2 = heap.alloc_struct(0, [I32(2)])
  // Create array containing references to s1 and s2
  let arr = heap.alloc_array(0, [StructRef(s1), StructRef(s2)])
  heap.alloc_struct(0, [I32(999)]) |> ignore // unreachable

  // Collect with only array as root
  let collected = heap.collect([ArrayRef(arr)])
  inspect(collected, content="1")
  inspect(heap.stats().live_objects, content="3")
}

///|
test "GC: reuse freed slots" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  // Allocate and collect
  heap.alloc_struct(0, [I32(1)]) |> ignore
  heap.alloc_struct(0, [I32(2)]) |> ignore
  heap.collect([]) |> ignore

  // Allocate again - should reuse freed slots
  let new1 = heap.alloc_struct(0, [I32(10)])
  let new2 = heap.alloc_struct(0, [I32(20)])
  // Slots should be reused (indices 0 or 1)
  inspect(new1 < 2, content="true")
  inspect(new2 < 2, content="true")
  inspect(heap.length(), content="2") // No new slots allocated

  // Verify new objects work correctly
  inspect(heap.struct_get(new1, 0), content="I32(10)")
  inspect(heap.struct_get(new2, 0), content="I32(20)")
}

///|
test "GC: threshold check" {
  let heap = MarkSweepHeap::with_threshold(5)
  inspect(heap.get_threshold(), content="5")
  inspect(heap.should_collect(), content="false")

  // Allocate until threshold
  for i in 0..<5 {
    heap.alloc_struct(0, [I32(i)]) |> ignore
  }
  inspect(heap.should_collect(), content="true")
}

///|
test "GC: collected object becomes inaccessible" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  let idx = heap.alloc_struct(0, [I32(42)])
  inspect(heap.is_alive(idx), content="true")

  // Collect with no roots
  heap.collect([]) |> ignore
  inspect(heap.is_alive(idx), content="false")

  // Trying to access collected object should fail
  inspect(
    heap_has_error(() => heap.get(idx), err => err is UndefinedElement),
    content="true",
  )
}

///|
test "GC rollback: rooted transaction object is not reclaimed or reused" {
  let heap = MarkSweepHeap::MarkSweepHeap()
  heap.alloc_struct(0, [I32(1)]) |> ignore
  heap.collect([]) |> ignore
  let checkpoint = heap.checkpoint_allocations()
  let escaped = heap.alloc_struct(0, [I32(7)])
  let garbage = heap.alloc_struct(0, [I32(8)])

  heap.rollback_allocations(checkpoint, [StructRef(escaped)])
  debug_inspect(
    (
      escaped,
      garbage,
      heap.is_alive(escaped),
      heap.is_alive(garbage),
      heap.struct_get(escaped, 0),
    ),
    content="(0, 1, true, false, I32(7))",
  )

  let next = heap.alloc_struct(0, [I32(9)])
  debug_inspect(
    (escaped, next, heap.struct_get(escaped, 0)),
    content="(0, 1, I32(7))",
  )
}
