///|
fn make_host_fail_module() -> @types.Module {
  {
    ..@types.Module::empty(),
    types: [@types.SubType::func([], [I32])],
    type_rec_groups: [0],
    imports: [{ mod_name: "env", name: "fail", desc: Func(0) }],
    funcs: [0],
    codes: [{ locals: [], body: [Call(0)] }],
    exports: [{ name: "main", desc: Func(1) }],
  }
}

///|
test "call_exported_func_with_options: classify wasm trap" {
  let mod = @types.Module::simple(
    [I32],
    [I32],
    [LocalGet(0), I32Const(0), I32DivS],
    "div_by_zero",
  )
  let (store, instance) = instantiate_module(mod)
  let result = call_exported_func_with_options(store, instance, "div_by_zero", [
    I32(7),
  ])
  match result {
    Ok(_) => fail("Expected trap failure")
    Err(failure) => {
      match failure.kind {
        Trap => ()
        _ => fail("Expected trap classification")
      }
      match failure.runtime_error {
        Some(err) => inspect(err.to_string(), content="integer divide by zero")
        None => fail("Expected runtime error payload")
      }
    }
  }
}

///|
test "call_exported_func_with_options: classify host invocation error" {
  let store = @runtime.Store::Store()
  let host_addr = store.alloc_host_func_with_caller(
    (_caller, _args) => raise LinkErrorDetail("host failed"),
    func_type={ params: [], results: [I32] },
    type_idx=0,
  )
  let imports = @runtime.Imports::Imports()
  imports.add_func("env", "fail", host_addr)
  let instance = instantiate_module_with_imports(
    store,
    make_host_fail_module(),
    imports,
  ) catch {
    _ => fail("instantiate_module_with_imports should succeed")
  }
  let result = call_exported_func_with_options(store, instance, "main", [])
  match result {
    Ok(_) => fail("Expected host invocation failure")
    Err(failure) => {
      match failure.kind {
        HostInvocation => ()
        _ => fail("Expected host invocation classification")
      }
      match failure.runtime_error {
        Some(err) => inspect(err.to_string(), content="link error: host failed")
        None => fail("Expected runtime error payload")
      }
    }
  }
}

///|
test "call_exported_func_with_options: preserve legacy host error behavior" {
  let store = @runtime.Store::Store()
  let host_addr = store.alloc_host_func_with_caller(
    (_caller, _args) => raise LinkErrorDetail("legacy host error"),
    func_type={ params: [], results: [I32] },
    type_idx=0,
  )
  let imports = @runtime.Imports::Imports()
  imports.add_func("env", "fail", host_addr)
  let instance = instantiate_module_with_imports(
    store,
    make_host_fail_module(),
    imports,
  ) catch {
    _ => fail("instantiate_module_with_imports should succeed")
  }
  let mut result = "ok"
  (call_exported_func(store, instance, "main", []) |> ignore) catch {
    err => result = normalize_runtime_error(err).to_string()
  }
  inspect(result, content="link error: legacy host error")
}

///|
test "call_exported_func_with_options: cancel before invocation" {
  let mod = @types.Module::simple([], [I32], [I32Const(42)], "main")
  let (store, instance) = instantiate_module(mod)
  let options = CallExportOptions::CallExportOptions(cancel=Some(fn() { true }))
  let result = call_exported_func_with_options(
    store,
    instance,
    "main",
    [],
    options~,
  )
  match result {
    Ok(_) => fail("Expected cancellation result")
    Err(failure) => {
      match failure.kind {
        Cancelled => ()
        _ => fail("Expected cancelled classification")
      }
      inspect(failure.message, content="invocation cancelled before execution")
    }
  }
}

///|
test "call_exported_func_with_options: unsupported budget options are structured" {
  let mod = @types.Module::simple([], [I32], [I32Const(1)], "main")
  let (store, instance) = instantiate_module(mod)
  let options = CallExportOptions::CallExportOptions(fuel=Some(100))
  let result = call_exported_func_with_options(
    store,
    instance,
    "main",
    [],
    options~,
  )
  match result {
    Ok(_) => fail("Expected unsupported option result")
    Err(failure) => {
      match failure.kind {
        UnsupportedOption => ()
        _ => fail("Expected UnsupportedOption classification")
      }
      inspect(
        failure.message,
        content="fuel is not supported yet (requested: 100)",
      )
    }
  }
}
