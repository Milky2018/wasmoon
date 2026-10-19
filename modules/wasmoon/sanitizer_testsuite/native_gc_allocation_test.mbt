///|
fn native_gc_allocation_module() -> @types.Module raise {
  let source =
    #|(module
    #|  (type $s (struct (field i32)))
    #|  (type $a (array i32))
    #|  (type $v (struct (field v128)))
    #|  (type $av (array v128))
    #|  (func (export "struct") (result i32)
    #|    (struct.get $s 0 (struct.new $s (i32.const 42))))
    #|  (func (export "array") (result i32)
    #|    (array.get $a (array.new $a (i32.const 42) (i32.const 2)) (i32.const 1)))
    #|  (func (export "fixed") (result i32)
    #|    (array.get $a (array.new_fixed $a 2 (i32.const 41) (i32.const 42)) (i32.const 1)))
    #|  (func (export "wide-struct") (result i32)
    #|    (i32x4.extract_lane 3 (struct.get $v 0 (struct.new $v (v128.const i32x4 1 2 3 42)))))
    #|  (func (export "wide-array") (result i32)
    #|    (i32x4.extract_lane 3 (array.get $av
    #|      (array.new $av (v128.const i32x4 1 2 3 42) (i32.const 2)) (i32.const 1))))
    #|  (func (export "wide-fixed") (result i32)
    #|    (i32x4.extract_lane 3 (array.get $av
    #|      (array.new_fixed $av 2 (v128.const i32x4 1 2 3 41)
    #|        (v128.const i32x4 1 2 3 42)) (i32.const 1)))))
  @wat.parse(source)
}

///|
test "all native allocation layouts retry and preserve payloads" {
  let module_ = native_gc_allocation_module()
  @validator.validate_module(module_)
  // A budget makes scalar allocations enter the allocator instead of writing
  // an inline object; fault injection then exercises its collection retry.
  let budget = @runtime.ResourceBudget::new(gc_bytes=4096L, gc_objects=64L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
  for index in 0..<6 {
    @wasmoon_jit.gc_debug_set_fail_alloc(1)
    assert_eq(context.call_core_func(store, instance, index, []), [I32(42)])
    @wasmoon_jit.gc_debug_set_fail_alloc(0, fail_every=1)
    try context.call_core_func(store, instance, index, []) catch {
      Trap(message) => assert_eq(message, "out of memory")
      error => fail(error.to_string())
    } noraise {
      _ => fail("persistent allocation failure was ignored")
    }
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    assert_eq(context.call_core_func(store, instance, index, []), [I32(42)])
  }
  store.collect_garbage() |> ignore
  assert_eq(budget.used(GcBytes), 0L)
}

///|
test "allocation root visitor failure stays distinct from exhaustion and aborts before reuse" {
  let module_ = native_gc_allocation_module()
  let store = @runtime.Store::with_c_heap(
    resource_budget=Some(@runtime.ResourceBudget::new(gc_bytes=4096L)),
  )
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  let heap = store.native_heap().unwrap()
  defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
  for index in 0..<6 {
    let aborted = Ref(0)
    store.begin_gc_tracing()
    heap.bind_root_visitor(fn(phase, _) {
      if phase == 2 {
        aborted.val += 1
      }
      if phase == 0 {
        [-2L]
      } else {
        []
      }
    })
    @wasmoon_jit.gc_debug_set_fail_alloc(1)
    try context.call_core_func(store, instance, index, []) catch {
      Trap(message) => assert_eq(message, "gc precise roots unavailable")
      error => fail(error.to_string())
    } noraise {
      _ => fail("allocation continued after its root visitor failed")
    }
    store.end_gc_tracing()
    assert_eq(aborted.val, 1)
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    assert_eq(context.call_core_func(store, instance, index, []), [I32(42)])
  }
}

///|
test "all native allocation layouts retain byte and identity quota classifications" {
  let module_ = native_gc_allocation_module()
  for byte_limit in [false, true] {
    let budget = if byte_limit {
      @runtime.ResourceBudget::new(gc_bytes=0L)
    } else {
      @runtime.ResourceBudget::new(gc_objects=0L)
    }
    let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = build_gc_root_context(module_, instance, store)
    defer context.close()
    for index in 0..<6 {
      try context.call_core_func(store, instance, index, []) catch {
        HostInvocation(ResourceLimitExceeded(kind)) =>
          assert_eq(kind, if byte_limit { GcBytes } else { GcObjects })
        error => fail(error.to_string())
      } noraise {
        _ => fail("allocation escaped its quota")
      }
      assert_eq(budget.used(GcBytes), 0L)
      assert_eq(budget.used(GcObjects), 0L)
    }
  }
}

///|
test "allocation retry keeps references staged in scalar and mixed vector payloads" {
  let source =
    #|(module
    #|  (type $leaf (struct (field i32)))
    #|  (type $scalar (struct (field (ref $leaf))))
    #|  (type $mixed (struct (field v128) (field (ref $leaf))))
    #|  (type $array (array (ref $leaf)))
    #|  (func (export "scalar") (result i32)
    #|    (struct.get $leaf 0 (struct.get $scalar 0
    #|      (struct.new $scalar (struct.new $leaf (i32.const 42))))))
    #|  (func (export "mixed") (result i32)
    #|    (struct.get $leaf 0 (struct.get $mixed 1
    #|      (struct.new $mixed (v128.const i64x2 -1 -2) (struct.new $leaf (i32.const 42))))))
    #|  (func (export "array") (result i32)
    #|    (struct.get $leaf 0 (array.get $array
    #|      (array.new $array (struct.new $leaf (i32.const 42)) (i32.const 2)) (i32.const 1))))
    #|  (func (export "fixed") (result i32)
    #|    (struct.get $leaf 0 (array.get $array
    #|      (array.new_fixed $array 1 (struct.new $leaf (i32.const 42))) (i32.const 0)))))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  let store = @runtime.Store::with_c_heap(
    resource_budget=Some(@runtime.ResourceBudget::new(gc_bytes=4096L)),
  )
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
  for index in 0..<4 {
    // The child exists only in the payload being staged for its parent.
    @wasmoon_jit.gc_debug_set_fail_alloc(2)
    assert_eq(context.call_core_func(store, instance, index, []), [I32(42)])
  }
}
