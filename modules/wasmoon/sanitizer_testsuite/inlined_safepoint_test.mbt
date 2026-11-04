///|
fn inlined_safepoint_module() -> @types.Module raise {
  @wat.parse(
    (
      #|(module
      #| (type $a (array i32))
      #| (func $leaf (param (ref $a)) (result i32) local.get 0 i32.const 0 array.get $a)
      #| (func (export "run") (result i32) (local $value (ref $a))
      #|  i32.const 42 i32.const 1 array.new $a local.set $value
      #|  local.get $value call $leaf drop
      #|  local.get $value call $leaf drop
      #|  local.get $value call $leaf))
    ),
  )
}

///|
test "inlined leaf polls preserve callbacks, scoped fuel and live GC arguments" {
  let module_ = inlined_safepoint_module()
  let counts : Array[Int32] = []
  let outcomes : Array[Array[Bool]] = []
  for opt_level in [0, 2] {
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
      opt_level~,
    )
    defer context.close()
    let polls = Ref(0)
    let result = store.with_execution_limits(
      () => context.call_core_func(store, instance, 1, []),
      cancel=Some(fn() {
        polls.val += 1
        store.collect_garbage() |> ignore
        false
      }),
    )
    assert_eq(result, [I32(42)])
    assert_true(polls.val >= 4)
    counts.push(polls.val)
    let interrupted = Ref(0)
    let cancel_at = polls.val - 1
    try
      store.with_execution_limits(
        () => context.call_core_func(store, instance, 1, []),
        cancel=Some(fn() {
          interrupted.val += 1
          interrupted.val == cancel_at
        }),
      )
      |> ignore
    catch {
      @wast.JITCoreCallError::HostInvocation(ExecutionCancelled) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("inlined leaf ignored cancellation")
    }
    assert_eq(interrupted.val, cancel_at)
    assert_eq(budget.used(PendingWork), 0L)
    assert_eq(context.call_core_func(store, instance, 1, []), [I32(42)])
    let permitted : Array[Bool] = []
    for allowance in 0L..<7L {
      let completed = try {
        assert_eq(
          store.with_execution_limits(
            () => context.call_core_func(store, instance, 1, []),
            safepoints=Some(allowance),
          ),
          [I32(42)],
        )
        true
      } catch {
        @wast.JITCoreCallError::HostInvocation(ExecutionBudgetExceeded) => false
        @runtime.RuntimeError::ExecutionBudgetExceeded => false
        error => fail(error.to_string())
      }
      permitted.push(completed)
      assert_eq(budget.used(PendingWork), 0L)
    }
    assert_false(permitted[0])
    assert_true(permitted[6])
    outcomes.push(permitted)
  }
  assert_eq(counts[0], counts[1])
  assert_eq(outcomes[0], outcomes[1])
}

///|
test "inlined leaf countdowns preserve suspension roots and cancellation" {
  let module_ = inlined_safepoint_module()
  let counts : Array[Int32] = []
  for opt_level in [0, 2] {
    let store = @runtime.Store::with_c_heap()
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
      opt_level~,
    )
    defer context.close()
    assert_true(context.jit_module.set_cooperative_scheduling(true, quantum=1))
    let mut outcome = context.call_core_func_resumable(store, instance, 1, [])
    defer (if outcome is NativeCoreSuspended(_, continuation) {
      continuation.cancel()
    })
    let mut yields = 0
    while outcome is NativeCoreSuspended(CooperativeYield, continuation) {
      yields += 1
      store.collect_garbage() |> ignore
      outcome = continuation.continue_execution()
    }
    guard outcome is NativeCoreReturned(values) else {
      fail("unexpected suspension")
    }
    assert_eq(values, [I32(42)])
    assert_true(yields >= 4)
    counts.push(yields)
    guard context.call_core_func_resumable(store, instance, 1, [])
      is NativeCoreSuspended(CooperativeYield, cancelled) else {
      fail("entry poll did not suspend")
    }
    cancelled.cancel()
    store.collect_garbage() |> ignore
    assert_true(context.jit_module.set_cooperative_scheduling(false))
    assert_eq(context.call_core_func(store, instance, 1, []), [I32(42)])
  }
  assert_eq(counts[0], counts[1])
}
