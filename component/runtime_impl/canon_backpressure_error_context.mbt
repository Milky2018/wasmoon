///|
/// Canonical section instantiation helpers.
/// (group: backpressure + error-context)

///|
fn parse_i32_like_arg(v : @types.Value) -> Int? {
  match v {
    I32(n) => Some(n)
    I64(n) => Some(n.to_int())
    _ => None
  }
}

///|
fn instantiate_canon_backpressure_set(
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
    if args.length() != 1 {
      trap_canon("type mismatch")
      return []
    }
    let enabled = match parse_i32_like_arg(args[0]) {
      Some(n) => n != 0
      None => {
        trap_canon("type mismatch")
        return []
      }
    }
    set_backpressure_value_for_instance(
      async_state,
      owner_component_id,
      if enabled {
        1
      } else {
        0
      },
    )
    []
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_backpressure_inc(
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
    let old = backpressure_value_for_instance(async_state, owner_component_id)
    if old >= 65535 {
      trap_canon("backpressure counter overflow")
      return []
    }
    set_backpressure_value_for_instance(
      async_state,
      owner_component_id,
      old + 1,
    )
    []
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_backpressure_dec(
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
    let old = backpressure_value_for_instance(async_state, owner_component_id)
    if old <= 0 {
      trap_canon("backpressure counter overflow")
      return []
    }
    set_backpressure_value_for_instance(
      async_state,
      owner_component_id,
      old - 1,
    )
    []
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_error_context_new(
  opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let resources = resolve_canon_resources(opts, state)
  let core_type : @types.FuncType = { params: [I32, I32], results: [I32] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let types = state.types
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let mem_addr = match resources.mem_addr {
      Some(addr) => addr
      None => {
        trap_canon(canon_err_message(MissingCanonMemory))
        return []
      }
    }
    let mem = store.get_mem(mem_addr) catch {
      e => {
        trap_canon(e.to_string())
        return []
      }
    }
    let lifted = lift_component_value_from_flat(
      Prim(String),
      args,
      types,
      Some(mem),
      mem.is_memory64(),
      resources.encoding,
    ) catch {
      e => {
        trap_canon(canon_err_message(e))
        return []
      }
    }
    let debug_message = match lifted {
      String(s) => s
      _ => {
        trap_canon("type mismatch")
        return []
      }
    }
    let handle = alloc_error_context_handle(
      async_state, owner_component_id, debug_message,
    )
    [I32(handle)]
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_error_context_debug_message(
  opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let resources = resolve_canon_resources(opts, state)
  let core_type : @types.FuncType = { params: [I32, I32], results: [] }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    if args.length() != 2 {
      trap_canon("type mismatch")
      return []
    }
    let handle = match parse_i32_like_arg(args[0]) {
      Some(h) => h
      None => {
        trap_canon("type mismatch")
        return []
      }
    }
    let retptr = match parse_i32_like_arg(args[1]) {
      Some(p) => p
      None => {
        trap_canon("type mismatch")
        return []
      }
    }
    let debug_message = match
      get_error_context_message(async_state, owner_component_id, handle) {
      Some(s) => s
      None => {
        trap_canon("unknown handle index \{handle}")
        return []
      }
    }
    let mem_addr = match resources.mem_addr {
      Some(addr) => addr
      None => {
        trap_canon(canon_err_message(MissingCanonMemory))
        return []
      }
    }
    let realloc = match resources.realloc {
      Some(f) => f
      None => {
        trap_canon(canon_err_message(MissingCanonRealloc))
        return []
      }
    }
    let mem = store.get_mem(mem_addr) catch {
      e => {
        trap_canon(e.to_string())
        return []
      }
    }
    let mem_is_64 = mem.is_memory64()
    let (bytes, canon_len, align) = encode_string_for_canon(
      debug_message,
      resources.encoding,
    )
    let ptr = write_bytes_to_memory_with_align(
      store, mem, realloc, mem_is_64, bytes, align,
    ) catch {
      e => {
        trap_canon(canon_err_message(e))
        return []
      }
    }
    if mem_is_64 {
      mem.store_i64(retptr, ptr.to_int64()) catch {
        e => {
          trap_canon(e.to_string())
          return []
        }
      }
      mem.store_i64(retptr + 8, canon_len.to_int64()) catch {
        e => {
          trap_canon(e.to_string())
          return []
        }
      }
    } else {
      mem.store_i32(retptr, ptr) catch {
        e => {
          trap_canon(e.to_string())
          return []
        }
      }
      mem.store_i32(retptr + 4, canon_len) catch {
        e => {
          trap_canon(e.to_string())
          return []
        }
      }
    }
    []
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_error_context_drop(
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
    if args.length() != 1 {
      trap_canon("type mismatch")
      return []
    }
    let handle = match parse_i32_like_arg(args[0]) {
      Some(h) => h
      None => {
        trap_canon("type mismatch")
        return []
      }
    }
    if !drop_error_context_handle(async_state, owner_component_id, handle) {
      trap_canon("unknown handle index \{handle}")
      return []
    }
    []
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}
