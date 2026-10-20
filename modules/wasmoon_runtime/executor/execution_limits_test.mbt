///|
fn budget_loop_module() -> @types.Module {
  @types.Module::simple(
    [I32],
    [I32],
    [LocalGet(0), If(Empty, [Loop(Empty, [Br(0)])], []), I32Const(42)],
    "run",
  )
}

///|
test "Core scoped execution limits preserve the instance after interruption" {
  let (store, instance) = @executor.instantiate_module(budget_loop_module())
  defer store.close()
  try
    store.with_execution_limits(
      () => @executor.call_exported_func(store, instance, "run", [I32(1)]),
      safepoints=Some(16L),
    )
  catch {
    @runtime.RuntimeError::ExecutionBudgetExceeded => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("loop ignored execution budget")
  }
  assert_eq(@executor.call_exported_func(store, instance, "run", [I32(0)]), [
    I32(42),
  ])
  try
    store.with_execution_limits(
      () => {
        store.with_execution_limits(
          () => @executor.call_exported_func(store, instance, "run", [I32(1)]),
          safepoints=Some(1000L),
        )
      },
      safepoints=Some(8L),
    )
  catch {
    @runtime.RuntimeError::ExecutionBudgetExceeded => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("nested scope reset the outer budget")
  }
  assert_eq(@executor.call_exported_func(store, instance, "run", [I32(0)]), [
    I32(42),
  ])
}

///|
test "parked Core work retains its budget outside the creation scope" {
  let budget = @runtime.ResourceBudget::new(pending_work=2L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    budget_loop_module(),
    Imports(store),
  )
  let mut outcome = store.with_execution_limits(
    () => {
      @executor.call_func_by_index_resumable(
        store,
        instance,
        0,
        [I32(1)],
        _ => None,
        cooperative=true,
      )
    },
    safepoints=Some(2000L),
  )
  let mut exhausted = false
  for _ in 0..<20 {
    guard outcome is Suspended(_, continuation) else {
      fail("infinite loop returned")
    }
    assert_eq(budget.used(PendingWork), 2L)
    let next = continuation.continue_execution() catch {
      ExecutionBudgetExceeded => {
        exhausted = true
        break
      }
      error => fail(error.to_string())
    }
    outcome = next
  }
  assert_true(exhausted)
  assert_eq(budget.used(PendingWork), 0L)
  assert_eq(@executor.call_exported_func(store, instance, "run", [I32(0)]), [
    I32(42),
  ])
}

///|
test "failed resource admission rolls back Core allocations and permits reuse" {
  let budget = @runtime.ResourceBudget::new(memory_bytes=65536L, instances=1L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let rejected = budget_loop_module()
  rejected.memories.push({
    limits: { min: 1L, max: None, },
    is_memory64: false,
    is_shared: false,
    page_size_log2: 16,
  })
  rejected.memories.push({
    limits: { min: 1L, max: None, },
    is_memory64: false,
    is_shared: false,
    page_size_log2: 16,
  })
  try
    @executor.instantiate_module_with_imports(store, rejected, Imports(store))
  catch {
    ResourceLimitExceeded(MemoryBytes) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("aggregate initial memories exceeded quota")
  }
  assert_eq(budget.used(MemoryBytes), 0L)
  assert_eq(budget.used(Instances), 0L)
  assert_eq(budget.used(CompilationUnits), 0L)
  let healthy = @executor.instantiate_module_with_imports(
    store,
    budget_loop_module(),
    Imports(store),
  )
  assert_eq(healthy.func_addrs[0], 0)
  assert_eq(@executor.call_exported_func(store, healthy, "run", [I32(0)]), [
    I32(42),
  ])
}

///|
test "deadline and cancellation preflight prevent guest effects" {
  let store = @runtime.Store::Store()
  defer store.close()
  let effects = Ref(0)
  for deadline in [true, false] {
    try
      store.with_execution_limits(
        () => effects.val += 1,
        timeout_ms=if deadline { Some(0) } else { None },
        cancel=if deadline { None } else { Some(() => true) },
      )
    catch {
      @runtime.RuntimeError::ExecutionTimedOut => assert_true(deadline)
      @runtime.RuntimeError::ExecutionCancelled => assert_false(deadline)
      error => fail(error.to_string())
    } noraise {
      _ => fail("preflight accepted stopped execution")
    }
  }
  assert_eq(effects.val, 0)
}

///|
async test "portable deadline includes time spent parked and cleanup restores budget" {
  let budget = @runtime.ResourceBudget::new(pending_work=2L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    budget_loop_module(),
    Imports(store),
  )
  let outcome = store.with_execution_limits(
    () => {
      @executor.call_func_by_index_resumable(
        store,
        instance,
        0,
        [I32(1)],
        _ => None,
        cooperative=true,
      )
    },
    timeout_ms=Some(500),
  )
  guard outcome is Suspended(_, continuation) else { fail("loop did not park") }
  @async.sleep(600)
  try continuation.continue_execution() catch {
    ExecutionTimedOut => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("resuming parked work reset its deadline")
  }
  assert_eq(budget.used(PendingWork), 0L)
  assert_eq(@executor.call_exported_func(store, instance, "run", [I32(0)]), [
    I32(42),
  ])
}
