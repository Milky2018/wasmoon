///|
test "acyclic object reads keep scoped roots through collection and precise quantum boundaries" {
  let source =
    #|(module
    #| (type $node (struct (field (mut i64)) (field i64)))
    #| (import "h" "collect" (func $collect))
    #| (func $read (param (ref $node)) (result i64)
    #|  local.get 0 struct.get $node 1)
    #| (func $body (param (ref $node)) (result i64)
    #|  (local $before i64)
    #|  local.get 0 struct.get $node 0 local.set $before
    #|  local.get 0 call $read drop
    #|  call $collect
    #|  local.get 0 struct.get $node 0 local.get $before i64.add)
    #| (func (export "probe") (result i64)
    #|  i64.const 42 i64.const 7 struct.new $node call $body))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for level in [0, 2, 3] {
    for quantum in [0, 1, 2, 3, 8] {
      let store = @runtime.Store::with_c_heap()
      defer store.close()
      let collections = Ref(0)
      let reclaimed : Array[Int32] = []
      let collect = store.alloc_host_func(_ => {
        collections.val += 1
        reclaimed.push(store.collect_garbage())
        []
      })
      let imports = @runtime.Imports::Imports(store)
      imports.add_func("h", "collect", collect)
      let instance = @executor.instantiate_module_with_imports(
        store, module_, imports,
      )
      let context = build_gc_root_context(
        module_,
        instance,
        store,
        enable_cancellation=true,
        opt_level=level,
      )
      defer context.close()
      context.install_hostcall_dispatcher(store, instance)
      if quantum > 0 {
        assert_true(
          context.jit_module.set_cooperative_scheduling(true, quantum~),
        )
      }
      let mut call = context.call_core_func_resumable(store, instance, 3, [])
      defer (if call is NativeCoreSuspended(_, continuation) {
        continuation.cancel()
      })
      while call is NativeCoreSuspended(CooperativeYield, continuation) {
        assert_eq(store.collect_garbage(), 0)
        call = continuation.continue_execution()
      }
      guard call is NativeCoreReturned(values) else {
        fail("scoped read did not return")
      }
      assert_eq(values, [I64(84L)])
      assert_eq(collections.val, 1)
      assert_eq(reclaimed, [0])
      assert_eq(store.collect_garbage(), 1)
    }
  }
}

///|
test "scoped acyclic roots retain a detached child across host collection" {
  let source =
    #|(module
    #| (type $child (struct (field i64)))
    #| (type $owner (struct (field (mut (ref null $child)))))
    #| (import "h" "collect" (func $collect))
    #| (func $read (param (ref $owner)) (result (ref null $child))
    #|  local.get 0 struct.get $owner 0)
    #| (func (export "probe") (param (ref $owner)) (result i64)
    #|  (local $child (ref null $child)) (local $before i64) (local $same i64)
    #|  local.get 0 struct.get $owner 0 local.tee $child struct.get $child 0 local.set $before
    #|  local.get 0 call $read local.get $child ref.eq i64.extend_i32_u local.set $same
    #|  call $collect
    #|  local.get $child struct.get $child 0 local.get $before i64.add local.get $same i64.add))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for level in [0, 2, 3] {
    let store = @runtime.Store::with_c_heap()
    defer store.close()
    let owner = Ref(-1)
    let reclaimed : Array[Int32] = []
    let collect = store.alloc_host_func(_ => {
      store.struct_set(owner.val, 0, Null)
      reclaimed.push(store.collect_garbage())
      []
    })
    let imports = @runtime.Imports::Imports(store)
    imports.add_func("h", "collect", collect)
    let instance = @executor.instantiate_module_with_imports(
      store, module_, imports,
    )
    let context = build_gc_root_context(
      module_,
      instance,
      store,
      enable_cancellation=true,
      opt_level=level,
    )
    defer context.close()
    context.install_hostcall_dispatcher(store, instance)
    let child = store.alloc_struct(0, [I64(42L)], instance~)
    owner.val = store.alloc_struct(1, [StructRef(child)], instance~)
    let lease = store.pin_gc_roots([StructRef(owner.val)])
    defer lease.release()
    assert_eq(
      context.call_core_func(store, instance, 2, [StructRef(owner.val)]),
      [I64(85L)],
    )
    assert_eq(reclaimed, [0])
    assert_eq(store.collect_garbage(), 1)
    lease.release()
    assert_eq(store.collect_garbage(), 1)
  }
}

///|
test "sparse call frames retain a detached child at a parked loop poll" {
  let source =
    #|(module
    #| (type $child (struct (field i64)))
    #| (type $owner (struct (field (mut (ref null $child)))))
    #| (global (mut i32) (i32.const 0))
    #| (func (export "probe") (param (ref $owner)) (result i64)
    #|  (local $child (ref null $child)) (local $sum i64) (local $i i32)
    #|  local.get 0 struct.get $owner 0 local.set $child
    #|  i32.const 1 global.set 0
    #|  (loop $again
    #|   local.get $sum local.get $child struct.get $child 0 i64.add local.set $sum
    #|   local.get $i i32.const 1 i32.add local.tee $i i32.const 33 i32.lt_u br_if $again)
    #|  local.get $sum))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for level in [0, 2, 3] {
    for quantum in [1, 2, 3, 8] {
      for cancel_ in [false, true] {
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
          enable_cancellation=true,
          opt_level=level,
        )
        defer context.close()
        assert_true(
          context.jit_module.set_cooperative_scheduling(true, quantum~),
        )
        let child = store.alloc_struct(0, [I64(42L)], instance~)
        let owner = store.alloc_struct(1, [StructRef(child)], instance~)
        let lease = store.pin_gc_roots([StructRef(owner)])
        defer lease.release()
        let started = store.get_global(instance.global_addrs[0])
        let mut detached = false
        let mut call = context.call_core_func_resumable(store, instance, 0, [
          StructRef(owner),
        ])
        defer (if call is NativeCoreSuspended(_, continuation) {
          continuation.cancel()
        })
        while call is NativeCoreSuspended(CooperativeYield, continuation) {
          if !detached && started.get() == I32(1) {
            store.struct_set(owner, 0, Null)
            detached = true
          }
          assert_eq(store.collect_garbage(), 0)
          if detached && cancel_ {
            continuation.cancel()
            call = NativeCoreReturned([])
            break
          }
          call = continuation.continue_execution()
        }
        assert_true(detached)
        guard call is NativeCoreReturned(values) else {
          fail("sparse rooted loop did not return")
        }
        assert_eq(values, if cancel_ { [] } else { [I64(1386L)] })
        assert_eq(store.collect_garbage(), 1)
        lease.release()
        assert_eq(store.collect_garbage(), 1)
      }
    }
  }
}
