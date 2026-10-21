///|
extern "c" fn continuation_test_is_windows() -> Bool = "wasmoon_host_is_windows"

///|
test "typed parked continuation resume preserves resource errors and releases ownership" {
  let module_ = @wat.parse(
    (
      #|(module (import "host" "arm" (func $arm))
      #|  (type $f (func (result i32))) (type $c (cont $f))
      #|  (tag $yield)
      #|  (global $saved (mut (ref null $c)) (ref.null $c))
      #|  (func $body (result i32) suspend $yield i32.const 42)
      #|  (elem declare func $body)
      #|  (func (export "make")
      #|    (block $s (result (ref $c))
      #|      (resume $c (on $yield $s) (cont.new $c (ref.func $body)))
      #|      drop unreachable)
      #|    global.set $saved)
      #|  (func (export "run") (result i32) call $arm
      #|    (resume $c (global.get $saved)))
      #|  (func (export "healthy") (result i32) i32.const 42)
      #|  (func (export "drop") (global.set $saved (ref.null $c))))
    ),
  )
  @validator.validate_module(module_, stack_switching=true)
  let budget = @runtime.ResourceBudget::new(pending_work=2L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  linker.add_host_func("host", "arm", fn(_) { [] })
  let instance = @executor.instantiate_with_linker(linker, "guest", module_)
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  let failure = Ref(0)
  context.jit_module.set_hostcall_callback(fn() {
    runtime_fail_native_allocation(failure.val)
    HostcallCompleted
  })
  defer runtime_fail_native_allocation(0)
  // Sweep the actual host-return/resume boundary: denial before consumption
  // leaves a usable handle; denial inside resume consumes it. Windows also
  // performs thread conversion here even though the parked stack already exists.
  let attempts = if continuation_test_is_windows() { 8 } else { 4 }
  let mut denied = 0
  let mut consumed = 0
  for attempt in 1..<=attempts {
    for _ in 0..<3 {
      context.call_core_func(store, instance, 2, []) |> ignore
      assert_eq(budget.used(PendingWork), 1L)
      failure.val = attempt
      let failed = try {
        assert_eq(context.call_core_func(store, instance, 3, []), [I32(42)])
        false
      } catch {
        @wast.JITCoreCallError::Trap(message) => {
          assert_true(message.contains("out of memory"))
          denied += 1
          true
        }
        error => fail(error.to_string())
      }
      runtime_fail_native_allocation(0)
      failure.val = 0
      if failed {
        try context.call_core_func(store, instance, 3, []) catch {
          Trap(message) => {
            assert_true(message.contains("consumed"))
            consumed += 1
          }
          error => fail(error.to_string())
        } noraise {
          values => assert_eq(values, [I32(42)])
        }
      }
      context.call_core_func(store, instance, 5, []) |> ignore
      store.collect_garbage() |> ignore
      assert_eq(budget.used(PendingWork), 0L)
      assert_eq(context.call_core_func(store, instance, 4, []), [I32(42)])
      context.call_core_func(store, instance, 2, []) |> ignore
      assert_eq(context.call_core_func(store, instance, 3, []), [I32(42)])
      store.native_execution_state().continuations().reclaim_retired()
      assert_eq(budget.used(PendingWork), 0L)
    }
  }
  assert_true(denied > 0)
  if continuation_test_is_windows() {
    assert_true(
      consumed > 0,
      msg="Windows resume resource failure was not exercised",
    )
  }
}
