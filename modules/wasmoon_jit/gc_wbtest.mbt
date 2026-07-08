///|
/// GC Algorithm Tests
/// Tests for mark-sweep-compact garbage collection

// ============================================================
// Test 1: Unreachable objects are collected
// ============================================================

///|
test "gc: collect root args from reference-typed heap values" {
  inspect(value_type_may_hold_gc_ref(RefStruct(0)), content="true")
  inspect(value_type_may_hold_gc_ref(I64), content="false")
  inspect(value_type_may_hold_gc_ref(ExternRef), content="false")
  debug_inspect(
    collect_gc_root_args([2L, 3L, 4L, 6L], [
      RefStruct(0),
      RefArray(0),
      I64,
      RefNullEq,
    ]),
    content="[2, 6]",
  )
}

///|
test "gc: unreachable objects are collected" {
  let heap = CHeap::new()

  // Allocate 3 structs, none are roots
  let _obj1 = heap.alloc_struct(0, [I32(1)])
  let _obj2 = heap.alloc_struct(0, [I32(2)])
  let _obj3 = heap.alloc_struct(0, [I32(3)])

  // All 3 should exist
  inspect(heap.get_object_count(), content="3")

  // Collect with no roots - all should be freed
  let collected = heap.collect([])
  inspect(collected, content="3")
}

// ============================================================
// Test 2: Rooted objects survive collection
// ============================================================

///|
test "gc: rooted objects survive" {
  let heap = CHeap::new()

  // Allocate 3 structs
  let obj1 = heap.alloc_struct(0, [I32(1)])
  let obj2 = heap.alloc_struct(0, [I32(2)])
  let _obj3 = heap.alloc_struct(0, [I32(3)])

  // Only obj1 and obj2 are roots
  let roots = [@types.Value::StructRef(obj1), StructRef(obj2)]
  let collected = heap.collect(roots)

  // Only obj3 should be collected
  inspect(collected, content="1")

  // obj1 and obj2 should still be valid
  inspect(heap.is_valid(obj1), content="true")
  inspect(heap.is_valid(obj2), content="true")
}

// ============================================================
// Test 3: Reference chain keeps all reachable objects alive
// ============================================================

///|
test "gc: reference chain keeps objects alive" {
  let heap = CHeap::new()

  // Create chain: obj1 -> obj2 -> obj3
  // obj3 has no references
  let obj3 = heap.alloc_struct(0, [I32(3)])
  // obj2 references obj3
  let obj2 = heap.alloc_struct(0, [StructRef(obj3)])
  // obj1 references obj2
  let obj1 = heap.alloc_struct(0, [StructRef(obj2)])

  // Also allocate an unreachable object
  let _unreachable = heap.alloc_struct(0, [I32(999)])

  // Only obj1 is a root, but obj2 and obj3 should survive via references
  let roots = [@types.Value::StructRef(obj1)]
  let collected = heap.collect(roots)

  // Only the unreachable object should be collected
  inspect(collected, content="1")

  // All chained objects should be valid
  inspect(heap.is_valid(obj1), content="true")
  inspect(heap.is_valid(obj2), content="true")
  inspect(heap.is_valid(obj3), content="true")
}

// ============================================================
// Test 4: Circular references without root are collected
// ============================================================

///|
test "gc: circular references without root are collected" {
  let heap = CHeap::new()

  // Create two objects that will reference each other
  // First allocate with placeholder values
  let obj1 = heap.alloc_struct(0, [I32(0)])
  let obj2 = heap.alloc_struct(0, [I32(0)])

  // Now set up circular references: obj1 -> obj2, obj2 -> obj1
  heap.struct_set(obj1, 0, StructRef(obj2))
  heap.struct_set(obj2, 0, StructRef(obj1))

  // Also allocate a rooted object
  let rooted = heap.alloc_struct(0, [I32(42)])

  // Only 'rooted' is a root - circular pair should be collected
  let roots = [@types.Value::StructRef(rooted)]
  let collected = heap.collect(roots)

  // Both circular objects should be collected
  inspect(collected, content="2")
  inspect(heap.is_valid(rooted), content="true")
  inspect(heap.is_valid(obj1), content="false")
  inspect(heap.is_valid(obj2), content="false")
}

// ============================================================
// Test 5: Array elements are traced
// ============================================================

///|
test "gc: array elements are traced" {
  let heap = CHeap::new()

  // Create leaf objects
  let leaf1 = heap.alloc_struct(0, [I32(1)])
  let leaf2 = heap.alloc_struct(0, [I32(2)])
  let leaf3 = heap.alloc_struct(0, [I32(3)])

  // Create array containing references to leaf objects
  let arr = heap.alloc_array_from_values(0, [
    StructRef(leaf1),
    StructRef(leaf2),
    StructRef(leaf3),
  ])

  // Create unreachable object
  let _unreachable = heap.alloc_struct(0, [I32(999)])

  // Only array is root, but all leaf objects should survive
  let roots = [@types.Value::ArrayRef(arr)]
  let collected = heap.collect(roots)
  inspect(collected, content="1")
  inspect(heap.is_valid(arr), content="true")
  inspect(heap.is_valid(leaf1), content="true")
  inspect(heap.is_valid(leaf2), content="true")
  inspect(heap.is_valid(leaf3), content="true")
}

// ============================================================
// Test 6: Multiple GC cycles work correctly
// ============================================================

///|
test "gc: multiple collection cycles" {
  let heap = CHeap::new()

  // First cycle: create and collect
  let obj1 = heap.alloc_struct(0, [I32(1)])
  let _temp1 = heap.alloc_struct(0, [I32(100)])
  let collected1 = heap.collect([StructRef(obj1)])
  inspect(collected1, content="1")

  // Second cycle: add more objects
  let obj2 = heap.alloc_struct(0, [I32(2)])
  let _temp2 = heap.alloc_struct(0, [I32(200)])
  let _temp3 = heap.alloc_struct(0, [I32(300)])
  let collected2 = heap.collect([StructRef(obj1), StructRef(obj2)])
  inspect(collected2, content="2")

  // Both survivors should still be valid
  inspect(heap.is_valid(obj1), content="true")
  inspect(heap.is_valid(obj2), content="true")

  // Stats should reflect all cycles
  inspect(heap.get_total_collections(), content="2")
}

// ============================================================
// Test 7: Deep reference chain
// ============================================================

///|
test "gc: deep reference chain" {
  let heap = CHeap::new()

  // Create a chain of 10 objects
  let mut prev = heap.alloc_struct(0, [I32(0)]) // leaf
  for i in 1..<10 {
    let curr = heap.alloc_struct(0, [StructRef(prev)])
    prev = curr
    ignore(i)
  }
  let head = prev

  // Add some garbage
  for _ in 0..<5 {
    let _ = heap.alloc_struct(0, [I32(999)])
  }
  inspect(heap.get_object_count(), content="15")

  // Only head is root, entire chain should survive
  let collected = heap.collect([StructRef(head)])
  inspect(collected, content="5") // 5 garbage objects collected
}

// ============================================================
// Test 8: i31 values are not treated as references
// ============================================================

///|
test "gc: i31 values are not traced as references" {
  let heap = CHeap::new()

  // Create struct with i31 value that looks like a valid gc_ref
  // i31 encoding: (value << 1) | 1
  // If value=0, encoded i31 = 1, which could be confused with gc_ref=1
  let obj = heap.alloc_struct(0, [I31(0)])

  // Create another object
  let _other = heap.alloc_struct(0, [I32(42)])

  // Collect with obj as root
  // The i31(0) in obj should NOT keep _other alive (gc_ref encoding is different)
  let collected = heap.collect([StructRef(obj)])

  // _other should be collected (i31 is tagged, not a heap ref)
  inspect(collected, content="1")
}

// ============================================================
// Test 9: Heap size tracking (preparation for compaction test)
// ============================================================

///|
test "gc: heap size after allocation and collection" {
  let heap = CHeap::new()
  let initial_size = heap.get_size()
  inspect(initial_size, content="0")

  // Allocate some objects
  let obj1 = heap.alloc_struct(0, [I32(1)])
  let _obj2 = heap.alloc_struct(0, [I32(2)])
  let _obj3 = heap.alloc_struct(0, [I32(3)])
  let size_after_alloc = heap.get_size()
  // Each struct: 16 (header) + 8 (one i64 field) = 24, aligned to 32
  // 3 objects = 96 bytes
  inspect(size_after_alloc, content="96")

  // Collect - keep only obj1
  let _ = heap.collect([StructRef(obj1)])

  // After compaction, only obj1 remains: 32 bytes
  let size_after_gc = heap.get_size()
  inspect(size_after_gc, content="32")
}

// ============================================================
// Test 10: Reference validity after collection
// ============================================================

///|
test "gc: field access after collection" {
  let heap = CHeap::new()

  // Create objects with distinct values
  let leaf = heap.alloc_struct(0, [I32(42)])
  let parent = heap.alloc_struct(0, [StructRef(leaf), I64(12345L)])

  // Add garbage
  for _ in 0..<10 {
    let _ = heap.alloc_struct(0, [I32(999)])
  }

  // Collect
  let _ = heap.collect([StructRef(parent)])

  // Verify we can still access fields correctly
  let field0 = heap.struct_get(parent, 0, RefStruct(0))
  let field1 = heap.struct_get(parent, 1, I64)
  inspect(field0, content="StructRef(0)")
  inspect(field1, content="I64(12345)")

  // Access the referenced object
  let leaf_value = heap.struct_get(leaf, 0, I32)
  inspect(leaf_value, content="I32(42)")
}

///|
test "gc: heap verify succeeds on valid graph" {
  let heap = CHeap::new()
  let leaf = heap.alloc_struct(0, [I32(7)])
  let root = heap.alloc_struct(0, [StructRef(leaf)])
  let _ = heap.collect([StructRef(root)])
  inspect(heap.verify(), content="true")
}

///|
test "gc: heap verify allows non-reference immediates" {
  let heap = CHeap::new()
  let obj = heap.alloc_struct(0, [I32(1)])
  // Large even i64 payload is a valid immediate value, not necessarily a GC ref.
  heap.struct_set(obj, 0, I64(2000000L))
  inspect(heap.verify(), content="true")
}

///|
test "gc: barrier write counter tracks reference stores" {
  let heap = CHeap::new()
  let object0 = heap.alloc_struct(0, [I32(10)])
  let object1 = heap.alloc_struct(0, [I32(20)])
  let array0 = heap.alloc_array(0, 2, I32(0))

  heap.struct_set(object0, 0, StructRef(object1))
  heap.array_set(array0, 0, StructRef(object0))
  inspect(heap.get_barrier_writes(), content="2")
}

///|
test "gc: fault injection fails configured allocation attempt" {
  gc_debug_set_fail_alloc(2)
  let heap_ptr = @jit_ffi.c_gc_heap_new(1024L)
  let fields = FixedArray::makei(1, fn(_) { 1L })

  let first = @jit_ffi.c_gc_heap_alloc_struct(heap_ptr, 0, fields, 1)
  let second = @jit_ffi.c_gc_heap_alloc_struct(heap_ptr, 0, fields, 1)

  inspect(first > 0, content="true")
  inspect(second == 0, content="true")

  @jit_ffi.c_gc_heap_free(heap_ptr)
  gc_debug_set_fail_alloc(0)
}

///|
test "gc: c_heap allocation fault is surfaced as OutOfMemory" {
  gc_debug_set_fail_alloc(1)
  let heap = CHeap::new(capacity=1024)
  let failed = try heap.alloc_struct(0, [I32(123)]) catch {
    OutOfMemory => true
    _ => false
  } noraise {
    _ => false
  }
  gc_debug_set_fail_alloc(0)

  guard failed else { fail("expected OutOfMemory") }
}

///|
test "gc_setup: fail fast on inconsistent function table context" {
  let heap = CHeap::new()
  let jit_ctx = @jit_ffi.c_jit_alloc_context_managed(1)
  let ctx_ptr = @jit_ffi.c_jit_context_ptr(jit_ctx)
  let missing_types = try
    gc_setup(
      heap,
      [],
      [],
      ctx_ptr~,
      func_type_indices=[],
      func_table_ptr=0L,
      num_funcs=1,
    )
  catch {
    FuncTypeIndicesLengthMismatch(func_type_indices_len=0, num_funcs=1) => true
    _ => false
  } noraise {
    _ => false
  }
  guard missing_types else {
    fail("expected func_type_indices length mismatch")
  }
  let missing_table_ptr = try
    gc_setup(
      heap,
      [],
      [],
      ctx_ptr~,
      func_type_indices=[0],
      func_table_ptr=0L,
      num_funcs=1,
    )
  catch {
    MissingFunctionTableContext(num_funcs=1) => true
    _ => false
  } noraise {
    _ => false
  }
  guard missing_table_ptr else {
    fail("expected missing function table context")
  }
  let zero_funcs_ok = try
    gc_setup(
      heap,
      [],
      [],
      ctx_ptr~,
      func_type_indices=[],
      func_table_ptr=0L,
      num_funcs=0,
    )
  catch {
    _ => false
  } noraise {
    _ => true
  }
  guard zero_funcs_ok else {
    fail("expected gc_setup success for zero-func module")
  }
  gc_teardown(ctx_ptr)
}

///|
test "gc: collect_for_alloc keeps scratch roots alive" {
  let heap = CHeap::new(capacity=1024)
  let jit_ctx = @jit_ffi.c_jit_alloc_context_managed(0)
  let ctx_ptr = @jit_ffi.c_jit_context_ptr(jit_ctx)
  gc_set_heap(ctx_ptr, heap)

  let rooted = heap.alloc_struct(0, [I32(1)])
  let _unrooted = heap.alloc_struct(0, [I32(2)])

  let rooted_raw = value_to_i64(StructRef(rooted))
  guard gc_set_root_scratch(ctx_ptr, [rooted_raw]) else {
    fail("expected gc_set_root_scratch success")
  }

  let collected = gc_collect_for_alloc(ctx_ptr, [])
  inspect(collected >= 1, content="true")
  inspect(heap.is_valid(rooted), content="true")

  gc_set_root_scratch(ctx_ptr, []) |> ignore
  gc_clear_heap(ctx_ptr)
}

///|
test "gc: begin/end frame API accepts nested scopes" {
  let jit_ctx = @jit_ffi.c_jit_alloc_context_managed(0)
  let ctx_ptr = @jit_ffi.c_jit_context_ptr(jit_ctx)

  gc_begin_frame(ctx_ptr, 100L)
  gc_begin_frame(ctx_ptr, 200L)
  gc_end_frame(ctx_ptr)
  gc_end_frame(ctx_ptr)

  inspect(true, content="true")
}
