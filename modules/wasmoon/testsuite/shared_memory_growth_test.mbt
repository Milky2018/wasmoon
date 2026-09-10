///|
test "shared growth serializes native and guest callers without moving backing" {
  for native in [false, true] {
    for wide in [false, true] {
      for custom_pages in [false, true] {
        let address_type = if wide { "i64" } else { "i32" }
        let memory_type = if wide { "i64" } else { "" }
        let initial = if custom_pages { 64 } else { 1 }
        let maximum = initial + 201
        let pages = if custom_pages { "(pagesize 1)" } else { "" }
        let extension = if wide { "" } else { "i64.extend_i32_u" }
        let page_bytes = if custom_pages { 1 } else { 65536 }
        let source =
          #|(module
          #| (memory (export "memory") MEMTYPE INITIAL MAXIMUM shared PAGES)
          #| (func (export "run") (result i64 i32)
          #|  (local $count i32) (local $sum i64)
          #|  ADDR.const 16 i32.const 1 i32.atomic.store
          #|  (loop $ready ADDR.const 20 i32.atomic.load i32.eqz br_if $ready)
          #|  i32.const 100 local.set $count
          #|  (loop $grow
          #|   local.get $sum ADDR.const 1 memory.grow EXTEND i64.add local.set $sum
          #|   local.get $count i32.const 1 i32.sub local.tee $count br_if $grow)
          #|  ADDR.const 24 i32.const 1 i32.atomic.store
          #|  (loop $done ADDR.const 28 i32.atomic.load i32.eqz br_if $done)
          #|  local.get $sum
          #|  memory.size ADDR.const BYTES ADDR.mul ADDR.const 1 ADDR.sub i32.load8_u))
        let source = source
          .replace_all(old="MEMTYPE", new=memory_type)
          .replace_all(old="INITIAL", new=initial.to_string())
          .replace_all(old="MAXIMUM", new=maximum.to_string())
          .replace_all(old="PAGES", new=pages)
          .replace_all(old="ADDR", new=address_type)
          .replace_all(old="EXTEND", new=extension)
          .replace_all(old="BYTES", new=page_bytes.to_string())
        let mod = @wat.parse(source)
        @validator.validate_module(mod)
        let store = @runtime.Store::with_c_heap()
        let linker = @runtime.Linker::with_store(store)
        defer linker.close()
        let instance = @executor.instantiate_with_linker(linker, "grow", mod)
        let memory = store.get_mem(instance.mem_addrs[0])
        let context = if native {
          Some(prepare_async_jit_context(mod, instance, store))
        } else {
          None
        }
        defer (if context is Some(context) { context.close() })
        let worker = Ref(
          @native_test_support.memory_growth_start(memory.desc_ptr(), 100),
        )
        guard worker.val != 0L else {
          fail("could not start native growth worker")
        }
        defer @native_test_support.memory_growth_finish(worker.val, 1) |> ignore
        let values = match context {
          Some(context) => context.call_core_func(store, instance, 0, [])
          None => @executor.call_exported_func(store, instance, "run", [])
        }
        let worker_sum = @native_test_support.memory_growth_finish(
          worker.val,
          0,
        )
        worker.val = 0L
        guard values is [I64(guest_sum), I32(last_byte)] else {
          fail("unexpected growth result")
        }
        inspect(last_byte, content="0")
        assert_eq(guest_sum + worker_sum, 201L * initial.to_int64() + 20100L)
        assert_eq(memory.byte_len(), maximum.to_int64() * page_bytes.to_int64())
      }
    }
  }
}
