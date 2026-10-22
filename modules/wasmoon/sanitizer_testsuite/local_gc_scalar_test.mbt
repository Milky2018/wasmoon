///|
test "private scalar promotion retains allocation failure and quota behavior" {
  let source =
    #|(module
    #| (type $box (struct (field (mut i32))))
    #| (func (export "test") (result i32) (local $box (ref $box))
    #|  (local.set $box (struct.new $box (i32.const 0)))
    #|  (loop $loop
    #|   (struct.set $box 0 (local.get $box)
    #|    (i32.add (struct.get $box 0 (local.get $box)) (i32.const 1)))
    #|   (br_if $loop (i32.lt_u (struct.get $box 0 (local.get $box)) (i32.const 20))))
    #|  (struct.get $box 0 (local.get $box))))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let budget = @runtime.ResourceBudget::new(gc_bytes=4096L, gc_objects=64L)
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
    assert_eq(context.call_core_func(store, instance, 0, []), [I32(20)])
    @wasmoon_jit.gc_debug_set_fail_alloc(0, fail_every=1)
    try context.call_core_func(store, instance, 0, []) catch {
      Trap(message) => assert_eq(message, "out of memory")
      error => fail(error.to_string())
    } noraise {
      _ => fail("scalar promotion erased the allocation failure")
    }
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    assert_eq(context.call_core_func(store, instance, 0, []), [I32(20)])
    store.collect_garbage() |> ignore
    assert_eq(budget.used(GcBytes), 0L)
  }
}
