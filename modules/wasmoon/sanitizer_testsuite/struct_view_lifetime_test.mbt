///|
fn struct_view_module() -> @types.Module raise {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $a (struct (field (mut i64)) (field i64)))
      #| (type $b (struct (field (mut f64)) (field i64)))
      #| (type $bytes (array (mut i8)))
      #| (func (param (ref $a)) (result i64) local.get 0 struct.get $a 0)
      #| (func (param (ref $b)) (result f64) local.get 0 struct.get $b 0))
    ),
  )
  @validator.validate_module(module_)
  module_
}

///|
test "repeated struct views observe writes growth compaction and nominal contracts" {
  let module_ = struct_view_module()
  for level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let instance = @executor.instantiate_module_with_imports(
      store,
      module_,
      Imports(store),
    )
    let context = build_gc_root_context(
      module_,
      instance,
      store,
      opt_level=level,
    )
    defer context.close()
    let heap = store.native_heap().unwrap()
    store.alloc_struct(0, [I64(99L), I64(0L)], instance~) |> ignore
    let object = store.alloc_struct(0, [I64(42L), I64(0L)], instance~)
    let roots = store.pin_gc_roots([StructRef(object)])
    defer roots.release()
    let read = fn() raise {
      context.jit_module.call_with_context(
        context.jit_module.get_func(0).unwrap(),
        [(object + 1).to_int64() << 1],
      )
    }
    assert_eq(read(), [42L])
    heap.struct_set(object, 0, I64(17L))
    assert_eq(read(), [17L])
    let offset = heap.get_offset(object)
    assert_eq(store.collect_garbage(), 1)
    assert_true(heap.get_offset(object) < offset)
    store.alloc_struct(0, [I64(99L), I64(0L)], instance~) |> ignore
    assert_eq(read(), [17L])
    assert_true(
      heap
      .get_ptr()
      .define_layout(instance.canonical_type_indices[2], [1], true),
    )
    let capacity = heap.get_capacity()
    heap.alloc_array(
      2,
      (capacity + 64L).to_int(),
      I32(0),
      runtime_type=instance.canonical_type_indices[2],
    )
    |> ignore
    assert_true(heap.get_capacity() > capacity)
    assert_eq(read(), [17L])
    try
      context.jit_module.call_with_context(
        context.jit_module.get_func(1).unwrap(),
        [(object + 1).to_int64() << 1],
      )
    catch {
      JITTrap(message) => assert_true(message.contains("unreachable"))
      error => fail(error.to_string())
    } noraise {
      _ => fail("an equal-width incompatible nominal type was admitted")
    }
    assert_eq(read(), [17L])
    assert_true(heap.verify())
  }
}

///|
test "struct view hints do not root provisional objects or survive heap close" {
  let module_ = struct_view_module()
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  let context = build_gc_root_context(module_, instance, store)
  defer context.close()
  let heap = store.native_heap().unwrap()
  let rollback = heap.make_allocation_rollback(fn() { [] })
  let object = store.alloc_struct(0, [I64(42L), I64(0L)], instance~)
  let raw = (object + 1).to_int64() << 1
  assert_eq(
    context.jit_module.call_with_context(
      context.jit_module.get_func(0).unwrap(),
      [raw],
    ),
    [42L],
  )
  rollback()
  assert_false(heap.is_valid(object))
  for closed in [false, true] {
    if closed {
      store.close()
    }
    try
      context.jit_module.call_with_context(
        context.jit_module.get_func(0).unwrap(),
        [raw],
      )
    catch {
      JITTrap(message) => assert_true(message.contains("unreachable"))
      error => fail(error.to_string())
    } noraise {
      _ => fail("a discarded struct view remained usable")
    }
  }
}
