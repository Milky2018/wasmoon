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

///|
test "outer rollback preserves snapshots in surviving imported tables" {
  let store = @runtime.Store::Store()
  defer store.close()
  let tag = store.alloc_tag({ params: [], results: [], })
  let exception = store.alloc_exn(tag, [])
  let table = @runtime.Table::Table(ExnRef, 1, None)
  store.alloc_table(table) |> ignore
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  linker.add_global(
    "host",
    "e",
    GlobalInstance({ value_type: ExnRef, mutable: false, }, ExnRef(exception)),
  )
  linker.add_table("host", "t", table)
  let transaction = @runtime.InstantiationTransaction::new()
  linker.register_rollback(transaction.registrar())
  let module_ = @wat.parse(
    "(module (import \"host\" \"e\" (global exnref)) (import \"host\" \"t\" (table 1 exnref)) (func $start i32.const 0 global.get 0 table.set unreachable) (start $start))",
  )
  @validator.validate_module(module_)
  try @executor.instantiate_with_linker(linker, "failing", module_) catch {
    Unreachable => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("expected start trap")
  }
  assert_eq(table.get(0), ExnRef(exception))
  transaction.rollback()
  assert_eq(store.get_exn(exception).tag_addr, tag)
  let after = table.get(0) catch {
    UndefinedElement =>
      fail("surviving imported table contains a released snapshot token")
    error => fail(error.to_string())
  }
  assert_eq(after, ExnRef(exception))
}

///|
test "outer rollback retains nested snapshots held by native globals and heap fields" {
  for in_heap in [false, true] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let child_tag = store.alloc_tag({ params: [], results: [], })
    let child = store.alloc_exn(child_tag, [])
    let parent_tag = store.alloc_tag({ params: [ExnRef], results: [], })
    let parent = store.alloc_exn(parent_tag, [ExnRef(child)])
    let module_ = @wat.parse(
      if in_heap {
        "(module (type $box (struct (field (mut exnref)))) (global $box (ref $box) (struct.new $box (ref.null exn))) (func (export \"read\") (result i32) global.get $box struct.get $box 0 ref.is_null))"
      } else {
        "(module (global $g (mut exnref) (ref.null exn)) (func (export \"read\") (result i32) global.get $g ref.is_null))"
      },
    )
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    // Real JIT setup binds globals to native slots; the heap case stays interpreted.
    let context = if in_heap {
      None
    } else {
      Some(build_gc_root_context(module_, instance, store))
    }
    defer (if context is Some(context) { context.close() })
    let global = store.get_global(instance.global_addrs[0])
    try
      store.with_instantiation(fn() -> Unit raise @runtime.RuntimeError {
        if in_heap {
          guard global.get() is StructRef(box) else { raise TypeMismatch }
          store.struct_set(box, 0, ExnRef(parent))
        } else {
          global.set(ExnRef(parent))
        }
        raise OutOfMemory
      })
    catch {
      OutOfMemory => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("expected rollback")
    }
    let value = if in_heap {
      guard global.get() is StructRef(box) else { fail("missing box") }
      store.struct_get(box, 0)
    } else {
      global.get()
    }
    assert_eq(value, ExnRef(parent))
    let token = store.encode_native_exception(parent)
    assert_eq(store.decode_native_exception(token), ExnRef(parent))
    assert_eq(store.get_exn(parent).values, [ExnRef(child)])
    assert_eq(store.collect_garbage(), 0)
    assert_eq(@executor.call_exported_func(store, instance, "read", []), [
      I32(0),
    ])
    if context is Some(context) {
      assert_eq(context.call_core_func(store, instance, 0, []), [I32(0)])
    }
  }
}
