///|
test "parked root sources isolate snapshots and retire independently on cancellation" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $value (struct (field i32)))
      #| (type $read_type (func (param (ref null $value)) (result i32)))
      #| (table 1 funcref) (elem (i32.const 0) $read)
      #| (func (export "run") (param $n i32) (param $id i32) (result i32)
      #|  (local $value (ref null $value))
      #|  local.get $id struct.new $value local.set $value
      #|  (loop $again
      #|   local.get $n i32.const 1 i32.sub local.tee $n br_if $again)
      #|  local.get $value i32.const 0 call_indirect (type $read_type))
      #| (func $read (type $read_type) local.get 0 struct.get $value 0))
    ),
  )
  for opt_level in [0, 2, 3] {
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
    assert_true(context.jit_module.set_cooperative_scheduling(true, quantum=8))
    let first = context.call_core_func_resumable(store, instance, 0, [
      I32(100),
      I32(41),
    ])
    guard first is NativeCoreSuspended(CooperativeYield, first) else {
      fail("first call did not park")
    }
    defer first.cancel()
    let snapshot = store.get_c_heap_ptr().execution_roots()
    assert_true(snapshot.length() > 0)
    let root = snapshot[0]
    snapshot[0] = 0L
    assert_eq(store.get_c_heap_ptr().execution_roots()[0], root)
    let mut second = context.call_core_func_resumable(store, instance, 0, [
      I32(100),
      I32(43),
    ])
    defer (if second is NativeCoreSuspended(_, continuation) {
      continuation.cancel()
    })
    guard second is NativeCoreSuspended(CooperativeYield, _) else {
      fail("second call did not park")
    }
    assert_eq(store.collect_garbage(), 0)
    first.cancel()
    first.cancel()
    assert_eq(store.collect_garbage(), 1)
    while second is NativeCoreSuspended(CooperativeYield, continuation) {
      assert_eq(store.collect_garbage(), 0)
      second = continuation.continue_execution()
    }
    guard second is NativeCoreReturned(values) else {
      fail("second call did not return")
    }
    assert_eq(values, [I32(43)])
    assert_eq(store.collect_garbage(), 1)
  }
}
