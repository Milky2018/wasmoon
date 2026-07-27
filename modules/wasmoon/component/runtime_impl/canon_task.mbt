///|
/// Canonical section instantiation helpers.
/// (group: task)

///|
fn lift_task_return_value(
  result : ValType,
  args : Array[@types.Value],
  resources : CanonResources,
  types : Array[TypeDef?],
  resource_table : ResourceTable,
  store : @runtime.Store,
) -> ComponentValue raise ComponentRuntimeError {
  let result_param : @component.Param = { label: "", ty: result }
  let result_func : FuncType = {
    is_async: false,
    params: [result_param],
    result: None,
  }
  match
    core_args_to_component(
      args, result_func, types, resources, store, resource_table, 16, "task.return result",
    ) {
    [value] => value
    _ => raise HostCallError("task.return argument type mismatch")
  }
}

///|
fn instantiate_canon_task_return(
  result : ValType?,
  opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  for opt in opts {
    match opt {
      Async =>
        raise ImportTypeMismatch(
          "cannot specify `async` option on `task.return`",
        )
      Callback(_) =>
        raise ImportTypeMismatch("cannot specify callback without async")
      PostReturn(_) =>
        raise ImportTypeMismatch(
          "cannot specify `post-return` option on `task.return`",
        )
      Realloc(_) =>
        raise ImportTypeMismatch(
          "cannot specify `realloc` option on `task.return`",
        )
      _ => ()
    }
  }
  let resources = resolve_canon_resources(opts, state)
  let core_params : Array[@types.ValueType] = match result {
    Some(vt) => {
      let flat = core_types_for_valtype(vt, state.types, false) catch {
        _ => []
      }
      if flat.length() > 16 {
        [I32]
      } else {
        flat
      }
    }
    None => []
  }
  let core_type : @types.FuncType = { params: core_params, results: [] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let types = state.types
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    if async_state.task_borrows.get(task_id) is Some(count) && count > 0 {
      trap_canon("borrow handles still remain at the end of the call")
      return []
    }
    // `canon task.return` can be executed multiple times if the surrounding
    // core function is cooperatively replayed after a suspension (e.g. a
    // sync stream.read/write inside a callback-style async task).
    // Treat re-execution as idempotent as long as it returns the same value.
    if async_state.task_returned.get(task_id) is Some(_) {
      match result {
        None => return []
        Some(vt) => {
          let v = lift_task_return_value(
            vt,
            args,
            resources,
            types,
            state.resource_table,
            store,
          ) catch {
            e => {
              trap_canon(canon_err_message(e))
              return []
            }
          }
          // NOTE: Unlike wasmtime, wasmoon currently implements sync-style
          // suspension by cooperatively replaying the whole core function.
          // This means `task.return` may be re-executed after its stream/future
          // readable handles have already been transferred to the caller's
          // component instance. In that case, re-validating the handle against
          // the original component's handle table would spuriously trap.
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
    }
    async_state.task_returned.set(task_id, true)
    let vals : Array[ComponentValue] = match result {
      None => []
      Some(vt) => {
        let v = lift_task_return_value(
          vt,
          args,
          resources,
          types,
          state.resource_table,
          store,
        ) catch {
          e => {
            trap_canon(canon_err_message(e))
            return []
          }
        }
        // `canon task.return` lifts core values into the component result; apply the
        // same stream/future handle validation as `canon lift`.
        validate_lifted_stream_future(
          vt, v, types, async_state, owner_component_id,
        ) catch {
          e => {
            trap_canon(canon_err_message(e))
            return []
          }
        }
        [v]
      }
    }
    set_task_result(async_state, task_id, owner_component_id, vals)
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
  let owner_component_id = state.resource_table.id
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    if async_state.task_borrows.get(task_id) is Some(count) && count > 0 {
      trap_canon("borrow handles still remain at the end of the call")
      return []
    }
    async_state.task_self_cancelled.set(task_id, true)
    async_state.task_cancelled.set(task_id, true)
    async_state.task_returned.set(task_id, true)
    set_task_result(async_state, task_id, owner_component_id, [])
    []
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}
