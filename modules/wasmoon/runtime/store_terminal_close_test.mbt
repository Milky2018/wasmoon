///|
fn closed_store_result(
  action : () -> Unit raise @runtime.RuntimeError,
) -> String {
  try action() catch {
    error => error.to_string()
  } noraise {
    _ => "accepted"
  }
}

///|
test "Store close is terminal for resource creation" {
  let store = @runtime.Store::Store()
  let memory = @runtime.Memory::Memory(1, None)
  store.close()
  let results = [
    closed_store_result(() => store.enable_c_heap()),
    closed_store_result(() => {
      store.alloc_func({ locals: [], body: [] }) |> ignore
    }),
    closed_store_result(() => store.alloc_host_func(fn(_args) { [] }) |> ignore),
    closed_store_result(() => {
      store.alloc_table(@runtime.Table::Table(@types.FuncRef, 0, None))
      |> ignore
    }),
    closed_store_result(() => store.alloc_mem(memory) |> ignore),
    closed_store_result(() => {
      store.alloc_global(
        @runtime.GlobalInstance::GlobalInstance(
          { value_type: I32, mutable: false },
          I32(0),
        ),
      )
      |> ignore
    }),
    closed_store_result(() => {
      store.alloc_tag({ params: [], results: [] }) |> ignore
    }),
    closed_store_result(() => store.alloc_exn(0, []) |> ignore),
    closed_store_result(() => store.alloc_struct(0, []) |> ignore),
    closed_store_result(() => store.alloc_array(0, []) |> ignore),
    closed_store_result(() => {
      store.register_instance(@runtime.ModuleInstance::ModuleInstance())
      |> ignore
    }),
  ]
  debug_inspect(
    results,
    content=(
      #|[
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|]
    ),
  )
}

///|
test "Store close is terminal for retained state mutation" {
  let store = @runtime.Store::Store()
  store.close()
  let results = [
    closed_store_result(() => store.set_module_types([])),
    closed_store_result(() => store.wrap_as_extern(I32(0)) |> ignore),
    closed_store_result(() => store.set_wasi_mem_addr(0)),
    closed_store_result(() => store.set_wasi_ctx_handle(1)),
    closed_store_result(() => store.struct_set(0, 0, I32(0))),
    closed_store_result(() => store.array_set(0, 0, I32(0))),
    closed_store_result(() => store.array_fill(0, 0, I32(0), 1)),
    closed_store_result(() => store.array_copy(0, 0, 0, 0, 1)),
  ]
  debug_inspect(
    results,
    content=(
      #|[
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|]
    ),
  )
}

///|
test "Linker close is terminal for registrations" {
  let linker = @runtime.Linker::Linker()
  let memory = @runtime.Memory::Memory(1, None)
  linker.close()
  let results = [
    closed_store_result(() => {
      linker.register("module", @runtime.ModuleInstance::ModuleInstance())
    }),
    closed_store_result(() => {
      linker.add_host_func("host", "func", fn(_args) { [] })
    }),
    closed_store_result(() => {
      linker.add_host_func_with_caller("host", "caller", fn(_caller, _args) {
        []
      })
    }),
    closed_store_result(() => linker.add_memory("host", "memory", memory)),
    closed_store_result(() => {
      linker.add_table(
        "host",
        "table",
        @runtime.Table::Table(@types.FuncRef, 0, None),
      )
    }),
    closed_store_result(() => {
      linker.add_global(
        "host",
        "global",
        @runtime.GlobalInstance::GlobalInstance(
          { value_type: I32, mutable: false },
          I32(0),
        ),
      )
    }),
  ]
  debug_inspect(
    results,
    content=(
      #|[
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|  "store is closed",
      #|]
    ),
  )
}

///|
test "closing an aliased Store closes the Linker mutation boundary" {
  let linker = @runtime.Linker::Linker()
  linker.get_store().close()
  inspect(
    closed_store_result(() => {
      linker.register("module", @runtime.ModuleInstance::ModuleInstance())
    }),
    content="store is closed",
  )
}

///|
test "Store close seals previously borrowed native execution state" {
  let store = @runtime.Store::Store()
  let state = store.native_execution_state()
  let releases = [0]
  store.close()
  let result = try {
    state.begin(release=fn() { releases[0] = releases[0] + 1 }) |> ignore
    "accepted"
  } catch {
    error => error.to_string()
  } noraise {
    result => result
  }
  debug_inspect(
    (result, releases[0], state.active_depth(), state.live_count()),
    content="(\"ExecutionStateSealed\", 0, 0, 0)",
  )
}
