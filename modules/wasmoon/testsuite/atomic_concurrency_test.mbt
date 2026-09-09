///|
test "guest atomic increments compose with an independent native thread" {
  for native in [false, true] {
    for wide in [false, true] {
      let instruction = if wide { "i64" } else { "i32" }
      let source =
        #|(module
        #| (memory (export "memory") 1 1 shared)
        #| (func (export "run") (param $count i32)
        #|  i32.const 16 i32.const 1 i32.atomic.store
        #|  (loop $ready i32.const 20 i32.atomic.load i32.eqz br_if $ready)
        #|  (loop $again
        #|   i32.const 0 VALUE.const 1 VALUE.atomic.rmw.add drop
        #|   local.get $count i32.const 1 i32.sub local.tee $count br_if $again)))
      let mod = @wat.parse(source.replace_all(old="VALUE", new=instruction))
      @validator.validate_module(mod)
      let store = @runtime.Store::with_c_heap()
      let linker = @runtime.Linker::with_store(store)
      defer linker.close()
      let instance = @executor.instantiate_with_linker(linker, "counter", mod)
      let memory = store.get_mem(instance.mem_addrs[0])
      let context = if native {
        Some(prepare_async_jit_context(mod, instance, store))
      } else {
        None
      }
      defer (if context is Some(context) { context.close() })
      let width = if wide { 8 } else { 4 }
      let worker = Ref(
        @native_test_support.atomic_counter_start(
          memory.desc_ptr(),
          width,
          1000000,
        ),
      )
      guard worker.val != 0L else {
        fail("could not start native counter worker")
      }
      defer @native_test_support.atomic_counter_finish(worker.val, 1)
      match context {
        Some(context) =>
          context.call_core_func(store, instance, 0, [I32(100000)]) |> ignore
        None =>
          @executor.call_exported_func(store, instance, "run", [I32(100000)])
          |> ignore
      }
      @native_test_support.atomic_counter_finish(worker.val, 0)
      worker.val = 0L
      inspect(memory.atomic_load(0L, width), content="1100000")
    }
  }
}
