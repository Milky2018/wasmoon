///|
test "precise function frames survive collection and hidden-result direct and indirect tails" {
  let results = "(result (ref $s) i64 i64 i64 i64 i64 i64 i64 i64 i64)"
  let values = Array::makei(9, index => "i64.const \{index + 1}").join(" ")
  let drops = Array::make(9, "drop").join(" ")
  let source =
    $|(module (type $s (struct (field i32)))
    $| (type $f (func (param (ref $s)) \{results}))
    $| (import "h" "collect" (func $collect))
    $| (table 1 funcref) (elem (i32.const 0) $body)
    $| (func $body (type $f) call $collect local.get 0 \{values})
    $| (func $direct (type $f) local.get 0 return_call $body)
    $| (func $indirect (type $f) local.get 0 i32.const 0 return_call_indirect (type $f))
    $| (func (export "direct") (result i32)
    $|  i32.const 42 struct.new $s call $direct \{drops} struct.get $s 0)
    $| (func (export "indirect") (result i32)
    $|  i32.const 42 struct.new $s call $indirect \{drops} struct.get $s 0))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let collections = Ref(0)
    let collect = store.alloc_host_func(fn(_) {
      collections.val += 1
      store.collect_garbage() |> ignore
      []
    })
    let imports = @runtime.Imports::Imports(store)
    imports.add_func("h", "collect", collect)
    let instance = @executor.instantiate_module_with_imports(
      store, module_, imports,
    )
    let context = build_gc_root_context(module_, instance, store, opt_level~)
    defer context.close()
    context.install_hostcall_dispatcher(store, instance)
    for index in [4, 5] {
      assert_eq(context.call_core_func(store, instance, index, []), [I32(42)])
      assert_eq(store.collect_garbage(), 1)
    }
    assert_eq(collections.val, 2)
  }
}
