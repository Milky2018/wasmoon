///|
fn check_parked_exception_rollback(
  through_start : Bool,
  preencoded~ : Bool = false,
  cancel~ : Bool = false,
  nested~ : Bool = false,
  in_heap~ : Bool = false,
) -> Unit raise {
  let budget = @runtime.ResourceBudget::new(gc_objects=7L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [], results: [], })
  let child = store.alloc_exn(tag, [])
  let exception = if nested {
    let parent_tag = store.alloc_tag({ params: [ExnRef], results: [], })
    store.alloc_exn(parent_tag, [ExnRef(child)])
  } else {
    child
  }
  let unused = store.alloc_exn(tag, [])
  let retained = if preencoded {
    Some(store.encode_native_exception(exception))
  } else {
    None
  }
  let worker = @wat.parse(
    if in_heap {
      (
        #|(module (type $box (struct (field (mut exnref))))
        #| (func (export "run") (param $box (ref $box)) (param $n i32) (result exnref)
        #|  (loop $again local.get $n i32.const 1 i32.sub local.tee $n br_if $again)
        #|  local.get $box struct.get $box 0))
      )
    } else {
      (
        #|(module (func (export "run") (param $e exnref) (param $n i32) (result exnref)
        #| (loop $again local.get $n i32.const 1 i32.sub local.tee $n br_if $again) local.get $e))
      )
    },
  )
  let instance = @executor.instantiate_module_with_imports(
    store,
    worker,
    Imports(store),
  )
  let box = if in_heap {
    Some(store.alloc_struct(0, [Null], instance~))
  } else {
    None
  }
  let before = budget.used(GcObjects) - (if preencoded { 1L } else { 0L })
  let context = build_gc_root_context(
    worker,
    instance,
    store,
    enable_cancellation=true,
  )
  defer context.close()
  assert_true(context.jit_module.set_cooperative_scheduling(true))
  let parked : Ref[@wast.JITCoreCallOutcome?] = Ref(None)
  defer (if parked.val is Some(NativeCoreSuspended(_, continuation)) {
    continuation.cancel()
  })
  let park = fn() -> Unit raise @runtime.RuntimeError {
    let argument : @types.Value = match box {
      Some(box) => {
        store.struct_set(box, 0, ExnRef(exception))
        StructRef(box)
      }
      None => ExnRef(exception)
    }
    parked.val = Some(
      context.call_core_func_resumable(store, instance, 0, [
        argument,
        I32(10000),
      ]) catch {
        error => raise AsyncHostError(error.to_string())
      },
    )
    // A separate unpublished snapshot must still be reclaimed.
    store.encode_native_exception(unused) |> ignore
  }
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  if through_start {
    linker.add_host_func(
      "host",
      "park",
      _ => {
        park()
        []
      },
      func_type={ params: [], results: [], },
    )
    let transaction = @runtime.InstantiationTransaction::new()
    linker.register_rollback(transaction.registrar())
    let failing = @wat.parse(
      "(module (import \"host\" \"park\" (func $park)) (func $start call $park unreachable) (start $start))",
    )
    try @executor.instantiate_with_linker(linker, "failing", failing) catch {
      Unreachable => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("expected start trap")
    }
    transaction.rollback()
  } else {
    try
      store.with_instantiation(fn() -> Unit raise @runtime.RuntimeError {
        park()
        raise OutOfMemory
      })
    catch {
      OutOfMemory => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("expected rollback")
    }
  }
  guard parked.val is Some(NativeCoreSuspended(CooperativeYield, _)) else {
    fail("worker did not park")
  }
  let after_rollback = budget.used(GcObjects)
  if retained is Some(token) {
    assert_eq(store.encode_native_exception(exception), token)
    // The preencoded control also exercises normal parked-root collection.
    store.collect_garbage() |> ignore
  }
  let mut yields = 0
  while parked.val is Some(NativeCoreSuspended(CooperativeYield, continuation)) {
    yields += 1
    if cancel {
      continuation.cancel()
      parked.val = None
      break
    }
    parked.val = Some(continuation.continue_execution())
  }
  if !cancel {
    guard parked.val is Some(NativeCoreReturned(values)) else {
      fail("unexpected suspension")
    }
    assert_eq(values, [ExnRef(exception)])
    if nested {
      assert_eq(store.get_exn(exception).values, [ExnRef(child)])
    }
  }
  assert_eq(after_rollback, before + (if nested { 2L } else { 1L }))
  assert_true(yields > 0)
  assert_eq(store.native_execution_state().live_count(), 0)
  store.collect_garbage() |> ignore
  if box is Some(box) {
    assert_false(store.is_gc_valid(box))
  }
  // Native heap identities remain reserved after collection; exception
  // handles and snapshots do not. No exception charge may remain here.
  let retired_heap_slots = if in_heap { 1L } else { 0L }
  assert_eq(budget.used(GcObjects), retired_heap_slots)
  store.alloc_exn(tag, []) |> ignore
  assert_eq(budget.used(GcObjects), retired_heap_slots + 1L)
}

///|
test "start rollback retains exception snapshots held by parked native calls" {
  for nested in [false, true] {
    check_parked_exception_rollback(true, nested~)
  }
}

///|
test "direct rollback retains parked snapshots until resume or cancellation" {
  for cancel in [false, true] {
    check_parked_exception_rollback(false, cancel~)
  }
}

///|
test "preexisting parked exception snapshots survive rollback and ordinary GC" {
  check_parked_exception_rollback(false, preencoded=true)
}

///|
test "reentrant rollback retains exception snapshots held by active native calls" {
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let tag = store.alloc_tag({ params: [], results: [], })
  let exception = store.alloc_exn(tag, [])
  let transaction = @runtime.InstantiationTransaction::new()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  linker.add_host_func(
    "host",
    "rollback",
    _ => {
      transaction.rollback()
      []
    },
    func_type={ params: [], results: [], },
  )
  let worker = @wat.parse(
    "(module (import \"host\" \"rollback\" (func $rollback)) (func (export \"run\") (param $e exnref) (result exnref) call $rollback local.get $e))",
  )
  let instance = @executor.instantiate_with_linker(linker, "worker", worker)
  let context = build_gc_root_context(worker, instance, store)
  defer context.close()
  context.install_hostcall_dispatcher(store, instance)
  linker.register_rollback(transaction.registrar())
  assert_eq(context.call_core_func(store, instance, 1, [ExnRef(exception)]), [
    ExnRef(exception),
  ])
}

///|
test "parked native heap roots retain nested exception snapshots across rollback" {
  check_parked_exception_rollback(false, in_heap=true, nested=true)
}
