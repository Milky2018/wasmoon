///|
/// Canonical section instantiation helpers.
/// (group: task)

///|
fn instantiate_canon_task_return(
  result : ValType?,
  opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let resources = resolve_canon_resources(opts, state)
  let core_params : Array[@types.ValueType] = match result {
    Some(vt) => core_types_for_valtype(vt, state.types, false) catch { _ => [] }
    None => []
  }
  let core_type : @types.FuncType = { params: core_params, results: [] }
  let async_state = state.async_state
  let types = state.types
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    // `canon task.return` can be executed multiple times if the surrounding
    // core function is cooperatively replayed after a suspension (e.g. a
    // sync stream.read/write inside a callback-style async task).
    // Treat re-execution as idempotent as long as it returns the same value.
    match async_state.task_returned.get(task_id) {
      Some(_) =>
        match result {
          None => return []
          Some(vt) => {
            let mem : @runtime.Memory? = match resources.mem_addr {
              Some(addr) =>
                Some(
                  store.get_mem(addr) catch {
                    e => {
                      trap_canon(e.to_string())
                      return []
                    }
                  },
                )
              None => None
            }
            let mem_is_64 = match mem {
              Some(m) => m.is_memory64()
              None => false
            }
            let v = lift_component_value_from_flat(
              vt,
              args,
              types,
              mem,
              mem_is_64,
              resources.encoding,
            ) catch {
              e => {
                trap_canon(canon_err_message(e))
                return []
              }
            }
            validate_lifted_stream_future(vt, v, types, async_state) catch {
              e => {
                trap_canon(canon_err_message(e))
                return []
              }
            }
            match async_state.task_results.get(task_id) {
              Some(prev) =>
                if prev.length() == 1 && prev[0] == v {
                  return []
                } else {
                  trap_canon("task.return called more than once")
                  return []
                }
              None => return []
            }
          }
        }
      None => ()
    }
    async_state.task_returned.set(task_id, true)
    let vals : Array[ComponentValue] = match result {
      None => []
      Some(vt) => {
        let mem : @runtime.Memory? = match resources.mem_addr {
          Some(addr) =>
            Some(
              store.get_mem(addr) catch {
                e => {
                  trap_canon(e.to_string())
                  return []
                }
              },
            )
          None => None
        }
        let mem_is_64 = match mem {
          Some(m) => m.is_memory64()
          None => false
        }
        let v = lift_component_value_from_flat(
          vt,
          args,
          types,
          mem,
          mem_is_64,
          resources.encoding,
        ) catch {
          e => {
            trap_canon(canon_err_message(e))
            return []
          }
        }
        // `canon task.return` lifts core values into the component result; apply the
        // same stream/future handle validation as `canon lift`.
        validate_lifted_stream_future(vt, v, types, async_state) catch {
          e => {
            trap_canon(canon_err_message(e))
            return []
          }
        }
        [v]
      }
    }
    set_task_result(async_state, task_id, vals)
    []
  }
  // Stash as a core func.
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_task_cancel(
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [], results: [] }
  let async_state = state.async_state
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    async_state.task_cancelled.set(task_id, true)
    async_state.task_returned.set(task_id, true)
    set_task_result(async_state, task_id, [])
    []
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}
