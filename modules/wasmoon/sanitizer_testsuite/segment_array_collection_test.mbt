///|
test "data segment allocation reaches the collecting watermark without losing locals" {
  for
    (allocation_expr, value) in [
      ("i32.const 25 i32.const 3 array.new $a", 25),
      ("i32.const 0 i32.const 3 array.new_data $a $data", 42),
    ] {
    let source = "(module (type $a (array (mut i32))) (type $s (struct (field i32))) " +
      "(data $data \"\\2a\\00\\00\\00\\2a\\00\\00\\00\\2a\\00\\00\\00\") " +
      "(func (export \"probe\") (result i32) (local $i i32) " +
      "(local $keep (ref $s)) (local $last (ref null $a)) " +
      "i32.const 17 struct.new $s local.set $keep " +
      "loop " +
      allocation_expr +
      " local.set $last " +
      "local.get $i i32.const 1 i32.add local.tee $i i32.const 1024 i32.lt_u br_if 0 end " +
      "local.get $keep struct.get $s 0 local.get $last i32.const 0 array.get $a i32.add))"
    let module_ = @wat.parse(source)
    @validator.validate_module(module_)
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = build_gc_root_context(module_, instance, store, opt_level=2)
    defer context.close()
    let heap = store.native_heap().unwrap()
    for _ in 0..<3 {
      let initial_collections = heap.get_total_collections()
      set_allocation_budget(heap.get_ptr(), 512L)
      assert_eq(context.call_core_func(store, instance, 0, []), [
        I32(17 + value),
      ])
      assert_true(heap.verify())
      let collections = heap.get_total_collections() - initial_collections
      assert_true(
        collections > 0,
        msg="allocation_expr=\{allocation_expr}, collections=\{collections}, bytes=\{heap.get_size()}",
      )
    }
  }
}

///|
test "data segment bounds faults and quota accounting retain their order" {
  let source =
    #|(module
    #| (type $a (array (mut i32)))
    #| (data $data "\2a\00\00\00")
    #| (func (export "get") (result i32)
    #|  i32.const 0 i32.const 1 array.new_data $a $data i32.const 0 array.get $a)
    #| (func (export "bad")
    #|  i32.const 1 i32.const 1 array.new_data $a $data drop)
    #| (func (export "drop") data.drop $data))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
  for bound in [false, true] {
    let budget = @runtime.ResourceBudget::new(gc_objects=1L)
    let store = @runtime.Store::with_c_heap(
      resource_budget=if bound { Some(budget) } else { None },
    )
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = build_gc_root_context(module_, instance, store, opt_level=2)
    defer context.close()
    let heap = store.native_heap().unwrap()
    assert_eq(context.call_core_func(store, instance, 0, []), [I32(42)])
    let bytes = heap.get_size()
    let allocations = heap.get_total_allocations()
    let collections = heap.get_total_collections()
    set_allocation_budget(heap.get_ptr(), 0L)
    if !bound {
      @wasmoon_jit.gc_debug_set_fail_alloc(1)
    }
    try context.call_core_func(store, instance, 1, []) catch {
      Trap(message) => assert_eq(message, "out of bounds memory access")
      error => fail(error.to_string())
    } noraise {
      _ => fail("segment range escaped the bounds check")
    }
    try context.call_core_func(store, instance, 0, []) catch {
      Trap(message) => assert_eq(message, "out of memory")
      error => fail(error.to_string())
    } noraise {
      _ => fail("segment allocation escaped its admission control")
    }
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    assert_eq(heap.get_total_allocations(), allocations)
    assert_eq(heap.get_total_collections(), collections)
    assert_eq(heap.get_size(), bytes)
    if bound {
      assert_eq(budget.used(GcBytes), bytes)
      assert_eq(budget.used(GcObjects), 1L)
    }
    assert_true(heap.verify())
    if bound {
      context.close()
      store.close()
      assert_eq(budget.used(GcBytes), 0L)
      assert_eq(budget.used(GcObjects), 0L)
      continue
    }
    store.collect_garbage() |> ignore
    assert_eq(heap.get_size(), 0L)
    assert_eq(context.call_core_func(store, instance, 0, []), [I32(42)])
    assert_eq(context.call_core_func(store, instance, 2, []), [])
    let before_dropped = heap.get_total_collections()
    set_allocation_budget(heap.get_ptr(), 0L)
    try context.call_core_func(store, instance, 0, []) catch {
      Trap(message) => assert_eq(message, "out of bounds memory access")
      error => fail(error.to_string())
    } noraise {
      _ => fail("dropped segment admitted a nonempty allocation")
    }
    assert_eq(heap.get_total_collections(), before_dropped)
    assert_true(heap.verify())
  }
}

///|
test "data segment collection retires whole identity pages with sparse survivors" {
  let source =
    #|(module
    #|  (type $a (array i32))
    #|  (data $data "\2a\00\00\00")
    #|  (global $saved (mut (ref null $a)) (ref.null $a))
    #|  (func $new (result (ref $a)) i32.const 0 i32.const 1 array.new_data $a $data)
    #|  (func (export "seed") (local $i i32)
    #|    call $new global.set $saved
    #|    loop
    #|      call $new drop
    #|      local.get $i i32.const 1 i32.add local.tee $i
    #|      i32.const 3072 i32.lt_u br_if 0
    #|    end)
    #|  (func (export "fresh") (result (ref $a)) call $new)
    #|  (func (export "saved") (result i32)
    #|    global.get $saved i32.const 0 array.get $a))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store, opt_level=2)
  defer context.close()
  let heap = store.native_heap().unwrap()
  assert_eq(context.call_core_func(store, instance, 1, []), [])
  assert_eq(heap.get_total_collections(), 0)
  assert_eq(heap.get_object_count(), 3073)
  assert_true(heap.is_valid(1023))
  assert_true(heap.is_valid(1024))
  assert_true(heap.is_valid(2047))
  assert_true(heap.is_valid(2048))
  set_allocation_budget(heap.get_ptr(), 0L)
  guard context.call_core_func(store, instance, 2, []) is [ArrayRef(fresh)] else {
    fail("missing replacement segment array")
  }
  assert_eq(heap.get_total_collections(), 1)
  assert_true(heap.is_valid(0))
  for retired in [1, 1023, 1024, 2047, 2048, 3072] {
    assert_false(heap.is_valid(retired))
  }
  assert_eq(heap.get_object_count(), 3074)
  assert_eq(context.call_core_func(store, instance, 3, []), [I32(42)])
  assert_eq(store.array_get(fresh, 0), I32(42))
  assert_true(heap.verify())
}
