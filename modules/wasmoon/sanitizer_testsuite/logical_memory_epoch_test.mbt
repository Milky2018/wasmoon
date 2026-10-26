///|
test "logical field reuse preserves roots through allocation-triggered collection" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $a (array (mut i32)))
      #| (type $s (struct (field (mut i64)) (field i64)))
      #| (func (export "probe") (param $n i32) (result i64)
      #|  (local $object (ref $s)) (local $alias (ref $s))
      #|  (local $before i64) (local $after i64)
      #|  i32.const 0 local.get $n array.new $a drop
      #|  i64.const 37 i64.const 5 struct.new $s local.tee $object local.set $alias
      #|  local.get $object struct.get $s 0 local.set $before
      #|  i32.const 0 local.get $n array.new $a drop
      #|  local.get $object struct.get $s 0 local.set $after
      #|  local.get $alias i64.const 53 struct.set $s 0
      #|  local.get $before local.get $after i64.add
      #|  local.get $object struct.get $s 0 i64.add
      #|  local.get $object struct.get $s 1 i64.add))
    ),
  )
  @validator.validate_module(module_)
  for opt_level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = build_gc_root_context(module_, instance, store, opt_level~)
    defer context.close()
    let heap = store.native_heap().unwrap()
    let capacity = heap.get_capacity()
    set_allocation_budget(heap.get_ptr(), capacity)
    let length = ((capacity / 2L - 16L) / 4L).to_int()
    assert_eq(context.call_core_func(store, instance, 0, [I32(length)]), [
      I64(132),
    ])
    assert_true(heap.get_total_collections() > 0)
    assert_true(heap.verify())
  }
}
