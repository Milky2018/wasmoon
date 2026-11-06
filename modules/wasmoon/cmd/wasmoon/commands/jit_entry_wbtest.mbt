///|
test "CLI entry preserves Store function identities and abstract array results" {
  let code = @core_wat.parse(
    (
      #|(module
      #| (type $a (array (mut i32)))
      #| (func $f)
      #| (elem declare func $f)
      #| (func (export "run") (result funcref anyref v128)
      #|   ref.func $f
      #|   i32.const 7 i32.const 2 array.new $a
      #|   v128.const i64x2 1 2))
    ),
  )
  let store = @runtime.Store()
  defer store.close()
  store.enable_c_heap()
  let instance = @executor.instantiate_module_with_imports(
    store,
    code,
    Imports(store),
  )
  let results = run_with_jit(
    code,
    instance,
    store,
    "run",
    [],
    false,
    false,
    None,
    2,
    false,
    None,
    [],
  )
  assert_eq(results.length(), 3)
  assert_eq(results[0], FuncRef(instance.func_addrs[0]))
  guard results[1] is ArrayRef(reference) else {
    fail("abstract array result lost its object kind")
  }
  assert_eq(store.array_get(reference, 1), I32(7))
  assert_eq(results[2], V128(@types.int64_pair_to_v128_le(1L, 2L)))
}
