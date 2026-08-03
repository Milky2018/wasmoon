///|
test "aborted Linker instantiation never publishes Store or name state" {
  let linker = @runtime.Linker::Linker()
  let store = linker.get_store()
  let instantiation = linker.begin_instantiation()
  let func_addr = store.alloc_func({ locals: [], body: [] })
  linker.register("staged", ModuleInstance())
  debug_inspect(
    (
      store.allocation_stats().funcs,
      store.get_func_inst_opt(func_addr) is Some(_),
      linker.get_module("staged") is Some(_),
    ),
    content="(0, true, true)",
  )
  instantiation.discard()
  debug_inspect(
    (
      store.allocation_stats().funcs,
      store.get_func_inst_opt(func_addr) is None,
      linker.get_module("staged") is None,
    ),
    content="(0, true, true)",
  )
  linker.close()
}

///|
test "committed Linker instantiation publishes once" {
  let linker = @runtime.Linker::Linker()
  let store = linker.get_store()
  let instantiation = linker.begin_instantiation()
  let func_addr = store.alloc_func({ locals: [], body: [] })
  linker.register("committed", ModuleInstance())
  instantiation.commit()
  debug_inspect(
    (
      store.allocation_stats().funcs,
      store.get_func_inst_opt(func_addr) is Some(_),
      linker.get_module("committed") is Some(_),
    ),
    content="(1, true, true)",
  )
  instantiation.commit()
  debug_inspect(store.allocation_stats().funcs, content="1")
  linker.close()
}

///|
test "aborting restores ownership of pre-existing unowned functions" {
  let linker = @runtime.Linker::Linker()
  let store = linker.get_store()
  let func_addr = store.alloc_func({ locals: [], body: [] })
  let instance = @runtime.ModuleInstance()
  instance.func_addrs.push(func_addr)
  let instantiation = linker.begin_instantiation()
  store.register_instance(instance) |> ignore
  debug_inspect(
    (store.get_func_owner_idx(func_addr), instance.store_idx),
    content="(0, 0)",
  )
  instantiation.discard()
  debug_inspect(
    (store.get_func_owner_idx(func_addr), instance.store_idx),
    content="(-1, -1)",
  )
  linker.close()
}

///|
test "a Linker instantiation does not affect another Linker" {
  let linker_a = @runtime.Linker::Linker()
  let instantiation = linker_a.begin_instantiation()
  let linker_b = @runtime.Linker::Linker()
  linker_b.register("kept", ModuleInstance())
  instantiation.discard()
  debug_inspect(linker_b.get_module("kept") is Some(_), content="true")
  linker_a.close()
  linker_b.close()
}
