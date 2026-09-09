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

///|
test "late task writes cannot resurrect a retired identity" {
  let state = AsyncState(StreamTable())
  let id = alloc_task_id(state)
  retire_task(state, id)
  state.tasks.write_task_results(id, [U32(42)])
  inspect(state.tasks.records.length(), content="0")
}

///|
test "linker close cancels an exported root host future exactly once" {
  let linker = ComponentLinker::ComponentLinker()
  let cancelled = Ref(0)
  let polled = Ref(0)
  let builder = linker.host_instance_builder(
    "host",
    linker.host_runtime_state(),
  )
  builder.add_async_func("run", { is_async: true, params: [], result: None, }, (
    _,
    _,
  ) => {
    HostFuture(
      () => {
        polled.val += 1
        Pending
      },
      () => cancelled.val += 1,
    )
  })
  let instance = builder.finish()
  let call = instance.start_exported_func("run", [])
  debug_inspect(call.poll(), content="InvocationPending")
  let polls = polled.val
  linker.close()
  inspect(cancelled.val, content="1")
  inspect(instance.async_state.tasks.records.length(), content="0")
  inspect(instance.async_state.tasks.aliases.length(), content="0")
  let result = try {
    call.poll() |> ignore
    "resumed"
  } catch {
    error => error.to_string()
  }
  inspect(result.contains("Cancelled"), content="true")
  inspect(polled.val == polls, content="true")
  call.cancel()
  linker.close()
  inspect(cancelled.val, content="1")
}

///|
fn TaskRegistry::entries_sync_lower_states(
  self : TaskRegistry,
) -> Array[(Int64, SyncLowerState)] {
  let result : Array[(Int64, SyncLowerState)] = []
  for id, record in self.records {
    if record.sync_lower_states is Some(value) {
      result.push((id, value))
    }
  }
  result
}

///|
test "reentrant linker close cannot publish or repoll a host future" {
  for close_during_start in [false, true] {
    let linker = ComponentLinker::ComponentLinker()
    let cancelled = Ref(0)
    let polled = Ref(0)
    let builder = linker.host_instance_builder(
      "host",
      linker.host_runtime_state(),
    )
    builder.add_async_func(
      "run",
      { is_async: true, params: [], result: None, },
      (_, _) => {
        if close_during_start {
          linker.close()
        }
        HostFuture(
          () => {
            polled.val += 1
            if !close_during_start {
              linker.close()
            }
            Pending
          },
          () => {
            cancelled.val += 1
            linker.close()
          },
        )
      },
    )
    let instance = builder.finish()
    let call = instance.start_exported_func("run", [])
    let error = try {
      call.poll() |> ignore
      "resumed"
    } catch {
      error => error.to_string()
    }
    inspect(error.contains("Cancelled"), content="true")
    inspect(cancelled.val, content="1")
    inspect(instance.async_state.tasks.records.length(), content="0")
    let polls = polled.val
    try call.poll() catch {
      _ => ()
    } noraise {
      _ => fail("closed invocation resumed")
    }
    inspect(polled.val == polls, content="true")
    let restart = try {
      instance.start_exported_func("run", []) |> ignore
      "started"
    } catch {
      error => error.to_string()
    }
    inspect(restart.contains("Cancelled"), content="true")
    inspect(instance.async_state.tasks.records.length(), content="0")
  }
}

///|
test "retired stack entry and duplicate handle binding preserve live tasks" {
  let state = AsyncState(StreamTable())
  let first = alloc_task_id(state)
  let second = alloc_task_id(state)
  state.tasks.bind_handle(first, 7L)
  state.tasks.bind_handle(second, 7L)
  inspect(state.tasks.resolve(7L) == first, content="true")
  retire_task(state, second)
  inspect(state.tasks.resolve(7L) == first, content="true")
  retire_task(state, first)
  let error = try {
    push_task(state, first, true)
    "entered"
  } catch {
    error => error.to_string()
  }
  inspect(error.contains("Cancelled"), content="true")
  inspect(state.task_stack.length(), content="1")
  inspect(state.tasks.records.length(), content="0")
}
