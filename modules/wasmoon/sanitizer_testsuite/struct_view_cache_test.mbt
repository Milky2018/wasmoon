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

///|
test "subtype struct views recheck registry replacement clear and object identity" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $base (sub (struct (field i64))))
      #| (type $child (sub $base (struct (field i64) (field i32))))
      #| (type $leaf (sub $child (struct (field i64) (field i32))))
      #| (type $wrong (struct (field i64)))
      #| (func (param (ref $base) i32) (result i64) (local $value i64)
      #|  loop $read
      #|    local.get 0 struct.get $base 0 local.set $value
      #|    local.get 1 i32.const 1 i32.sub local.tee 1 br_if $read
      #|  end
      #|  local.get $value)
      #| (func (param (ref $child)) (result i32)
      #|  local.get 0 struct.get $child 1))
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
    let ids = instance.canonical_type_indices
    let mut count = 0
    for identity in ids {
      count = count.max(identity + 1)
    }
    let parents = Array::make(count, -1)
    parents[ids[1]] = ids[0]
    parents[ids[2]] = ids[1]
    let registry = @wasmoon_jit.NativeCallableRegistry::new()
    assert_true(registry.replace(parents, []))
    context.jit_module.bind_callable_registry(registry, ids[:].to_owned(), [])
    for object_type in [1, 2] {
      let object = store.alloc_struct(
        object_type,
        [I64(42L), I32(17)],
        instance~,
      )
      let roots = store.pin_gc_roots([StructRef(object)])
      defer roots.release()
      let read = fn() raise @jit.JITTrap {
        context.jit_module.call_with_context(
          context.jit_module.get_func(0).unwrap(),
          [(object + 1).to_int64() << 1, 3L],
        )
      }
      let rejected = fn(change : String) raise {
        try read() catch {
          JITTrap(message) => assert_true(message.contains("unreachable"))
          error => fail(error.to_string())
        } noraise {
          _ => fail("a stale subtype admission survived \{change}")
        }
      }
      assert_eq(read(), [42L])
      assert_eq(
        context.jit_module.call_with_context(
          context.jit_module.get_func(1).unwrap(),
          [(object + 1).to_int64() << 1],
        ),
        [17L],
      )
      assert_eq(read(), [42L])
      assert_true(registry.replace(Array::make(count, -1), []))
      rejected("parent replacement")
      // A parent sentinel is not a type, even when it equals a rebound
      // local entry. The preceding child read warmed the physical prefix.
      let missing_base = ids[:].to_owned()
      missing_base[0] = -1
      context.jit_module.bind_callable_registry(registry, missing_base, [])
      rejected("rebinding the target to a missing identity")
      let out_of_range_parents = Array::make(count, -1)
      out_of_range_parents[ids[object_type]] = count
      assert_true(registry.replace(out_of_range_parents, []))
      missing_base[0] = count
      context.jit_module.bind_callable_registry(registry, missing_base, [])
      rejected("rebinding the target to an out-of-range identity")
      context.jit_module.bind_callable_registry(registry, ids[:].to_owned(), [])
      assert_true(registry.replace(parents, []))
      assert_eq(read(), [42L])
      registry.clear()
      rejected("registry clear")
      assert_true(registry.replace(parents, []))
      assert_eq(read(), [42L])
      let heap = store.native_heap().unwrap()
      heap.set_runtime_type(object, ids[3])
      if object_type == 1 {
        // Exact physical access retains its existing semantics, but may not
        // publish a nominal subtype hint for a different runtime identity.
        assert_eq(
          context.jit_module.call_with_context(
            context.jit_module.get_func(1).unwrap(),
            [(object + 1).to_int64() << 1],
          ),
          [17L],
        )
      }
      rejected("object runtime type replacement")
      heap.set_runtime_type(object, ids[object_type])
      assert_eq(read(), [42L])
      assert_true(heap.verify())
    }
  }
}
