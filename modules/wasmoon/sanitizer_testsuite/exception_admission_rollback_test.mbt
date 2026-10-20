///|
test "failed table instantiation releases only provisional native exception snapshots" {
  for existing in [false, true] {
    let budget = @runtime.ResourceBudget::new(
      gc_objects=if existing { 3L } else { 2L },
      table_elements=1L,
    )
    let store = @runtime.Store::Store(resource_budget=Some(budget))
    defer store.close()
    let tag = store.alloc_tag({ params: [], results: [], })
    let exception = store.alloc_exn(tag, [])
    let retained = if existing {
      Some(store.encode_native_exception(exception))
    } else {
      None
    }
    let before = budget.used(GcObjects)
    let before_bytes = budget.used(GcBytes)
    let global = store.alloc_global(
      GlobalInstance({ value_type: ExnRef, mutable: false, }, ExnRef(exception)),
    )
    let module_ = @wat.parse(
      "(module (import \"host\" \"e\" (global exnref)) (table 1 exnref (global.get 0)) (table 1 funcref))",
    )
    @validator.validate_module(module_)
    let imports = @runtime.Imports::Imports(store)
    imports.add_global("host", "e", global)
    let counts = store.counts()
    for _ in 0..<2 {
      try
        @executor.instantiate_module_with_imports(store, module_, imports)
      catch {
        ResourceLimitExceeded(TableElements) => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("expected table quota rejection")
      }
      assert_eq(
        store.counts().to_repr().to_string(),
        counts.to_repr().to_string(),
      )
      assert_eq(budget.used(TableElements), 0L)
      assert_eq(budget.used(GcObjects), before)
      assert_eq(budget.used(GcBytes), before_bytes)
      if retained is Some(token) {
        assert_eq(store.encode_native_exception(exception), token)
        assert_eq(store.decode_native_exception(token), ExnRef(exception))
      }
    }
    store.alloc_exn(tag, []) |> ignore
    assert_eq(budget.used(GcObjects), before + 1L)
  }
}

///|
test "failed table instantiation rolls back nested snapshots without releasing existing children" {
  for existing_child in [false, true] {
    let budget = @runtime.ResourceBudget::new(gc_objects=4L, table_elements=1L)
    let store = @runtime.Store::Store(resource_budget=Some(budget))
    defer store.close()
    let child_tag = store.alloc_tag({ params: [], results: [], })
    let child = store.alloc_exn(child_tag, [])
    let parent_tag = store.alloc_tag({ params: [ExnRef], results: [], })
    let parent = store.alloc_exn(parent_tag, [ExnRef(child)])
    let retained = if existing_child {
      Some(store.encode_native_exception(child))
    } else {
      None
    }
    let before = (budget.used(GcObjects), budget.used(GcBytes))
    let imports = @runtime.Imports::Imports(store)
    imports.add_global(
      "host",
      "e",
      store.alloc_global(
        GlobalInstance({ value_type: ExnRef, mutable: false, }, ExnRef(parent)),
      ),
    )
    let module_ = @wat.parse(
      "(module (import \"host\" \"e\" (global exnref)) (table 1 exnref (global.get 0)) (table 1 funcref))",
    )
    @validator.validate_module(module_)
    try
      @executor.instantiate_module_with_imports(store, module_, imports)
    catch {
      ResourceLimitExceeded(TableElements) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("expected table quota rejection")
    }
    assert_eq((budget.used(GcObjects), budget.used(GcBytes)), before)
    assert_eq(budget.used(TableElements), 0L)
    if retained is Some(token) {
      assert_eq(store.encode_native_exception(child), token)
      assert_eq(store.decode_native_exception(token), ExnRef(child))
    }
    store.alloc_exn(child_tag, []) |> ignore
  }
}
