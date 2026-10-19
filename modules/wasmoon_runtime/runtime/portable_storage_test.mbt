///|
test "checked memory64 storage preserves overlap growth and quota rollback" {
  let budget = @runtime.ResourceBudget::new(memory_bytes=131072L)
  let memory = @runtime.Memory::Memory(
    1,
    Some(2),
    is_memory64=true,
    resource_budget=Some(budget),
  )
  defer memory.close()
  memory.init_data_at(0L, b"abcdef")
  memory.copy_from(1L, memory, 0L, 5L)
  inspect(memory.read_bytes(0, 6), content="b\"aabcde\"")
  memory.fill_at(2L, b'z', 2L)
  inspect(memory.read_bytes(0, 6), content="b\"aazzde\"")
  assert_eq(memory.grow64(1L), 1L)
  assert_eq(memory.load_i32_at(65536L), 0)
  assert_eq(budget.used(MemoryBytes), 131072L)
  assert_eq(memory.grow64(0x7FFF_FFFF_FFFF_FFFFL), -1L)
  assert_eq(memory.byte_len(), 131072L)
  assert_eq(budget.used(MemoryBytes), 131072L)
  for offset in [-1L, 0x7FFF_FFFF_FFFF_FFFFL, 131069L] {
    try memory.load_i32_at(offset) catch {
      OutOfBoundsMemoryAccess => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("out-of-bounds address was accepted")
    }
  }
  memory.close()
  memory.close()
  assert_eq(budget.used(MemoryBytes), 0L)
}

///|
test "memory32 high-bit addresses remain unsigned without wrapping" {
  let memory = @runtime.Memory::Memory(1, None)
  defer memory.close()
  memory.store_i32(0, 42)
  for address in [-1, -2147483648] {
    try memory.store_i32(address, 0) catch {
      OutOfBoundsMemoryAccess => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("high-bit address wrapped into small memory")
    }
  }
  assert_eq(memory.load_i32(0), 42)
}

///|
test "explicit reservation aliases release once and cannot revive" {
  let budget = @runtime.ResourceBudget::new(pending_work=2L)
  let reservation = budget.reserve(PendingWork, 1L)
  let retained = reservation
  assert_true(retained.resize(2L))
  assert_false(reservation.resize(3L))
  assert_eq(budget.used(PendingWork), 2L)
  reservation.release()
  retained.release()
  assert_false(retained.resize(1L))
  assert_eq(budget.used(PendingWork), 0L)
}

///|
test "explicit rooted aliases protect objects until close and then become stale" {
  let budget = @runtime.ResourceBudget::new(
    gc_bytes=32L,
    gc_objects=1L,
    pending_work=1L,
  )
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let index = store.alloc_struct(0, [I32(42)])
  let root = store.root_raw_value(StructRef(index))
  defer root.close()
  let retained = root
  assert_eq(store.collect_garbage(), 0)
  assert_eq(store.struct_get(index, 0), I32(42))
  root.close()
  retained.close()
  assert_eq(budget.used(PendingWork), 0L)
  try store.borrow_rooted_value(retained) catch {
    InvalidHandle => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("closed root revived through retained")
  }
  assert_eq(store.collect_garbage(), 1)
  assert_eq(budget.used(GcBytes), 0L)
  store.close()
  assert_eq(budget.used(GcObjects), 0L)
}

///|
#cfg(target="wasm")
test "managed capacity and unsupported shared memory return reservations" {
  let budget = @runtime.ResourceBudget::new()
  try
    @runtime.Memory::Memory(
      32768,
      None,
      is_memory64=true,
      resource_budget=Some(budget),
    )
  catch {
    OutOfMemory => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("contiguous wasm capacity was not enforced")
  }
  assert_eq(budget.used(MemoryBytes), 0L)
  try
    @runtime.Memory::Memory(
      1,
      Some(2),
      is_shared=true,
      resource_budget=Some(budget),
    )
  catch {
    UnsupportedHostCapability("shared memory") => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("shared memory was emulated with ordinary accesses")
  }
  assert_eq(budget.used(MemoryBytes), 0L)
}

///|
test "Store close keeps retained Memory aliases terminal with the same error" {
  let owner = @runtime.Store::Store()
  let foreign = @runtime.Store::Store()
  defer owner.close()
  defer foreign.close()
  let memory = @runtime.Memory::Memory(1, None)
  assert_eq(owner.alloc_mem(memory), owner.alloc_mem(memory))
  try foreign.alloc_mem(memory) catch {
    ForeignStore => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("memory acquired a second Store owner")
  }
  owner.close()
  assert_eq(memory.byte_len(), 0L)
  assert_eq(memory.grow64(1L), -1L)
  try memory.load_i32(0) catch {
    MemoryClosed => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("closed memory alias remained accessible")
  }
}
