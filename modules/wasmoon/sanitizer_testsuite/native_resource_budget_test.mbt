///|
test "native scoped compute interruption releases invocation budget and preserves Core reuse" {
  let source =
    #|(module (func (export "run") (param i32) (result i32)
    #|  local.get 0 if (loop $spin br $spin) end i32.const 42))
  let module_ = @wat.parse(source)
  let budget = @runtime.ResourceBudget::new(pending_work=1L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(
    module_,
    instance,
    store,
    enable_cancellation=true,
  )
  defer context.close()
  try
    store.with_execution_limits(
      () => context.call_core_func(store, instance, 0, [I32(1)]),
      safepoints=Some(16L),
    )
  catch {
    @wast.JITCoreCallError::HostInvocation(ExecutionBudgetExceeded) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("native compute ignored scope")
  }
  assert_eq(budget.used(PendingWork), 0L)
  assert_eq(context.call_core_func(store, instance, 0, [I32(0)]), [I32(42)])
  assert_eq(budget.used(PendingWork), 0L)
}

///|
test "native continuation metadata is admitted and returned after unreachable cleanup" {
  let source =
    #|(module
    #|  (type $f (func)) (type $c (cont $f))
    #|  (func $body) (elem declare func $body)
    #|  (func (export "allocate") ref.func $body cont.new $c drop ref.func $body cont.new $c drop)
    #|  (func (export "healthy") (result i32) i32.const 42))
  let module_ = @wat.parse(source)
  let budget = @runtime.ResourceBudget::new(pending_work=2L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  try context.call_core_func(store, instance, 1, []) catch {
    HostInvocation(ResourceLimitExceeded(PendingWork)) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("native continuation bodies escaped quota")
  }
  store.collect_garbage() |> ignore
  assert_eq(budget.used(PendingWork), 0L)
  assert_eq(context.call_core_func(store, instance, 2, []), [I32(42)])
  context.close()
  store.close()
  assert_eq(budget.used(PendingWork), 0L)
  assert_eq(budget.used(CodeBytes), 0L)
}

///|
test "native exception snapshot quota is classified and reclaimed with its Store handle" {
  let budget = @runtime.ResourceBudget::new(gc_objects=2L, gc_bytes=64L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [I32], results: [], })
  let first = store.alloc_exn(tag, [I32(42)])
  let native = store.encode_native_exception(first)
  assert_eq(budget.used(GcObjects), 2L)
  assert_eq(budget.used(GcBytes), 64L)
  assert_eq(
    store.native_execution_state().exceptions().snapshot(native).unwrap().1,
    [42L],
  )
  try store.alloc_exn(tag, []) catch {
    ResourceLimitExceeded(GcBytes) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("exception snapshot escaped payload quota")
  }
  store.collect_garbage() |> ignore
  assert_eq(budget.used(GcObjects), 0L)
  assert_eq(budget.used(GcBytes), 0L)
  let next = store.alloc_exn(tag, [I32(43)])
  store.encode_native_exception(next) |> ignore
  store.close()
  assert_eq(budget.used(GcObjects), 0L)
  assert_eq(budget.used(GcBytes), 0L)
}

///|
test "array allocation policy denial survives native slow-path error propagation" {
  let source =
    #|(module
    #|  (type $a (array i32))
    #|  (global $saved (mut (ref null $a)) (ref.null $a))
    #|  (func (export "allocate") i32.const 0 i32.const 1 array.new $a global.set $saved))
  let module_ = @wat.parse(source)
  for native in [false, true] {
    let budget = @runtime.ResourceBudget::new(gc_bytes=48L, gc_objects=4L)
    let store = if native {
      @runtime.Store::with_c_heap(resource_budget=Some(budget))
    } else {
      Store(resource_budget=Some(budget))
    }
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = if native {
      Some(build_gc_root_context(module_, instance, store))
    } else {
      None
    }
    defer (if context is Some(context) { context.close() })
    let call = fn() raise {
      if context is Some(context) {
        context.call_core_func(store, instance, 0, [])
      } else {
        @executor.call_exported_func(store, instance, "allocate", [])
      }
    }
    call() |> ignore
    assert_eq(budget.used(GcBytes), 48L)
    try call() catch {
      @wast.JITCoreCallError::HostInvocation(ResourceLimitExceeded(GcBytes)) if native =>
        ()
      @runtime.RuntimeError::ResourceLimitExceeded(GcBytes) if !native => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("array allocation ignored aggregate allowance")
    }
    if context is Some(context) {
      context.close()
    }
    store.close()
    assert_eq(budget.used(GcBytes), 0L)
  }
}
