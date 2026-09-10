///|
test "atomic waits compare both widths and respect zero timeout" {
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  let store = @runtime.Store::Store()
  defer store.close()
  store.alloc_mem(memory) |> ignore
  memory.atomic_store(0L, 8, 0x100000001L)
  for
    case in [
      (4, 1L, 0L, 2),
      (8, 1L, -1L, 1),
      (8, 0x100000001L, 0L, 2),
      (4, 2L, 0L, 1),
    ] {
    let (width, expected, timeout, result) = case
    let waiter = memory.atomic_wait_begin(0L, width, expected, timeout)
    defer waiter.cancel()
    assert_eq(waiter.poll(), result)
    inspect(memory.atomic_notify(0L, 0xffffffffU), content="0")
  }
}

///|
test "atomic notification isolates memory addresses and shares wait widths" {
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  let store = @runtime.Store::Store()
  defer store.close()
  store.alloc_mem(memory) |> ignore
  let other = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  store.alloc_mem(other) |> ignore
  let first = memory.atomic_wait_begin(0L, 4, 0L, -1L)
  let second = memory.atomic_wait_begin(0L, 8, 0L, -1L)
  let separate = memory.atomic_wait_begin(8L, 4, 0L, -1L)
  defer first.cancel()
  defer second.cancel()
  defer separate.cancel()
  inspect(memory.atomic_notify(0L, 0U), content="0")
  inspect(other.atomic_notify(0L, 0xffffffffU), content="0")
  inspect(memory.atomic_notify(4L, 0xffffffffU), content="0")
  inspect(memory.atomic_notify(0L, 1U), content="1")
  let results = [first.poll(), second.poll()]
  assert_true(results == [0, -1] || results == [-1, 0])
  inspect(memory.atomic_notify(0L, 0xffffffffU), content="1")
  inspect(first.poll(), content="0")
  inspect(second.poll(), content="0")
  inspect(separate.poll(), content="-1")
  separate.cancel()
  separate.cancel()
  inspect(separate.poll(), content="3")
  inspect(memory.atomic_notify(8L, 0xffffffffU), content="0")
}

///|
test "atomic wait registration retains memory after its Store closes" {
  let store = @runtime.Store::Store()
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  store.alloc_mem(memory) |> ignore
  let waiter = memory.atomic_wait_begin(0L, 4, 0L, -1L)
  store.close()
  inspect(waiter.poll(), content="-1")
  waiter.cancel()
  inspect(waiter.poll(), content="3")
}

///|
test "expired atomic wait is not counted by a later notification" {
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  let store = @runtime.Store::Store()
  defer store.close()
  store.alloc_mem(memory) |> ignore
  let waiter = memory.atomic_wait_begin(0L, 4, 0L, 1L)
  defer waiter.cancel()
  for _ in 0..<10000 {
    if waiter.poll() == 2 {
      break
    }
  }
  inspect(memory.atomic_notify(0L, 1U), content="0")
  inspect(waiter.poll(), content="2")
}
