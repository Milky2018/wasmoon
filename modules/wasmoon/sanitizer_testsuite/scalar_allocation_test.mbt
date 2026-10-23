///|
test "native scalar allocation preserves packed layout quotas failure injection and reuse" {
  let module_ = @wat.parse(
    (
      #|(module (type $s (struct (field i8) (field i16) (field i32) (field i64) (field f32) (field f64)))
      #| (func (export "make") (param $x i32) (param $wide i64) (param $f f32) (param $d f64) (result (ref $s))
      #|  local.get $x local.get $x local.get $x local.get $wide
      #|  local.get $f local.get $d struct.new $s))
    ),
  )
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let budget = @runtime.ResourceBudget::new(gc_bytes=240L, gc_objects=10L)
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
    let objects : Array[@types.Value] = []
    for _ in 0..<5 {
      guard context.call_core_func(store, instance, 0, [
          I32(257),
          I64(4294967297L),
          F32(1.5),
          F64(2.5),
        ])
        is [StructRef(reference)] else {
        fail("missing allocated struct")
      }
      objects.push(StructRef(reference))
      assert_eq(Array::makei(6, field => store.struct_get(reference, field)), [
        I32(1),
        I32(257),
        I32(257),
        I64(4294967297L),
        F32(1.5),
        F64(2.5),
      ])
    }
    let roots = store.pin_gc_roots(objects)
    defer roots.release()
    assert_eq((budget.used(GcObjects), budget.used(GcBytes)), (5L, 240L))
    try
      context.call_core_func(store, instance, 0, [
        I32(257),
        I64(4294967297L),
        F32(1.5),
        F64(2.5),
      ])
    catch {
      HostInvocation(ResourceLimitExceeded(GcBytes)) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("scalar fast path bypassed payload admission")
    }
    assert_eq((budget.used(GcObjects), budget.used(GcBytes)), (5L, 240L))
    roots.release()
    assert_eq(store.collect_garbage(), 5)
    assert_eq((budget.used(GcObjects), budget.used(GcBytes)), (5L, 0L))
    @wasmoon_jit.gc_debug_set_fail_alloc(0, fail_every=1)
    try
      context.call_core_func(store, instance, 0, [
        I32(42),
        I64(-4294967297L),
        F32(-1.5),
        F64(-2.5),
      ])
    catch {
      Trap(message) => assert_eq(message, "out of memory")
      error => fail(error.to_string())
    } noraise {
      _ => fail("scalar fast path bypassed failure injection")
    }
    assert_eq((budget.used(GcObjects), budget.used(GcBytes)), (5L, 0L))
    @wasmoon_jit.gc_debug_set_fail_alloc(0)
    context.call_core_func(store, instance, 0, [
      I32(42),
      I64(-4294967297L),
      F32(-1.5),
      F64(-2.5),
    ])
    |> ignore
    assert_eq((budget.used(GcObjects), budget.used(GcBytes)), (6L, 48L))
  }
}
