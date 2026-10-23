///|
test "inlined GC leaves preserve allocation inputs failures and quota classification" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $node (struct (field i32) (field (ref null $node))))
      #| (func $new (param i32 (ref null $node)) (result (ref $node))
      #|   local.get 0 local.get 1 struct.new $node)
      #| (func $get (param (ref $node)) (result i32) local.get 0 struct.get $node 0)
      #| (func (export "test") (result i32)
      #|   i32.const 0 i32.const 42 ref.null $node call $new call $new
      #|   struct.get $node 1 ref.as_non_null call $get))
    ),
  )
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    for denial in ["none", "bytes", "objects"] {
      let budget = @runtime.ResourceBudget::new(
        gc_bytes=if denial == "bytes" { 0L } else { 4096L },
        gc_objects=if denial == "objects" { 0L } else { 64L },
      )
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
      if denial != "none" {
        try context.call_core_func(store, instance, 2, []) catch {
          HostInvocation(ResourceLimitExceeded(kind)) =>
            assert_eq(kind, if denial == "bytes" { GcBytes } else { GcObjects })
          error => fail(error.to_string())
        } noraise {
          _ => fail("inlining removed a quota-admitted allocation")
        }
        assert_eq((budget.used(GcObjects), budget.used(GcBytes)), (0L, 0L))
        continue
      }
      @wasmoon_jit.gc_debug_set_fail_alloc(2)
      assert_eq(context.call_core_func(store, instance, 2, []), [I32(42)])
      store.collect_garbage() |> ignore
      assert_eq((budget.used(GcObjects), budget.used(GcBytes)), (2L, 0L))
      @wasmoon_jit.gc_debug_set_fail_alloc(0, fail_every=1)
      try context.call_core_func(store, instance, 2, []) catch {
        Trap(message) => assert_eq(message, "out of memory")
        error => fail(error.to_string())
      } noraise {
        _ => fail("inlining removed injected allocation failure")
      }
      assert_eq((budget.used(GcObjects), budget.used(GcBytes)), (2L, 0L))
      @wasmoon_jit.gc_debug_set_fail_alloc(0)
      assert_eq(context.call_core_func(store, instance, 2, []), [I32(42)])
    }
  }
}
