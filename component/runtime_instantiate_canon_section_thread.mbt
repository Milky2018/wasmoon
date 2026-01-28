///|
/// Canonical section instantiation helpers.
/// (group: thread)

///|
fn instantiate_canon_thread_index(
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    [@types.Value::I32(0)]
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_thread_yield(
  _cancellable : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let async_state = state.async_state
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    // In a synchronous task, `thread.yield` is just a normal call that
    // returns a conventional code (it must not block by itself).
    if !async_state.task_can_block[0] {
      return [@types.Value::I32(1)]
    }
    let task_id = current_task_id(async_state)
    // Restartable yield points: only suspend once per ordinal.
    let cur = if async_state.yield_cursor_stack.length() == 0 {
      0
    } else {
      async_state.yield_cursor_stack[async_state.yield_cursor_stack.length() - 1]
    }
    let replay_upto = match async_state.yield_replay_upto.get(task_id) {
      Some(n) => n
      None => 0
    }
    if cur < replay_upto {
      async_state.yield_cursor_stack[async_state.yield_cursor_stack.length() - 1] = cur +
        1
      // On replay, thread.yield returns 0.
      return [@types.Value::I32(0)]
    }
    async_state.yield_replay_upto.set(task_id, replay_upto + 1)
    canon_suspend[0] = Some(CanonSuspend::Yield)
    raise @runtime.RuntimeError::Unreachable
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_thread_yield_to(
  _cancellable : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let async_state = state.async_state
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    // For now, model yield-to as a regular yield.
    if !async_state.task_can_block[0] {
      return [@types.Value::I32(1)]
    }
    canon_suspend[0] = Some(CanonSuspend::Yield)
    raise @runtime.RuntimeError::Unreachable
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_thread_switch_to(
  _cancellable : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let async_state = state.async_state
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    // For now, switching is treated as yielding.
    if !async_state.task_can_block[0] {
      return [@types.Value::I32(1)]
    }
    canon_suspend[0] = Some(CanonSuspend::Yield)
    raise @runtime.RuntimeError::Unreachable
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_thread_resume_later(
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    []
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_thread_suspend(
  _cancellable : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I32],
  }
  let async_state = state.async_state
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    if !async_state.task_can_block[0] {
      trap_canon("cannot block a synchronous task before returning")
      return [@types.Value::I32(0)]
    }
    canon_suspend[0] = Some(CanonSuspend::Yield)
    raise @runtime.RuntimeError::Unreachable
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_thread_new_indirect(
  _type_idx : Int,
  _table_idx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let async_state = state.async_state
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let id = alloc_shared_handle(async_state)
    [@types.Value::I32(id)]
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}
