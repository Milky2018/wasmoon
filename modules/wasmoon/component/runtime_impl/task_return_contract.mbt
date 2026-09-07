///|
fn install_task_return_contract(
  async_state : AsyncState,
  task_id : Int64,
  func : ComponentFunc,
) -> Unit {
  if func is Lifted(_, ft, resources, types, table, _, _, true) {
    async_state.task_return_contracts.set(task_id, {
      result: ft.result,
      types,
      resources,
      owner_component_id: table.id,
    })
  }
}

///|
fn finish_task_children(
  async_state : AsyncState,
  store : @runtime.Store,
  owner_component_id : Int,
  task_id : Int64,
) -> TaskStep raise ComponentRuntimeError {
  if async_state.task_returned.get(task_id) is Some(true) ||
    async_state.task_results.get(task_id) is Some(_) {
    return Done
  }
  wake_ready_waiting_threads(async_state, owner_component_id, task_id)
  if pop_runnable_explicit_thread(async_state, owner_component_id, task_id)
    is Some(handle) {
    run_explicit_thread_once(
      async_state, store, owner_component_id, task_id, handle,
    )
    return Progressed
  }
  for entry in async_state.threads {
    let (_, thread) = entry
    if thread.parent_task_id == task_id && thread.phase[0] != Completed {
      return Blocked
    }
  }
  Done
}

///|
fn discard_task_children(async_state : AsyncState, task_id : Int64) -> Unit {
  let children : Array[(Int64, Int64)] = []
  for entry in async_state.threads {
    let (key, thread) = entry
    if thread.parent_task_id == task_id {
      if thread.continuation[0] is Some(continuation) {
        thread.continuation[0] = None
        continuation.cancel()
      }
      children.push((key, thread.task_id))
    }
  }
  async_state.thread_runnable.remove(task_id)
  async_state.main_thread_scheduled.remove(task_id)
  for entry in children {
    let (key, child) = entry
    async_state.threads.remove(key)
    cleanup_thread_task(async_state, child)
  }
}

///|
fn take_required_task_result(
  async_state : AsyncState,
  store : @runtime.Store,
  owner_component_id : Int,
  task_id : Int64,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  while true {
    match
      finish_task_children(async_state, store, owner_component_id, task_id) {
      Done => break
      Progressed => continue
      Blocked => {
        if !async_state.task_can_block[0] {
          raise CanonCallError(
            "cannot block a synchronous task before returning",
          )
        }
        if !progress_one_subtask(async_state, store) {
          let awakened = match async_state.host_event_loop.val {
            Some(event_loop) => (event_loop.wait)()
            None => false
          }
          if !awakened {
            raise CanonCallError(
              "wasm trap: deadlock detected: event loop cannot make further progress",
            )
          }
        }
      }
    }
  }
  match take_task_result(async_state, task_id) {
    Some(values) => values
    None =>
      raise CanonCallError("async-lifted export failed to produce a result")
  }
}
