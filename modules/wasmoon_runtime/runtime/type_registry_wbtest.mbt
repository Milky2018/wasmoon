///|
fn registry_struct_type() -> @types.SubType {
  @types.SubType::simple(
    Struct({ fields: [{ storage_type: Val(I32), mutable: false, }], }),
  )
}

///|
test "GC allocations reuse the current module's registered identity mapping" {
  let store = Store()
  defer store.close()
  store.set_module_types([registry_struct_type()], rec_groups=[0])
  store.alloc_struct(0, [I32(1)]) |> ignore
  let mapping = store.module_type_indices()
  for value in 2..<10 {
    store.alloc_struct(0, [I32(value)]) |> ignore
    assert_true(physical_equal(mapping, store.module_type_indices()))
  }
}

///|
test "type graph replacement snapshots both types and recursive groups" {
  let store = Store()
  defer store.close()
  let types = [registry_struct_type(), registry_struct_type()]
  let groups = [0, 0]
  store.set_module_types(types, rec_groups=groups)
  let grouped = store.module_type_indices()
  groups[1] = 1
  types[0] = @types.SubType::simple(
    Array({ element: { storage_type: Val(I64), mutable: true, }, }),
  )
  assert_true(physical_equal(grouped, store.module_type_indices()))
  store.set_module_types([registry_struct_type(), registry_struct_type()], rec_groups=[
    0, 1,
  ])
  let split = store.module_type_indices()
  assert_false(physical_equal(grouped, split))
  assert_false(grouped[0] == split[0])
  assert_eq(split[0], split[1])
}

///|
test "nested type graph scopes roll back to the original registered mapping" {
  let store = Store()
  defer store.close()
  store.set_module_types([registry_struct_type()], rec_groups=[0])
  let original = store.module_type_indices()
  try
    store.with_instantiation(fn() -> Unit raise RuntimeError {
      store.set_module_types([
        @types.SubType::simple(
          Array({ element: { storage_type: Val(I64), mutable: true, }, }),
        ),
      ])
      store.alloc_array(0, [I64(3)]) |> ignore
      store.with_instantiation(fn() -> Unit raise RuntimeError {
        store.set_module_types([@types.SubType::func([], [])])
        store.module_type_indices() |> ignore
      })
      raise Unreachable
    })
  catch {
    Unreachable => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("transaction did not fail")
  }
  assert_true(physical_equal(original, store.module_type_indices()))
  store.alloc_struct(0, [I32(9)]) |> ignore
  assert_true(physical_equal(original, store.module_type_indices()))
}

///|
test "Store close drops initialization graph ownership" {
  let store = Store()
  store.set_module_types([registry_struct_type()])
  store.alloc_struct(0, [I32(1)]) |> ignore
  assert_true(store.native_types.initialization_graph is Some(_))
  assert_false(store.native_types.group_buckets.is_empty())
  store.close()
  assert_true(store.native_types.initialization_graph is None)
  assert_true(store.native_types.group_buckets.is_empty())
  assert_true(store.native_types.representatives.is_empty())
  assert_true(store.native_types.mappings.is_empty())
}

///|
test "rollback after Store close cannot restore a cached initialization graph" {
  let store = Store()
  store.set_module_types([registry_struct_type()])
  store.module_type_indices() |> ignore
  try
    store.with_instantiation(fn() -> Unit raise RuntimeError {
      store.set_module_types([@types.SubType::func([], [])])
      store.module_type_indices() |> ignore
      store.close()
      raise Unreachable
    })
  catch {
    Unreachable => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("transaction did not fail")
  }
  assert_true(store.native_types.initialization_graph is None)
  assert_true(store.native_types.group_buckets.is_empty())
  assert_true(store.current_types().is_empty())
}

///|
test "Store registration rejects colliding group candidates before reusing identities" {
  let store = Store()
  defer store.close()
  store.set_module_types([registry_struct_type()])
  let first = store.module_type_indices()[0]
  let buckets = store.native_types.group_buckets.values().to_array()
  let other = [
    @types.SubType::simple(
      Array({ element: { storage_type: Val(I64), mutable: true, }, }),
    ),
  ]
  @types.fold_type_groups(other, external_identity=fn(_) { -1 }, visit=fn(
    _,
    fingerprint,
  ) {
    store.native_types.group_buckets[fingerprint] = buckets[0].copy()
  })
  store.set_module_types(other)
  let second = store.module_type_indices()[0]
  assert_false(first == second)
  store.set_module_types(other)
  assert_eq(store.module_type_indices()[0], second)
  assert_eq(store.native_types.representatives.length(), 2)
}

///|
test "callable publication cannot restore graph caches after reentrant Store close" {
  for registered in [false, true] {
    let store = Store()
    defer store.close()
    let instance = store.new_instance(
      @validator.ValidatedModule::new({
        ..@types.Module::empty(),
        types: [registry_struct_type()],
        type_rec_groups: [0],
      }),
      func_addrs=[],
      table_addrs=[],
      mem_addrs=[],
      global_addrs=[],
      tag_addrs=[],
      elem_values=[],
    )
    store.set_module_types([registry_struct_type()])
    let armed = Ref(false)
    store.bind_native_callable_view(fn(_, _) { if armed.val { store.close() } })
    armed.val = true
    if registered {
      store.native_type_indices(instance) |> ignore
    } else {
      store.module_type_indices() |> ignore
    }
    assert_true(store.is_closed())
    assert_true(store.native_types.mappings.is_empty())
    assert_true(store.native_types.initialization_graph is None)
  }
}

///|
test "callable publication preserves a reentrant change of initialization graph" {
  let store = Store()
  defer store.close()
  store.set_module_types([registry_struct_type()])
  let armed = Ref(false)
  store.bind_native_callable_view(fn(_, _) {
    if armed.val {
      armed.val = false
      store.set_module_types([
        @types.SubType::simple(
          Array({ element: { storage_type: Val(I64), mutable: true, }, }),
        ),
      ]) catch {
        _ => abort("test graph replacement failed")
      }
    }
  })
  armed.val = true
  let original = store.module_type_indices()
  let current = store.module_type_indices()
  assert_false(original[0] == current[0])
}
