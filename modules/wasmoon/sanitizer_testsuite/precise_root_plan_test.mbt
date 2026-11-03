///|
test "precise root plans retain six detached children at a collecting call" {
  let source =
    #|(module
    #| (type $child (struct (field i64)))
    #| (type $owner (struct
    #|  (field (mut (ref null $child))) (field (mut (ref null $child)))
    #|  (field (mut (ref null $child))) (field (mut (ref null $child)))
    #|  (field (mut (ref null $child))) (field (mut (ref null $child)))))
    #| (import "h" "collect" (func $collect))
    #| (func (export "probe") (param (ref $owner)) (result i64)
    #|  (local $a (ref null $child)) (local $b (ref null $child))
    #|  (local $c (ref null $child)) (local $d (ref null $child))
    #|  (local $e (ref null $child)) (local $f (ref null $child))
    #|  local.get 0 struct.get $owner 0 local.set $a
    #|  local.get 0 struct.get $owner 1 local.set $b
    #|  local.get 0 struct.get $owner 2 local.set $c
    #|  local.get 0 struct.get $owner 3 local.set $d
    #|  local.get 0 struct.get $owner 4 local.set $e
    #|  local.get 0 struct.get $owner 5 local.set $f
    #|  call $collect
    #|  local.get $a struct.get $child 0 local.get $b struct.get $child 0 i64.add
    #|  local.get $c struct.get $child 0 i64.add local.get $d struct.get $child 0 i64.add
    #|  local.get $e struct.get $child 0 i64.add local.get $f struct.get $child 0 i64.add))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let owner = Ref(-1)
    let reclaimed = Ref(-1)
    let collect = store.alloc_host_func(_ => {
      for field in 0..<6 {
        store.struct_set(owner.val, field, Null)
      }
      reclaimed.val = store.collect_garbage()
      []
    })
    let imports = @runtime.Imports::Imports(store)
    imports.add_func("h", "collect", collect)
    let instance = @executor.instantiate_module_with_imports(
      store, module_, imports,
    )
    let context = build_gc_root_context(
      module_,
      instance,
      store,
      opt_level=level,
    )
    defer context.close()
    context.install_hostcall_dispatcher(store, instance)
    let children : Array[@types.Value] = Array::makei(6, index => {
      StructRef(store.alloc_struct(0, [I64(index.to_int64() + 1L)], instance~))
    })
    owner.val = store.alloc_struct(1, children, instance~)
    let lease = store.pin_gc_roots([StructRef(owner.val)])
    defer lease.release()
    let outcome = Ok(
      context.call_core_func(store, instance, 1, [StructRef(owner.val)]),
    ) catch {
      error => Err(error)
    }
    assert_eq(reclaimed.val, 0, msg="a live precise root was reclaimed")
    let result = match outcome {
      Ok(values) => values
      Err(error) => raise error
    }
    assert_eq(result, [I64(21L)])
    assert_eq(store.collect_garbage(), 6)
    lease.release()
    assert_eq(store.collect_garbage(), 1)
  }
}
