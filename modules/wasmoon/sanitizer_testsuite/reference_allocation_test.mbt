///|
test "reference struct initialization preserves packed fields quotas and injected failures" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $leaf (struct (field i32)))
      #| (type $parent (struct (field i8) (field (ref $leaf)) (field (ref null any)) (field i64)))
      #| (func (export "leaf") (result (ref $leaf)) (struct.new $leaf (i32.const 42)))
      #| (func (export "wrap") (param $child (ref $leaf)) (result (ref $parent))
      #|   (struct.new $parent (i32.const 257) (local.get $child) (ref.i31 (i32.const -7)) (i64.const 42))))
    ),
  )
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    // One 32-byte child and three 48-byte parents, with packed and tagged fields.
    let budget = @runtime.ResourceBudget::new(gc_bytes=176L, gc_objects=16L)
    let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = build_gc_root_context(module_, instance, store, opt_level~)
    defer context.close()
    defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    let child = context.call_core_func(store, instance, 0, [])[0]
    let child_root = store.pin_gc_roots([child])
    defer child_root.release()
    let parents : Array[@types.Value] = []
    for _ in 0..<3 {
      guard context.call_core_func(store, instance, 1, [child])
        is [StructRef(parent)] else {
        fail("missing reference struct")
      }
      parents.push(StructRef(parent))
      assert_eq(Array::makei(4, field => store.struct_get(parent, field)), [
        I32(1),
        child,
        I31(-7),
        I64(42),
      ])
    }
    let roots = store.pin_gc_roots(parents)
    defer roots.release()
    assert_eq((budget.used(GcObjects), budget.used(GcBytes)), (4L, 176L))
    try context.call_core_func(store, instance, 1, [child]) catch {
      HostInvocation(ResourceLimitExceeded(GcBytes)) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("reference reservation bypassed payload admission")
    }
    assert_eq((budget.used(GcObjects), budget.used(GcBytes)), (4L, 176L))
    roots.release()
    assert_eq(store.collect_garbage(), 3)
    assert_eq((budget.used(GcObjects), budget.used(GcBytes)), (4L, 32L))
    @wasmoon_jit.gc_debug_set_fail_alloc(0, fail_every=1)
    try context.call_core_func(store, instance, 1, [child]) catch {
      Trap(message) => assert_eq(message, "out of memory")
      error => fail(error.to_string())
    } noraise {
      _ => fail("reference reservation bypassed failure injection")
    }
    assert_eq((budget.used(GcObjects), budget.used(GcBytes)), (4L, 32L))
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    context.call_core_func(store, instance, 1, [child]) |> ignore
    assert_eq((budget.used(GcObjects), budget.used(GcBytes)), (5L, 80L))
  }
}

///|
test "reference allocation retains transitive inputs across collection and initializes null defaults" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $node (struct (field i32) (field (ref null $node))))
      #| (func (export "make") (result (ref $node)) (local $child (ref $node)) (local $n i32)
      #|   (local.set $child (struct.new $node (i32.const 42) (ref.null $node)))
      #|   (loop $loop
      #|     (drop (struct.new $node (i32.const 0) (local.get $child)))
      #|     (br_if $loop (i32.lt_u (local.tee $n (i32.add (local.get $n) (i32.const 1))) (i32.const 100))))
      #|   (struct.new $node (i32.const 7) (local.get $child)))
      #| (func (export "default") (result i32)
      #|   (ref.is_null (struct.get $node 1 (struct.new_default $node)))))
    ),
  )
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = build_gc_root_context(module_, instance, store, opt_level~)
    defer context.close()
    let heap = store.native_heap().unwrap()
    defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
    for fail_at in [0, 2] {
      @wasmoon_jit.gc_debug_set_fail_alloc(fail_at)
      set_allocation_budget(heap.get_ptr(), 512L)
      guard context.call_core_func(store, instance, 0, [])
        is [StructRef(parent)] else {
        fail("missing reference graph")
      }
      let roots = store.pin_gc_roots([StructRef(parent)])
      assert_eq(store.struct_get(parent, 0), I32(7))
      guard store.struct_get(parent, 1) is StructRef(child) else {
        fail("missing child after allocation retry")
      }
      store.collect_garbage() |> ignore
      assert_eq(store.struct_get(child, 0), I32(42))
      assert_true(heap.get_total_collections() > 0)
      roots.release()
      store.collect_garbage() |> ignore
      @wasmoon_jit.gc_debug_set_fail_alloc(0)
      assert_eq(context.call_core_func(store, instance, 1, []), [I32(1)])
    }
  }
}

///|
test "generated allocation publishes complete identities across pages and observes debug changes" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $pair (struct (field i64) (field i64)))
      #| (func (export "make") (param $n i64) (result i64) (local $p (ref $pair))
      #|   (local.set $p (struct.new $pair (local.get $n) (i64.const 17)))
      #|   (i64.add (struct.get $pair 0 (local.get $p)) (struct.get $pair 1 (local.get $p)))))
    ),
  )
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = build_gc_root_context(module_, instance, store, opt_level~)
    defer context.close()
    defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    let heap = store.native_heap().unwrap()
    let before = heap.get_total_allocations()
    for n in 0..<1100 {
      assert_eq(
        context.call_core_func(store, instance, 0, [I64(n.to_int64())]),
        [I64(n.to_int64() + 17L)],
      )
    }
    assert_eq(heap.get_total_allocations() - before, 1100)
    assert_true(heap.verify())
    assert_eq(store.collect_garbage(), 1100)
    assert_true(heap.verify())
    @wasmoon_jit.gc_debug_set_fail_alloc(0, fail_every=1)
    try context.call_core_func(store, instance, 0, [I64(25L)]) catch {
      Trap(message) => assert_eq(message, "out of memory")
      error => fail(error.to_string())
    } noraise {
      _ => fail("compiled allocation ignored changed failure controls")
    }
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    assert_eq(context.call_core_func(store, instance, 0, [I64(25L)]), [I64(42L)])
    assert_eq(store.collect_garbage(), 1)
  }
}
