///|
test "Store close invalidates retained Memory aliases" {
  let store = @runtime.Store::Store()
  let memory = @runtime.Memory::Memory(1, None)
  store.alloc_mem(memory) |> ignore
  store.close()
  debug_inspect((memory.byte_len(), memory.desc_ptr()), content="(0, 0)")
}

///|
test "Memory aliases shared by Stores are released exactly once" {
  let first = @runtime.Store::Store()
  let second = @runtime.Store::Store()
  let memory = @runtime.Memory::Memory(1, None)
  first.alloc_mem(memory) |> ignore
  second.alloc_mem(memory) |> ignore
  first.close()
  second.close()
  memory.write_i32(0, 42)
  memory.write_byte(0, b'\x2A')
  debug_inspect(
    (memory.byte_len(), memory.desc_ptr(), memory.grow(1), memory.read_i32(0)),
    content="(0, 0, -1, 0)",
  )
  debug_inspect(memory.read_bytes(0, 1), content="<Bytes: []>")
}

///|
test "raising Memory access reports a closed handle" {
  let store = @runtime.Store::Store()
  let memory = @runtime.Memory::Memory(1, None)
  store.alloc_mem(memory) |> ignore
  store.close()
  try memory.load_i32(0) catch {
    error => inspect(error, content="memory is closed")
  } noraise {
    _ => fail("expected closed Memory access to fail")
  }
}

///|
test "independent shared memory owners survive either Store closing" {
  for source_closes_first in [false, true] {
    for memory64 in [false, true] {
      let source = @runtime.Store::Store()
      let destination = @runtime.Store::Store()
      defer source.close()
      defer destination.close()
      let original = @runtime.Memory::Memory(
        1,
        Some(3),
        is_shared=true,
        is_memory64=memory64,
      )
      source.alloc_mem(original) |> ignore
      let shared = destination.get_mem(destination.alloc_shared_mem(original))
      original.store_i32(0, 42)
      inspect(shared.load_i32(0), content="42")
      inspect(shared.grow(1), content="1")
      inspect(original.byte_len(), content="131072")
      let survivor = if source_closes_first {
        source.close()
        inspect(original.desc_ptr(), content="0")
        shared
      } else {
        destination.close()
        inspect(shared.desc_ptr(), content="0")
        original
      }
      inspect(survivor.load_i32(0), content="42")
      survivor.store_i32(65536, 99)
      inspect(survivor.load_i32(65536), content="99")
      inspect(survivor.grow(1), content="2")
      inspect(survivor.byte_len(), content="196608")
      source.close()
      destination.close()
      debug_inspect((original.desc_ptr(), shared.desc_ptr()), content="(0, 0)")
    }
  }
}

///|
test "shared memory can be retained again after its original Store closes" {
  let first = @runtime.Store::Store()
  let second = @runtime.Store::Store()
  let third = @runtime.Store::Store()
  defer first.close()
  defer second.close()
  defer third.close()
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  first.alloc_mem(memory) |> ignore
  let middle = second.get_mem(second.alloc_shared_mem(memory))
  first.close()
  let last = third.get_mem(third.alloc_shared_mem(middle))
  second.close()
  last.atomic_store(0L, 4, 123L)
  inspect(last.atomic_load(0L, 4), content="123")
}

///|
test "shared memory import rejects ordinary and closed handles" {
  let source = @runtime.Store::Store()
  let destination = @runtime.Store::Store()
  defer source.close()
  defer destination.close()
  let ordinary = @runtime.Memory::Memory(1, Some(1))
  source.alloc_mem(ordinary) |> ignore
  try destination.alloc_shared_mem(ordinary) catch {
    error =>
      inspect(
        error,
        content="link error: only shared memory can be imported across Stores",
      )
  } noraise {
    _ => fail("ordinary memory must not cross Store ownership")
  }
  let memory = @runtime.Memory::Memory(1, Some(1), is_shared=true)
  source.alloc_mem(memory) |> ignore
  destination.close()
  try destination.alloc_shared_mem(memory) catch {
    error => inspect(error, content="store is closed")
  } noraise {
    _ => fail("closed Store must not acquire memory")
  }
  memory.store_i32(0, 7)
  inspect(memory.load_i32(0), content="7")
  source.close()
  let next = @runtime.Store::Store()
  defer next.close()
  try next.alloc_shared_mem(memory) catch {
    error => inspect(error, content="memory is closed")
  } noraise {
    _ => fail("closed source must not be retained")
  }
}
