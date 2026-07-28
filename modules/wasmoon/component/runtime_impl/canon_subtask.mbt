///|
/// Canonical section instantiation helpers.
/// (group: subtask)

///|
fn instantiate_canon_subtask_cancel(
  is_async_cancel : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [I32], results: [I32] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    fn ret_i32(n : Int) -> Array[@types.Value] {
      [I32(n)]
    }

    match args {
      [I32(id)] => {
        if !is_async_cancel &&
          waitable_is_in_set(async_state, owner_component_id, id) {
          trap_canon(
            "waitable cannot be used synchronously while added to a waitable set",
          )
          return ret_i32(0)
        }
        if !is_async_cancel && !async_state.task_can_block[0] {
          trap_canon("cannot block a synchronous task before returning")
          return ret_i32(0)
        }
        let skey = handle_key(owner_component_id, id)
        match async_state.subtasks.get(skey) {
          None => {
            trap_canon("unknown subtask handle index \{id}")
            ret_i32(0)
          }
          Some(st) => {
            if st.phase[0] == Returned {
              // Already resolved.
              return ret_i32(0)
            }
            async_state.task_cancelled.set(skey, true)

            // Mark cancellation request for callback-driven tasks.
            match st.driver {
              CallbackLifted(t) => t.cancelled[0] = true
            }

            if st.phase[0] == Starting {
              st.phase[0] = Returned
              let pending_keys : Array[Int] = []
              for kv in async_state.pending_by_instance.iter() {
                let (key, _) = kv
                pending_keys.push(key)
              }
              for key in pending_keys {
                if async_state.pending_by_instance.get(key) is Some(queue) {
                  let mut i = 0
                  while i < queue.length() {
                    if queue[i] == skey {
                      queue.remove(i) |> ignore
                    } else {
                      i = i + 1
                    }
                  }
                  if queue.length() == 0 {
                    async_state.pending_by_instance.remove(key)
                  }
                }
              }
              // CANCELLED_BEFORE_STARTED.
              return ret_i32(3)
            }

            // Best-effort: if the subtask uses the callback-style async ABI,
            // attempt to deliver the cancellation immediately.
            let is_callback = match st.driver {
              CallbackLifted(t) =>
                match t.func {
                  Lifted(
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
            }
            if is_callback {
              match st.driver {
                CallbackLifted(t) => {
                  push_task(async_state, skey, true)
                  let step = step_task_once(
                    t,
                    store,
                    st.caller_table,
                    async_state,
                  ) catch {
                    e => {
                      pop_task(async_state)
                      trap_canon(canon_err_message(e))
                      return ret_i32(0)
                    }
                  }
                  pop_task(async_state)
                  match step {
                    Done => {
                      st.phase[0] = Returned
                      async_state.inflight_by_instance.set(st.bp_key, 0)
                      enqueue_waitable_event(async_state, skey, {
                        owner_component_id,
                        code: 1,
                        index: id,
                        payload: 4,
                      })
                      // CANCELLED_BEFORE_RETURNED=4 (component-spec convention).
                      return ret_i32(4)
                    }
                    _ => ()
                  }
                }
              }
            }

            // BLOCKED=-1 (cancellation didn't complete synchronously).
            ret_i32(-1)
          }
        }
      }
      _ => {
        trap_canon("type mismatch")
        ret_i32(0)
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
  let core_type : @types.FuncType = { params: [I32], results: [] }
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
        let st_opt = async_state.subtasks.get(skey)
        match st_opt {
          Some(st) =>
            if st.phase[0] != Returned {
              trap_canon("cannot drop a subtask which has not yet resolved")
              return ret_void()
            } else {
              async_state.subtasks.remove(skey)
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
        async_state.task_results.remove(skey)
        async_state.task_result_owner.remove(skey)
        async_state.task_returned.remove(skey)
        async_state.task_self_cancelled.remove(skey)
        async_state.task_cancelled.remove(skey)
        async_state.task_contexts.remove(skey)
        drop_task_thread(async_state, skey)
        async_state.yield_suspended.remove(skey)
        async_state.waiting_ws.remove(skey)
        async_state.sync_lower_states.remove(skey)

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
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}
