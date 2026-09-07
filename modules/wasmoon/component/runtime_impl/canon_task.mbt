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
  let result_param : @component.Param = { label: "", ty: result, }
  match
    core_args_to_component(
      args,
      [result_param],
      types,
      resources,
      store,
      resource_table,
      16,
      "task.return result",
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
  let mem_is_64 = match resources.mem_addr {
    Some(addr) => {
      let mem = store.get_mem(addr) catch {
        error => raise CanonCallError(error.to_string())
      }
      mem.is_memory64()
    }
    None => false
  }
  let core_params : Array[@types.ValueType] = match result {
    Some(vt) => {
      let flat = core_types_for_valtype(vt, state.types, mem_is_64)
      if flat.length() > 16 {
        if mem_is_64 {
          [I64]
        } else {
          [I32]
        }
      } else {
        flat
      }
    }
    None => []
  }
  let core_type : @types.FuncType = { params: core_params, results: [], }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let types = state.types
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let (_, _, task_id, _) = current_thread_info(
      async_state, owner_component_id,
    ) catch {
      e => {
        trap_canon(canon_err_message(e))
        return []
      }
    }
    guard async_state.task_return_contracts.get(task_id) is Some(contract) &&
      contract.owner_component_id == owner_component_id &&
      optional_val_types_match(
        contract.result,
        contract.types,
        result,
        types,
        0,
      ) &&
      (
        resources.mem_addr is None ||
        contract.resources.mem_addr == resources.mem_addr
      ) &&
      contract.resources.encoding == resources.encoding else {
      trap_canon(
        "invalid `task.return` signature and/or options for current task",
      )
      return []
    }
    if async_state.task_borrows.get(task_id) is Some(count) && count > 0 {
      trap_canon("borrow handles still remain at the end of the call")
      return []
    }
    if async_state.task_returned.get(task_id) is Some(_) {
      trap_canon("task.return called more than once")
      return []
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
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_task_cancel(
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [], results: [], }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let (_, _, task_id, _) = current_thread_info(
      async_state, owner_component_id,
    ) catch {
      e => {
        trap_canon(canon_err_message(e))
        return []
      }
    }
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
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}
