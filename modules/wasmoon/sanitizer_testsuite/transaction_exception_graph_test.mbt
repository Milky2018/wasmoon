///|
fn check_transaction_exception_graph(
  created_inside : Bool,
  nested : Bool,
  cancel~ : Bool = false,
  through_start~ : Bool = false,
) -> Unit raise {
  let budget = @runtime.ResourceBudget::new(gc_objects=6L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let source = if nested {
    (
      #|(module (tag $child (param i32)) (tag $parent (param exnref))
      #| (func (export "run") (param $e exnref) (param $n i32) (result i32)
      #|  (loop $again local.get $n i32.const 1 i32.sub local.tee $n br_if $again)
      #|  (block $child_done (result i32)
      #|   (try_table (catch $child $child_done)
      #|    (block $parent_done (result exnref)
      #|     (try_table (catch $parent $parent_done) local.get $e throw_ref)
      #|     unreachable)
      #|    throw_ref)
      #|   unreachable))
      #| (func (export "identity") (param exnref) (result exnref) local.get 0))
    )
  } else {
    (
      #|(module (tag $child (param i32)) (tag $parent (param exnref))
      #| (func (export "run") (param $e exnref) (param $n i32) (result i32)
      #|  (loop $again local.get $n i32.const 1 i32.sub local.tee $n br_if $again)
      #|  (block $done (result i32)
      #|   (try_table (catch $child $done) local.get $e throw_ref) unreachable))
      #| (func (export "identity") (param exnref) (result exnref) local.get 0))
    )
  }
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
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
  )
  defer context.close()
  assert_true(context.jit_module.set_cooperative_scheduling(true))
  let ids : Ref[(Int32, Int32)?] = Ref(None)
  let allocate = fn() -> Unit raise @runtime.RuntimeError {
    let child = store.alloc_exn(instance.tag_addrs[0], [I32(42)])
    let parent = if nested {
      store.alloc_exn(instance.tag_addrs[1], [ExnRef(child)])
    } else {
      child
    }
    ids.val = Some((child, parent))
  }
  if !created_inside {
    allocate()
  }
  let outcome : Ref[@wast.JITCoreCallOutcome?] = Ref(None)
  defer (if outcome.val is Some(NativeCoreSuspended(_, continuation)) {
    continuation.cancel()
  })
  let child_token = Ref(0L)
  let parent_token = Ref(0L)
  let unused : Ref[Int32?] = Ref(None)
  let parked_usage = Ref((0L, 0L))
  let park = fn() -> Unit raise @runtime.RuntimeError {
    if created_inside {
      allocate()
    }
    let (child, parent) = ids.val.unwrap()
    outcome.val = Some(
      context.call_core_func_resumable(store, instance, 0, [
        ExnRef(parent),
        I32(10000),
      ]) catch {
        error => raise AsyncHostError(error.to_string())
      },
    )
    guard outcome.val is Some(NativeCoreSuspended(CooperativeYield, _)) else {
      raise TypeMismatch
    }
    child_token.val = store.encode_native_exception(child)
    parent_token.val = store.encode_native_exception(parent)
    parked_usage.val = (budget.used(GcObjects), budget.used(GcBytes))
    let dead = store.alloc_exn(instance.tag_addrs[0], [I32(99)])
    unused.val = Some(dead)
    store.encode_native_exception(dead) |> ignore
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
  let (child, parent) = ids.val.unwrap()
  let arena = store.native_execution_state().exceptions()
  assert_true(arena.snapshot(parent_token.val) is Some(_))
  assert_true(arena.snapshot(child_token.val) is Some(_))
  assert_eq(store.get_exn(child).values, [I32(42)])
  assert_eq(
    store.get_exn(parent).values,
    if nested {
      [ExnRef(child)]
    } else {
      [I32(42)]
    },
  )
  assert_eq((budget.used(GcObjects), budget.used(GcBytes)), parked_usage.val)
  try store.get_exn(unused.val.unwrap()) catch {
    UndefinedElement => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("unpublished exception survived rollback")
  }
  assert_eq(store.collect_garbage(), 0)
  assert_eq((budget.used(GcObjects), budget.used(GcBytes)), parked_usage.val)
  while outcome.val is Some(NativeCoreSuspended(CooperativeYield, continuation)) {
    if cancel {
      continuation.cancel()
      outcome.val = None
      break
    }
    outcome.val = Some(continuation.continue_execution())
  }
  if !cancel {
    guard outcome.val is Some(NativeCoreReturned(values)) else {
      fail("unexpected suspension")
    }
    assert_eq(values, [I32(42)])
    // The same identity must remain usable at the native/host boundary too.
    assert_eq(context.call_core_func(store, instance, 1, [ExnRef(parent)]), [
      ExnRef(parent),
    ])
    assert_eq(store.get_exn(child).values, [I32(42)])
  }
  assert_eq(store.native_execution_state().live_count(), 0)
  store.collect_garbage() |> ignore
  assert_eq(budget.used(GcObjects), 0L)
  assert_eq(budget.used(GcBytes), 0L)
  store.alloc_exn(instance.tag_addrs[0], [I32(7)]) |> ignore
}

///|
test "transaction-created nested payload survives parked rollback" {
  check_transaction_exception_graph(true, true)
}

///|
test "preexisting nested payload control" {
  check_transaction_exception_graph(false, true)
}

///|
test "transaction-created flat exception preserves host identity" {
  check_transaction_exception_graph(true, false)
}

///|
test "transaction-created nested payload is reclaimed after cancellation" {
  check_transaction_exception_graph(true, true, cancel=true)
}

///|
test "start rollback preserves transaction-created nested payload" {
  check_transaction_exception_graph(true, true, through_start=true)
}

///|
test "rollback cleans managed exceptions without native snapshots" {
  let budget = @runtime.ResourceBudget::new(gc_objects=1L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [], results: [], })
  for _ in 0..<3 {
    store.with_instantiation(fn() -> Unit raise @runtime.RuntimeError {
      store.alloc_exn(tag, []) |> ignore
      raise OutOfMemory
    }) catch {
      OutOfMemory => ()
      error => fail(error.to_string())
    }
    assert_eq(budget.used(GcObjects), 0L)
    assert_eq(budget.used(GcBytes), 0L)
  }
  store.alloc_exn(tag, []) |> ignore
}

///|
test "rollback retains new exception records escaping into managed tables" {
  let budget = @runtime.ResourceBudget::new(gc_objects=2L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [], results: [], })
  let table = @runtime.Table::Table(ExnRef, 1, None)
  store.alloc_table(table, use_jit=false) |> ignore
  store.with_instantiation(fn() -> Unit raise @runtime.RuntimeError {
    let exception = store.alloc_exn(tag, [])
    table.set(0, ExnRef(exception))
    raise OutOfMemory
  }) catch {
    OutOfMemory => ()
    error => fail(error.to_string())
  }
  guard table.get(0) is ExnRef(exception) else { fail("missing exception") }
  assert_eq(store.get_exn(exception).tag_addr, tag)
  assert_eq(budget.used(GcObjects), 1L)
  table.set(0, Null)
  store.collect_garbage() |> ignore
  assert_eq(budget.used(GcObjects), 0L)
}
