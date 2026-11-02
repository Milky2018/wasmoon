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

///|
test "array view entries expire together across compaction and payload growth" {
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
    assert_true(
      heap
      .get_ptr()
      .define_layout(instance.canonical_type_indices[1], [1], true),
    )
    for _ in 0..<12 {
      store.alloc_array(0, [I64(-1L)], instance~) |> ignore
    }
    let objects = Array::makei(20, index => {
      store.alloc_array(0, [I64(index.to_int64()), I64(7L)], instance~)
    })
    let roots = store.pin_gc_roots(objects.map(object => ArrayRef(object)))
    defer roots.release()
    let read_all = fn() raise {
      for index, object in objects {
        assert_eq(
          context.jit_module.call_with_context(
            context.jit_module.get_func(0).unwrap(),
            [(object + 1).to_int64() << 1],
          ),
          [index.to_int64() + 7L],
        )
      }
    }
    read_all()
    assert_eq(store.collect_garbage(), 12)
    assert_true(heap.verify())
    read_all()
    let capacity = heap.get_capacity()
    heap.alloc_array(
      1,
      (capacity + 64L).to_int(),
      I32(0),
      runtime_type=instance.canonical_type_indices[1],
    )
    |> ignore
    assert_true(heap.get_capacity() > capacity)
    assert_true(heap.verify())
    read_all()
  }
}

///|
test "loop array projections preserve alternating reference keys and writes" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $a (array (mut i32)))
      #| (func (param (ref $a) (ref $a)) (result i32) (local $i i32) (local $sum i32)
      #|   loop $next
      #|     local.get $sum
      #|     local.get $i i32.const 1 i32.and
      #|     if (result (ref $a)) local.get 0 else local.get 1 end
      #|     i32.const 0 array.get $a i32.add local.set $sum
      #|     local.get $i i32.const 1 i32.add local.tee $i i32.const 12 i32.lt_u
      #|     br_if $next
      #|   end
      #|   local.get $sum)
      #| (func (param (ref $a)) (result i32)
      #|   local.get 0 i32.const 0 array.get $a))
    ),
  )
  @validator.validate_module(module_)
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
    let a = store.alloc_array(0, [I32(3)], instance~)
    let first_root = store.pin_gc_roots([ArrayRef(a)])
    defer first_root.release()
    for _ in 0..<15 {
      store.alloc_array(0, [I32(-1)], instance~) |> ignore
    }
    let b = store.alloc_array(0, [I32(5)], instance~)
    let roots = store.pin_gc_roots([ArrayRef(a), ArrayRef(b)])
    defer roots.release()
    context.jit_module.call_with_context(
      context.jit_module.get_func(1).unwrap(),
      [(a + 1).to_int64() << 1],
    )
    |> ignore
    let sum = fn() -> Array[Int64] raise @jit.JITTrap {
      context.jit_module.call_with_context(
        context.jit_module.get_func(0).unwrap(),
        [(a + 1).to_int64() << 1, (b + 1).to_int64() << 1],
      )
    }
    assert_eq(sum(), [48L])
    store.array_set(a, 0, I32(7))
    assert_eq(sum(), [72L])
    assert_true(store.native_heap().unwrap().verify())
  }
}
