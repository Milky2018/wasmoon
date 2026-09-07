///|
fn complete_subtask(
  async_state : AsyncState,
  store : @runtime.Store,
  task_id : Int64,
  st : Subtask,
) -> Unit raise ComponentRuntimeError {
  drop_task_thread(async_state, task_id)
  if st.detached {
    // Detached background tasks are not observable by core code; avoid emitting events
    // and proactively clean up so shared handles can be reused deterministically.
    let owner_component_id = st.caller_table.id
    let wkey = handle_key(owner_component_id, st.id)
    remove_waitable_membership(async_state, owner_component_id, st.id)
    async_state.waitable_events.remove(wkey)
    async_state.subtasks.remove(task_id)
    async_state.task_results.remove(task_id)
    async_state.task_result_owner.remove(task_id)
    async_state.task_returned.remove(task_id)
    async_state.task_self_cancelled.remove(task_id)
    async_state.task_cancelled.remove(task_id)
    async_state.task_contexts.remove(task_id)
    remove_task_meta(async_state, task_id)
    async_state.yield_suspended.remove(task_id)
    async_state.waiting_ws.remove(task_id)
    async_state.sync_lower_states.remove(task_id)
    free_shared_handle(async_state, owner_component_id, st.id)
    return ()
  }
  // Write subtask results into the return buffer (async-lower ABI).
  // component-spec expects the return value to be materialized in memory
  // before emitting the RETURNED event.
  let cancelled = async_state.task_self_cancelled.get(task_id) is Some(true)
  match st.result_ty {
    Some(_) =>
      if st.mem_addr is Some(mem_addr) {
        let mem = store.get_mem(mem_addr) catch {
          e => raise CanonCallError(e.to_string())
        }
        let mut vals = if cancelled {
          // Cancelled subtasks resolve without writing a value.
          take_task_result(async_state, task_id) |> ignore
          ([] : Array[ComponentValue])
        } else {
          match async_state.task_results.get(task_id) {
            Some(v) => v
            None => []
          }
        }
        // Lower into core values; direct scalars come back as a single
        // value which we store at `retptr`. Indirect results are written
        // by `component_results_to_core` via `retptr`.
        if !cancelled {
          let (ft, ftypes) = match st.driver {
            CallbackLifted(t) =>
              match t.func {
                Host(func_type, types, _) => (func_type, types)
                HostAsync(func_type, types, _) => (func_type, types)
                Lifted(_, func_type, _, types, _, _, _, _) => (func_type, types)
              }
          }
          // Subtask results are observed by the caller component instance; if the task ran
          // in a nested component, move stream/future handles into the caller's local space.
          vals = transfer_results_if_needed(
            vals,
            ft.result,
            ftypes,
            async_state,
            st.callee_instance_id,
            st.caller_table.id,
          )
          set_task_result(async_state, task_id, st.caller_table.id, vals)
          let core_vals = component_results_to_core(
            vals,
            ft,
            ftypes,
            st.resources,
            store,
            Some(st.retptr),
          )
          store_async_lower_result(mem, st.retptr, core_vals)
        }
      } else {
        // Result present but no memory: validated earlier for async-lower.
        raise MissingCanonMemory
      }
    None => ()
  }
  // Publish terminal status only after storing the result.
  st.phase[0] = Returned
  async_state.inflight_by_instance.set(st.bp_key, 0)
  let owner_component_id = st.caller_table.id
  let payload = if cancelled {
    // CANCELLED_BEFORE_RETURNED
    4
  } else {
    // RETURNED
    2
  }
  enqueue_waitable_event(async_state, handle_key(owner_component_id, st.id), {
    owner_component_id,
    code: 1,
    index: st.id,
    payload,
  })
  return ()
}
