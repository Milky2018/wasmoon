///|
test "loop-carried private reference fields remain precise roots during forced collection" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $item (struct (field i32)))
      #| (type $box (struct (field (mut (ref null $item)))))
      #| (type $bytes (array (mut i8)))
      #| (func $allocate i32.const 1024 array.new_default $bytes drop)
      #| (func (export "test") (result i32)
      #|  (local $box (ref null $box)) (local $i i32) (local $sum i32)
      #|  i32.const 42 struct.new $item struct.new $box local.set $box
      #|  (loop $again
      #|   call $allocate
      #|   local.get $sum local.get $box struct.get $box 0 struct.get $item 0
      #|   i32.add local.set $sum
      #|   local.get $box local.get $i i32.const 43 i32.add struct.new $item
      #|   struct.set $box 0
      #|   local.get $i i32.const 1 i32.add local.tee $i
      #|   i32.const 100 i32.lt_u br_if $again)
      #|  local.get $sum))
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
    set_allocation_budget(heap.get_ptr(), 512L)
    assert_eq(context.call_core_func(store, instance, 1, []), [I32(9150)])
    assert_true(heap.get_total_collections() > 0)
    assert_true(heap.verify())
  }
}
