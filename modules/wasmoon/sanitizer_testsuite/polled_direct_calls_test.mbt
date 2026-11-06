///|
fn polled_direct_module() -> @types.Module raise {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $node (struct (field (mut i64)) (field i64)))
      #| (func $leaf (param (ref $node)) (result i64)
      #|  local.get 0 struct.get $node 0 i64.const 3 i64.div_s i64.const 5 i64.div_s)
      #| (func $wrapper (param (ref $node)) (result i64) local.get 0 call $leaf)
      #| (func $body (param (ref $node)) (result i64)
      #|  local.get 0 struct.get $node 0 local.get 0 call $wrapper i64.add
      #|  local.get 0 struct.get $node 1 i64.add)
      #| (func (export "probe") (result i64)
      #|  i64.const 90 i64.const 7 struct.new $node call $body))
    ),
  )
  @validator.validate_module(module_)
  module_
}

///|
test "direct calls preserve callback fuel and quantum boundaries" {
  let module_ = polled_direct_module()
  let callback_counts : Array[Int32] = []
  let allowances : Array[Array[Bool]] = []
  let yields : Array[Array[Int32]] = []
  for level in [0, 2, 3] {
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
      opt_level=level,
    )
    defer context.close()
    let callbacks = Ref(0)
    let result = store.with_execution_limits(
      () => context.call_core_func(store, instance, 3, []),
      cancel=Some(fn() {
        callbacks.val += 1
        store.collect_garbage() |> ignore
        false
      }),
    )
    assert_eq(result, [I64(103L)])
    callback_counts.push(callbacks.val)
    let permitted : Array[Bool] = []
    for allowance in 0L..<8L {
      permitted.push(
        try {
          assert_eq(
            store.with_execution_limits(
              () => context.call_core_func(store, instance, 3, []),
              safepoints=Some(allowance),
            ),
            [I64(103L)],
          )
          true
        } catch {
          @wast.JITCoreCallError::HostInvocation(ExecutionBudgetExceeded) =>
            false
          @runtime.RuntimeError::ExecutionBudgetExceeded => false
          error => fail(error.to_string())
        },
      )
    }
    assert_false(permitted[0])
    assert_true(permitted[7])
    allowances.push(permitted)
    let interruptions = Ref(0)
    try
      store.with_execution_limits(
        () => context.call_core_func(store, instance, 3, []),
        cancel=Some(fn() {
          interruptions.val += 1
          interruptions.val == 3
        }),
      )
      |> ignore
    catch {
      @wast.JITCoreCallError::HostInvocation(ExecutionCancelled) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("direct call ignored cancellation")
    }
    assert_eq(interruptions.val, 3)
    let counts : Array[Int32] = []
    for quantum in [1, 2, 3, 4, 8, 64] {
      assert_true(context.jit_module.set_cooperative_scheduling(true, quantum~))
      let mut call = context.call_core_func_resumable(store, instance, 3, [])
      defer (if call is NativeCoreSuspended(_, continuation) {
        continuation.cancel()
      })
      let mut count = 0
      while call is NativeCoreSuspended(CooperativeYield, continuation) {
        store.collect_garbage() |> ignore
        count += 1
        call = continuation.continue_execution()
      }
      guard call is NativeCoreReturned(values) else {
        fail("direct call did not return")
      }
      assert_eq(values, [I64(103L)])
      counts.push(count)
    }
    yields.push(counts)
  }
  assert_true(callback_counts[0] > 0)
  for i in 1..<3 {
    assert_eq(callback_counts[i], callback_counts[0])
    assert_eq(allowances[i], allowances[0])
    assert_eq(yields[i], yields[0])
  }
}
