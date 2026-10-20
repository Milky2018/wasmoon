// End-to-end coverage for type-graph registration cost and identity
// semantics on type-heavy modules (ISS-644 regression class).

///|
/// Build a module with `count` distinct singleton function types (each
/// referencing an earlier type), one struct type, and optional allocating
/// globals. With no globals the module contains only its type section.
fn many_types_module(count : Int32, globals~ : Int32 = 1) -> @types.Module {
  let types : Array[@types.SubType] = []
  let type_rec_groups : Array[Int32] = []
  for i in 0..<count {
    let params : Array[@types.ValueType] = if i < 13 {
      let scalars : Array[@types.ValueType] = []
      for _ in 0..<i {
        scalars.push(I32)
      }
      scalars
    } else {
      [RefNullFuncTyped(i - 13)]
    }
    types.push(
      @types.SubType::from_func({
        params: ReadOnlyArray::from_array(params),
        results: [],
      }),
    )
    type_rec_groups.push(i)
  }
  let struct_idx = count
  types.push(
    @types.SubType::simple(
      Struct({ fields: [{ storage_type: Val(I32), mutable: true, }], }),
    ),
  )
  type_rec_groups.push(struct_idx)
  {
    ..@types.Module::empty(),
    types,
    type_rec_groups,
    globals: Array::make(globals, {
      type_: { value_type: RefNullStruct(struct_idx), mutable: false, },
      init: [StructNewDefault(struct_idx)],
    }),
  }
}

///|
test "distinct type groups scale independently of allocating globals" {
  for count in [1000, 2000, 5000] {
    for globals in [0, 1] {
      let module_ = many_types_module(count, globals~)
      let canonical = @types.compute_canonical_type_indices(
        module_.types,
        type_rec_groups=module_.type_rec_groups,
      )
      for i in 0..<=count {
        assert_eq(canonical[i], i)
      }
      let (store, instance) = @executor.instantiate_module(module_)
      assert_eq(instance.global_addrs.length(), globals)
      if globals == 1 {
        assert_true(
          store.get_global(instance.global_addrs[0]).get() is StructRef(_),
        )
      }
      store.close()
    }
  }
}

///|
test "identical modules share GC type identities across instances" {
  let count = 40
  let store = @runtime.Store::Store()
  defer store.close()
  let module_ = many_types_module(count)
  let imports = @runtime.Imports::Imports(store)
  let first = @executor.instantiate_module_with_imports(store, module_, imports)
  let second = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let value = store.get_global(first.global_addrs[0]).get()
  guard value is StructRef(reference) else {
    fail("expected struct reference from global initializer")
  }
  // The struct allocated through the first instance's constant-expression
  // graph must satisfy the struct type of the second instance: identities
  // are content-based, not per registration. many_types_module appends the
  // struct type right after the `count` function types.
  let struct_type_idx = count
  assert_true(store.gc_type_is_subtype(reference, second, struct_type_idx))
}
