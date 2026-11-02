///|
test "struct view entries expire together across compaction and payload growth" {
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
    assert_true(
      heap
      .get_ptr()
      .define_layout(instance.canonical_type_indices[2], [1], true),
    )
    for _ in 0..<12 {
      store.alloc_struct(0, [I64(-1L), I64(0L)], instance~) |> ignore
    }
    let objects = Array::makei(20, index => {
      store.alloc_struct(0, [I64(index.to_int64()), I64(0L)], instance~)
    })
    let roots = store.pin_gc_roots(objects.map(object => StructRef(object)))
    defer roots.release()
    let read_all = fn() raise {
      for index, object in objects {
        assert_eq(
          context.jit_module.call_with_context(
            context.jit_module.get_func(0).unwrap(),
            [(object + 1).to_int64() << 1],
          ),
          [index.to_int64()],
        )
      }
    }
    read_all()
    assert_eq(store.collect_garbage(), 12)
    assert_true(heap.verify())
    read_all()
    let capacity = heap.get_capacity()
    heap.alloc_array(
      2,
      (capacity + 64L).to_int(),
      I32(0),
      runtime_type=instance.canonical_type_indices[2],
    )
    |> ignore
    assert_true(heap.get_capacity() > capacity)
    assert_true(heap.verify())
    read_all()
  }
}

///|
test "loop struct projections reject equal-width foreign nominal hints" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (rec (type $node (struct (field i64) (field (ref null $node)))))
      #| (type $other (struct (field f64) (field (ref null $node))))
      #| (func (param (ref null $node)) (result i64) (local $sum i64)
      #|   block $done
      #|     loop $walk
      #|       local.get 0 ref.is_null br_if $done
      #|       local.get $sum local.get 0 ref.as_non_null struct.get $node 0
      #|       i64.add local.set $sum
      #|       local.get 0 ref.as_non_null struct.get $node 1 local.set 0
      #|       br $walk
      #|     end
      #|   end
      #|   local.get $sum)
      #| (func (param (ref $other)) (result f64)
      #|   local.get 0 struct.get $other 0))
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
    let good = store.alloc_struct(0, [I64(42L), Null], instance~)
    let other = store.alloc_struct(1, [F64(3.0), Null], instance~)
    let sum = fn(object : Int32) -> Array[Int64] raise @jit.JITTrap {
      context.jit_module.call_with_context(
        context.jit_module.get_func(0).unwrap(),
        [(object + 1).to_int64() << 1],
      )
    }
    assert_eq(sum(good), [42L])
    context.jit_module.call_with_context(
      context.jit_module.get_func(1).unwrap(),
      [(other + 1).to_int64() << 1],
    )
    |> ignore
    try sum(other) catch {
      JITTrap(message) => assert_true(message.contains("unreachable"))
      error => fail(error.to_string())
    } noraise {
      _ => fail("a cached foreign nominal layout entered a typed loop")
    }
    assert_eq(sum(good), [42L])
  }
}
