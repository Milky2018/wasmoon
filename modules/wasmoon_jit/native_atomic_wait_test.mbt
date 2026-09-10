///|
test "atomic wait enqueue composes with an independent native notifier" {
  let memory = @wasmoon_jit.alloc_memory_desc(65536L, Some(1L), is_shared=true)
  guard memory != 0L else { fail("memory allocation failed") }
  defer @wasmoon_jit.free_memory_desc(memory)
  for i in 0..<100 {
    let worker = @native_test_support.atomic_notify_start(memory, 0L)
    guard worker != 0L else { fail("native notifier allocation failed") }
    let waiter = @wasmoon_jit.atomic_wait_begin(
      memory,
      0L,
      if i % 2 == 0 {
        4
      } else {
        8
      },
      0L,
      -1L,
    )
    let result = @native_test_support.atomic_notify_finish(worker)
    guard waiter is Some(waiter) else { fail("waiter allocation failed") }
    defer waiter.cancel()
    assert_eq(result, 1)
    assert_eq(waiter.poll(), 0)
    assert_eq(@native_test_support.memory_owner_count(memory), 2L)
    waiter.cancel()
    assert_eq(@native_test_support.memory_owner_count(memory), 1L)
  }
}

///|
test "dropping an atomic waiter removes its queue entry" {
  let memory = @wasmoon_jit.alloc_memory_desc(65536L, Some(1L), is_shared=true)
  guard memory != 0L else { fail("memory allocation failed") }
  defer @wasmoon_jit.free_memory_desc(memory)
  fn register_and_drop() {
    let waiter = @wasmoon_jit.atomic_wait_begin(memory, 0L, 4, 0L, -1L)
    guard waiter is Some(waiter) else { abort("waiter allocation failed") }
    assert_eq(waiter.poll(), -1) catch {
      _ => abort("unexpected wait state")
    }
  }
  for _ in 0..<1000 {
    register_and_drop()
    assert_eq(@wasmoon_jit.atomic_notify(memory, 0L, -1), 0)
    assert_eq(@native_test_support.memory_owner_count(memory), 1L)
  }
}
