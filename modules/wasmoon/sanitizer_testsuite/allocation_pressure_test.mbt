///|
fn check_allocation_pressure(retain : Bool) -> Unit raise {
  let module_ = @wat.parse(
    (
      #|(module (type $a (array (mut i32)))
      #| (func (export "dead") (param $n i32) (result i32)
      #|   i32.const -7 local.get $n array.new $a drop
      #|   i32.const 42 local.get $n array.new $a i32.const 0 array.get $a)
      #| (func (export "live") (param $n i32) (result i32) (local $first (ref $a))
      #|   i32.const -7 local.get $n array.new $a local.set $first
      #|   i32.const 42 local.get $n array.new $a i32.const 0 array.get $a
      #|   local.get $first i32.const 0 array.get $a i32.add))
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
    // Each object is half the capacity plus 16 bytes after alignment. The
    // second allocation crosses the collection boundary by just 32 bytes.
    let length = ((capacity / 2L - 16L) / 4L).to_int()
    assert_eq(
      context.call_core_func(store, instance, if retain { 1 } else { 0 }, [
        I32(length),
      ]),
      [I32(if retain { 35 } else { 42 })],
    )
    if retain {
      // Both arrays are live at admission: growth is necessary and safe.
      assert_true(heap.get_capacity() > capacity)
    } else {
      assert_eq(heap.get_capacity(), capacity)
      assert_true(heap.get_total_collections() > 0)
    }
    assert_true(heap.verify())
  }
}

///|
test "allocation pressure collects dead payloads before growing across its boundary" {
  check_allocation_pressure(false)
}

///|
test "allocation pressure still grows when both payloads remain live" {
  check_allocation_pressure(true)
}
