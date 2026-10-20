///|
test "public shared-table initialization preserves Store references and roots" {
  for selective in [false, true] {
    let mod_ = @wat.parse(
      "(module (func $a) (func $b) (table 1 funcref (ref.func $a)) (func (export \"read\") (result i32) i32.const 0 table.get ref.is_null))",
    )
    let (store, instance) = @executor.instantiate_module(mod_)
    defer store.close()
    let context = prepare_async_jit_context(
      mod_,
      instance,
      store,
      local_compile_mask=if selective {
        Some([false, false, true])
      } else {
        None
      },
    )
    defer context.close()
    let table = store.get_table(instance.table_addrs[0])
    context.jit_module.init_shared_tables(
      [store.get_jit_table(instance.table_addrs[0])],
      [(0, 0, Some(1), 0)],
    )
    assert_eq(table.get(0), FuncRef(instance.func_addrs[1]))
    assert_eq(@executor.call_exported_func(store, instance, "read", []), [
      I32(0),
    ])
    assert_eq(store.collect_garbage(), 0)
    // Invalid later initializers must not leave an earlier write published.
    try
      context.jit_module.init_shared_tables(
        [store.get_jit_table(instance.table_addrs[0])],
        [(0, 0, None, 0), (0, 0, Some(99), 0)],
      )
    catch {
      InvalidBinding(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected invalid Store function identity")
    }
    assert_eq(table.get(0), FuncRef(instance.func_addrs[1]))
  }
}

///|
test "public shared-table initialization retains standalone native encoding" {
  let mod_ = @wat.parse("(module (func) (func) (table 1 funcref))")
  let (store, instance) = @executor.instantiate_module(mod_)
  defer store.close()
  let context = prepare_async_jit_context(mod_, instance, store)
  defer context.close()
  let owner = @wasmoon_jit.JITTableOwner::try_alloc(1, None).unwrap()
  defer owner.close()
  context.jit_module.init_shared_tables([Some(owner.table())], [
    (0, 0, Some(1), 7),
  ])
  assert_eq(
    owner.table().get_entry_value(0),
    @wasmoon_jit.tag_funcref_ptr(context.jit_module.get_func_ptr(1)),
  )
  context.jit_module.init_shared_tables([Some(owner.table())], [
    (0, 0, None, -1),
  ])
  assert_eq(owner.table().get_entry_value(0), 0L)
}
