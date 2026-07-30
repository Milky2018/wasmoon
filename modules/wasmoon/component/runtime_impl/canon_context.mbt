///|
/// Canonical section instantiation helpers.
/// (group: context)

///|
fn instantiate_canon_context_get(
  _vt : @types.ValueType,
  _idx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [], results: [_vt] }
  let async_state = state.async_state
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    let task_id = current_task_id(async_state)
    match async_state.task_contexts.get(task_id) {
      Some(m) =>
        match m.get(_idx) {
          Some(v) => [v]
          None =>
            // Default 0 per value type.
            match _vt {
              I32 => [I32(0)]
              I64 => [I64(0L)]
              F32 => [F32(0.0)]
              F64 => [F64(0.0)]
              _ => {
                trap_canon("unsupported context type")
                []
              }
            }
        }
      None =>
        match _vt {
          I32 => [I32(0)]
          I64 => [I64(0L)]
          F32 => [F32(0.0)]
          F64 => [F64(0.0)]
          _ => {
            trap_canon("unsupported context type")
            []
          }
        }
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_context_set(
  _vt : @types.ValueType,
  _idx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [_vt], results: [] }
  let async_state = state.async_state
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if args.length() != 1 {
      trap_canon("type mismatch")
      return []
    }
    let task_id = current_task_id(async_state)
    let m = match async_state.task_contexts.get(task_id) {
      Some(m) => m
      None => {
        let m : Map[Int, @types.Value] = Map([])
        async_state.task_contexts.set(task_id, m)
        m
      }
    }
    m.set(_idx, args[0])
    []
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}
