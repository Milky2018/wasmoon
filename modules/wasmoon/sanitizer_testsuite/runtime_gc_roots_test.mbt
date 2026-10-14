///|
fn lifecycle_store(native : Bool) -> @runtime.Store raise {
  let store = if native { @runtime.Store::with_c_heap() } else { Store() }
  store.set_module_types([
    {
      final_: true,
      supertypes: [],
      composite: Struct({
        fields: [{ storage_type: Val(I32), mutable: true, }],
      }),
    },
    {
      final_: true,
      supertypes: [],
      composite: Struct({
        fields: [{ storage_type: Val(ExternRef), mutable: true, }],
      }),
    },
    {
      final_: true,
      supertypes: [],
      composite: Struct({
        fields: [{ storage_type: Val(ExnRef), mutable: true, }],
      }),
    },
  ])
  store
}

///|
test "GC reclaims discarded extern wrappers in an open Store" {
  for native in [false, true] {
    let store = lifecycle_store(native)
    defer store.close()
    for _ in 0..<100 {
      let index = store.alloc_struct(0, [I32(0)])
      store.wrap_as_extern(StructRef(index)) |> ignore
    }
    inspect(store.collect_garbage(), content="100")
    inspect(store.wrapped_externs.length(), content="0")
    assert_true(store.wrapped_externs.capacity() <= 16)
  }
}

///|
test "GC roots follow live extern and exception edges through heap objects" {
  for native in [false, true] {
    let store = lifecycle_store(native)
    defer store.close()
    let tag = store.alloc_tag({ params: [ExternRef], results: [], })
    let child = store.alloc_struct(0, [I32(37)])
    let wrapped = store.wrap_as_extern(StructRef(child))
    let exception = store.alloc_exn(tag, [wrapped])
    let parent = store.alloc_struct(2, [ExnRef(exception)])
    let lease = store.pin_gc_roots([StructRef(parent)])
    inspect(store.collect_garbage(), content="0")
    guard store.struct_get(parent, 0) is ExnRef(reference) else {
      fail("exception edge lost")
    }
    let payload = store.get_exn(reference).values[0]
    inspect(store.unwrap_extern(payload), content="StructRef(0)")
    inspect(store.struct_get(child, 0), content="I32(37)")
    lease.release()
    lease.release()
    inspect(store.collect_garbage(), content="2")
    inspect(store.exns.length(), content="0")
    inspect(store.wrapped_externs.length(), content="0")
  }
}

///|
test "GC reclaims discarded exception snapshots without closing the Store" {
  for native in [false, true] {
    let store = lifecycle_store(native)
    defer store.close()
    let tag = store.alloc_tag({ params: [AnyRef], results: [], })
    let mut reference = 0L
    for _ in 0..<100 {
      let child = store.alloc_struct(0, [I32(0)])
      let exception = store.alloc_exn(tag, [StructRef(child)])
      if native {
        reference = store.encode_native_exception(exception)
      }
    }
    inspect(store.collect_garbage(), content="100")
    inspect(store.exns.length(), content="0")
    if native {
      inspect(
        store.native_execution_state().exceptions().snapshot(reference) is None,
        content="true",
      )
    }
  }
}

///|
test "GC does not mistake scalar heap fields for references" {
  for native in [false, true] {
    let store = lifecycle_store(native)
    defer store.close()
    let child = store.alloc_struct(0, [I32(0)])
    let parent = store.alloc_struct(0, [I32(2)])
    inspect(
      store.collect_garbage(additional_roots=[StructRef(parent)]),
      content="1",
    )
    inspect(store.is_gc_valid(child), content="false")
    inspect(store.struct_get(parent, 0), content="I32(2)")
  }
}

///|
test "GC traces guest continuation roots and cancels discarded owners" {
  for native in [false, true] {
    let store = lifecycle_store(native)
    defer store.close()
    let child = store.alloc_struct(0, [I32(42)])
    let releases = Ref(0)
    let lease = store.pin_gc_roots([StructRef(child)])
    let handle = store.put_guest_continuation(
      @runtime.GuestContinuationBody::new(
        fn(_) raise { [store.struct_get(child, 0)] },
        fn() {
          lease.release()
          releases.val += 1
        },
        leases=[lease],
      ),
    )
    inspect(
      store.collect_garbage(additional_roots=[ContRef(handle)]),
      content="0",
    )
    inspect(releases.val, content="0")
    inspect(store.collect_garbage(), content="1")
    inspect(releases.val, content="1")
    inspect(store.collect_garbage(), content="0")
    inspect(releases.val, content="1")
    try store.take_guest_continuation(handle) catch {
      error =>
        inspect(error.to_string(), content="continuation already consumed")
    } noraise {
      _ => fail("collected continuation remained usable")
    }
  }
}

///|
test "GC root leases snapshot host values and release idempotently" {
  for native in [false, true] {
    let store = lifecycle_store(native)
    defer store.close()
    let child = store.alloc_struct(0, [I32(42)])
    let wrapper = store.wrap_as_extern(StructRef(child))
    let roots = [wrapper]
    let lease = store.pin_gc_roots(roots)
    roots.clear()
    inspect(store.collect_garbage(), content="0")
    inspect(store.unwrap_extern(wrapper), content="StructRef(0)")
    lease.release()
    lease.release()
    inspect(store.collect_garbage(), content="1")
    try store.unwrap_extern(wrapper) catch {
      error =>
        inspect(
          error.to_string(),
          content="undefined element: out of bounds table access",
        )
    } noraise {
      _ => fail("collected wrapper remained usable")
    }
    let next = store.wrap_as_extern(I31(7))
    assert_true(next != wrapper)
    inspect(store.unwrap_extern(next), content="I31(7)")
  }
}

///|
test "GC walks deep and cyclic externalized heap edges without recursion" {
  for native in [false, true] {
    let store = lifecycle_store(native)
    defer store.close()
    let mut value : @types.Value = Null
    for _ in 0..<5000 {
      let reference = store.alloc_struct(1, [value])
      value = store.wrap_as_extern(StructRef(reference))
    }
    inspect(store.collect_garbage(additional_roots=[value]), content="0")
    let first = store.alloc_struct(1, [Null])
    let cycle = store.wrap_as_extern(StructRef(first))
    store.struct_set(first, 0, cycle)
    inspect(store.collect_garbage(additional_roots=[cycle]), content="5000")
    inspect(store.is_gc_valid(first), content="true")
    inspect(store.collect_garbage(), content="1")
    inspect(store.wrapped_externs.length(), content="0")
  }
}

///|
test "native exception translation and tracing do not recurse through deep payloads" {
  let store = lifecycle_store(true)
  defer store.close()
  let scalar = store.alloc_tag({ params: [AnyRef], results: [], })
  let nested = store.alloc_tag({ params: [ExnRef], results: [], })
  let child = store.alloc_struct(0, [I32(42)])
  let mut current = store.alloc_exn(scalar, [StructRef(child)])
  for _ in 0..<3000 {
    current = store.alloc_exn(nested, [ExnRef(current)])
  }
  let word = store.encode_native_exception(current)
  inspect(
    store.collect_garbage(additional_roots=[ExnRef(current)]),
    content="0",
  )
  // Build native-only snapshots in a separate Store to exercise mirror creation.
  let target = lifecycle_store(true)
  defer target.close()
  let tag = target.alloc_tag({ params: [ExnRef], results: [], })
  let terminal = target.alloc_tag({ params: [I32], results: [], })
  let arena = target.native_execution_state().exceptions()
  assert_true(arena.define_tag(tag, [ExnRef]))
  assert_true(arena.define_tag(terminal, [I32]))
  let mut token = arena.insert(target.get_c_heap_ptr(), terminal, [42L])
  for _ in 0..<3000 {
    token = arena.insert(target.get_c_heap_ptr(), tag, [token])
  }
  let result = target.decode_native_exception(token)
  inspect(target.collect_garbage(additional_roots=[result]), content="0")
  inspect(target.exns.length(), content="3001")
  inspect(target.collect_garbage(), content="0")
  inspect(target.exns.length(), content="0")
  inspect(store.collect_garbage(), content="1")
  inspect(
    store.native_execution_state().exceptions().snapshot(word) is None,
    content="true",
  )
}

///|
async test "completed and cancelled host tasks retire externalized exception result roots" {
  for native in [false, true] {
    for consume in [false, true] {
      let store = lifecycle_store(native)
      defer store.close()
      let child = store.alloc_struct(0, [I32(42)])
      let wrapped = store.wrap_as_extern(StructRef(child))
      let tag = store.alloc_tag({ params: [ExternRef], results: [], })
      let exception = store.alloc_exn(tag, [wrapped])
      let caller = @runtime.Caller(store, ModuleInstance())
      @runtime.with_async_host_call_driver(async fn(driver) {
        let host : @runtime.AsyncHostFunction = async fn(_, _) {
          @async.sleep(0)
          Ok([ExnRef(exception)])
        }
        guard driver.poll(0, host, caller, []) is AsyncHostPending else {
          fail("host did not park")
        }
        driver.wait_pending()
        inspect(store.collect_garbage(), content="0")
        if consume {
          guard driver.poll(0, host, caller, [])
            is AsyncHostReady([ExnRef(index)]) else {
            fail("host result lost")
          }
          inspect(
            store.unwrap_extern(store.get_exn(index).values[0]),
            content="StructRef(0)",
          )
        }
      })
      inspect(store.collect_garbage(), content="1")
      inspect(store.exns.length(), content="0")
      inspect(store.wrapped_externs.length(), content="0")
    }
  }
}

///|
test "failed instantiation retires temporary globals functions wrappers and exception snapshots" {
  let source =
    #|(module
    #|  (type $s (struct (field i32)))
    #|  (global externref (extern.convert_any (struct.new $s (i32.const 42))))
    #|  (tag $e (param (ref $s)))
    #|  (func $start
    #|    (block $caught (result exnref)
    #|      (try_table (catch_all_ref $caught) (throw $e (struct.new $s (i32.const 7))))
    #|      unreachable)
    #|    drop unreachable)
    #|  (start $start))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for native in [false, true] {
    let store = lifecycle_store(native)
    let linker = @runtime.Linker::with_store(store)
    defer linker.close()
    for _ in 0..<30 {
      let transaction = @runtime.InstantiationTransaction::new()
      linker.register_rollback(transaction.registrar())
      try @executor.instantiate_with_linker(linker, "guest", module_) catch {
        error => {
          assert_true(error is Unreachable)
          transaction.rollback()
        }
      } noraise {
        _ => fail("start function did not trap")
      }
      debug_inspect(
        (
          store.globals.length(),
          store.funcs.length(),
          store.instances.length(),
          store.tags.length(),
        ),
        content="(0, 0, 0, 0)",
      )
      inspect(store.collect_garbage(), content="0")
      inspect(store.exns.length(), content="0")
      inspect(store.wrapped_externs.length(), content="0")
      inspect(store.heap.stats().live_objects, content="0")
      if store.c_heap is Some(heap) {
        inspect(heap.get_size(), content="0")
      }
    }
  }
}

///|
test "taking a continuation transfers root protection until run or cancel" {
  for native in [false, true] {
    let store = lifecycle_store(native)
    defer store.close()
    let child = store.alloc_struct(0, [I32(42)])
    let handle = store.put_guest_continuation(
      @runtime.GuestContinuationBody::new(
        fn(_) raise { [store.struct_get(child, 0)] },
        fn() { () },
        roots=[StructRef(child)],
      ),
    )
    let body = store.take_guest_continuation(handle)
    inspect(store.collect_garbage(), content="0")
    debug_inspect((body.run)(Values([])), content="[I32(42)]")
    inspect(store.collect_garbage(), content="1")
  }
}

///|
test "GC keeps captured type layouts after another module replaces the active types" {
  for native in [false, true] {
    let store = lifecycle_store(native)
    defer store.close()
    let child = store.alloc_struct(0, [I32(42)])
    let wrapper = store.wrap_as_extern(StructRef(child))
    let parent = store.alloc_struct(1, [wrapper])
    store.set_module_types([
      {
        final_: true,
        supertypes: [],
        composite: Struct({
          fields: [{ storage_type: Val(I32), mutable: true, }],
        }),
      },
      {
        final_: true,
        supertypes: [],
        composite: Struct({
          fields: [{ storage_type: Val(I32), mutable: true, }],
        }),
      },
    ])
    inspect(
      store.collect_garbage(additional_roots=[StructRef(parent)]),
      content="0",
    )
    inspect(store.struct_get(child, 0), content="I32(42)")
    inspect(store.collect_garbage(), content="2")
  }
}

///|
test "continuation cancellation can allocate a successor during GC cleanup" {
  for native in [false, true] {
    let store = lifecycle_store(native)
    defer store.close()
    let successor : Ref[@types.Value] = Ref(Null)
    let nested_collection = Ref(0)
    store.put_guest_continuation(
      @runtime.GuestContinuationBody::new(fn(_) { [] }, fn() {
        nested_collection.val = store.collect_garbage()
        successor.val = store.wrap_as_extern(I31(7)) catch { _ => Null }
      }),
    )
    |> ignore
    inspect(store.collect_garbage(), content="0")
    inspect(nested_collection.val, content="-1")
    inspect(store.unwrap_extern(successor.val), content="I31(7)")
    inspect(store.collect_garbage(), content="0")
    inspect(store.wrapped_externs.length(), content="0")
  }
}

///|
test "failed native root tracing leaves live objects intact and allows another collection" {
  let store = lifecycle_store(true)
  defer store.close()
  guard store.c_heap is Some(heap) else { fail("missing native heap") }
  let child = store.alloc_struct(0, [I32(42)])
  // The low-level heap permits an unvalidated token. The Store visitor must
  // abort collection rather than sweep through an unknown exception edge.
  let parent = heap.alloc_struct(2, [ExnRef(99)])
  store.begin_gc_tracing()
  inspect(heap.collect([StructRef(parent)]), content="-1")
  store.end_gc_tracing()
  inspect(store.is_gc_valid(child), content="true")
  inspect(store.is_gc_valid(parent), content="true")
  heap.struct_set(parent, 0, Null)
  inspect(
    store.collect_garbage(additional_roots=[StructRef(parent)]),
    content="1",
  )
  inspect(store.collect_garbage(), content="1")
}

///|
test "GC cancellation can retire its Store without invalidating the native collector" {
  for native in [false, true] {
    let store = lifecycle_store(native)
    defer store.close()
    store.alloc_struct(0, [I32(42)]) |> ignore
    store.put_guest_continuation(
      @runtime.GuestContinuationBody::new(fn(_) { [] }, fn() { store.close() }),
    )
    |> ignore
    inspect(store.collect_garbage(), content="1")
    try store.alloc_struct(0, [I32(0)]) catch {
      error => assert_true(error is StoreClosed)
    } noraise {
      _ => fail("collector cancellation did not close its Store")
    }
  }
}
