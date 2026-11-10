///|
test "checked struct types retain fresh addresses across forced collection" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $bytes (array (mut i8)))
      #| (type $s (struct (field (ref $bytes)) (field (mut i32))))
      #| (func $read (param $s (ref $s)) (result i32)
      #|  (local $i i32) (local $sum i32)
      #|  local.get $s struct.get $s 1 drop
      #|  (loop $again
      #|   i32.const 1024 array.new_default $bytes drop
      #|   local.get $s struct.get $s 0 array.len drop
      #|   local.get $sum local.get $s struct.get $s 0 i32.const 0
      #|   array.get_u $bytes i32.add local.set $sum
      #|   local.get $i i32.const 1 i32.add local.tee $i
      #|   i32.const 100 i32.lt_u br_if $again)
      #|  local.get $s struct.get $s 0 drop local.get $sum)
      #| (func (export "test") (result i32)
      #|  i32.const 42 i32.const 8 array.new $bytes
      #|  i32.const 0 struct.new $s call $read))
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
    assert_eq(context.call_core_func(store, instance, 1, []), [I32(4200)])
    assert_true(heap.get_total_collections() > 0)
    assert_true(heap.verify())
  }
}
