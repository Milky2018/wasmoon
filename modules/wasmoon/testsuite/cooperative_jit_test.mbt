///|
test "cooperative JIT preserves guest work and parked GC references" {
  let source =
    #|(module
    #| (type $value (struct (field i32)))
    #| (global $count (mut i32) (i32.const 0))
    #| (func (export "run") (param $remaining i32) (result i32)
    #|  (local $value (ref null $value))
    #|  i32.const 42 struct.new $value local.set $value
    #|  (loop $again
    #|   global.get $count i32.const 1 i32.add global.set $count
    #|   local.get $remaining i32.const 1 i32.sub local.tee $remaining
    #|   br_if $again)
    #|  global.get $count local.get $value struct.get $value 0 i32.add))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    @runtime.Imports::Imports(),
  )
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
  )
  defer context.close()
  let mut outcome = context.call_core_func_resumable(store, instance, 0, [
    I32(10000),
  ])
  defer (if outcome is NativeCoreSuspended(_, continuation) {
    continuation.cancel()
  })
  let mut yields = 0
  while outcome is NativeCoreSuspended(CooperativeYield, continuation) {
    yields += 1
    store.collect_garbage() |> ignore
    outcome = continuation.continue_execution()
  }
  assert_true(yields > 1)
  guard outcome is NativeCoreReturned(values) else {
    fail("unexpected suspension")
  }
  debug_inspect(values, content="[I32(10042)]")
}

///|
test "cooperative JIT wait is notified by interpreter and cancellation dequeues" {
  let module_ = cooperative_wait_module()
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  let imports = @runtime.Imports::Imports()
  imports.add_memory("shared", "memory", store.alloc_mem(memory))
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
  )
  defer context.close()
  let baseline = @native_test_support.memory_owner_count(memory.desc_ptr())
  for cancel in [false, true] {
    let outcome = context.call_core_func_resumable(store, instance, 0, [])
    guard outcome is NativeCoreSuspended(AtomicWait, continuation) else {
      fail("expected native atomic wait suspension")
    }
    defer continuation.cancel()
    assert_eq(
      @native_test_support.memory_owner_count(memory.desc_ptr()),
      baseline + 1L,
    )
    if cancel {
      continuation.cancel()
      continuation.cancel()
    }
    let notified = @executor.call_exported_func(store, instance, "notify", [])
    assert_eq(notified, [I32(if cancel { 0 } else { 1 })])
    if !cancel {
      guard continuation.continue_execution() is NativeCoreReturned(values) else {
        fail("notified native wait did not return")
      }
      debug_inspect(values, content="[I32(0)]")
    }
    assert_eq(
      @native_test_support.memory_owner_count(memory.desc_ptr()),
      baseline,
    )
  }
}

///|
test "synchronous JIT wait is woken by a native notifier" {
  let module_ = cooperative_wait_module()
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  let imports = @runtime.Imports::Imports()
  imports.add_memory("shared", "memory", store.alloc_mem(memory))
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = prepare_async_jit_context(module_, instance, store)
  defer context.close()
  let worker = @native_test_support.atomic_notify_start(memory.desc_ptr(), 0L)
  guard worker != 0L else { fail("native notifier allocation failed") }
  defer @native_test_support.atomic_notify_finish(worker) |> ignore
  debug_inspect(
    context.call_core_func(store, instance, 0, []),
    content="[I32(0)]",
  )
}

///|
test "controlled JIT cancellation releases an indefinitely blocked atomic wait" {
  let module_ = cooperative_wait_module()
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  let imports = @runtime.Imports::Imports()
  imports.add_memory("shared", "memory", store.alloc_mem(memory))
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    cooperative=true,
  )
  defer context.close()
  assert_true(context.jit_module.set_cooperative_scheduling(false))
  let baseline = @native_test_support.memory_owner_count(memory.desc_ptr())
  let polls = Ref(0)
  debug_inspect(
    context.jit_module.call_with_context_controlled(
      context.jit_module.get_func(0).unwrap(),
      [],
      cancel=Some(() => {
        polls.val += 1
        polls.val >= 3
      }),
    ),
    content="Cancelled",
  )
  inspect(memory.atomic_notify(0L, 0xffffffffU), content="0")
  assert_eq(
    @native_test_support.memory_owner_count(memory.desc_ptr()),
    baseline,
  )
}
