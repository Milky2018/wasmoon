///|
fn module_with_imported_func(expected_type : @types.FuncType) -> @types.Module {
  {
    ..@types.Module::empty(),
    types: [@types.SubType::from_func(expected_type)],
    type_rec_groups: [0],
    imports: [{ mod_name: "env", name: "f", desc: Func(0) }],
    funcs: [0],
    codes: [{ locals: [], body: [Call(0)] }],
    exports: [{ name: "main", desc: Func(1) }],
  }
}

///|
test "validate_imports_with_diagnostics: missing import" {
  let store = @runtime.Store::new()
  let mod = module_with_imported_func({
    params: [],
    results: [@types.ValueType::I32],
  })
  let result = validate_imports_with_diagnostics(
    store,
    mod,
    @runtime.Imports::new(),
  )
  assert_false(result.ok)
  inspect(result.diagnostics.length(), content="1")
  match result.diagnostics[0].kind {
    MissingImport => ()
    _ => fail("Expected MissingImport")
  }
  inspect(result.diagnostics[0].module_name, content="env")
  inspect(result.diagnostics[0].name, content="f")
}

///|
test "validate_imports_with_diagnostics: import kind mismatch" {
  let store = @runtime.Store::new()
  let mod = module_with_imported_func({
    params: [],
    results: [@types.ValueType::I32],
  })
  let mem_addr = store.alloc_mem(@runtime.Memory::new(1, None))
  let imports = @runtime.Imports::new()
  imports.add_memory("env", "f", mem_addr)
  let result = validate_imports_with_diagnostics(store, mod, imports)
  assert_false(result.ok)
  inspect(result.diagnostics.length(), content="1")
  match result.diagnostics[0].kind {
    ImportKindMismatch => ()
    _ => fail("Expected ImportKindMismatch")
  }
  inspect(result.diagnostics[0].expected, content="func")
  inspect(result.diagnostics[0].actual, content="Some(\"memory\")")
}

///|
test "validate_imports_with_diagnostics: function signature mismatch" {
  let store = @runtime.Store::new()
  let mod = module_with_imported_func({
    params: [],
    results: [@types.ValueType::I32],
  })
  let host_addr = store.alloc_host_func_with_caller(
    (_caller, _args) => [I64(1L)],
    func_type={ params: [], results: [@types.ValueType::I64] },
    type_idx=0,
  )
  let imports = @runtime.Imports::new()
  imports.add_func("env", "f", host_addr)
  let result = validate_imports_with_diagnostics(store, mod, imports)
  assert_false(result.ok)
  inspect(result.diagnostics.length(), content="1")
  match result.diagnostics[0].kind {
    ImportTypeMismatch => ()
    _ => fail("Expected ImportTypeMismatch")
  }
}

///|
test "instantiate_module_with_import_diagnostics: returns import error" {
  let store = @runtime.Store::new()
  let mod = module_with_imported_func({
    params: [],
    results: [@types.ValueType::I32],
  })
  let result = instantiate_module_with_import_diagnostics(
    store,
    mod,
    @runtime.Imports::new(),
  )
  match result {
    ImportError(diagnostics) => assert_false(diagnostics.ok)
    _ => fail("Expected ImportError")
  }
}

///|
test "instantiate_module_with_import_diagnostics: returns ok on valid imports" {
  let store = @runtime.Store::new()
  let mod = module_with_imported_func({
    params: [],
    results: [@types.ValueType::I32],
  })
  let host_addr = store.alloc_host_func_with_caller(
    (_caller, _args) => [I32(9)],
    func_type={ params: [], results: [@types.ValueType::I32] },
    type_idx=0,
  )
  let imports = @runtime.Imports::new()
  imports.add_func("env", "f", host_addr)
  let result = instantiate_module_with_import_diagnostics(store, mod, imports)
  match result {
    Ok(instance) => {
      let values = call_exported_func(store, instance, "main", [])
      inspect(values[0], content="I32(9)")
    }
    _ => fail("Expected successful instantiation")
  }
}

///|
test "instantiate_module_with_import_diagnostics: returns runtime failure" {
  let store = @runtime.Store::new()
  let mod : @types.Module = {
    ..@types.Module::empty(),
    types: [@types.SubType::func([], [])],
    type_rec_groups: [0],
    funcs: [0],
    codes: [{ locals: [], body: [Unreachable] }],
    start: Some(0),
  }
  let result = instantiate_module_with_import_diagnostics(
    store,
    mod,
    @runtime.Imports::new(),
  )
  match result {
    RuntimeFailure(err) => inspect(err.to_string(), content="unreachable")
    _ => fail("Expected RuntimeFailure")
  }
}
