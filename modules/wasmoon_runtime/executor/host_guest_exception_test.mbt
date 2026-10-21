///|
fn host_guest_exception_module() -> @types.Module {
  @wat.parse(
    (
      #|(module (import "h" "fail" (func $fail))
      #| (import "h" "tag" (tag $e (param i32)))
      #| (import "h" "other" (tag $other (param i32)))
      #| (func (export "all") (result i32)
      #|  (block $caught (try_table (catch_all $caught) call $fail) unreachable)
      #|  i32.const 1)
      #| (func (export "match") (result i32)
      #|  (block $caught (result i32) (try_table (catch $e $caught) call $fail) unreachable))
      #| (func (export "mismatch") (result i32)
      #|  (block $caught (result i32) (try_table (catch $other $caught) call $fail) unreachable))
      #| (func (export "uncaught") call $fail)
      #| (func (export "trap") (result i32)
      #|  (block $caught (try_table (catch_all $caught) unreachable)) i32.const 1)
      #| (func (export "healthy") (result i32) i32.const 42))
    ),
  ) catch {
    error => abort(error.to_string())
  }
}

///|
test "explicit host exceptions are catchable while ordinary errors and traps escape" {
  let budget = @runtime.ResourceBudget::new(pending_work=8L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [I32], results: [], })
  let other = store.alloc_tag({ params: [I32], results: [], })
  let ordinary = Ref(false)
  let host = store.alloc_throwing_host_func(fn(_) raise {
    if ordinary.val {
      raise @runtime.RuntimeError::OutOfBoundsArrayAccess
    }
    let exception = store.guest_exception(tag, [@runtime.RootedValue::i32(42)])
    defer exception.close()
    exception.throw_into_guest()
  })
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "fail", host)
  imports.add_tag("h", "tag", tag)
  imports.add_tag("h", "other", other)
  let instance = @executor.instantiate_module_with_imports(
    store,
    host_guest_exception_module(),
    imports,
  )
  for _ in 0..<3 {
    assert_eq(@executor.call_exported_func(store, instance, "all", []), [I32(1)])
    assert_eq(@executor.call_exported_func(store, instance, "match", []), [
      I32(42),
    ])
    for index in [3, 4] {
      guard @executor.call_func_by_index_with_exception(
          store,
          instance,
          index,
          [],
        )
        is Thrown(actual_tag, values) else {
        fail("uncaught exception lost its structured payload")
      }
      assert_eq(actual_tag, tag)
      assert_eq(values, [I32(42)])
    }
    assert_eq(budget.used(PendingWork), 0L)
  }
  ordinary.val = true
  try @executor.call_exported_func(store, instance, "all", []) catch {
    OutOfBoundsArrayAccess => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("ordinary host failure became a guest exception")
  }
  try @executor.call_exported_func(store, instance, "trap", []) catch {
    Unreachable => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("guest trap became catchable")
  }
  assert_eq(budget.used(PendingWork), 0L)
}

///|
test "host exception creation validates payload ownership and tag lifetime" {
  let budget = @runtime.ResourceBudget::new(pending_work=4L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [I32], results: [], })
  for payload in [[], [@runtime.RootedValue::i64(42L)]] {
    try store.guest_exception(tag, payload) catch {
      TypeMismatch => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("invalid payload accepted")
    }
  }
  try store.guest_exception(-1, []) catch {
    UndefinedElement => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("invalid tag accepted")
  }
  let saved : Ref[@runtime.GuestException?] = Ref(None)
  store.with_instantiation(fn() -> Unit raise @runtime.RuntimeError {
    let transient = store.alloc_tag({ params: [], results: [], })
    saved.val = Some(store.guest_exception(transient, []))
    raise Unreachable
  }) catch {
    Unreachable => ()
    error => fail(error.to_string())
  }
  let replacement = store.alloc_tag({ params: [], results: [], })
  assert_eq(replacement, 1)
  let stale = saved.val.unwrap()
  try store.take_guest_exception(stale) catch {
    InvalidHandle => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("rolled-back tag alias was accepted")
  }
  assert_eq(budget.used(PendingWork), 0L)
  let foreign = @runtime.Store()
  defer foreign.close()
  foreign.alloc_tag({ params: [I32], results: [], }) |> ignore
  let exception = store.guest_exception(tag, [@runtime.RootedValue::i32(42)])
  try foreign.take_guest_exception(exception) catch {
    ForeignStore => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("foreign exception was accepted")
  }
  assert_eq(budget.used(PendingWork), 0L)
  let fresh = store.guest_exception(replacement, [])
  fresh.close()
  fresh.close()
  assert_eq(budget.used(PendingWork), 0L)
  let foreign_instance = @executor.instantiate_module_with_imports(
    foreign,
    @wat.parse(
      "(module (type $s (struct (field i32))) (func (export \"make\") (result (ref $s)) i32.const 42 struct.new $s))",
    ),
    Imports(foreign),
  )
  let foreign_values = @executor.call_exported_func(
    foreign,
    foreign_instance,
    "make",
    [],
  )
  let foreign_root = foreign.root_raw_value(foreign_values[0])
  defer foreign_root.close()
  let reference_tag = store.alloc_tag({ params: [AnyRef], results: [], })
  try store.guest_exception(reference_tag, [foreign_root]) catch {
    ForeignStore => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("foreign rooted payload was accepted")
  }
  assert_eq(budget.used(PendingWork), 0L)
}

///|
test "host exception roots survive reentry and deliver a concrete reference payload" {
  let store = @runtime.Store()
  defer store.close()
  let selected : Ref[@runtime.GuestException?] = Ref(None)
  let nested = @executor.instantiate_module_with_imports(
    store,
    @types.Module::simple([], [I32], [I32Const(7)], "run"),
    Imports(store),
  )
  let host = store.alloc_throwing_host_func_with_caller(fn(_, _) raise {
    @executor.call_exported_func(store, nested, "run", []) |> ignore
    store.collect_garbage() |> ignore
    selected.val.unwrap().throw_into_guest()
  })
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "fail", host)
  let module_ = @wat.parse(
    (
      #|(module (type $s (struct (field i32))) (type $t (struct (field i64)))
      #| (import "h" "fail" (func $fail)) (tag $e (export "e") (param (ref $s)))
      #| (func (export "run") (result i32)
      #|  (block $caught (result (ref $s)) (try_table (catch $e $caught) call $fail) unreachable)
      #|  struct.get $s 0))
    ),
  )
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let wrong = store.alloc_struct(1, [I64(42L)], instance~)
  let wrong_root = store.root_raw_value(StructRef(wrong))
  defer wrong_root.close()
  try store.guest_exception(instance.tag_addrs[0], [wrong_root]) catch {
    TypeMismatch => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("concrete payload subtype was not checked")
  }
  let reference = store.alloc_struct(0, [I32(42)], instance~)
  let rooted = store.root_raw_value(StructRef(reference))
  selected.val = Some(store.guest_exception(instance.tag_addrs[0], [rooted]))
  rooted.close()
  store.collect_garbage() |> ignore
  assert_true(store.is_gc_valid(reference))
  assert_eq(@executor.call_exported_func(store, instance, "run", []), [I32(42)])
  selected.val = None
  store.collect_garbage() |> ignore
  assert_false(store.is_gc_valid(reference))
}

///|
async test "async host exceptions preserve rooted payloads across await and completion" {
  let budget = @runtime.ResourceBudget::new(pending_work=8L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [I32], results: [], })
  let other = store.alloc_tag({ params: [I32], results: [], })
  let ordinary = Ref(false)
  let host = store.alloc_async_host_func(async fn(_) {
    if ordinary.val {
      raise @runtime.RuntimeError::OutOfBoundsArrayAccess
    }
    let exception = store.guest_exception(tag, [@runtime.RootedValue::i32(42)])
    defer exception.close()
    @async.sleep(1)
    store.collect_garbage() |> ignore
    exception.throw_into_guest()
  })
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "fail", host)
  imports.add_tag("h", "tag", tag)
  imports.add_tag("h", "other", other)
  let instance = @executor.instantiate_module_with_imports(
    store,
    host_guest_exception_module(),
    imports,
  )
  assert_eq(@executor.call_exported_func_async(store, instance, "match", []), [
    I32(42),
  ])
  assert_eq(@executor.call_exported_func_async(store, instance, "all", []), [
    I32(1),
  ])
  @runtime.with_async_host_call_driver(async fn(driver) {
    guard @executor.call_func_by_index_resumable_async_with_exception(
        store,
        instance,
        4,
        [],
        driver,
      )
      is ResumableSuspended(continuation) else {
      fail("missing async suspension")
    }
    driver.wait_pending()
    store.collect_garbage() |> ignore
    guard continuation.continue_execution_with_exception()
      is ResumableThrown(actual, values) else {
      fail("async exception lost its structured payload")
    }
    assert_eq(actual, tag)
    assert_eq(values, [I32(42)])
  })
  ordinary.val = true
  try @executor.call_exported_func_async(store, instance, "all", []) catch {
    OutOfBoundsArrayAccess => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("ordinary async failure became catchable")
  }
  assert_eq(budget.used(PendingWork), 0L)
}

///|
test "guest exception admission obeys root quota and permits reuse after denial" {
  let budget = @runtime.ResourceBudget::new(pending_work=1L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [], results: [], })
  let first = store.guest_exception(tag, [])
  try store.guest_exception(tag, []) catch {
    ResourceLimitExceeded(PendingWork) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("exception escaped root quota")
  }
  assert_eq(budget.used(PendingWork), 1L)
  first.close()
  let second = store.guest_exception(tag, [])
  let (_, values, roots) = store.take_guest_exception(second)
  assert_eq(values.length(), 0)
  assert_eq(budget.used(PendingWork), 1L)
  roots.release()
  assert_eq(budget.used(PendingWork), 0L)
}

///|
test "rollback retires prepared exceptions without revoking handed-off roots" {
  let budget = @runtime.ResourceBudget::new(pending_work=2L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [I32], results: [], })
  let prepared : Ref[@runtime.GuestException?] = Ref(None)
  let delivered : Ref[@runtime.GcRootLease?] = Ref(None)
  store.with_instantiation(fn() -> Unit raise @runtime.RuntimeError {
    prepared.val = Some(
      store.guest_exception(tag, [@runtime.RootedValue::i32(1)]),
    )
    let exception = store.guest_exception(tag, [@runtime.RootedValue::i32(2)])
    let (_, _, roots) = store.take_guest_exception(exception)
    delivered.val = Some(roots)
    raise Unreachable
  }) catch {
    Unreachable => ()
    error => fail(error.to_string())
  }
  assert_eq(budget.used(PendingWork), 1L)
  try store.take_guest_exception(prepared.val.unwrap()) catch {
    InvalidHandle => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("rolled-back prepared exception remained valid")
  }
  assert_eq(budget.used(PendingWork), 1L)
  delivered.val.unwrap().release()
  assert_eq(budget.used(PendingWork), 0L)
}

///|
async test "cancelling an async host operation retires its prepared exception" {
  let budget = @runtime.ResourceBudget::new(pending_work=8L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [], results: [], })
  let started = @async.Semaphore(1, initial_value=0)
  let blocked = @async.Semaphore(1, initial_value=0)
  let host = store.alloc_async_host_func(async fn(_) {
    let exception = store.guest_exception(tag, [])
    defer exception.close()
    started.release()
    blocked.acquire()
    exception.throw_into_guest()
  })
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "wait", host)
  let instance = @executor.instantiate_module_with_imports(
    store,
    @wat.parse(
      "(module (import \"h\" \"wait\" (func)) (func (export \"run\") call 0) (func (export \"healthy\") (result i32) i32.const 42))",
    ),
    imports,
  )
  @async.with_task_group(group => {
    let call = group.spawn(no_wait=true, allow_failure=true, () => {
      @executor.call_exported_func_async(store, instance, "run", [])
    })
    started.acquire()
    call.cancel()
    try call.wait() catch {
      _ => ()
    } noraise {
      _ => fail("cancelled call returned")
    }
  })
  assert_eq(budget.used(PendingWork), 0L)
  assert_eq(@executor.call_exported_func(store, instance, "healthy", []), [
    I32(42),
  ])
}

///|
async test "concurrent host exception completions keep invocation payloads separate" {
  let budget = @runtime.ResourceBudget::new(pending_work=16L)
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [I32], results: [], })
  let started = @async.Semaphore(1, initial_value=0)
  let release_first = @async.Semaphore(1, initial_value=0)
  let host = store.alloc_async_host_func(
    async fn(args) {
      guard args[0] is I32(value) else {
        raise @runtime.RuntimeError::TypeMismatch
      }
      let exception = store.guest_exception(tag, [
        @runtime.RootedValue::i32(value),
      ])
      defer exception.close()
      if value == 41 {
        started.release()
        release_first.acquire()
      } else {
        started.acquire()
        release_first.release()
      }
      exception.throw_into_guest()
      []
    },
    func_type={ params: [I32], results: [], },
  )
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "fail", host)
  imports.add_tag("h", "e", tag)
  let instance = @executor.instantiate_module_with_imports(
    store,
    @wat.parse(
      (
        #|(module (import "h" "fail" (func $fail (param i32)))
        #| (import "h" "e" (tag $e (param i32)))
        #| (func (export "run") (param i32) (result i32)
        #|  (block $caught (result i32) (try_table (catch $e $caught) local.get 0 call $fail) unreachable)))
      ),
    ),
    imports,
  )
  @async.with_task_group(group => {
    let first = group.spawn(no_wait=true, () => {
      @executor.call_exported_func_async(store, instance, "run", [I32(41)])
    })
    let second = group.spawn(no_wait=true, () => {
      @executor.call_exported_func_async(store, instance, "run", [I32(42)])
    })
    assert_eq(first.wait(), [I32(41)])
    assert_eq(second.wait(), [I32(42)])
  })
  assert_eq(budget.used(PendingWork), 0L)
}
