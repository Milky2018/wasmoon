///|
fn[T] interpreter_failure_from(
  run : () -> T raise @executor.InterpreterDiagnosticError,
) -> @executor.InterpreterFailure raise {
  try run() catch {
    InterpreterFailed(failure) => failure
  } noraise {
    _ => fail("expected an interpreter diagnostic failure")
  }
}

///|
test "an ordinary continuation can enable owned diagnostics only on resume" {
  let (store, instance) = @executor.instantiate_module(
    @wat.parse("(module (func (export \"run\") nop unreachable))"),
  )
  defer store.close()
  guard @executor.call_func_by_index_resumable(
      store,
      instance,
      0,
      [],
      _ => None,
      cooperative=true,
      cooperative_quantum=1,
    )
    is Suspended(CooperativeYield, continuation) else {
    fail("missing yield")
  }
  let failure = interpreter_failure_from(() => {
    continuation.continue_execution_with_diagnostics()
  })
  assert_true(failure.error is Unreachable)
  assert_eq(failure.frames.length(), 1)
  assert_eq(failure.frames[0].function_index, 0)
  assert_eq(failure.frames[0].instruction_path, [1])
}

///|
test "diagnostics own the guest call chain after repeated host suspension" {
  let ready = Ref(false)
  let store = @runtime.Store()
  defer store.close()
  let host = store.alloc_host_func(
    fn(_) raise @runtime.RuntimeError {
      if !ready.val {
        raise Unreachable
      }
      []
    },
    func_type={ params: [], results: [], },
    type_idx=0,
  )
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("host", "pause", host)
  let module_ = @wat.parse(
    (
      #|(module (import "host" "pause" (func $pause))
      #| (func $leaf call $pause unreachable)
      #| (func $middle call $leaf)
      #| (func $entry (export "run") call $middle))
    ),
  )
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let mut outcome = @executor.call_func_by_index_resumable_with_diagnostics(
    store,
    instance,
    3,
    [],
    _ => Some(7L),
  )
  module_.func_names[1] = "modified after instantiation"
  for _ in 0..<3 {
    guard outcome is Suspended(HostCall(7L), continuation) else {
      fail("missing host pause")
    }
    outcome = continuation.continue_execution_with_diagnostics()
  }
  ready.val = true
  guard outcome is Suspended(_, continuation) else {
    fail("missing last pause")
  }
  let failure = interpreter_failure_from(() => {
    continuation.continue_execution_with_diagnostics()
  })
  assert_true(failure.kind is GuestTrap)
  assert_true(failure.error is Unreachable)
  assert_eq(failure.frames.map(f => f.function_index), [1, 2, 3])
  assert_eq(failure.frames.map(f => f.function_name), [
    Some("leaf"),
    Some("middle"),
    Some("entry"),
  ])
  assert_eq(failure.frames[0].instruction_path, [1])
  assert_true(failure.frames.all(f => f.module_index == instance.store_index()))
  let consumed = interpreter_failure_from(() => {
    continuation.continue_execution_with_diagnostics()
  })
  assert_true(consumed.error is ContinuationAlreadyConsumed)
  assert_eq(consumed.frames.length(), 0)
  store.close()
  // Only owned names/indices/positions remain; no execution handle is needed.
  assert_eq(failure.frames[0].function_name, Some("leaf"))
  assert_eq(failure.frames[0].instruction_path, [1])
}

///|
test "initial nested control traps have structural instruction paths and unnamed frames" {
  let (store, instance) = @executor.instantiate_module(
    @wat.parse(
      "(module (func (block unreachable)) (func (export \"run\") call 0))",
    ),
  )
  defer store.close()
  let failure = interpreter_failure_from(() => {
    @executor.call_func_by_index_resumable_with_diagnostics(
      store,
      instance,
      1,
      [],
      _ => None,
    )
  })
  assert_eq(failure.frames.map(f => f.function_index), [0, 1])
  assert_eq(failure.frames[0].function_name, None)
  assert_eq(failure.frames[0].instruction_path, [0, 0])
  assert_eq(failure.frames[1].instruction_path, [0])
  // Existing callers retain the original typed runtime error contract.
  try
    @executor.call_func_by_index_resumable(store, instance, 1, [], _ => None)
  catch {
    Unreachable => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("unreachable returned")
  }
}

///|
test "host failure and guest trap retain distinct diagnostic provenance" {
  let store = @runtime.Store()
  defer store.close()
  let host = store.alloc_host_func(
    fn(_) raise @runtime.RuntimeError { raise Unreachable },
    func_type={ params: [], results: [], },
    type_idx=0,
  )
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "bad", host)
  let instance = @executor.instantiate_module_with_imports(
    store,
    @wat.parse(
      "(module (import \"h\" \"bad\" (func)) (func call 0) (func unreachable))",
    ),
    imports,
  )
  for index in [1, 2] {
    let failure = interpreter_failure_from(() => {
      @executor.call_func_by_index_resumable_with_diagnostics(
        store,
        instance,
        index,
        [],
        _ => None,
      )
    })
    assert_true(failure.error is Unreachable)
    assert_eq(failure.frames.length(), 1)
    assert_true(
      if index == 1 {
        failure.kind is HostFailure
      } else {
        failure.kind is GuestTrap
      },
    )
  }
}

///|
test "start trap diagnostics preserve Core publication semantics and Store reuse" {
  let store = @runtime.Store()
  defer store.close()
  let module_ = @wat.parse(
    "(module (func $leaf unreachable) (func $start call $leaf) (start $start))",
  )
  let failure = interpreter_failure_from(() => {
    @executor.instantiate_module_with_diagnostics(
      store,
      module_,
      Imports(store),
    )
  })
  assert_true(failure.error is Unreachable)
  assert_eq(failure.frames.map(f => f.function_index), [0, 1])
  assert_eq(failure.frames[0].function_name, Some("leaf"))
  let healthy = @executor.instantiate_module_with_imports(
    store,
    @types.Module::simple([], [I32], [I32Const(42)], "run"),
    Imports(store),
  )
  assert_eq(healthy.store_index(), 1)
  assert_eq(@executor.call_exported_func(store, healthy, "run", []), [I32(42)])
}

///|
test "handled guest exceptions discard provisional frames before a later trap" {
  let (store, instance) = @executor.instantiate_module(
    @wat.parse(
      (
        #|(module (tag $e) (func $throw throw $e)
        #| (func $caught (block $done (try_table (catch_all $done) call $throw)) unreachable))
      ),
    ),
  )
  defer store.close()
  let uncaught = interpreter_failure_from(() => {
    @executor.call_func_by_index_resumable_with_diagnostics(
      store,
      instance,
      0,
      [],
      _ => None,
    )
  })
  assert_true(uncaught.error is UncaughtException)
  assert_eq(uncaught.frames.length(), 1)
  assert_eq(uncaught.frames[0].function_index, 0)
  let caught = interpreter_failure_from(() => {
    @executor.call_func_by_index_resumable_with_diagnostics(
      store,
      instance,
      1,
      [],
      _ => None,
    )
  })
  assert_true(caught.error is Unreachable)
  assert_eq(caught.frames.map(f => f.function_index), [1])
  assert_eq(caught.frames[0].instruction_path, [1])
}

///|
test "cross-module diagnostics report each function's owning instance" {
  let store = @runtime.Store()
  defer store.close()
  let first = @executor.instantiate_module_with_imports(
    store,
    @wat.parse("(module (func $leaf (export \"leaf\") unreachable))"),
    Imports(store),
  )
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("first", "leaf", first.func_addrs[0])
  let second = @executor.instantiate_module_with_imports(
    store,
    @wat.parse(
      "(module (import \"first\" \"leaf\" (func)) (func $entry call 0))",
    ),
    imports,
  )
  let failure = interpreter_failure_from(() => {
    @executor.call_func_by_index_resumable_with_diagnostics(
      store,
      second,
      1,
      [],
      _ => None,
    )
  })
  assert_eq(failure.frames.map(f => f.module_index), [
    first.store_index(),
    second.store_index(),
  ])
  assert_eq(failure.frames.map(f => f.function_index), [0, 1])
}

///|
test "guest continuation diagnostics preserve the trapping body before unwind" {
  let (store, instance) = @executor.instantiate_module(
    @wat.parse(
      (
        #|(module (type $f (func)) (type $c (cont $f))
        #| (func $body unreachable) (elem declare func $body)
        #| (func $entry (resume $c (cont.new $c (ref.func $body)))))
      ),
    ),
  )
  defer store.close()
  let failure = interpreter_failure_from(() => {
    @executor.call_func_by_index_resumable_with_diagnostics(
      store,
      instance,
      1,
      [],
      _ => None,
    )
  })
  assert_true(failure.error is Unreachable)
  assert_true(failure.kind is GuestTrap)
  assert_eq(failure.frames.map(f => f.function_index), [0, 1])
  assert_eq(failure.frames[0].instruction_path, [0])
  assert_eq(failure.frames[1].instruction_path, [2])
}

///|
test "guest body diagnostics survive repeated resumes and late opt in" {
  let (store, instance) = @executor.instantiate_module(
    @wat.parse(
      (
        #|(module (type $f (func)) (type $c (cont $f))
        #| (func $body nop nop nop unreachable) (elem declare func $body)
        #| (func $entry (resume $c (cont.new $c (ref.func $body)))))
      ),
    ),
  )
  defer store.close()
  for late in [false, true] {
    let mut outcome = if late {
      @executor.call_func_by_index_resumable(
        store,
        instance,
        1,
        [],
        _ => None,
        cooperative=true,
        cooperative_quantum=1,
      )
    } else {
      @executor.call_func_by_index_resumable_with_diagnostics(
        store,
        instance,
        1,
        [],
        _ => None,
        cooperative=true,
        cooperative_quantum=1,
      )
    }
    // Enter the body and park it before enabling diagnostics on its parent.
    for _ in 0..<2 {
      guard outcome is Suspended(CooperativeYield, continuation) else {
        fail("missing initial yield")
      }
      outcome = continuation.continue_execution()
    }
    let resumes = Ref(0)
    let failure = interpreter_failure_from(() => {
      while outcome is Suspended(CooperativeYield, continuation) {
        resumes.val += 1
        outcome = continuation.continue_execution_with_diagnostics()
      }
      outcome
    })
    assert_true(resumes.val >= 2)
    assert_true(failure.error is Unreachable)
    assert_true(failure.kind is GuestTrap)
    assert_eq(failure.frames.map(f => f.function_index), [0, 1])
    assert_eq(failure.frames[0].instruction_path, [3])
    assert_eq(failure.frames[1].instruction_path, [2])
    assert_eq(failure.frames[0].function_name, Some("body"))
  }
}

///|
test "guest effect resumes preserve body frames with the current caller chain" {
  let (store, instance) = @executor.instantiate_module(
    @wat.parse(
      (
        #|(module (type $f (func)) (type $c (cont $f)) (tag $yield)
        #| (global $next (mut (ref null $c)) (ref.null $c))
        #| (func $body suspend $yield suspend $yield unreachable)
        #| (elem declare func $body)
        #| (func $start (block $paused (result (ref $c))
        #|   (resume $c (on $yield $paused) (cont.new $c (ref.func $body))) unreachable)
        #|   global.set $next)
        #| (func $step (block $paused (result (ref $c))
        #|   (resume $c (on $yield $paused) (global.get $next)) unreachable)
        #|   global.set $next)
        #| (func $finish (resume $c (global.get $next))))
      ),
    ),
  )
  defer store.close()
  guard @executor.call_func_by_index_resumable_with_diagnostics(
      store,
      instance,
      1,
      [],
      _ => None,
    )
    is Returned(_) else {
    fail("start did not return")
  }
  guard @executor.call_func_by_index_resumable_with_diagnostics(
      store,
      instance,
      2,
      [],
      _ => None,
    )
    is Returned(_) else {
    fail("step did not return")
  }
  let failure = interpreter_failure_from(() => {
    @executor.call_func_by_index_resumable_with_diagnostics(
      store,
      instance,
      3,
      [],
      _ => None,
    )
  })
  assert_true(failure.error is Unreachable)
  assert_eq(failure.frames.map(f => f.function_index), [0, 3])
  assert_eq(failure.frames[0].instruction_path, [2])
  assert_eq(failure.frames[1].instruction_path, [1])
}

///|
test "guest body exceptions stay catchable and clear transported diagnostic frames" {
  let (store, instance) = @executor.instantiate_module(
    @wat.parse(
      (
        #|(module (type $f (func)) (type $c (cont $f)) (tag $e)
        #| (func $body throw $e) (elem declare func $body)
        #| (func $entry (block $done (try_table (catch_all $done)
        #|   (resume $c (cont.new $c (ref.func $body))))) unreachable))
      ),
    ),
  )
  defer store.close()
  let failure = interpreter_failure_from(() => {
    @executor.call_func_by_index_resumable_with_diagnostics(
      store,
      instance,
      1,
      [],
      _ => None,
    )
  })
  assert_true(failure.error is Unreachable)
  assert_eq(failure.frames.map(f => f.function_index), [1])
  assert_eq(failure.frames[0].instruction_path, [1])
  try
    @executor.call_func_by_index_resumable(store, instance, 1, [], _ => None)
  catch {
    Unreachable => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("ordinary API lost its runtime error")
  }
}

///|
test "guest body host errors preserve their cause and provenance" {
  let store = @runtime.Store()
  defer store.close()
  let host = store.alloc_host_func(
    fn(_) raise @runtime.RuntimeError { raise TypeMismatch },
    func_type={ params: [], results: [], },
    type_idx=0,
  )
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "fail", host)
  let instance = @executor.instantiate_module_with_imports(
    store,
    @wat.parse(
      (
        #|(module (type $f (func)) (type $c (cont $f)) (import "h" "fail" (func $host))
        #| (func $body call $host) (elem declare func $body)
        #| (func $entry (resume $c (cont.new $c (ref.func $body)))))
      ),
    ),
    imports,
  )
  let failure = interpreter_failure_from(() => {
    @executor.call_func_by_index_resumable_with_diagnostics(
      store,
      instance,
      2,
      [],
      _ => None,
    )
  })
  assert_true(failure.error is TypeMismatch)
  assert_true(failure.kind is HostFailure)
  assert_eq(failure.frames.map(f => f.function_index), [1, 2])
  try
    @executor.call_func_by_index_resumable(store, instance, 2, [], _ => None)
  catch {
    TypeMismatch => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("ordinary API lost its host error")
  }
}
