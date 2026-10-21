///|
fn native_host_exception_module() -> @types.Module raise {
  @wat.parse(
    (
      #|(module (import "h" "fail" (func $fail))
      #| (import "h" "tag" (tag $e (param i32)))
      #| (import "h" "other" (tag $other (param i32)))
      #| (func (export "all") (result i32)
      #|  (block $caught (try_table (catch_all $caught) call $fail) unreachable) i32.const 1)
      #| (func (export "match") (result i32)
      #|  (block $caught (result i32) (try_table (catch $e $caught) call $fail) unreachable))
      #| (func (export "mismatch") (result i32)
      #|  (block $caught (result i32) (try_table (catch $other $caught) call $fail) unreachable))
      #| (func (export "uncaught") call $fail)
      #| (func (export "trap") (block $caught (try_table (catch_all $caught) unreachable)))
      #| (func (export "healthy") (result i32) i32.const 42))
    ),
  )
}

///|
async test "native async exception reference payload survives await and completion handoff" {
  let budget = @runtime.ResourceBudget::new(pending_work=8L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let selected : Ref[@runtime.GuestException?] = Ref(None)
  let host = store.alloc_async_host_func(async fn(_) {
    let exception = selected.val.unwrap()
    defer exception.close()
    @async.sleep(1)
    store.collect_garbage() |> ignore
    exception.throw_into_guest()
  })
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "fail", host)
  let module_ = @wat.parse(
    (
      #|(module (type $s (struct (field i32))) (import "h" "fail" (func $fail))
      #| (tag $e (param (ref $s))) (func (export "run") (result i32)
      #|  (block $caught (result (ref $s)) (try_table (catch $e $caught) call $fail) unreachable)
      #|  struct.get $s 0))
    ),
  )
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  context.install_hostcall_dispatcher(store, instance, after_dispatch=fn() {
    store.collect_garbage() |> ignore
  })
  let reference = store.alloc_struct(0, [I32(42)], instance~)
  let rooted = store.root_raw_value(StructRef(reference))
  selected.val = Some(store.guest_exception(instance.tag_addrs[0], [rooted]))
  rooted.close()
  assert_eq(context.call_core_func_async(store, instance, 1, []), [I32(42)])
  selected.val = None
  store.collect_garbage() |> ignore
  assert_false(store.is_gc_valid(reference))
  assert_eq(budget.used(PendingWork), 0L)
}

///|
test "actual JIT catches explicit host exceptions without converting ordinary failures" {
  let budget = @runtime.ResourceBudget::new(pending_work=8L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
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
  let module_ = native_host_exception_module()
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  context.install_hostcall_dispatcher(store, instance)
  for _ in 0..<3 {
    assert_eq(context.call_core_func(store, instance, 1, []), [I32(1)])
    assert_eq(context.call_core_func(store, instance, 2, []), [I32(42)])
    for index in [3, 4] {
      try context.call_core_func(store, instance, index, []) catch {
        Trap(message) => assert_eq(message, "uncaught exception")
        error => fail(error.to_string())
      } noraise {
        _ => fail("uncaught exception returned")
      }
    }
    assert_eq(budget.used(PendingWork), 0L)
  }
  ordinary.val = true
  try context.call_core_func(store, instance, 1, []) catch {
    HostInvocation(OutOfBoundsArrayAccess) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("ordinary host failure became catchable")
  }
  try context.call_core_func(store, instance, 5, []) catch {
    Trap(message) => assert_true(message.has_prefix("unreachable"))
    error => fail(error.to_string())
  } noraise {
    _ => fail("true trap became catchable")
  }
  assert_eq(context.call_core_func(store, instance, 6, []), [I32(42)])
  assert_eq(budget.used(PendingWork), 0L)
}

///|
test "native host exception handoff roots mixed payloads through dispatch hooks and failure" {
  let budget = @runtime.ResourceBudget::new(pending_work=8L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let selected : Ref[@runtime.GuestException?] = Ref(None)
  let host = store.alloc_throwing_host_func(fn(_) raise {
    selected.val.unwrap().throw_into_guest()
  })
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "fail", host)
  let module_ = @wat.parse(
    (
      #|(module (type $s (struct (field i32))) (import "h" "fail" (func $fail))
      #| (tag $e (param v128 i64 (ref $s)))
      #| (func (export "run") (result i32) (local $v v128) (local $n i64) (local $s (ref null $s))
      #|  (block $caught (result v128 i64 (ref $s))
      #|    (try_table (catch $e $caught) call $fail) unreachable)
      #|  local.set $s local.set $n local.set $v
      #|  local.get $s ref.as_non_null struct.get $s 0
      #|  local.get $n i32.wrap_i64 i32.add
      #|  local.get $v i32x4.extract_lane 0 i32.add))
    ),
  )
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  defer runtime_fail_native_allocation(0)
  for mode in [0, 1, 2] {
    let reference = store.alloc_struct(0, [I32(42)], instance~)
    let rooted = store.root_raw_value(StructRef(reference))
    let vector = @runtime.RootedValue::v128(
      b"\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    )
    selected.val = Some(
      store.guest_exception(instance.tag_addrs[0], [
        vector,
        @runtime.RootedValue::i64(99L),
        rooted,
      ]),
    )
    rooted.close()
    context.install_hostcall_dispatcher(store, instance, after_dispatch=fn() raise @runtime.RuntimeError {
      store.collect_garbage() |> ignore
      if mode == 0 {
        raise Unreachable
      }
      if mode == 1 {
        runtime_fail_native_allocation(1)
      }
    })
    if mode < 2 {
      try context.call_core_func(store, instance, 1, []) catch {
        Trap(message) =>
          assert_true(
            message.has_prefix(
              if mode == 0 {
                "unreachable"
              } else {
                "out of memory"
              },
            ),
          )
        error => fail(error.to_string())
      } noraise {
        _ => fail("dispatch hook failure returned")
      }
    } else {
      assert_eq(context.call_core_func(store, instance, 1, []), [I32(148)])
    }
    runtime_fail_native_allocation(0)
    selected.val = None
    store.collect_garbage() |> ignore
    assert_false(store.is_gc_valid(reference))
    assert_eq(budget.used(PendingWork), 0L)
  }
}

///|
async test "actual JIT async host exceptions and cancellation retire completion owners" {
  let budget = @runtime.ResourceBudget::new(pending_work=8L)
  let store = @runtime.Store::with_c_heap(resource_budget=Some(budget))
  defer store.close()
  let tag = store.alloc_tag({ params: [I32], results: [], })
  let other = store.alloc_tag({ params: [I32], results: [], })
  let cancel_mode = Ref(false)
  let started = @async.Semaphore(1, initial_value=0)
  let blocked = @async.Semaphore(1, initial_value=0)
  let host = store.alloc_async_host_func(async fn(_) {
    let exception = store.guest_exception(tag, [@runtime.RootedValue::i32(42)])
    defer exception.close()
    if cancel_mode.val {
      started.release()
      blocked.acquire()
    } else {
      @async.sleep(1)
    }
    store.collect_garbage() |> ignore
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
  assert_eq(context.call_core_func_async(store, instance, 1, []), [I32(1)])
  assert_eq(context.call_core_func_async(store, instance, 2, []), [I32(42)])
  assert_eq(budget.used(PendingWork), 0L)
  cancel_mode.val = true
  @async.with_task_group(group => {
    let call = group.spawn(no_wait=true, allow_failure=true, () => {
      context.call_core_func_async(store, instance, 2, [])
    })
    started.acquire()
    call.cancel()
    try call.wait() catch {
      _ => ()
    } noraise {
      _ => fail("cancelled JIT call returned")
    }
  })
  assert_eq(budget.used(PendingWork), 0L)
  assert_eq(context.call_core_func(store, instance, 6, []), [I32(42)])
}
