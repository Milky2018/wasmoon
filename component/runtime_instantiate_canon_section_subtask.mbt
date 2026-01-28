///|
/// Canonical section instantiation helpers.
/// (group: subtask)

///|
fn instantiate_canon_subtask_cancel(
  is_async_cancel : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let async_state = state.async_state
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    let cur = if async_state.call_cursor_stack.length() == 0 {
      0
    } else {
      async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1]
    }
    let per_task = match async_state.call_results.get(task_id) {
      Some(m) => m
      None => {
        let m : Map[Int, Array[@types.Value]] = {}
        async_state.call_results.set(task_id, m)
        m
      }
    }
    match per_task.get(cur) {
      Some(v) => {
        async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1] = cur +
          1
        return v
      }
      None => ()
    }
    fn cache_i32(n : Int) -> Array[@types.Value] {
      let out = [@types.Value::I32(n)]
      per_task.set(cur, out)
      async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1] = cur +
        1
      out
    }

    if !is_async_cancel && !async_state.task_can_block[0] {
      trap_canon("cannot block a synchronous task before returning")
      return cache_i32(0)
    }
    match args {
      [@types.Value::I32(id)] =>
        match async_state.subtasks.get(id) {
          None => {
            trap_canon("unknown subtask handle index \{id}")
            cache_i32(0)
          }
          Some(st) => {
            if st.phase[0] == SubtaskPhase::Returned {
              // Already resolved.
              return cache_i32(0)
            }

            // Mark cancellation request for callback-driven tasks.
            match st.driver {
              SubtaskDriver::CallbackLifted(t) => t.cancelled[0] = true
              _ => ()
            }

            // Best-effort: if the subtask uses the callback-style async ABI,
            // attempt to deliver the cancellation immediately.
            let is_callback = match st.driver {
              SubtaskDriver::CallbackLifted(t) =>
                match t.func {
                  ComponentFunc::Lifted(
                    _,
                    _ft,
                    _res,
                    _tys,
                    _tbl,
                    _may_enter,
                    Some(_cb),
                    _async_abi
                  ) => true
                  _ => false
                }
              _ => false
            }
            if is_callback {
              match st.driver {
                SubtaskDriver::CallbackLifted(t) => {
                  push_task(async_state, id, true)
                  let step = step_task_once(
                    t,
                    store,
                    st.caller_table,
                    async_state,
                  ) catch {
                    e => {
                      pop_task(async_state)
                      trap_canon(canon_err_message(e))
                      return cache_i32(0)
                    }
                  }
                  pop_task(async_state)
                  match step {
                    TaskStep::Done => {
                      st.phase[0] = SubtaskPhase::Returned
                      async_state.inflight_by_instance.set(st.bp_key, 0)
                      enqueue_waitable_event(async_state, id, {
                        code: 1,
                        index: id,
                        payload: 2,
                      })
                      // CANCELLED_BEFORE_RETURNED=4 (component-spec convention).
                      return cache_i32(4)
                    }
                    _ => ()
                  }
                }
                _ => ()
              }
            }

            // BLOCKED=-1 (cancellation didn't complete synchronously).
            cache_i32(-1)
          }
        }
      _ => {
        trap_canon("type mismatch")
        cache_i32(0)
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_subtask_drop(
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  let async_state = state.async_state
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    let cur = if async_state.call_cursor_stack.length() == 0 {
      0
    } else {
      async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1]
    }
    let per_task = match async_state.call_results.get(task_id) {
      Some(m) => m
      None => {
        let m : Map[Int, Array[@types.Value]] = {}
        async_state.call_results.set(task_id, m)
        m
      }
    }
    match per_task.get(cur) {
      Some(v) => {
        async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1] = cur +
          1
        return v
      }
      None => ()
    }
    fn cache_void() -> Array[@types.Value] {
      let out : Array[@types.Value] = []
      per_task.set(cur, out)
      async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1] = cur +
        1
      out
    }

    match args {
      [@types.Value::I32(id)] => {
        // Ensure this is a known subtask and it has completed.
        let st_opt = async_state.subtasks.get(id)
        match st_opt {
          Some(st) =>
            if st.phase[0] != SubtaskPhase::Returned {
              trap_canon("cannot drop a subtask which has not yet resolved")
              return cache_void()
            } else {
              async_state.subtasks.remove(id)
            }
          None => {
            trap_canon("unknown subtask handle index \{id}")
            return cache_void()
          }
        }

        // Remove from any waitable-set membership and queued events.
        match async_state.waitable_to_set.get(id) {
          Some(ws) => {
            async_state.waitable_to_set.remove(id)
            match async_state.waitable_sets.get(ws) {
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
        async_state.waitable_events.remove(id)

        // Clear per-task bookkeeping so the handle id can be reused.
        async_state.task_results.remove(id)
        async_state.task_returned.remove(id)
        async_state.task_cancelled.remove(id)
        async_state.task_contexts.remove(id)
        async_state.yield_replay_upto.remove(id)
        async_state.wait_results.remove(id)
        async_state.waiting_ws.remove(id)
        async_state.call_results.remove(id)
        async_state.sync_lower_states.remove(id)

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
                if q[j] == id {
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
        free_shared_handle(async_state, id)
        cache_void()
      }
      _ => {
        trap_canon("type mismatch")
        cache_void()
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}
