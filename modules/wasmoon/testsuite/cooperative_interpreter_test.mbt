///|
test "cooperative interpreter preserves completed work across instruction quanta" {
  let source =
    #|(module
    #| (global $count (mut i32) (i32.const 0))
    #| (func $step global.get $count i32.const 1 i32.add global.set $count)
    #| (func (export "run") (param $remaining i32) (result i32)
    #|  (loop $again
    #|   call $step
    #|   local.get $remaining i32.const 1 i32.sub local.tee $remaining
    #|   br_if $again)
    #|  global.get $count))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  let store = @runtime.Store::Store()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    @runtime.Imports::Imports(),
  )
  let mut outcome = @executor.call_func_by_index_resumable(
    store,
    instance,
    1,
    [I32(10000)],
    _ => None,
    cooperative=true,
  )
  defer (if outcome is Suspended(_, continuation) { continuation.cancel() })
  let mut yields = 0
  while outcome is Suspended(CooperativeYield, continuation) {
    yields += 1
    outcome = continuation.continue_execution()
  }
  assert_true(yields > 1)
  debug_inspect(outcome, content="Returned([I32(10000)])")
}

///|
fn cooperative_wait_module() -> @types.Module raise {
  let source =
    #|(module
    #| (memory (import "shared" "memory") 1 1 shared)
    #| (func (export "wait") (result i32)
    #|  i32.const 0 i32.const 0 i64.const -1 memory.atomic.wait32)
    #| (func (export "notify") (result i32)
    #|  i32.const 0 i32.const -1 memory.atomic.notify))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  module_
}

///|
test "independent interpreter Stores resume notified waits and cancel parked waits" {
  let module_ = cooperative_wait_module()
  let first = @runtime.Store::Store()
  let second = @runtime.Store::Store()
  defer first.close()
  defer second.close()
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  let imports = @runtime.Imports::Imports()
  imports.add_memory("shared", "memory", first.alloc_mem(memory))
  let first_instance = @executor.instantiate_module_with_imports(
    first, module_, imports,
  )
  let other_imports = @runtime.Imports::Imports()
  other_imports.add_memory("shared", "memory", second.alloc_shared_mem(memory))
  let second_instance = @executor.instantiate_module_with_imports(
    second, module_, other_imports,
  )
  for cancel in [false, true] {
    let outcome = @executor.call_func_by_index_resumable(
      first,
      first_instance,
      0,
      [],
      _ => None,
      cooperative=true,
    )
    guard outcome is Suspended(AtomicWait, continuation) else {
      fail("expected an actual parked atomic wait")
    }
    defer continuation.cancel()
    if cancel {
      continuation.cancel()
      continuation.cancel()
    }
    let notified = @executor.call_exported_func(
      second,
      second_instance,
      "notify",
      [],
    )
    assert_eq(notified, [I32(if cancel { 0 } else { 1 })])
    if !cancel {
      debug_inspect(
        continuation.continue_execution(),
        content="Returned([I32(0)])",
      )
    }
  }
}

///|
test "synchronous interpreter wait is woken by a native notifier" {
  let module_ = cooperative_wait_module()
  let store = @runtime.Store::Store()
  defer store.close()
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  let imports = @runtime.Imports::Imports()
  imports.add_memory("shared", "memory", store.alloc_mem(memory))
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let worker = @native_test_support.atomic_notify_start(memory.desc_ptr(), 0L)
  guard worker != 0L else { fail("native notifier allocation failed") }
  defer @native_test_support.atomic_notify_finish(worker) |> ignore
  debug_inspect(
    @executor.call_exported_func(store, instance, "wait", []),
    content="[I32(0)]",
  )
}

///|
test "a consumed interpreter continuation cannot cancel its resumed waiter" {
  let module_ = cooperative_wait_module()
  let store = @runtime.Store::Store()
  defer store.close()
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  let imports = @runtime.Imports::Imports()
  imports.add_memory("shared", "memory", store.alloc_mem(memory))
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  guard @executor.call_func_by_index_resumable(
      store,
      instance,
      0,
      [],
      _ => None,
      cooperative=true,
    )
    is Suspended(AtomicWait, first) else {
    fail("expected wait")
  }
  guard first.continue_execution() is Suspended(AtomicWait, second) else {
    fail("an unnotified wait must remain pending")
  }
  defer second.cancel()
  first.cancel()
  try first.continue_execution() catch {
    @runtime.Unreachable => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("consumed continuation must reject a second resume")
  }
  inspect(memory.atomic_notify(0L, 0xffffffffU), content="1")
  debug_inspect(second.continue_execution(), content="Returned([I32(0)])")
}
