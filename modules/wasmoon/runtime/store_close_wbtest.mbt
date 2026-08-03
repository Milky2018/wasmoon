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
  let before = store.allocation_stats()
  debug_inspect(
    (before.funcs, before.mems, store.c_heap is Some(_), store.closed.val),
    content="(1, 2, true, false)",
  )
  store.close()
  store.close()
  let after = store.allocation_stats()
  debug_inspect(
    (
      after.funcs,
      after.mems,
      after.instances,
      store.c_heap is Some(_),
      store.closed.val,
    ),
    content="(0, 0, 0, false, true)",
  )
}

///|
test "Linker close releases its modules and store" {
  let linker = Linker::Linker()
  linker.register("empty", ModuleInstance())
  linker.close()
  linker.close()
  debug_inspect(
    (linker.modules.length(), linker.store.closed.val),
    content="(0, true)",
  )
}
