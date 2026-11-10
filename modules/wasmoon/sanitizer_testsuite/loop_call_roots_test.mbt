///|
test "collecting loop calls retain escaping references and mutable field writes" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $node (struct (field (mut i64))))
      #| (type $child (struct (field (mut i64))))
      #| (import "h" "collect" (func $collect (param (ref $child))))
      #| (func $worker (param (ref $node)) (result i64)
      #|  (local $i i32) (local $keep (ref null $child)) (local $result i64)
      #|  loop $step
      #|    local.get $i i64.extend_i32_s i64.const 40 i64.add
      #|    struct.new $child local.set $keep
      #|    local.get $keep ref.as_non_null call $collect
      #|    local.get 0 local.get 0 struct.get $node 0 i64.const 1 i64.add struct.set $node 0
      #|    local.get $keep struct.get $child 0 local.set $result
      #|    local.get $i i32.const 1 i32.add local.tee $i i32.const 3 i32.lt_u br_if $step
      #|  end
      #|  local.get $result)
      #| (func (export "probe") (param (ref $node)) (result i64)
      #|  (local $i i32) (local $sum i64)
      #|  loop $repeat
      #|    local.get $sum local.get 0 call $worker i64.add local.set $sum
      #|    local.get $i i32.const 1 i32.add local.tee $i i32.const 2 i32.lt_u br_if $repeat
      #|  end
      #|  local.get $sum local.get 0 struct.get $node 0 i64.add))
    ),
  )
  @validator.validate_module(module_)
  for level in [0, 2, 3] {
    for polling in [false, true] {
      let store = @runtime.Store::with_c_heap()
      defer store.close()
      let observed : Array[Int32] = []
      // The unknown writer makes this object escape scalar promotion. The
      // guest must read its changed payload after the collecting host call.
      let collect = store.alloc_host_func(
        args => {
          guard args is [StructRef(child)] else { raise TypeMismatch }
          observed.push(store.collect_garbage())
          guard store.struct_get(child, 0) is I64(value) else {
            raise TypeMismatch
          }
          store.struct_set(child, 0, I64(value + 100L))
          []
        },
        func_type={ params: [RefStruct(1)], results: [], },
      )
      let imports = @runtime.Imports(store)
      imports.add_func("h", "collect", collect)
      let instance = @executor.instantiate_module_with_imports(
        store, module_, imports,
      )
      let context = build_gc_root_context(
        module_,
        instance,
        store,
        opt_level=level,
        enable_cancellation=polling,
      )
      defer context.close()
      context.install_hostcall_dispatcher(store, instance)
      let object = store.alloc_struct(0, [I64(0L)], instance~)
      let lease = store.pin_gc_roots([StructRef(object)])
      defer lease.release()
      let heap = store.native_heap().unwrap()
      let before = heap.get_total_allocations()
      assert_eq(
        context.call_core_func(store, instance, 2, [StructRef(object)]),
        [I64(290L)],
      )
      assert_eq(heap.get_total_allocations() - before, 6)
      assert_eq(observed, [0, 1, 1, 1, 1, 1])
      assert_eq(store.struct_get(object, 0), I64(6L))
      assert_eq(store.collect_garbage(), 1)
      assert_true(heap.verify())
      lease.release()
      assert_eq(store.collect_garbage(), 1)
    }
  }
}
