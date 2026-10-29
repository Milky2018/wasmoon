///|
fn array_view_module() -> @types.Module raise {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $a (array (mut i64)))
      #| (type $bytes (array (mut i8)))
      #| (func (param (ref $a)) (result i64)
      #|   local.get 0 i32.const 0 array.get $a
      #|   local.get 0 i32.const 1 array.get $a i64.add))
    ),
  )
  @validator.validate_module(module_)
  module_
}

///|
test "array metadata views observe writes growth and relocating collection" {
  let module_ = array_view_module()
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
    store.alloc_array(0, [I64(99L)], instance~) |> ignore
    let object = store.alloc_array(0, [I64(35L), I64(7L)], instance~)
    let roots = store.pin_gc_roots([ArrayRef(object)])
    defer roots.release()
    let read = fn() -> Array[Int64] raise @jit.JITTrap {
      context.jit_module.call_with_context(
        context.jit_module.get_func(0).unwrap(),
        [(object + 1).to_int64() << 1],
      )
    }
    assert_eq(read(), [42L])
    store.array_set(object, 0, I64(17L))
    assert_eq(read(), [24L])
    let offset = heap.get_offset(object)
    assert_eq(store.collect_garbage(), 1)
    assert_true(heap.get_offset(object) < offset)
    assert_eq(read(), [24L])
    assert_true(
      heap
      .get_ptr()
      .define_layout(instance.canonical_type_indices[1], [1], true),
    )
    let capacity = heap.get_capacity()
    heap.alloc_array(
      1,
      (capacity + 64L).to_int(),
      I32(0),
      runtime_type=instance.canonical_type_indices[1],
    )
    |> ignore
    assert_true(heap.get_capacity() > capacity)
    assert_eq(read(), [24L])
    store.array_set(object, 1, I64(25L))
    assert_eq(read(), [42L])
    assert_true(heap.verify())
  }
}

///|
test "array metadata views do not root discarded objects or escape Store close" {
  let module_ = array_view_module()
  for rollback in [false, true] {
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
    let undo = heap.make_allocation_rollback(fn() { [] })
    let object = store.alloc_array(0, [I64(35L), I64(7L)], instance~)
    let read = fn() -> Array[Int64] raise @jit.JITTrap {
      context.jit_module.call_with_context(
        context.jit_module.get_func(0).unwrap(),
        [(object + 1).to_int64() << 1],
      )
    }
    assert_eq(read(), [42L])
    if rollback {
      undo()
    } else {
      assert_eq(store.collect_garbage(), 1)
    }
    assert_false(heap.is_valid(object))
    assert_true(heap.verify())
    for closed in [false, true] {
      if closed {
        store.close()
      }
      try read() catch {
        JITTrap(_) => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("a discarded array metadata view remained usable")
      }
    }
  }
}
