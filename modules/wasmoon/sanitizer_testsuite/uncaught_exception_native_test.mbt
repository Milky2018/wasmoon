///|
test "exception-aware native entry preserves a rooted uncaught host exception" {
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let tag = store.alloc_tag({ params: [I32], results: [], })
  let host = store.alloc_throwing_host_func(fn(_) raise {
    let exception = store.guest_exception(tag, [@runtime.RootedValue::i32(42)])
    defer exception.close()
    exception.throw_into_guest()
  })
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "fail", host)
  imports.add_tag("h", "tag", tag)
  let module_ = @wat.parse(
    (
      #|(module (import "h" "fail" (func $fail))
      #| (import "h" "tag" (tag (param i32)))
      #| (func (export "run") call $fail))
    ),
  )
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  context.install_hostcall_dispatcher(store, instance)
  guard context.call_core_func_with_exception(store, instance, 1, [])
    is Thrown(exception) else {
    fail("uncaught guest exception returned ordinary results")
  }
  defer exception.close()
  store.collect_garbage() |> ignore
  guard store.borrow_rooted_value(exception) is ExnRef(index) else {
    fail("uncaught exception did not retain its Store identity")
  }
  let value = store.get_exn(index)
  assert_eq(value.tag_addr, tag)
  assert_eq(value.values, [I32(42)])
}

///|
test "exception-aware entry distinguishes guest replacement from host failure and trap" {
  let budget = @runtime.ResourceBudget::new(pending_work=8L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [I32], results: [], })
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
  let module_ = @wat.parse(
    (
      #|(module (import "h" "fail" (func $fail))
      #| (import "h" "tag" (tag $original (param i32))) (tag $replacement (param i64))
      #| (func (export "replace")
      #|  (block $caught (try_table (catch_all $caught) call $fail) unreachable)
      #|  i64.const 99 throw $replacement)
      #| (func (export "trap") unreachable)
      #| (func (export "healthy") (result i32) i32.const 7))
    ),
  )
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  context.install_hostcall_dispatcher(store, instance)
  let retained : Array[@runtime.RootedValue] = []
  defer (for value in retained {
    value.close()
  })
  for _ in 0..<3 {
    guard context.call_core_func_with_exception(store, instance, 1, [])
      is Thrown(exception) else {
      fail("replacement exception returned")
    }
    retained.push(exception)
    assert_eq(budget.used(PendingWork), retained.length().to_int64())
    guard context.call_core_func_with_exception(store, instance, 3, [])
      is Returned([I32(7)]) else {
      fail("ordinary return was lost")
    }
  }
  store.collect_garbage() |> ignore
  for exception in retained {
    guard store.borrow_rooted_value(exception) is ExnRef(index) else {
      fail("missing identity")
    }
    let value = store.get_exn(index)
    assert_eq(value.tag_addr, instance.tag_addrs[1])
    assert_eq(value.values, [I64(99L)])
  }
  ordinary.val = true
  try context.call_core_func_with_exception(store, instance, 1, []) catch {
    HostInvocation(OutOfBoundsArrayAccess) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("host failure became guest exception")
  }
  try context.call_core_func_with_exception(store, instance, 2, []) catch {
    Trap(message) => assert_true(message.has_prefix("unreachable"))
    error => fail(error.to_string())
  } noraise {
    _ => fail("true trap became guest exception")
  }
  assert_eq(budget.used(PendingWork), retained.length().to_int64())
}

///|
test "resumed uncaught exception retains nested reference payload and Store provenance" {
  let budget = @runtime.ResourceBudget::new(pending_work=8L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let module_ = @wat.parse(
    (
      #|(module (type $s (struct (field i32))) (tag $child (param (ref $s)))
      #| (tag $parent (param exnref v128 i64))
      #| (func (export "run") (param $e exnref) (param $n i32)
      #|  (loop $again local.get $n i32.const 1 i32.sub local.tee $n br_if $again)
      #|  local.get $e throw_ref))
    ),
  )
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let reference = store.alloc_struct(0, [I32(42)], instance~)
  let child = store.alloc_exn(instance.tag_addrs[0], [StructRef(reference)])
  let vector = @types.int64_pair_to_v128_le(7L, 9L)
  let parent = store.alloc_exn(instance.tag_addrs[1], [
    ExnRef(child),
    V128(vector),
    I64(99L),
  ])
  let context = build_gc_root_context(
    module_,
    instance,
    store,
    enable_cancellation=true,
  )
  defer context.close()
  assert_true(context.jit_module.set_cooperative_scheduling(true))
  let mut outcome = context.call_core_func_resumable_with_exception(
    store,
    instance,
    0,
    [ExnRef(parent), I32(10000)],
  )
  guard outcome is Suspended(CooperativeYield, _) else {
    fail("worker never suspended")
  }
  while outcome is Suspended(_, continuation) {
    errdefer continuation.cancel()
    store.collect_garbage() |> ignore
    outcome = continuation.continue_execution_with_exception()
  }
  guard outcome is Thrown(exception) else { fail("resumed exception returned") }
  defer exception.close()
  store.collect_garbage() |> ignore
  assert_eq(store.borrow_rooted_value(exception), ExnRef(parent))
  assert_eq(store.get_exn(parent).values, [
    ExnRef(child),
    V128(vector),
    I64(99L),
  ])
  assert_eq(store.get_exn(child).values, [StructRef(reference)])
  assert_true(store.is_gc_valid(reference))
  assert_eq(budget.used(PendingWork), 1L)
  let foreign = @runtime.Store::with_c_heap()
  defer foreign.close()
  try foreign.borrow_rooted_value(exception) catch {
    ForeignStore => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("foreign Store accepted exception")
  }
  exception.close()
  assert_eq(budget.used(PendingWork), 0L)
  try store.borrow_rooted_value(exception) catch {
    InvalidHandle => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("closed exception remained accessible")
  }
  store.collect_garbage() |> ignore
  assert_false(store.is_gc_valid(reference))
}

///|
async test "uncaught async host exception survives await and returns owned payload" {
  let budget = @runtime.ResourceBudget::new(pending_work=4L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [I32], results: [], })
  let host = store.alloc_async_host_func(async fn(_) {
    @async.sleep(1)
    let exception = store.guest_exception(tag, [@runtime.RootedValue::i32(42)])
    defer exception.close()
    exception.throw_into_guest()
  })
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "fail", host)
  imports.add_tag("h", "tag", tag)
  let module_ = @wat.parse(
    "(module (import \"h\" \"fail\" (func $f)) (import \"h\" \"tag\" (tag (param i32))) (func (export \"run\") call $f))",
  )
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  context.install_hostcall_dispatcher(store, instance, after_dispatch=fn() {
    store.collect_garbage() |> ignore
  })
  guard context.call_core_func_async_with_exception(store, instance, 1, [])
    is Thrown(exception) else {
    fail("async exception returned")
  }
  defer exception.close()
  store.collect_garbage() |> ignore
  guard store.borrow_rooted_value(exception) is ExnRef(index) else {
    fail("missing async identity")
  }
  assert_eq(store.get_exn(index).values, [I32(42)])
  assert_eq(budget.used(PendingWork), 1L)
  store.close()
  assert_eq(budget.used(PendingWork), 0L)
  try store.borrow_rooted_value(exception) catch {
    StoreClosed => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("closed Store accepted exception")
  }
}

///|
test "nested native entry delivers its own exception without replacing the outer escape" {
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let inner_module = @wat.parse(
    "(module (tag (param i32)) (func (export \"run\") i32.const 7 throw 0))",
  )
  let inner_instance = @executor.instantiate_module_with_imports(
    store,
    inner_module,
    Imports(store),
  )
  let inner = build_gc_root_context(inner_module, inner_instance, store)
  defer inner.close()
  let retained : Ref[@runtime.RootedValue?] = Ref(None)
  defer (if retained.val is Some(value) { value.close() })
  let outer_tag = store.alloc_tag({ params: [I32], results: [], })
  let host = store.alloc_throwing_host_func(fn(_) raise {
    let result = inner.call_core_func_with_exception(store, inner_instance, 0, []) catch {
      error => raise @runtime.RuntimeError::AsyncHostError(error.to_string())
    }
    guard result is Thrown(value) else {
      raise @runtime.RuntimeError::TypeMismatch
    }
    retained.val = Some(value)
    store.collect_garbage() |> ignore
    let exception = store.guest_exception(outer_tag, [
      @runtime.RootedValue::i32(42),
    ])
    defer exception.close()
    exception.throw_into_guest()
  })
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "call", host)
  imports.add_tag("h", "tag", outer_tag)
  let outer_module = @wat.parse(
    "(module (import \"h\" \"call\" (func $f)) (import \"h\" \"tag\" (tag (param i32))) (func (export \"run\") call $f))",
  )
  let outer_instance = @executor.instantiate_module_with_imports(
    store, outer_module, imports,
  )
  let outer = build_gc_root_context(outer_module, outer_instance, store)
  defer outer.close()
  outer.install_hostcall_dispatcher(store, outer_instance)
  guard outer.call_core_func_with_exception(store, outer_instance, 1, [])
    is Thrown(value) else {
    fail("outer exception lost")
  }
  defer value.close()
  store.collect_garbage() |> ignore
  guard store.borrow_rooted_value(value) is ExnRef(outer_index) else {
    fail("outer identity lost")
  }
  guard store.borrow_rooted_value(retained.val.unwrap()) is ExnRef(inner_index) else {
    fail("inner identity lost")
  }
  assert_eq(store.get_exn(outer_index).tag_addr, outer_tag)
  assert_eq(store.get_exn(outer_index).values, [I32(42)])
  assert_eq(store.get_exn(inner_index).tag_addr, inner_instance.tag_addrs[0])
  assert_eq(store.get_exn(inner_index).values, [I32(7)])
}

///|
test "uncaught delivery root admission failure preserves quota and leaves entry reusable" {
  let budget = @runtime.ResourceBudget::new(pending_work=1L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let module_ = @wat.parse(
    "(module (tag (param i32)) (func (export \"run\") i32.const 42 throw 0))",
  )
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  for _ in 0..<3 {
    try context.call_core_func_with_exception(store, instance, 0, []) catch {
      HostInvocation(ResourceLimitExceeded(PendingWork)) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("root quota failure returned a guest exception")
    }
    store.collect_garbage() |> ignore
    assert_eq(budget.used(PendingWork), 0L)
    assert_eq(store.native_execution_state().live_count(), 0)
  }
  store.close()
  context.close()
  assert_true(context.jit_module.gc_environment_is_clear())
}

///|
test "native exception delivery allocation failures stay traps and release transient roots" {
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  defer runtime_fail_native_allocation(0)
  let host = store.alloc_host_func(_ => [])
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "hook", host)
  let module_ = @wat.parse(
    "(module (import \"h\" \"hook\" (func $f)) (tag (param i32)) (func (export \"run\") (param exnref) call $f local.get 0 throw_ref))",
  )
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  let index = store.alloc_exn(instance.tag_addrs[0], [I32(42)])
  let root = store.root_raw_value(ExnRef(index))
  defer root.close()
  store.encode_native_exception(index) |> ignore
  for failure in [1, 2] {
    context.install_hostcall_dispatcher(store, instance, after_dispatch=fn() {
      runtime_fail_native_allocation(failure)
    })
    try
      context.call_core_func_with_exception(store, instance, 1, [ExnRef(index)])
    catch {
      Trap(message) => assert_true(message.has_prefix("out of memory"))
      error => fail(error.to_string())
    } noraise {
      _ => fail("allocation failure produced exception delivery")
    }
    runtime_fail_native_allocation(0)
    assert_eq(store.native_execution_state().live_count(), 0)
  }
  context.install_hostcall_dispatcher(store, instance)
  guard context.call_core_func_with_exception(store, instance, 1, [
      ExnRef(index),
    ])
    is Thrown(exception) else {
    fail("entry not reusable")
  }
  defer exception.close()
  store.collect_garbage() |> ignore
  assert_eq(store.borrow_rooted_value(exception), ExnRef(index))
  store.close()
  context.close()
  assert_true(context.jit_module.gc_environment_is_clear())
}

///|
async test "exception-aware async cancellation retires the parked delivery and invocation" {
  let budget = @runtime.ResourceBudget::new(pending_work=8L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [I32], results: [], })
  let started = @async.Semaphore(1, initial_value=0)
  let blocked = @async.Semaphore(1, initial_value=0)
  let host = store.alloc_async_host_func(async fn(_) {
    let exception = store.guest_exception(tag, [@runtime.RootedValue::i32(42)])
    defer exception.close()
    started.release()
    blocked.acquire()
    exception.throw_into_guest()
  })
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "fail", host)
  imports.add_tag("h", "tag", tag)
  let module_ = @wat.parse(
    "(module (import \"h\" \"fail\" (func $f)) (import \"h\" \"tag\" (tag (param i32))) (func (export \"run\") call $f) (func (export \"healthy\") (result i32) i32.const 42))",
  )
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  context.install_hostcall_dispatcher(store, instance)
  @async.with_task_group(group => {
    let call = group.spawn(no_wait=true, allow_failure=true, () => {
      context.call_core_func_async_with_exception(store, instance, 1, [])
    })
    started.acquire()
    call.cancel()
    try call.wait() catch {
      @async.WaitedTaskAlreadyCancelled => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("cancelled call returned an exception")
    }
  })
  assert_eq(budget.used(PendingWork), 0L)
  assert_eq(store.native_execution_state().live_count(), 0)
  guard context.call_core_func_with_exception(store, instance, 2, [])
    is Returned([I32(42)]) else {
    fail("cancel left entry unusable")
  }
}

///|
test "exception-aware entry preserves matching and mismatching handler semantics" {
  for native_heap in [false, true] {
    let store = if native_heap {
      @runtime.Store::with_c_heap()
    } else {
      Store()
    }
    defer store.close()
    let tag = store.alloc_tag({ params: [I32], results: [], })
    let other = store.alloc_tag({ params: [I32], results: [], })
    let host = store.alloc_throwing_host_func(fn(_) raise {
      let exception = store.guest_exception(tag, [@runtime.RootedValue::i32(42)])
      defer exception.close()
      exception.throw_into_guest()
    })
    let imports = @runtime.Imports::Imports(store)
    imports.add_func("h", "fail", host)
    imports.add_tag("h", "tag", tag)
    imports.add_tag("h", "other", other)
    let module_ = native_host_exception_module()
    let instance = @executor.instantiate_module_with_imports(
      store, module_, imports,
    )
    let context = build_gc_root_context(module_, instance, store)
    defer context.close()
    context.install_hostcall_dispatcher(store, instance)
    guard context.call_core_func_with_exception(store, instance, 1, [])
      is Returned([I32(1)]) else {
      fail("catch_all failed")
    }
    guard context.call_core_func_with_exception(store, instance, 2, [])
      is Returned([I32(42)]) else {
      fail("matching catch failed")
    }
    for index in [3, 4] {
      guard context.call_core_func_resumable_with_exception(
          store,
          instance,
          index,
          [],
        )
        is Thrown(exception) else {
        fail("mismatching catch lost exception")
      }
      defer exception.close()
      store.collect_garbage() |> ignore
      guard store.borrow_rooted_value(exception) is ExnRef(index) else {
        fail("uncaught identity lost")
      }
      assert_eq(store.get_exn(index).tag_addr, tag)
      assert_eq(store.get_exn(index).values, [I32(42)])
    }
  }
}

///|
test "fresh guest exception roots allocated struct SIMD and callable payloads" {
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let module_ = @wat.parse(
    (
      #|(module (type $s (struct (field i32))) (tag (param (ref $s) funcref v128))
      #| (func $target (result i32) i32.const 99) (elem declare func $target)
      #| (func (export "run") i32.const 42 struct.new $s ref.func $target
      #|  v128.const i32x4 1 2 3 4 throw 0))
    ),
  )
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  guard context.call_core_func_with_exception(store, instance, 1, [])
    is Thrown(exception) else {
    fail("guest exception lost")
  }
  defer exception.close()
  store.collect_garbage() |> ignore
  guard store.borrow_rooted_value(exception) is ExnRef(index) else {
    fail("missing identity")
  }
  let value = store.get_exn(index)
  guard value.values is [StructRef(reference), FuncRef(function_), V128(vector)] else {
    fail("mixed payload corrupted")
  }
  assert_true(store.is_gc_valid(reference))
  assert_eq(function_, instance.func_addrs[0])
  assert_eq(
    vector, b"\x01\x00\x00\x00\x02\x00\x00\x00\x03\x00\x00\x00\x04\x00\x00\x00",
  )
  assert_eq(context.call_core_func(store, instance, 0, []), [I32(99)])
  exception.close()
  store.collect_garbage() |> ignore
  assert_false(store.is_gc_valid(reference))
}
