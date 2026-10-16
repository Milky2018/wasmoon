///|
test "resource reservations deny before accounting and release exactly once" {
  let budget = @runtime.ResourceBudget::new(pending_work=2L)
  let first = budget.reserve(PendingWork, 1L)
  let second = budget.reserve(PendingWork, 1L)
  assert_eq(budget.used(PendingWork), 2L)
  try budget.reserve(PendingWork, 1L) catch {
    ResourceLimitExceeded(PendingWork) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("quota exceeded")
  }
  assert_eq(budget.used(PendingWork), 2L)
  first.release()
  first.release()
  let third = budget.reserve(PendingWork, 1L)
  second.release()
  third.release()
  assert_eq(budget.used(PendingWork), 0L)
}

///|
test "aggregate memory budget covers growth and independent shared owners" {
  let budget = @runtime.ResourceBudget::new(memory_bytes=196608L)
  let source = @runtime.Store(resource_budget=Some(budget))
  let destination = @runtime.Store(resource_budget=Some(budget))
  let memory = @runtime.Memory::Memory(
    1,
    Some(4),
    is_shared=true,
    resource_budget=Some(budget),
  )
  source.alloc_mem(memory) |> ignore
  source.alloc_mem(memory) |> ignore
  let shared = destination.get_mem(destination.alloc_shared_mem(memory))
  assert_eq(budget.used(MemoryBytes), 65536L)
  let other = @runtime.Memory::Memory(1, Some(4), resource_budget=Some(budget))
  destination.alloc_mem(other) |> ignore
  assert_eq(shared.grow(1), 1)
  assert_eq(memory.grow(1), -1)
  assert_eq(other.grow(1), -1)
  assert_eq(budget.used(MemoryBytes), 196608L)
  source.close()
  assert_eq(budget.used(MemoryBytes), 196608L)
  assert_eq(shared.byte_len(), 131072L)
  destination.close()
  assert_eq(budget.used(MemoryBytes), 0L)
  let replacement = @runtime.Memory::Memory(
    3,
    Some(3),
    resource_budget=Some(budget),
  )
  let replacement_store = @runtime.Store(resource_budget=Some(budget))
  replacement_store.alloc_mem(replacement) |> ignore
  replacement_store.close()
  assert_eq(budget.used(MemoryBytes), 0L)
}

///|
test "quota rejects initial memory and does not alter the remaining allowance" {
  let budget = @runtime.ResourceBudget::new(memory_bytes=65536L)
  try @runtime.Memory::Memory(2, None, resource_budget=Some(budget)) catch {
    ResourceLimitExceeded(MemoryBytes) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("minimum must be admitted before allocating")
  }
  assert_eq(budget.used(MemoryBytes), 0L)
  let store = @runtime.Store(resource_budget=Some(budget))
  store.alloc_mem(Memory(1, None, resource_budget=Some(budget))) |> ignore
  assert_eq(budget.used(MemoryBytes), 65536L)
  store.close()
  assert_eq(budget.used(MemoryBytes), 0L)
}

///|
test "table quota covers native mirrors and interpreter growth" {
  let budget = @runtime.ResourceBudget::new(table_elements=4L)
  let store = @runtime.Store(resource_budget=Some(budget))
  let first = @runtime.Table::Table(
    FuncRef,
    1,
    None,
    resource_budget=Some(budget),
  )
  let second = @runtime.Table::Table(
    FuncRef,
    1,
    None,
    resource_budget=Some(budget),
  )
  let address = store.alloc_table(first)
  store.alloc_table(second) |> ignore
  assert_eq(first.grow(2, Null), 1)
  assert_eq(second.grow(1, Null), -1)
  assert_eq(store.get_jit_table(address).unwrap().get_size(), 3)
  assert_eq(budget.used(TableElements), 4L)
  store.close()
  assert_eq(budget.used(TableElements), 0L)
}

///|
test "GC budgets bound aggregate payload and retain identity accounting" {
  for native in [false, true] {
    let budget = @runtime.ResourceBudget::new(gc_bytes=64L, gc_objects=4L)
    let store = if native {
      @runtime.Store::with_c_heap(resource_budget=Some(budget))
    } else {
      Store(resource_budget=Some(budget))
    }
    defer store.close()
    let first = store.alloc_struct(0, [I32(1)])
    let second = store.alloc_struct(0, [I32(2)])
    assert_eq(budget.used(GcBytes), 64L)
    try store.alloc_struct(0, [I32(3)]) catch {
      ResourceLimitExceeded(GcBytes) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("GC payload quota exceeded")
    }
    assert_eq(budget.used(GcBytes), 64L)
    store.collect_garbage(additional_roots=[StructRef(first), StructRef(second)])
    |> ignore
    assert_eq(budget.used(GcBytes), 64L)
    store.collect_garbage() |> ignore
    assert_eq(budget.used(GcBytes), 0L)
    assert_eq(budget.used(GcObjects), 2L)
    store.alloc_struct(0, [I32(4)]) |> ignore
    assert_eq(budget.used(GcBytes), 32L)
    store.close()
    assert_eq(budget.used(GcBytes), 0L)
    assert_eq(budget.used(GcObjects), 0L)
  }
}

///|
test "GC identity denial restores the already admitted byte allowance" {
  for native in [false, true] {
    let budget = @runtime.ResourceBudget::new(gc_bytes=64L, gc_objects=1L)
    let store = if native {
      @runtime.Store::with_c_heap(resource_budget=Some(budget))
    } else {
      Store(resource_budget=Some(budget))
    }
    defer store.close()
    store.alloc_struct(0, [I32(1)]) |> ignore
    try store.alloc_struct(0, [I32(2)]) catch {
      ResourceLimitExceeded(GcObjects) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("GC identity quota exceeded")
    }
    assert_eq(budget.used(GcBytes), 32L)
    assert_eq(budget.used(GcObjects), 1L)
    store.close()
    assert_eq(budget.used(GcBytes), 0L)
    assert_eq(budget.used(GcObjects), 0L)
  }
}

///|
test "zero execution limits and cancellation reject before host side effects" {
  let store = @runtime.Store()
  defer store.close()
  let entered = Ref(false)
  for mode in 0..<3 {
    try
      store.with_execution_limits(
        fn() { entered.val = true },
        timeout_ms=if mode == 0 { Some(0) } else { None },
        safepoints=if mode == 1 { Some(0L) } else { None },
        cancel=if mode == 2 { Some(() => true) } else { None },
      )
    catch {
      @runtime.RuntimeError::ExecutionTimedOut if mode == 0 => ()
      @runtime.RuntimeError::ExecutionBudgetExceeded if mode == 1 => ()
      @runtime.RuntimeError::ExecutionCancelled if mode == 2 => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("stopped scope entered its callback")
    }
    assert_false(entered.val)
  }
  assert_eq(store.with_execution_limits(() => 42, safepoints=Some(1L)), 42)
}

///|
test "instance and compilation admissions are aggregate transactional and reusable" {
  let module_ = @types.Module::simple([], [], [Nop], "run")
  let measure = @runtime.ResourceBudget::new()
  let measuring_store = @runtime.Store(resource_budget=Some(measure))
  let measured = measuring_store.reserve_instance(module_~)
  let units = measure.used(CompilationUnits)
  assert_true(units > 0L)
  measured.cancel()
  assert_eq(measure.used(CompilationUnits), 0L)
  measuring_store.close()
  let budget = @runtime.ResourceBudget::new(
    instances=1L,
    compilation_units=units,
  )
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let foreign = @runtime.Store()
  defer foreign.close()
  let admission = store.reserve_instance(module_~)
  try foreign.check_instance_admission(admission) catch {
    ForeignStore => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("foreign admission accepted")
  }
  try store.reserve_instance() catch {
    ResourceLimitExceeded(Instances) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("instance quota exceeded")
  }
  admission.cancel()
  admission.cancel()
  assert_eq(budget.used(Instances), 0L)
  assert_eq(budget.used(CompilationUnits), 0L)
  try store.check_instance_admission(admission) catch {
    InvalidHandle => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("cancelled admission reused")
  }
  let replacement = store.reserve_instance(module_~)
  store.register_instance(ModuleInstance(), admission=replacement) |> ignore
  assert_eq(budget.used(CompilationUnits), units)
  store.close()
  assert_eq(budget.used(CompilationUnits), 0L)
  assert_eq(budget.used(Instances), 0L)
  let insufficient = @runtime.ResourceBudget::new(compilation_units=units - 1L)
  let denied = @runtime.Store(resource_budget=Some(insufficient))
  defer denied.close()
  try denied.reserve_instance(module_~) catch {
    ResourceLimitExceeded(CompilationUnits) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("AST quota exceeded")
  }
  assert_eq(insufficient.used(Instances), 0L)
  assert_eq(insufficient.used(CompilationUnits), 0L)
}

///|
test "Store decoder restores temporary allowances on expansion denial" {
  let budget = @runtime.ResourceBudget::new(
    input_bytes=64L,
    compilation_units=40L,
  )
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let bytes = b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x03\x02\x01\x00\x0a\x06\x01\x04\x01\x40\x7f\x0b"
  try store.decode_module(bytes) catch {
    @runtime.RuntimeError::ResourceLimitExceeded(CompilationUnits) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("compressed locals bypassed work quota")
  }
  assert_eq(budget.used(InputBytes), 0L)
  assert_eq(budget.used(CompilationUnits), 0L)
  assert_eq(store.decode_module(b"\x00asm\x01\x00\x00\x00").codes.length(), 0)
}

///|
test "auxiliary GC handles and parked roots share budgets and release on collection" {
  let budget = @runtime.ResourceBudget::new(
    gc_objects=1L,
    gc_bytes=64L,
    pending_work=1L,
  )
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let wrapper = store.wrap_as_extern(I32(42))
  try store.wrap_as_extern(I32(43)) catch {
    ResourceLimitExceeded(GcObjects) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("wrapper metadata was not admitted")
  }
  assert_eq(store.unwrap_extern(wrapper), I32(42))
  store.collect_garbage() |> ignore
  assert_eq(budget.used(GcObjects), 0L)
  assert_eq(budget.used(GcBytes), 0L)
  let root = store.pin_gc_roots([])
  try store.pin_gc_roots([]) catch {
    ResourceLimitExceeded(PendingWork) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("root registry ignored its budget")
  }
  root.release()
  root.release()
  let next = store.pin_gc_roots([])
  store.close()
  assert_eq(budget.used(PendingWork), 0L)
  next.release()
}

///|
test "repeated GC array is admitted before constructing its temporary elements" {
  for native in [false, true] {
    let budget = @runtime.ResourceBudget::new(gc_bytes=48L, gc_objects=2L)
    let store = if native {
      @runtime.Store::with_c_heap(resource_budget=Some(budget))
    } else {
      Store(resource_budget=Some(budget))
    }
    defer store.close()
    try store.alloc_array_repeated(0, 1000000, I32(0)) catch {
      ResourceLimitExceeded(GcBytes) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("expanded array ignored payload quota")
    }
    assert_eq(budget.used(GcBytes), 0L)
    store.alloc_array_repeated(0, 1, I32(0)) |> ignore
    assert_eq(budget.used(GcBytes), 48L)
  }
}

///|
test "an admission for a small AST cannot authorize a different validated module" {
  let budget = @runtime.ResourceBudget::new(compilation_units=8L, instances=1L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let small = @types.Module::Module()
  let admission = store.reserve_instance(module_=small)
  let larger = @types.Module::simple([], [], [Nop], "run")
  for _ in 0..<20 {
    larger.funcs.push(0)
  }
  // Keep a valid large module: each extra function has its corresponding body.
  for _ in 0..<20 {
    larger.codes.push({ locals: [], body: [Nop], })
  }
  let validated = @validator.ValidatedModule::new(larger)
  try store.check_instance_admission(admission, validated~) catch {
    ResourceLimitExceeded(CompilationUnits) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("provisional admission authorized a larger module")
  }
  assert_eq(budget.used(CompilationUnits), 0L)
  admission.cancel()
  assert_eq(budget.used(Instances), 0L)
}

///|
test "Core initialization traps retain quota for functions published into an imported table" {
  let budget = @runtime.ResourceBudget::new(
    instances=2L,
    table_elements=1L,
    memory_bytes=0L,
  )
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let table = store.alloc_table(Table(FuncRef, 1, None))
  let imports = @runtime.Imports(store)
  imports.add_table("host", "table", table)
  let source =
    #|(module (import "host" "table" (table 1 funcref))
    #|  (func $escaped (result i32) i32.const 7)
    #|  (elem (i32.const 0) $escaped)
    #|  (memory 0) (data (i32.const 0) "x"))
  try
    @executor.instantiate_module_with_imports(
      store,
      @wat.parse(source),
      imports,
    )
  catch {
    @runtime.RuntimeError::OutOfBoundsMemoryAccess => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("out-of-bounds initializer returned")
  }
  assert_eq(budget.used(Instances), 1L)
  let reader = @wat.parse(
    "(module (import \"host\" \"table\" (table 1 funcref)) (type (func (result i32))) (func (export \"run\") (result i32) i32.const 0 call_indirect (type 0)))",
  )
  let reader = @executor.instantiate_module_with_imports(store, reader, imports)
  assert_eq(@executor.call_exported_func(store, reader, "run", []), [I32(7)])
  assert_eq(budget.used(Instances), 2L)
  store.close()
  assert_eq(budget.used(Instances), 0L)
  assert_eq(budget.used(CompilationUnits), 0L)
}
