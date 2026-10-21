///|
test "selectively uncompiled functions preserve reference identity and type" {
  let mod_ = @wat.parse(
    "(module (type $t (func (result i32))) (func $target (type $t) i32.const 42) (elem declare func $target) (table 1 (ref null $t) (ref.func $target)) (func (export \"read\") (result i32) i32.const 0 table.get ref.is_null) (func (export \"get\") (result funcref) i32.const 0 table.get) (func (export \"typed\") (result i32) i32.const 0 table.get ref.cast (ref $t) ref.is_null) (func (export \"call\") (result i32) i32.const 0 table.get ref.as_non_null call_ref $t) (func (export \"tail\") (result i32) i32.const 0 table.get ref.as_non_null return_call_ref $t) (func (export \"direct\") (result funcref) ref.func $target))",
  )
  let (store, instance) = @executor.instantiate_module(mod_)
  defer store.close()
  let context = prepare_async_jit_context(
    mod_,
    instance,
    store,
    local_compile_mask=Some([false, true, true, true, true, true, true]),
  )
  defer context.close()
  assert_eq(context.call_core_func(store, instance, 1, []), [I32(0)])
  assert_eq(context.call_core_func(store, instance, 2, []), [
    FuncRef(instance.func_addrs[0]),
  ])
  assert_eq(context.call_core_func(store, instance, 3, []), [I32(0)])
  assert_eq(context.call_core_func(store, instance, 6, []), [
    FuncRef(instance.func_addrs[0]),
  ])
  // Code availability is independent of reference nullness. An unavailable
  // entry must fail safely rather than executing the Store handle as a pointer.
  for index in [4, 5] {
    try context.call_core_func(store, instance, index, []) catch {
      Trap("jit backend trap") => ()
      error => raise error
    } noraise {
      _ => fail("expected an unavailable native entry")
    }
  }
  let compiled = prepare_async_jit_context(mod_, instance, store)
  defer compiled.close()
  for index in [4, 5] {
    assert_eq(context.call_core_func(store, instance, index, []), [I32(42)])
  }
  assert_eq(
    store.get_table(instance.table_addrs[0]).get(0),
    FuncRef(instance.func_addrs[0]),
  )
}

///|
test "stable function table identities survive executable registration withdrawal" {
  let mod_ = @wat.parse(
    "(module (type $t (func (result i32))) (func $target (type $t) i32.const 42) (table 1 (ref null $t) (ref.func $target)) (func (export \"call\") (result i32) i32.const 0 table.get ref.as_non_null call_ref $t))",
  )
  let (store, instance) = @executor.instantiate_module(mod_)
  defer store.close()
  let context = prepare_async_jit_context(
    mod_,
    instance,
    store,
    local_compile_mask=Some([false, true]),
  )
  defer context.close()
  let other_module = @wat.parse(
    "(module (func (export \"run\") (result i32) i32.const 77))",
  )
  let other_instance = @executor.instantiate_module_with_imports(
    store,
    other_module,
    Imports(store),
  )
  let other_context = prepare_async_jit_context(
    other_module, other_instance, store,
  )
  defer other_context.close()
  let address = instance.func_addrs[0]
  let entries = [
    @runtime.StoreFuncrefEntry::StoreFuncrefEntry(
      store_addr=address,
      func_ptr=other_context.jit_module.get_func_ptr(0),
    ),
  ]
  for _ in 0..<2 {
    let registration = store.register_jit_funcrefs(entries)
    assert_eq(context.call_core_func(store, instance, 1, []), [I32(77)])
    registration.release()
    assert_eq(store.get_table(instance.table_addrs[0]).get(0), FuncRef(address))
    try context.call_core_func(store, instance, 1, []) catch {
      Trap("jit backend trap") => ()
      error => raise error
    } noraise {
      _ => fail("withdrawn executable must not be called")
    }
  }
}

///|
test "stable function references round trip through native heap slots" {
  let mod_ = @wat.parse(
    "(module (type $t (func (result i32))) (type $a (array (mut (ref $t)))) (func $target (type $t) i32.const 42) (elem declare func $target) (func (export \"make\") (result (ref $a)) ref.func $target array.new_fixed $a 1) (func (export \"call\") (param (ref $a)) (result i32) local.get 0 i32.const 0 array.get $a call_ref $t))",
  )
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    mod_,
    Imports(store),
  )
  let context = prepare_async_jit_context(mod_, instance, store)
  defer context.close()
  guard context.call_core_func(store, instance, 1, []) is [ArrayRef(array)] else {
    fail("expected a native array")
  }
  assert_eq(store.array_get(array, 0), FuncRef(instance.func_addrs[0]))
  let host_array = store.alloc_array(
    1,
    [FuncRef(instance.func_addrs[0])],
    instance~,
  )
  assert_eq(
    store.collect_garbage(additional_roots=[
      ArrayRef(array),
      ArrayRef(host_array),
    ]),
    0,
  )
  assert_eq(
    context.call_core_func(store, instance, 2, [ArrayRef(host_array)]),
    [I32(42)],
  )
}

///|
test "selective passive table initialization retains uncompiled Store identities" {
  let module_ = @wat.parse(
    "(module (func $target) (table 1 funcref) (elem $payload func $target) (func (export \"init\") (result i32) i32.const 0 i32.const 0 i32.const 1 table.init $payload i32.const 0 table.get ref.is_null))",
  )
  let (store, instance) = @executor.instantiate_module(module_)
  defer store.close()
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    local_compile_mask=Some([false, true]),
  )
  defer context.close()
  assert_eq(context.call_core_func(store, instance, 1, []), [I32(0)])
  assert_eq(
    store.get_table(instance.table_addrs[0]).get(0),
    FuncRef(instance.func_addrs[0]),
  )
  assert_eq(store.collect_garbage(), 0)
}

///|
test "stable function identities survive native global binding reads" {
  let module_ = @wat.parse(
    "(module (func $target) (table 1 funcref (ref.func $target)) (global $g (mut funcref) (ref.null func)) (func (export \"set\") i32.const 0 table.get global.set $g) (func (export \"get\") (result funcref) global.get $g))",
  )
  let (store, instance) = @executor.instantiate_module(module_)
  defer store.close()
  let context = prepare_async_jit_context(
    module_,
    instance,
    store,
    local_compile_mask=Some([false, true, true]),
  )
  defer context.close()
  context.call_core_func(store, instance, 1, []) |> ignore
  assert_eq(context.call_core_func(store, instance, 2, []), [
    FuncRef(instance.func_addrs[0]),
  ])
  let global = store.get_global(instance.global_addrs[0])
  assert_eq(global.get(), FuncRef(instance.func_addrs[0]))
  assert_eq(store.collect_garbage(), 0)
  global.set(Null)
  assert_eq(context.call_core_func(store, instance, 2, []), [Null])
  global.set(FuncRef(instance.func_addrs[0]))
  assert_eq(context.call_core_func(store, instance, 2, []), [
    FuncRef(instance.func_addrs[0]),
  ])
}
