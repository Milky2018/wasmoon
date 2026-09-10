///|
/// Canonical section instantiation helpers.
/// (group: resource)

///|
fn instantiate_canon_resource_new(
  tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  if tyidx < 0 || tyidx >= state.types.length() {
    raise InvalidTypeIndex(tyidx)
  }
  let (type_id, kind, dtor) = match state.types[tyidx] {
    Some(ResourceType(id, rep, dtor_idx, kind)) => {
      if rep != 0x7f {
        raise UnsupportedComponent("resources can only be represented by `i32`")
      }
      let dtor_ref = match dtor_idx {
        Some(idx) =>
          if idx < 0 || idx >= state.core_funcs.length() {
            raise InvalidCoreFuncIndex(idx)
          } else {
            Some(state.core_funcs[idx])
          }
        None => None
      }
      (id, kind, dtor_ref)
    }
    _ => raise InvalidTypeDef(tyidx)
  }
  let core_type : @types.FuncType = { params: [I32], results: [I32], }
  let table = state.resource_table
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [I32(rep)] => {
        let handle = table.alloc({
          type_id,
          rep,
          dtor,
          host_dtor: None,
          kind,
          impl_component_id: table.id,
          own: true,
          borrow_scope: None,
          num_lends: [0],
        })
        [I32(handle)]
      }
      _ => {
        trap_canon("type mismatch")
        []
      }
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_resource_rep(
  tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  if tyidx < 0 || tyidx >= state.types.length() {
    raise InvalidTypeIndex(tyidx)
  }
  let (type_id, expected_kind) = match state.types[tyidx] {
    Some(ResourceType(id, _, _, kind)) => (id, kind)
    _ => raise InvalidTypeDef(tyidx)
  }
  let core_type : @types.FuncType = { params: [I32], results: [I32], }
  let table = state.resource_table
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    match args {
      [I32(handle)] =>
        match table.get(handle) {
          Some(entry) =>
            if entry.type_id < 0 {
              trap_canon(
                "unknown handle index \{resource_handle_index_text(handle)}; index \{resource_handle_index_text(handle)} is not a resource",
              )
              []
            } else if entry.type_id != type_id {
              let expected_desc = if expected_kind == GuestDefined {
                "guest-defined resource"
              } else {
                "host-defined resource"
              }
              let found_desc = if entry.kind == GuestDefined {
                "guest-defined resource"
              } else {
                "host-defined resource"
              }
              let suffix = if entry.kind == expected_kind {
                "a different \{found_desc}"
              } else {
                found_desc
              }
              trap_canon(
                "handle index \{resource_handle_index_text(handle)} used with the wrong type, expected \{expected_desc} but found \{suffix}",
              )
              []
            } else {
              [I32(entry.rep)]
            }
          None => {
            trap_canon(
              "resource.rep: unknown handle index \{resource_handle_index_text(handle)}; index \{resource_handle_index_text(handle)} is not a resource in table \{table.id}",
            )
            []
          }
        }
      _ => {
        trap_canon("type mismatch")
        []
      }
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_resource_drop(
  tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  if tyidx < 0 || tyidx >= state.types.length() {
    raise InvalidTypeIndex(tyidx)
  }
  let (type_id, expected_kind) = match state.types[tyidx] {
    Some(ResourceType(id, _, _, kind)) => (id, kind)
    _ => raise InvalidTypeDef(tyidx)
  }
  let core_type : @types.FuncType = { params: [I32], results: [], }
  let table = state.resource_table
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [I32(handle)] =>
        match table.get(handle) {
          Some(entry) =>
            if entry.type_id < 0 {
              trap_canon(
                "unknown handle index \{resource_handle_index_text(handle)}; index \{resource_handle_index_text(handle)} is not a resource",
              )
              []
            } else if entry.type_id != type_id {
              let expected_desc = if expected_kind == GuestDefined {
                "guest-defined resource"
              } else {
                "host-defined resource"
              }
              let found_desc = if entry.kind == GuestDefined {
                "guest-defined resource"
              } else {
                "host-defined resource"
              }
              let suffix = if entry.kind == expected_kind {
                "a different \{found_desc}"
              } else {
                found_desc
              }
              trap_canon(
                "handle index \{resource_handle_index_text(handle)} used with the wrong type, expected \{expected_desc} but found \{suffix}",
              )
              []
            } else {
              if entry.own && entry.num_lends[0] > 0 {
                trap_canon("cannot drop resource handle while it is borrowed")
                return []
              }
              let taken = table.free(handle)
              match taken {
                Some(real) =>
                  if real.own {
                    call_resource_destructor(state.async_state, store, real) catch {
                      UncaughtWasmException =>
                        trap_canon(
                          "uncaught exception propagated out of component",
                        )
                      CanonCallError(message) => trap_canon(message)
                      error => trap_canon(error.to_string())
                    }
                  } else {
                    real.num_lends[0] -= 1
                    match real.borrow_scope {
                      Some(scope) => {
                        let task_id = scope
                        let count = match
                          state.async_state.tasks.read_task_borrows(task_id) {
                          Some(n) => n
                          None => 0
                        }
                        if count <= 1 {
                          state.async_state.tasks.clear_task_borrows(task_id)
                        } else {
                          state.async_state.tasks.write_task_borrows(
                            task_id,
                            count - 1,
                          )
                        }
                      }
                      None => ()
                    }
                  }
                None => ()
              }
              []
            }
          None => {
            trap_canon(
              "resource.drop: unknown handle index \{resource_handle_index_text(handle)}; index \{resource_handle_index_text(handle)} is not a resource in table \{table.id}",
            )
            []
          }
        }
      _ => {
        trap_canon("type mismatch")
        []
      }
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
/// Destructors run synchronously with fresh context slots owned by the resource's
/// defining component. Retiring their task restores the caller on every exit.
fn call_resource_destructor(
  state : AsyncState,
  store : @runtime.Store,
  resource : ResourceHandle,
) -> Unit raise ComponentRuntimeError {
  if resource.dtor is None && resource.host_dtor is None {
    return
  }
  let task_id = alloc_task_id(state)
  init_task_meta(
    state,
    task_id,
    resource.impl_component_id,
    current_task_id(state),
  )
  push_task(state, task_id, false)
  defer {
    pop_task(state)
    retire_task(state, task_id)
  }
  if resource.host_dtor is Some(dtor) {
    dtor.destroy(resource.rep)
  }
  if resource.dtor is Some(dtor) {
    call_core_func(store, dtor, [I32(resource.rep)]) |> ignore
  }
}
