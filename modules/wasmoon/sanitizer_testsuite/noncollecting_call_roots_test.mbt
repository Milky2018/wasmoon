///|
test "noncollecting local call chains keep live returned references across host collection" {
  let source =
    #|(module
    #| (type $child (struct (field i64)))
    #| (type $owner (struct (field (mut (ref null $child)))))
    #| (import "h" "collect" (func $collect))
    #| (func $read (param (ref $owner)) (result (ref null $child))
    #|  local.get 0 struct.get $owner 0 ref.is_null
    #|  if (result (ref null $child)) ref.null $child
    #|  else local.get 0 struct.get $owner 0 end)
    #| (func $chain (param (ref $owner)) (result (ref null $child))
    #|  local.get 0 call $read)
    #| (func (export "probe") (param (ref $owner)) (result i64)
    #|  (local $saved (ref null $child))
    #|  local.get 0 call $chain local.set $saved
    #|  call $collect local.get $saved struct.get $child 0))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for level in [0, 2, 3] {
    for polling in [false, true] {
      for with_child in [false, true] {
        let store = @runtime.Store::with_c_heap()
        defer store.close()
        let owner = Ref(-1)
        let observed : Array[Int32] = []
        let collect = store.alloc_host_func(_ => {
          store.struct_set(owner.val, 0, Null)
          observed.push(store.collect_garbage())
          []
        })
        let imports = @runtime.Imports(store)
        imports.add_func("h", "collect", collect)
        let instance = @executor.instantiate_module_with_imports(
          store, module_, imports,
        )
        let context = build_gc_root_context(
          module_,
          instance,
          store,
          enable_cancellation=polling,
          opt_level=level,
        )
        defer context.close()
        context.install_hostcall_dispatcher(store, instance)
        let child : @types.Value = if with_child {
          StructRef(store.alloc_struct(0, [I64(42L)], instance~))
        } else {
          Null
        }
        owner.val = store.alloc_struct(1, [child], instance~)
        let lease = store.pin_gc_roots([StructRef(owner.val)])
        defer lease.release()
        if with_child {
          assert_eq(
            context.call_core_func(store, instance, 3, [StructRef(owner.val)]),
            [I64(42L)],
          )
        } else {
          try
            context.call_core_func(store, instance, 3, [StructRef(owner.val)])
            |> ignore
          catch {
            Trap(message) => assert_true(message.has_prefix("null reference"))
            error => fail(error.to_string())
          } noraise {
            _ => fail("null child returned")
          }
        }
        assert_eq(observed, [0])
        assert_eq(store.collect_garbage(), if with_child { 1 } else { 0 })
        lease.release()
        assert_eq(store.collect_garbage(), 1)
        assert_true(store.native_heap().unwrap().verify())
      }
    }
  }
}

///|
test "noncollecting calls retain results at allocation fallback and every logical allocation" {
  let source =
    #|(module
    #| (type $child (struct (field i64)))
    #| (type $owner (struct (field (ref $child))))
    #| (type $temporary (struct (field i32)))
    #| (func $read (param (ref $owner)) (result (ref $child))
    #|  local.get 0 struct.get $owner 0)
    #| (func $chain (param (ref $owner)) (result (ref $child))
    #|  local.get 0 call $read)
    #| (func (export "probe") (param (ref $owner)) (result i64)
    #|  (local $saved (ref null $child)) (local $sum i64) (local $i i32)
    #|  local.get 0 call $chain local.set $saved
    #|  (loop $again
    #|   local.get $i struct.new $temporary drop
    #|   local.get $sum local.get $saved struct.get $child 0 i64.add local.set $sum
    #|   local.get $i i32.const 1 i32.add local.tee $i i32.const 100 i32.lt_u br_if $again)
    #|  local.get $sum))
  let module_ = @wat.parse(source)
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
    let child = store.alloc_struct(0, [I64(42L)], instance~)
    let owner = store.alloc_struct(1, [StructRef(child)], instance~)
    let heap = store.native_heap().unwrap()
    let before = heap.get_total_allocations()
    set_allocation_budget(heap.get_ptr(), 128L)
    assert_eq(context.call_core_func(store, instance, 2, [StructRef(owner)]), [
      I64(4200L),
    ])
    assert_eq(heap.get_total_allocations() - before, 100)
    assert_true(heap.get_total_collections() > 0)
    assert_eq(store.struct_get(child, 0), I64(42L))
    assert_true(heap.verify())
  }
}

///|
test "noncollecting mutable call chains invalidate field values" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $node (struct (field (mut i64))))
      #| (func $write (param (ref $node))
      #|  local.get 0 i64.const 9 struct.set $node 0)
      #| (func $chain (param (ref $node)) local.get 0 call $write)
      #| (func (export "probe") (param (ref $node)) (result i64)
      #|  (local $before i64)
      #|  local.get 0 struct.get $node 0 local.set $before
      #|  local.get 0 call $chain
      #|  local.get 0 struct.get $node 0 local.get $before i64.add))
    ),
  )
  @validator.validate_module(module_)
  for level in [0, 2, 3] {
    for polling in [false, true] {
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
        enable_cancellation=polling,
        opt_level=level,
      )
      defer context.close()
      let object = store.alloc_struct(0, [I64(42L)], instance~)
      assert_eq(
        context.call_core_func(store, instance, 2, [StructRef(object)]),
        [I64(51L)],
      )
      assert_eq(store.struct_get(object, 0), I64(9L))
      assert_true(store.native_heap().unwrap().verify())
    }
  }
}

///|
test "read-only call values keep first traps and refresh after host mutation and collection" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $node (struct (field (mut i64))))
      #| (import "h" "mutate" (func $mutate))
      #| (func $read (param (ref $node)) (result i64)
      #|  local.get 0 struct.get $node 0)
      #| (func $chain (param (ref $node)) (result i64) local.get 0 call $read)
      #| (func (export "probe") (param (ref null $node)) (result i64)
      #|  (local $sum i64)
      #|  local.get 0 struct.get $node 0 drop
      #|  local.get 0 ref.as_non_null call $chain
      #|  local.get 0 ref.as_non_null call $chain i64.add local.set $sum
      #|  call $mutate
      #|  local.get 0 ref.as_non_null call $chain local.get $sum i64.add))
    ),
  )
  @validator.validate_module(module_)
  for level in [0, 2, 3] {
    for polling in [false, true] {
      for null in [false, true] {
        let store = @runtime.Store::with_c_heap()
        defer store.close()
        let object = Ref(-1)
        let calls = Ref(0)
        let mutate = store.alloc_host_func(_ => {
          calls.val += 1
          store.struct_set(object.val, 0, I64(9L))
          store.collect_garbage() |> ignore
          []
        })
        let imports = @runtime.Imports(store)
        imports.add_func("h", "mutate", mutate)
        let instance = @executor.instantiate_module_with_imports(
          store, module_, imports,
        )
        let context = build_gc_root_context(
          module_,
          instance,
          store,
          enable_cancellation=polling,
          opt_level=level,
        )
        defer context.close()
        context.install_hostcall_dispatcher(store, instance)
        object.val = store.alloc_struct(0, [I64(42L)], instance~)
        if null {
          try
            context.call_core_func(store, instance, 3, [Null]) |> ignore
          catch {
            Trap(message) => assert_true(message.has_prefix("null reference"))
            error => fail(error.to_string())
          } noraise {
            _ => fail("first null trap disappeared")
          }
          assert_eq(calls.val, 0)
        } else {
          assert_eq(
            context.call_core_func(store, instance, 3, [StructRef(object.val)]),
            [I64(93L)],
          )
          assert_eq(calls.val, 1)
          assert_eq(store.struct_get(object.val, 0), I64(9L))
        }
        assert_true(store.native_heap().unwrap().verify())
      }
    }
  }
}
