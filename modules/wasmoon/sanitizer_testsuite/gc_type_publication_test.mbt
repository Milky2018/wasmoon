///|
fn publication_gc_types(
  kind : Int32,
  wide : Bool,
) -> Array[@types.SubType] raise {
  let scalar = if wide { "i64" } else { "i32" }
  let shape = if kind == 0 {
    "struct (field \{scalar})"
  } else {
    "array \{scalar}"
  }
  @wat.parse("(module (type (\{shape})))").types
}

///|
fn allocate_published_gc_value(
  store : @runtime.Store,
  kind : Int32,
  value : @types.Value,
  instance? : @runtime.ModuleInstance,
) -> Int32 raise {
  match kind {
    0 => store.alloc_struct(0, [value], instance?)
    1 => store.alloc_array(0, [value, value], instance?)
    _ => store.alloc_array_repeated(0, 2, value, instance?)
  }
}

///|
test "GC allocation preserves its identity across reentrant type replacement" {
  for native in [true, false] {
    for kind in 0..<3 {
      let store = if native { @runtime.Store::with_c_heap() } else { Store() }
      defer store.close()
      store.set_module_types(publication_gc_types(kind, false))
      let replacement = publication_gc_types(kind, true)
      let armed = Ref(false)
      store.bind_native_callable_view(fn(_, _) {
        if armed.val {
          armed.val = false
          store.set_module_types(replacement) catch {
            error => abort(error.to_string())
          }
        }
      })
      armed.val = true
      let reference = allocate_published_gc_value(store, kind, I32(-42))
      assert_false(armed.val)
      let next = allocate_published_gc_value(store, kind, I64(-64L))
      if kind == 0 {
        assert_eq(store.struct_get(reference, 0), I32(-42))
        assert_eq(store.struct_get(next, 0), I64(-64L))
      } else {
        assert_eq(store.array_get(reference, 1), I32(-42))
        assert_eq(store.array_get(next, 1), I64(-64L))
      }
    }
  }
}

///|
test "GC allocation rejects Store closure during type publication" {
  for native in [true, false] {
    for kind in 0..<3 {
      let budget = @runtime.ResourceBudget::new(gc_bytes=1024L, gc_objects=8L)
      let store = if native {
        @runtime.Store::with_c_heap(resource_budget=Some(budget))
      } else {
        Store(resource_budget=Some(budget))
      }
      defer store.close()
      store.set_module_types(publication_gc_types(kind, false))
      let armed = Ref(false)
      store.bind_native_callable_view(fn(_, _) {
        if armed.val {
          store.close()
        }
      })
      armed.val = true
      try allocate_published_gc_value(store, kind, I32(-42)) catch {
        @runtime.RuntimeError::StoreClosed => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("allocation continued after Store close")
      }
      assert_true(store.is_closed())
      assert_eq(budget.used(GcBytes), 0L)
      assert_eq(budget.used(GcObjects), 0L)
    }
  }
}

///|
test "GC allocation rejects an instance rolled back during type publication" {
  for native in [true, false] {
    for kind in 0..<3 {
      let store = if native { @runtime.Store::with_c_heap() } else { Store() }
      defer store.close()
      let linker = @runtime.Linker::with_store(store)
      defer linker.close()
      let transaction = @runtime.InstantiationTransaction::new()
      linker.register_rollback(transaction.registrar())
      defer transaction.rollback()
      let instance = store.new_instance(
        @validator.ValidatedModule::new({
          ..@types.Module::empty(),
          types: publication_gc_types(kind, false),
        }),
        func_addrs=[],
        table_addrs=[],
        mem_addrs=[],
        global_addrs=[],
        tag_addrs=[],
        elem_values=[],
      )
      let armed = Ref(false)
      store.bind_native_callable_view(fn(_, _) {
        if armed.val {
          transaction.rollback()
        }
      })
      armed.val = true
      try allocate_published_gc_value(store, kind, I32(-42), instance~) catch {
        @runtime.RuntimeError::InvalidHandle => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("allocation used a rolled-back instance")
      }
    }
  }
}
