///|
test "cooperative quantum counts dispatches and retains the compatible default" {
  let body = Array::make(2050, @types.Instruction::Nop)
  body.push(I32Const(42))
  let (store, instance) = @executor.instantiate_module(
    @types.Module::simple([], [I32], ReadOnlyArray::from_array(body), "run"),
  )
  defer store.close()
  for quantum in [1, 8, 1024, 2051, 4096] {
    let mut outcome = store.with_execution_limits(
      () => {
        @executor.call_func_by_index_resumable(
          store,
          instance,
          0,
          [],
          _ => None,
          cooperative=true,
          cooperative_quantum=quantum,
        )
      },
      safepoints=Some(1L),
    )
    let mut yields = 0
    while outcome is Suspended(CooperativeYield, continuation) {
      yields += 1
      outcome = continuation.continue_execution()
    }
    assert_eq(yields, 2050 / quantum)
    guard outcome is Returned(values) else { fail("unexpected suspension") }
    assert_eq(values, [I32(42)])
  }
  let mut outcome = @executor.call_func_by_index_resumable(
    store,
    instance,
    0,
    [],
    _ => None,
    cooperative=true,
  )
  let mut yields = 0
  while outcome is Suspended(CooperativeYield, continuation) {
    yields += 1
    outcome = continuation.continue_execution()
  }
  assert_eq(yields, 2)
  for quantum in [0, -1] {
    try
      @executor.call_func_by_index_resumable(
        store,
        instance,
        0,
        [],
        _ => None,
        cooperative_quantum=quantum,
      )
    catch {
      TypeMismatch => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("accepted a nonpositive quantum")
    }
  }
}

///|
test "cooperative boundaries poll cancellation without resetting scope budgets" {
  let body = Array::make(100, @types.Instruction::Nop)
  body.push(I32Const(42))
  let budget = @runtime.ResourceBudget::new(pending_work=2L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    @types.Module::simple([], [I32], ReadOnlyArray::from_array(body), "run"),
    Imports(store),
  )
  let stopped = Ref(false)
  let outcome = store.with_execution_limits(
    () => {
      @executor.call_func_by_index_resumable(
        store,
        instance,
        0,
        [],
        _ => None,
        cooperative=true,
        cooperative_quantum=3,
      )
    },
    cancel=Some(() => stopped.val),
    safepoints=Some(1L),
  )
  guard outcome is Suspended(CooperativeYield, continuation) else {
    fail("expected yield")
  }
  stopped.val = true
  try continuation.continue_execution() catch {
    ExecutionCancelled => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("cooperative quantum ignored cancellation")
  }
  assert_eq(budget.used(PendingWork), 0L)
  try continuation.continue_execution() catch {
    ContinuationAlreadyConsumed => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("cancelled continuation remained usable")
  }
  assert_eq(@executor.call_exported_func(store, instance, "run", []), [I32(42)])
}

///|
test "host suspension preserves the unfinished cooperative quantum" {
  let ready = Ref(false)
  let store = @runtime.Store::Store()
  defer store.close()
  let nested = @executor.instantiate_module_with_imports(
    store,
    @types.Module::simple([], [I32], [Nop, Nop, I32Const(7)], "nested"),
    Imports(store),
  )
  let inner_yields = Ref(0)
  let host = store.alloc_host_func(
    fn(_) raise @runtime.RuntimeError {
      if !ready.val {
        raise Unreachable
      }
      let mut inner = @executor.call_func_by_index_resumable(
        store,
        nested,
        0,
        [],
        _ => None,
        cooperative=true,
        cooperative_quantum=1,
      )
      while inner is Suspended(CooperativeYield, continuation) {
        inner_yields.val += 1
        inner = continuation.continue_execution()
      }
      guard inner is Returned(_) else { raise TypeMismatch }
      []
    },
    func_type={ params: [], results: [], },
    type_idx=0,
  )
  let module_ = @wat.parse(
    "(module (import \"host\" \"pause\" (func)) (func (export \"run\") (result i32) nop nop call 0 nop nop i32.const 42))",
  )
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("host", "pause", host)
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  guard @executor.call_func_by_index_resumable(
      store,
      instance,
      1,
      [],
      _ => Some(7L),
      cooperative=true,
      cooperative_quantum=4,
    )
    is Suspended(HostCall(7L), host_pause) else {
    fail("expected host pause")
  }
  ready.val = true
  guard host_pause.continue_execution()
    is Suspended(CooperativeYield, quantum_pause) else {
    fail("host resume reset the instruction counter")
  }
  guard quantum_pause.continue_execution() is Returned(values) else {
    fail("unexpected pause")
  }
  assert_eq(values, [I32(42)])
  assert_eq(inner_yields.val, 2)
}

///|
test "different quanta preserve parked GC roots and independent invocation fairness" {
  let module_ = @wat.parse(
    (
      #|(module (type $s (struct (field i32)))
      #| (func (export "run") (param i32) (result i32) (local (ref null $s))
      #| local.get 0 struct.new $s local.set 1 nop nop nop nop nop nop nop nop
      #| local.get 1 ref.as_non_null struct.get $s 0))
    ),
  )
  let (store, instance) = @executor.instantiate_module(module_)
  defer store.close()
  let mut first = @executor.call_func_by_index_resumable(
    store,
    instance,
    0,
    [I32(41)],
    _ => None,
    cooperative=true,
    cooperative_quantum=2,
  )
  let mut second = @executor.call_func_by_index_resumable(
    store,
    instance,
    0,
    [I32(42)],
    _ => None,
    cooperative=true,
    cooperative_quantum=5,
  )
  let mut first_yields = 0
  let mut second_yields = 0
  for _ in 0..<20 {
    store.collect_garbage() |> ignore
    if first is Suspended(CooperativeYield, continuation) {
      first_yields += 1
      first = continuation.continue_execution()
    }
    if second is Suspended(CooperativeYield, continuation) {
      second_yields += 1
      second = continuation.continue_execution()
    }
  }
  assert_true(first_yields > second_yields && second_yields > 0)
  guard first is Returned(first_values) else { fail("first did not return") }
  guard second is Returned(second_values) else { fail("second did not return") }
  assert_eq(first_values, [I32(41)])
  assert_eq(second_values, [I32(42)])
}

///|
test "cooperative scheduling preserves nested last-unit scopes and charged exhaustion" {
  let (store, instance) = @executor.instantiate_module(
    @wat.parse(
      "(module (func (export \"straight\") (result i32) nop nop i32.const 42) (func call 0 drop))",
    ),
  )
  defer store.close()
  for quantum in [1, 16] {
    let mut outcome = store.with_execution_limits(
      () => {
        store.with_execution_limits(
          () => {
            @executor.call_func_by_index_resumable(
              store,
              instance,
              0,
              [],
              _ => None,
              cooperative=true,
              cooperative_quantum=quantum,
            )
          },
          safepoints=Some(2L),
        )
      },
      safepoints=Some(1L),
    )
    while outcome is Suspended(CooperativeYield, continuation) {
      outcome = continuation.continue_execution()
    }
    guard outcome is Returned(values) else { fail("unexpected suspension") }
    assert_eq(values, [I32(42)])
    for budget in [0L, 1L] {
      try
        store.with_execution_limits(
          () => {
            let mut call = @executor.call_func_by_index_resumable(
              store,
              instance,
              1,
              [],
              _ => None,
              cooperative=true,
              cooperative_quantum=quantum,
            )
            while call is Suspended(CooperativeYield, continuation) {
              call = continuation.continue_execution()
            }
          },
          safepoints=Some(budget),
        )
      catch {
        @runtime.RuntimeError::ExecutionBudgetExceeded => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("charged function entry ignored the budget")
      }
    }
  }
}

///|
test "cooperative scheduling observes exhaustion already latched by another charged call" {
  let (store, instance) = @executor.instantiate_module(
    @wat.parse("(module (func nop nop nop))"),
  )
  defer store.close()
  let outcome = store.with_execution_limits(
    () => {
      let outcome = @executor.call_func_by_index_resumable(
        store,
        instance,
        0,
        [],
        _ => None,
        cooperative=true,
        cooperative_quantum=1,
      )
      try
        @executor.call_func_by_index_resumable(store, instance, 0, [], _ => None)
      catch {
        ExecutionBudgetExceeded => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("second function entry did not exhaust the budget")
      }
      outcome
    },
    safepoints=Some(1L),
  )
  guard outcome is Suspended(CooperativeYield, continuation) else {
    fail("missing yield")
  }
  try continuation.continue_execution() catch {
    ExecutionBudgetExceeded => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("latched exhaustion was ignored")
  }
}
