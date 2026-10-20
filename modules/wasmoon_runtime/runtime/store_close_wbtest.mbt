///|
test "Store close releases owned state and is idempotent" {
  let store = Store::with_c_heap()
  let memory = Memory::Memory(1, None)
  store.alloc_mem(memory) |> ignore
  store.alloc_mem(memory) |> ignore
  store.alloc_host_func(fn(_args) {
    store.get_wasi_ctx_handle() |> ignore
    []
  })
  |> ignore
  debug_inspect(
    (
      store.funcs.length(),
      store.mems.length(),
      store.native_heap() is Some(_),
      store.closed.val,
    ),
    content="(1, 1, true, false)",
  )
  store.close()
  store.close()
  debug_inspect(
    (
      store.funcs.length(),
      store.mems.length(),
      store.instances.length(),
      store.native_heap() is Some(_),
      store.closed.val,
    ),
    content="(0, 0, 0, false, true)",
  )
}

///|
test "Linker close releases its modules and store" {
  let linker = Linker::Linker()
  linker.register("empty", linker.get_store().host_exports([]))
  linker.close()
  linker.close()
  debug_inspect(
    (linker.modules.length(), linker.store.closed.val),
    content="(0, true)",
  )
}
