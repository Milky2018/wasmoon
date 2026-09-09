///|
fn TaskRegistry::entries_thread_runnable(
  self : TaskRegistry,
) -> Array[(Int64, Array[Int])] {
  let result : Array[(Int64, Array[Int])] = []
  for id, record in self.records {
    if record.thread_runnable is Some(value) {
      result.push((id, value))
    }
  }
  result
}

///|
test "reusing a guest handle never revives retired task state" {
  let state = AsyncState(StreamTable())
  let first = alloc_task_id(state)
  init_task_meta(state, first, 10, 0L)
  state.tasks.write_task_contexts(first, Map([(0, I32(42))]))
  state.tasks.bind_handle(first, handle_key(10, 1))
  push_task(state, handle_key(10, 1), true)
  inspect(current_task_id(state) == first, content="true")
  pop_task(state)
  retire_task(state, handle_key(10, 1))
  let second = alloc_task_id(state)
  state.tasks.bind_handle(second, handle_key(10, 1))
  inspect(first != second, content="true")
  debug_inspect(
    state.tasks.read_task_contexts(handle_key(10, 1)),
    content="None",
  )
  retire_task(state, first)
  inspect(state.tasks.resolve(handle_key(10, 1)) == second, content="true")
  retire_task(state, second)
  inspect(state.tasks.records.length(), content="0")
  inspect(state.tasks.aliases.length(), content="0")
  inspect(state.tasks.handles.length(), content="0")
}

///|
test "host runtime acquired after guest instantiation shares task and event state" {
  let bytes = @component_text.parse_component_wat("(component)")
  let component = @component.parse_component(bytes)
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    component,
    ComponentValidationConfig(false),
  )
  let linker = ComponentLinker::ComponentLinker()
  defer linker.close()
  let guest = linker.instantiate("first", validated)
  let runtime = linker.host_runtime_state()
  let second = linker.instantiate("second", validated)
  let id = alloc_task_id(guest.async_state)
  init_task_meta(guest.async_state, id, 31, 0L)
  debug_inspect(
    runtime.async_state.tasks.read_task_instance(id),
    content="Some(31)",
  )
  debug_inspect(
    second.async_state.tasks.read_task_instance(id),
    content="Some(31)",
  )
  runtime.set_event_loop(fn() { false })
  inspect(guest.async_state.host_event_loop.val is Some(_), content="true")
  inspect(second.async_state.host_event_loop.val is Some(_), content="true")
  retire_task(runtime.async_state, id)
  inspect(guest.async_state.tasks.records.length(), content="0")
}
