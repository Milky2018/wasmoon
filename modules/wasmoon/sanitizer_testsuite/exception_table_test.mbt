///|
test "exception table function payloads cross interpreter and JIT boundaries" {
  let module_ = @wat.parse(
    "(module (type $t (func (result i32))) (func $target (type $t) i32.const 42) (elem declare func $target) (tag $e (param (ref $t))) (table 1 exnref) (func (export \"capture\") i32.const 0 (block $caught (result exnref) (try_table (catch_all_ref $caught) (throw $e (ref.func $target))) unreachable) table.set) (func (export \"read\") (result i32) (block $caught (result (ref $t)) (try_table (catch $e $caught) i32.const 0 table.get throw_ref) unreachable) call_ref $t))",
  )
  let (store, instance) = @executor.instantiate_module(module_)
  defer store.close()
  @executor.call_exported_func(store, instance, "capture", []) |> ignore
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  assert_eq(context.call_core_func(store, instance, 2, []), [I32(42)])
  assert_eq(@executor.call_exported_func(store, instance, "read", []), [I32(42)])
  context.call_core_func(store, instance, 1, []) |> ignore
  assert_eq(@executor.call_exported_func(store, instance, "read", []), [I32(42)])
  let table = store.get_table(instance.table_addrs[0])
  guard table.get(0) is ExnRef(index) else { fail("expected exception") }
  assert_eq(store.get_exn(index).values, [FuncRef(instance.func_addrs[0])])
  // Keep decoding snapshots produced by the pre-migration pointer format.
  let arena = store.native_execution_state().exceptions()
  let legacy = arena.insert(store.get_c_heap_ptr(), instance.tag_addrs[0], [
    @wasmoon_jit.tag_funcref_ptr(context.jit_module.get_func_ptr(0)),
  ])
  assert_true(legacy != 0L)
  guard store.decode_native_exception(legacy) is ExnRef(legacy_index) else {
    fail("expected legacy native exception")
  }
  assert_eq(store.get_exn(legacy_index).values, [
    FuncRef(instance.func_addrs[0]),
  ])
  assert_eq(store.collect_garbage(), 0)
  assert_eq(context.call_core_func(store, instance, 2, []), [I32(42)])
}
