///|
/// Canonical section instantiation helpers.
/// (group: subtask)

///|
fn take_subtask_terminal_status(
  async_state : AsyncState,
  owner : Int,
  id : Int,
) -> Int raise @runtime.RuntimeError {
  let key = handle_key(owner, id)
  if async_state.waitable_events.get(key) is Some(events) {
    for event in events {
      if event.code == 1 && (event.payload == 2 || event.payload == 4) {
        let status = event.payload
        remove_waitable_events_for(async_state, owner, id, 1)
        return status
      }
    }
  }
  trap_canon("`subtask.cancel` called after terminal status delivered")
  0
}

///|
fn instantiate_canon_subtask_cancel(
  is_async_cancel : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32], results: [I32], }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    guard args is [I32(id)] else {
      trap_canon("type mismatch")
      return []
    }
    let caller_task = current_task_id(async_state)
    if !is_async_cancel {
      resume_sync_waitable_use(async_state, owner_component_id, id, caller_task)
      |> ignore
    }
    if waitable_is_in_set(async_state, owner_component_id, id) {
      trap_canon(
        "waitable cannot be used synchronously while added to a waitable set",
      )
    }
    if waitable_is_in_sync_use(async_state, owner_component_id, id) {
      trap_canon("waitable already in synchronous use")
    }
    let key = handle_key(owner_component_id, id)
    guard async_state.tasks.read_subtasks(key) is Some(subtask) else {
      trap_canon("unknown subtask handle index \{id}")
      return []
    }
    if subtask.phase[0] == Returned {
      return [
        I32(take_subtask_terminal_status(async_state, owner_component_id, id)),
      ]
    }
    async_state.tasks.write_task_cancelled(key, true)
    let CallbackLifted(task) = subtask.driver
    task.cancelled[0] = true
    if subtask.phase[0] == Starting {
      subtask.phase[0] = Returned
      if async_state.pending_by_instance.get(subtask.bp_key) is Some(queue) {
        let mut i = 0
        while i < queue.length() {
          if queue[i] == key {
            queue.remove(i) |> ignore
          } else {
            i += 1
          }
        }
        if queue.is_empty() {
          async_state.pending_by_instance.remove(subtask.bp_key)
        }
      }
      remove_waitable_events_for(async_state, owner_component_id, id, 1)
      return [I32(3)]
    }
    let can_cancel_now = task.continuation[0] is None ||
      (
        async_state.tasks.read_task_suspensions(key) is Some(point) &&
        point.is_cancellable()
      )
    if is_async_cancel && !can_cancel_now {
      return [I32(-1)]
    }
    let step = {
      push_canon_task(async_state, key, true)
      defer pop_task(async_state)
      step_task_once(task, store, subtask.caller_table, async_state) catch {
        error => {
          trap_canon(canon_err_message(error))
          return []
        }
      }
    }
    if step == Done {
      complete_subtask(async_state, store, key, subtask) catch {
        error => {
          trap_canon(canon_err_message(error))
          return []
        }
      }
      return [
        I32(take_subtask_terminal_status(async_state, owner_component_id, id)),
      ]
    }
    if is_async_cancel {
      return [I32(-1)]
    }
    if !async_state.task_can_block[0] {
      trap_canon("cannot block a synchronous task before returning")
    }
    // STARTED is not a cancellation result and cannot wake this synchronous wait.
    remove_waitable_events_for(async_state, owner_component_id, id, 1)
    mark_sync_waitable_blocked(async_state, owner_component_id, id, caller_task)
    canon_suspend[0] = Some(Yield)
    raise Unreachable
  }
  state.core_funcs.push(
    alloc_component_host_core_func(
      store,
      core_type,
      host,
      may_suspend=!is_async_cancel,
    ),
  )
}

///|
fn instantiate_canon_subtask_drop(
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32], results: [], }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    fn ret_void() -> Array[@types.Value] {
      []
    }

    match args {
      [I32(id)] => {
        let skey = handle_key(owner_component_id, id)
        // Ensure this is a known subtask and it has completed.
        let st_opt = async_state.tasks.read_subtasks(skey)
        match st_opt {
          Some(st) =>
            if st.phase[0] != Returned {
              trap_canon("cannot drop a subtask which has not yet resolved")
              return ret_void()
            } else {
              async_state.tasks.clear_subtasks(skey)
            }
          None => {
            trap_canon("unknown subtask handle index \{id}")
            return ret_void()
          }
        }

        // Remove from any waitable-set membership and queued events.
        match async_state.waitable_to_set.get(skey) {
          Some(ws_key) => {
            async_state.waitable_to_set.remove(skey)
            match async_state.waitable_sets.get(ws_key) {
              Some(set) => {
                set.members.remove(id)
                // Purge queued events for this waitable.
                let mut i = 0
                while i < set.queue.length() {
                  if set.queue[i].index == id {
                    set.queue.remove(i) |> ignore
                  } else {
                    i = i + 1
                  }
                }
              }
              None => ()
            }
          }
          None => ()
        }
        async_state.waitable_events.remove(skey)

        // Clear per-task bookkeeping so the handle id can be reused.
        retire_task(async_state, skey)

        // Remove from pending queues if it was still STARTING.
        let inst_ids : Array[Int] = []
        for kv in async_state.pending_by_instance.iter() {
          let (inst_id, _q) = kv
          inst_ids.push(inst_id)
        }
        for inst_id in inst_ids {
          match async_state.pending_by_instance.get(inst_id) {
            Some(q) => {
              let mut j = 0
              while j < q.length() {
                if q[j] == skey {
                  q.remove(j) |> ignore
                } else {
                  j = j + 1
                }
              }
              if q.length() == 0 {
                async_state.pending_by_instance.remove(inst_id)
              }
            }
            None => ()
          }
        }
        free_shared_handle(async_state, owner_component_id, id)
        ret_void()
      }
      _ => {
        trap_canon("type mismatch")
        ret_void()
      }
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}
