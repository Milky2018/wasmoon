///|
test "prepared array identities and reference fills survive collecting fallbacks and changed controls" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $node (struct (field i32)))
      #| (type $refs (array (mut (ref null $node))))
      #| (func (export "make") (result (ref $refs))
      #|  (local $child (ref $node)) (local $array (ref $refs)) (local $n i32)
      #|  i32.const 42 struct.new $node local.set $child
      #|  (loop $again
      #|   local.get $child i32.const 17 array.new $refs local.set $array
      #|   local.get $n i32.const 1 i32.add local.tee $n i32.const 1100 i32.lt_u br_if $again)
      #|  local.get $array)
      #| (func (export "default") (result i32)
      #|  i32.const 3 array.new_default $refs i32.const 2 array.get $refs ref.is_null))
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
      guard context.call_core_func(store, instance, 0, []) is [ArrayRef(array)] else {
        fail("missing reference array")
      }
      let root = store.pin_gc_roots([ArrayRef(array)])
      defer root.release()
      store.collect_garbage() |> ignore
      for index in 0..<17 {
        guard store.array_get(array, index) is StructRef(child) else {
          fail("array fill reference was lost")
        }
        assert_eq(store.struct_get(child, 0), I32(42))
      }
      assert_true(heap.get_total_collections() > 0)
      assert_true(heap.verify())
      root.release()
      store.collect_garbage() |> ignore
    }
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    assert_eq(context.call_core_func(store, instance, 1, []), [I32(1)])
    @wasmoon_jit.gc_debug_set_fail_alloc(0, fail_every=1)
    try context.call_core_func(store, instance, 1, []) catch {
      Trap(message) => assert_eq(message, "out of memory")
      error => fail(error.to_string())
    } noraise {
      _ => fail("prepared array ignored changed allocation controls")
    }
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    assert_eq(context.call_core_func(store, instance, 1, []), [I32(1)])
  }
}
