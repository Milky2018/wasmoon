///|
fn invalid_tag_export_module() -> @types.Module {
  let module_ = @types.Module::simple([], [I32], [I32Const(7)], "run")
  module_.memories.push({
    limits: { min: 1L, max: None, },
    is_memory64: false,
    is_shared: false,
    page_size_log2: 16,
  })
  module_.exports.push({ name: "bad", desc: Tag(-1), })
  module_
}

///|
test "checked fresh-store instantiation rejects negative tag exports" {
  for with_init in [false, true] {
    try {
      let (store, _) = if with_init {
        @executor.instantiate_module_with_init(invalid_tag_export_module())
      } else {
        @executor.instantiate_module(invalid_tag_export_module())
      }
      store.close()
    } catch {
      InvalidModule(message) =>
        assert_eq(message, "UnknownExport(\"unknown tag -1\")")
      error => fail(error.to_string())
    } noraise {
      _ => fail("checked instantiation accepted a negative tag export")
    }
  }
}

///|
test "negative tag export rejection preserves existing Store state and budgets" {
  let budget = @runtime.ResourceBudget::new()
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let imports = @runtime.Imports(store)
  let baseline = @executor.instantiate_module_with_imports(
    store,
    @types.Module::simple([], [I32], [I32Const(42)], "run"),
    imports,
  )
  let before = Repr(store.counts()).to_string()
  let instances = budget.used(Instances)
  let units = budget.used(CompilationUnits)
  for unstarted in [false, true] {
    try {
      if unstarted {
        @executor.instantiate_module_with_imports_unstarted(
          store,
          invalid_tag_export_module(),
          imports,
        )
        |> ignore
      } else {
        @executor.instantiate_module_with_imports(
          store,
          invalid_tag_export_module(),
          imports,
        )
        |> ignore
      }
    } catch {
      InvalidModule(message) =>
        assert_eq(message, "UnknownExport(\"unknown tag -1\")")
      error => fail(error.to_string())
    } noraise {
      _ => fail("existing-store instantiation accepted a negative tag export")
    }
    assert_eq(Repr(store.counts()).to_string(), before)
    assert_eq(budget.used(Instances), instances)
    assert_eq(budget.used(CompilationUnits), units)
    assert_eq(budget.used(MemoryBytes), 0L)
  }
  match
    @executor.instantiate_module_with_import_diagnostics(
      store,
      invalid_tag_export_module(),
      imports,
    ) {
    RuntimeFailure(InvalidModule(message)) =>
      assert_eq(message, "UnknownExport(\"unknown tag -1\")")
    _ => fail("import diagnostics did not report the invalid module")
  }
  assert_eq(Repr(store.counts()).to_string(), before)
  assert_eq(budget.used(Instances), instances)
  assert_eq(budget.used(CompilationUnits), units)
  assert_eq(budget.used(MemoryBytes), 0L)
  assert_eq(@executor.call_exported_func(store, baseline, "run", []), [I32(42)])
}

///|
async test "async instantiation rejects negative tag exports before Store mutation" {
  let budget = @runtime.ResourceBudget::new()
  let store = @runtime.Store(resource_budget=Some(budget))
  defer store.close()
  let before = Repr(store.counts()).to_string()
  try
    @executor.instantiate_module_with_imports_async(
      store,
      invalid_tag_export_module(),
      Imports(store),
    )
  catch {
    InvalidModule(message) =>
      assert_eq(message, "UnknownExport(\"unknown tag -1\")")
    error => fail(error.to_string())
  } noraise {
    _ => fail("async instantiation accepted a negative tag export")
  }
  assert_eq(Repr(store.counts()).to_string(), before)
  assert_eq(budget.used(Instances), 0L)
  assert_eq(budget.used(CompilationUnits), 0L)
  assert_eq(budget.used(MemoryBytes), 0L)
}

///|
test "validated imported and defined tag exports remain linkable snapshots" {
  let module_ = @types.Module::empty()
  module_.types.push(@types.SubType::func([I32], []))
  module_.type_rec_groups.push(0)
  module_.imports.push({ mod_name: "host", name: "tag", desc: Tag(0), })
  module_.tags.push({ type_idx: 0, })
  module_.exports.append([
    { name: "imported", desc: Tag(0), },
    { name: "defined", desc: Tag(1), },
  ])
  let validated = @validator.ValidatedModule::new(module_)
  module_.exports[0] = { name: "bad", desc: Tag(-1), }
  let store = @runtime.Store()
  defer store.close()
  let tag = store.alloc_tag({ params: [I32], results: [], })
  let imports = @runtime.Imports(store)
  imports.add_tag("host", "tag", tag)
  let instance = @executor.instantiate_validated_module_with_imports_unstarted(
    store, validated, imports,
  )
  let linker = @runtime.Linker::with_store(store)
  linker.register("valid", instance)
  let linked = linker.build_imports()
  assert_true(
    linked.resolve("valid", "imported") is Some(Tag(address)) && address == tag,
  )
  assert_true(
    linked.resolve("valid", "defined") is Some(Tag(address)) && address != tag,
  )
  assert_true(linked.resolve("valid", "bad") is None)
}
