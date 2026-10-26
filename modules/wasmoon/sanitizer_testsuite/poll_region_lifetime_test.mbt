///|
test "budget protected loops preserve exact yields and views across relocating callbacks" {
  let module_ = @wat.parse(
    (
      #|(module
      #| (type $a (array (mut i32)))
      #| (type $s (struct (field (mut (ref $a))) (field (mut i32))))
      #| (func $leaf (param i32) (result i32) local.get 0)
      #| (func (export "run") (param $s (ref $s)) (result i32)
      #|  (local $i i32) (local $sum i32) (local $old (ref null $a))
      #|  loop $again
      #|   local.get $i i32.const 41 i32.lt_u
      #|   if
      #|    local.get $s struct.get $s 0 local.tee $old
      #|    i32.const 0 array.get $a call $leaf
      #|    local.get $sum i32.add
      #|    local.get $old array.len i32.add local.set $sum
      #|    local.get $s struct.get $s 0 array.len drop
      #|    local.get $i i32.const 1 i32.add local.set $i
      #|    br $again
      #|   end
      #|  end
      #|  local.get $sum local.get $s struct.get $s 1 i32.add))
    ),
  )
  @validator.validate_module(module_)
  let traces : Array[Array[(Int32, Array[@types.Value])]] = []
  for opt_level in [0, 2] {
    let results : Array[(Int32, Array[@types.Value])] = []
    for quantum in [1, 2, 3, 5, 17, 1024] {
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
        opt_level~,
        enable_cancellation=true,
      )
      defer context.close()
      store.alloc_array(0, [I32(99)], instance~) |> ignore
      let array = store.alloc_array(0, [I32(3), I32(7)], instance~)
      let holder = store.alloc_struct(1, [ArrayRef(array), I32(0)], instance~)
      let roots = store.pin_gc_roots([StructRef(holder)])
      defer roots.release()
      assert_true(context.jit_module.set_cooperative_scheduling(true, quantum~))
      let mut outcome = context.call_core_func_resumable(store, instance, 1, [
        StructRef(holder),
      ])
      let mut yields = 0
      while outcome is NativeCoreSuspended(CooperativeYield, continuation) {
        yields += 1
        let replacement = store.alloc_array(
          0,
          Array::make(1 + yields % 3, I32(3 + yields)),
          instance~,
        )
        store.struct_set(holder, 0, ArrayRef(replacement))
        store.struct_set(holder, 1, I32(yields))
        store.collect_garbage() |> ignore
        assert_true(store.native_heap().unwrap().verify())
        outcome = continuation.continue_execution()
      }
      guard outcome is NativeCoreReturned(values) else {
        fail("unexpected native loop suspension")
      }
      if quantum == 1024 {
        assert_eq(yields, 0)
        assert_eq(values, [I32(205)])
      }
      results.push((yields, values))
    }
    traces.push(results)
  }
  assert_eq(traces[0], traces[1])
}
