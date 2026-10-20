///|
test "low-level indirect setter honors borrowed Store representation" {
  let module_ = @wat.parse(
    "(module (func $f (export \"f\")) (table 1 funcref (ref.func $f)))",
  )
  @validator.validate_module(module_)
  let (store, instance) = @executor.instantiate_module(module_)
  defer store.close()
  guard @commands.compile_module_to_jit(module_, false, false, 0, false)
    is Some((artifact, debug_db)) else {
    fail("compilation failed")
  }
  let jm = @jit.JITModule::load_artifact_with_imports(
    @commands.verify_compiled_jit_artifact(artifact),
    @wast.build_func_signatures(module_),
    {},
    function_names=@commands.build_jit_function_names(module_),
    debug_db~,
  )
  defer jm.close()
  @wast.register_instance_funcrefs_for_jit(jm, instance, store)
  let context = @wasmoon_jit.NativeJITContext::try_alloc(1).unwrap()
  context.set_func(0, jm.get_func_ptr(0))
  context.set_table_pointers([store.get_jit_table(instance.table_addrs[0])])
  context.bind_callable_registry(
    store.native_callable_registry().unwrap(),
    store.native_type_indices(instance),
    [],
    functions=instance.func_addrs[:].to_owned(),
  )
  let table = store.get_table(instance.table_addrs[0])
  let before = table.get(0)
  assert_eq(before, FuncRef(instance.func_addrs[0]))
  context.set_indirect(0, 0, module_.funcs[0])
  let after = table.get(0) catch {
    InvalidHandle =>
      fail(
        "borrowed Store table decoder rejects the set_indirect representation",
      )
    error => fail(error.to_string())
  }
  assert_eq(after, before)
  // A valid identity is independent of executable availability.
  context.set_func(0, 0L)
  table.set(0, Null)
  context.set_indirect(0, 0, module_.funcs[0])
  assert_eq(table.get(0), before)
  assert_eq(store.collect_garbage(), 0)
  // Missing or invalid local Store mappings must leave the owner untouched.
  let native = store.get_jit_table(instance.table_addrs[0]).unwrap().raw_ptr()
  for functions in [[], [-1]] {
    context.bind_callable_registry(
      store.native_callable_registry().unwrap(),
      store.native_type_indices(instance),
      [],
      functions~,
    )
    let revision = native.revision()
    context.set_indirect(0, 0, module_.funcs[0])
    assert_eq(table.get(0), before)
    assert_eq(native.revision(), revision)
  }
}
