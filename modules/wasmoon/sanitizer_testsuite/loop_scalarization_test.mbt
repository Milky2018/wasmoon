///|
test "conditional scalar boxes reset each iteration and retain allocation quotas" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $box (struct (field (mut i32))))
      #| (func (export "test") (param $n i32) (result i32)
      #|   (local $i i32) (local $j i32) (local $sum i32) (local $box (ref $box))
      #|   (block $done
      #|     (loop $outer
      #|       (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
      #|       (if (i32.eqz (i32.and (local.get $i) (i32.const 1)))
      #|         (then
      #|           (local.set $box (struct.new $box (local.get $i)))
      #|           (local.set $j (i32.const 0))
      #|           (loop $inner
      #|             (struct.set $box 0 (local.get $box)
      #|               (i32.add (struct.get $box 0 (local.get $box)) (i32.const 1)))
      #|             (local.set $j (i32.add (local.get $j) (i32.const 1)))
      #|             (br_if $inner (i32.lt_u (local.get $j) (i32.const 3))))
      #|           (local.set $sum (i32.add (local.get $sum) (struct.get $box 0 (local.get $box)))))
      #|         (else (local.set $sum (i32.add (local.get $sum) (local.get $i)))))
      #|       (local.set $i (i32.add (local.get $i) (i32.const 1)))
      #|       (br $outer)))
      #|   (local.get $sum)))
    ),
  )
  @validator.validate_module(module_)
  defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
  for opt_level in [0, 2, 3] {
    for objects in [3L, 32L] {
      let budget = @runtime.ResourceBudget::new(
        gc_bytes=4096L,
        gc_objects=objects,
      )
      let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
      defer store.close()
      let instance = @executor.instantiate_module_with_imports(
        store,
        module_,
        Imports(store),
      )
      @wasmoon_jit.gc_debug_set_fail_alloc(0)
      let context = build_gc_root_context(module_, instance, store, opt_level~)
      defer context.close()
      assert_eq(context.call_core_func(store, instance, 0, [I32(0)]), [I32(0)])
      assert_eq(budget.used(GcObjects), 0L)
      if objects == 3L {
        try context.call_core_func(store, instance, 0, [I32(8)]) catch {
          HostInvocation(ResourceLimitExceeded(GcObjects)) => ()
          error => fail(error.to_string())
        } noraise {
          _ => fail("scalarization removed dynamic allocations")
        }
        assert_eq(budget.used(GcObjects), 3L)
      } else {
        assert_eq(context.call_core_func(store, instance, 0, [I32(8)]), [
          I32(40),
        ])
        assert_eq(budget.used(GcObjects), 4L)
        assert_eq(context.call_core_func(store, instance, 0, [I32(2)]), [I32(4)])
        assert_eq(budget.used(GcObjects), 5L)
        @wasmoon_jit.gc_debug_set_fail_alloc(0, fail_every=1)
        assert_eq(context.call_core_func(store, instance, 0, [I32(0)]), [I32(0)])
        try context.call_core_func(store, instance, 0, [I32(1)]) catch {
          Trap(message) => assert_eq(message, "out of memory")
          error => fail(error.to_string())
        } noraise {
          _ => fail("scalarization removed injected allocation failure")
        }
        assert_eq(budget.used(GcObjects), 5L)
        @wasmoon_jit.gc_debug_set_fail_alloc(0)
        assert_eq(context.call_core_func(store, instance, 0, [I32(1)]), [I32(3)])
        assert_eq(budget.used(GcObjects), 6L)
      }
    }
  }
}
