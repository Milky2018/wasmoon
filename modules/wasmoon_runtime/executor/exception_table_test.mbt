///|
test "interpreter exceptions carrying Wasm functions can be stored in tables" {
  let module_ = @wat.parse(
    "(module (type $t (func)) (func $dummy) (elem declare func $dummy) (tag $e (param (ref $t))) (table 1 exnref) (func (export \"run\") (result i32) i32.const 0 (block $caught (result exnref) (try_table (catch_all_ref $caught) (throw $e (ref.func $dummy))) unreachable) table.set i32.const 0 table.get ref.is_null))",
  )
  let (store, instance) = @executor.instantiate_module(module_)
  defer store.close()
  assert_eq(@executor.call_exported_func(store, instance, "run", []), [I32(0)])
  assert_eq(store.collect_garbage(), 0)
}

///|
test "interpreter function exception payloads survive table admission and mutation" {
  let module_ = @wat.parse("(module (func (export \"target\")))")
  let (store, instance) = @executor.instantiate_module(module_)
  defer store.close()
  let host = store.alloc_host_func(_ => [])
  let tag = store.alloc_tag({ params: [RefFunc], results: [], })
  for function in [host, instance.func_addrs[0]] {
    let exception = store.alloc_exn(tag, [FuncRef(function)])
    let initial = @runtime.Table::Table(
      ExnRef,
      1,
      None,
      init_value=ExnRef(exception),
    )
    store.alloc_table(initial) |> ignore
    let mutated = @runtime.Table::Table(ExnRef, 1, None)
    store.alloc_table(mutated) |> ignore
    mutated.set(0, ExnRef(exception))
    for table in [initial, mutated] {
      assert_eq(table.get(0), ExnRef(exception))
      guard table.get(0) is ExnRef(index) else { fail("expected exception") }
      assert_eq(store.get_exn(index).values, [FuncRef(function)])
    }
    assert_eq(store.collect_garbage(), 0)
  }
}
