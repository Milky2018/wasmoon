///|
fn parked_host_call(
  ready : Ref[Bool],
  close_in_host? : Bool = false,
) -> (@runtime.Store, @executor.ExecutionContinuation) raise {
  let store = @runtime.Store::Store()
  errdefer store.close()
  let host = store.alloc_host_func_with_caller(
    fn(_, _) raise @runtime.RuntimeError {
      if close_in_host {
        store.close()
      }
      if !ready.val {
        raise Unreachable
      }
      [I32(42)]
    },
    func_type={ params: [], results: [I32], },
    type_idx=0,
  )
  let imports = @runtime.Imports::Imports()
  imports.add_func("host", "leaf", host)
  let module_ = @wat.parse(
    (
      #|(module
      #|  (import "host" "leaf" (func $leaf (result i32)))
      #|  (func (export "run") (result i32) call $leaf))
    ),
  )
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let outcome = @executor.call_func_by_index_resumable(store, instance, 1, [], fn(
    _,
  ) {
    Some(7L)
  })
  guard outcome is Suspended(_, continuation) else {
    fail("expected suspension")
  }
  (store, continuation)
}

///|
fn require_consumed(
  continuation : @executor.ExecutionContinuation,
) -> Unit raise {
  try continuation.continue_execution() catch {
    ContinuationAlreadyConsumed => ()
    error => raise error
  } noraise {
    _ => fail("expected consumed continuation")
  }
}

///|
test "Store close cancels parked interpreter execution with retained handles" {
  for _ in 0..<16 {
    let (store, continuation) = parked_host_call(Ref(false))
    store.close()
    require_consumed(continuation)
    continuation.cancel()
    store.close()
  }
}

///|
test "explicit cancellation releases interpreter execution before Store close" {
  let (store, continuation) = parked_host_call(Ref(false))
  continuation.cancel()
  continuation.cancel()
  require_consumed(continuation)
  store.close()
}

///|
test "resuspension transfers ownership without retaining consumed handles" {
  let ready = Ref(false)
  let (store, first) = parked_host_call(ready)
  defer store.close()
  let outcome = first.continue_execution()
  guard outcome is Suspended(_, second) else {
    fail("expected another suspension")
  }
  first.cancel()
  require_consumed(first)
  ready.val = true
  debug_inspect(second.continue_execution(), content="Returned([I32(42)])")
  require_consumed(second)
}

///|
test "closing Store inside host call prevents suspension publication" {
  try parked_host_call(Ref(false), close_in_host=true) catch {
    @runtime.StoreClosed => ()
    error => raise error
  } noraise {
    _ => fail("expected closed Store")
  }
}

///|
test "Store cancellation releases an atomic waiter before retained continuation drops" {
  let module_ = @wat.parse(
    (
      #|(module
      #|  (memory 1 1 shared)
      #|  (func (export "wait") (result i32)
      #|    i32.const 0 i32.const 0 i64.const -1 memory.atomic.wait32))
    ),
  )
  let (store, instance) = @executor.instantiate_module(module_)
  let observer = @runtime.Store::Store()
  defer observer.close()
  let memory = observer.get_mem(observer.alloc_shared_mem(store.get_mem(0)))
  let outcome = @executor.call_func_by_index_resumable(
    store,
    instance,
    0,
    [],
    fn(_) { None },
    cooperative=true,
  )
  guard outcome is Suspended(AtomicWait, continuation) else {
    fail("expected atomic wait")
  }
  store.close()
  inspect(memory.atomic_notify(0L, 1U), content="0")
  require_consumed(continuation)
}

///|
test "Store suspended cleanup detaches registrations before reentrant callbacks" {
  let store = @runtime.Store::Store()
  let calls = Ref(0)
  store.register_suspended_execution(fn() {
    calls.val += 1
    store.close()
  })
  |> ignore
  let removed = store.register_suspended_execution(fn() { calls.val += 100 })
  store.release_suspended_execution(removed)
  store.close()
  store.close()
  inspect(calls.val, content="1")
  try store.register_suspended_execution(fn() { () }) catch {
    StoreClosed => ()
    error => raise error
  } noraise {
    _ => fail("expected terminal registration rejection")
  }
}

///|
async test "Store close cancels a pending asynchronous interpreter host call" {
  let store = @runtime.Store::Store()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  let started = @async.Semaphore(1, initial_value=0)
  let pending = @async.Semaphore(1, initial_value=0)
  let finished = Ref(false)
  linker.add_async_host_func(
    "host",
    "wait",
    async fn(_) {
      started.release()
      defer {
        finished.val = true
        store.close()
      }
      pending.acquire()
      []
    },
    func_type={ params: [], results: [], },
  )
  let module_ = @wat.parse(
    (
      #|(module
      #|  (import "host" "wait" (func $wait))
      #|  (func (export "run") call $wait))
    ),
  )
  let instance = @executor.instantiate_with_linker(linker, "guest", module_)
  @async.with_task_group(group => {
    let call = group.spawn(no_wait=true, allow_failure=true, () => {
      @executor.call_exported_func_async(store, instance, "run", [])
    })
    started.acquire()
    store.close()
    try call.wait() catch {
      _ => ()
    } noraise {
      _ => fail("expected cancellation")
    }
  })
  inspect(finished.val, content="true")
}
