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
    Some(TypeDef::ResourceType(id, rep, dtor_idx, kind)) => {
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
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let table = state.resource_table
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [@types.Value::I32(rep)] => {
        let handle = table.alloc({ type_id, rep, dtor, kind })
        [@types.Value::I32(handle)]
      }
      _ => {
        trap_canon("type mismatch")
        []
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
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
    Some(TypeDef::ResourceType(id, _, _, kind)) => (id, kind)
    _ => raise InvalidTypeDef(tyidx)
  }
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let table = state.resource_table
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [@types.Value::I32(handle)] =>
        match table.get(handle) {
          Some(entry) =>
            if entry.type_id < 0 {
              trap_canon(
                "unknown handle index \{handle}; index \{handle} is not a resource",
              )
              []
            } else if entry.type_id != type_id {
              let expected_desc = if expected_kind == ResourceKind::GuestDefined {
                "guest-defined resource"
              } else {
                "host-defined resource"
              }
              let found_desc = if entry.kind == ResourceKind::GuestDefined {
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
                "handle index \{handle} used with the wrong type, expected \{expected_desc} but found \{suffix}",
              )
              []
            } else {
              [@types.Value::I32(entry.rep)]
            }
          None => {
            trap_canon(
              "unknown handle index \{handle}; index \{handle} is not a resource",
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
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
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
    Some(TypeDef::ResourceType(id, _, _, kind)) => (id, kind)
    _ => raise InvalidTypeDef(tyidx)
  }
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  let table = state.resource_table
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [@types.Value::I32(handle)] =>
        match table.get(handle) {
          Some(entry) =>
            if entry.type_id < 0 {
              trap_canon(
                "unknown handle index \{handle}; index \{handle} is not a resource",
              )
              []
            } else if entry.type_id != type_id {
              let expected_desc = if expected_kind == ResourceKind::GuestDefined {
                "guest-defined resource"
              } else {
                "host-defined resource"
              }
              let found_desc = if entry.kind == ResourceKind::GuestDefined {
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
                "handle index \{handle} used with the wrong type, expected \{expected_desc} but found \{suffix}",
              )
              []
            } else {
              let taken = table.free(handle)
              match taken {
                Some(real) =>
                  match real.dtor {
                    Some(d) => {
                      clear_canon_trap_message()
                      (@executor.call_func_by_index(
                        store,
                        d.instance,
                        d.func_idx,
                        [@types.Value::I32(real.rep)],
                      ) catch {
                        e => {
                          trap_canon(e.to_string())
                          []
                        }
                      })
                      |> ignore
                    }
                    None => ()
                  }
                None => ()
              }
              []
            }
          None => {
            trap_canon(
              "unknown handle index \{handle}; index \{handle} is not a resource",
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
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}
