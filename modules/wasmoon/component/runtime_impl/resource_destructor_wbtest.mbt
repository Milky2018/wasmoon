///|
test "resource destructor dispatch restores task context on return and trap" {
  for traps in [false, true] {
    let state = AsyncState(StreamTable())
    let caller = alloc_task_id(state)
    init_task_meta(state, caller, 11, 0L)
    state.tasks.write_task_contexts(caller, Map([(0, I32(1234))]))
    push_task(state, caller, true)
    let store = @runtime.Store::Store()
    defer store.close()
    let observed : Array[(Int?, Bool, Bool)] = []
    let engine = CoreExecutionEngine(fn(_, _, _) { () }, fn(
      _,
      _,
      _,
      _,
      _,
    ) raise ComponentRuntimeError {
      let task = current_task_id(state)
      observed.push(
        (
          state.tasks.read_task_instance(task),
          state.tasks.read_task_contexts(task) is None,
          state.task_can_block[0],
        ),
      )
      state.tasks.write_task_contexts(task, Map([(0, I32(999))]))
      if traps {
        raise CanonCallError("destructor failed")
      }
      Returned([])
    })
    let base = alloc_host_core_func(store, { params: [I32], results: [], }, fn(
      _,
    ) {
      []
    })
    let resource : ResourceHandle = {
      type_id: 1,
      rep: 42,
      dtor: Some({ ..base, engine, }),
      host_dtor: None,
      kind: GuestDefined,
      impl_component_id: 77,
      own: true,
      borrow_scope: None,
      num_lends: [0],
    }
    let error = try {
      call_resource_destructor(state, store, resource)
      None
    } catch {
      error => Some(error.to_string())
    }
    debug_inspect(
      error,
      content=if traps {
        "Some(\"CanonCallError(\\\"destructor failed (core store_idx=-1 func_idx=0)\\\")\")"
      } else {
        "None"
      },
    )
    debug_inspect(observed, content="[(Some(77), true, false)]")
    inspect(current_task_id(state) == caller, content="true")
    inspect(state.task_can_block[0], content="true")
    debug_inspect(
      state.tasks.read_task_contexts(caller).unwrap().get(0),
      content="Some(I32(1234))",
    )
    inspect(state.tasks.records.length(), content="1")
    pop_task(state)
    retire_task(state, caller)
  }
}
