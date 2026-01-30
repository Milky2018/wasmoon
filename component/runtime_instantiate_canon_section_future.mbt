///|
/// Canonical section instantiation helpers.
/// (group: future)

///|
fn instantiate_canon_future_new(
  _tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I64],
  }
  let async_state = state.async_state
  let creator_component_id = state.resource_table.id
  let payload_ty : ValType? = match state.types.get(_tyidx) {
    Some(Some(TypeDef::Future(v))) => v
    _ => None
  }
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    // Replay-safe: `canon future.new` can be re-executed when a callback-style
    // async core function is restarted after a suspension.
    let task_id = current_task_id(async_state)
    let cur = if async_state.call_cursor_stack.length() == 0 {
      0
    } else {
      async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1]
    }
    let per_task = match async_state.call_results.get(task_id) {
      Some(m) => m
      None => {
        let m : Map[Int, Array[@types.Value]] = {}
        async_state.call_results.set(task_id, m)
        m
      }
    }
    match per_task.get(cur) {
      Some(v) => {
        async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1] = cur +
          1
        return v
      }
      None => ()
    }
    fn cache_i64(x : Int64) -> Array[@types.Value] {
      let out = [@types.Value::I64(x)]
      per_task.set(cur, out)
      async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1] = cur +
        1
      out
    }

    let future_id = async_state.next_future_id[0]
    async_state.next_future_id[0] = future_id + 1
    let (rh, wh) = if payload_ty is Some(_) {
      // For typed futures, prefer reusing a freed handle for the readable end.
      let (h1, f1) = alloc_shared_handle_with_source(
        async_state, creator_component_id,
      )
      let (h2, f2) = alloc_shared_handle_with_source(
        async_state, creator_component_id,
      )
      if f1 != f2 {
        if f1 {
          (h1, h2)
        } else {
          (h2, h1)
        }
      } else if h1 < h2 {
        (h2, h1)
      } else {
        (h1, h2)
      }
    } else {
      // Empty future: allocate readable then writable.
      let (rh, _fr) = alloc_shared_handle_with_source(
        async_state, creator_component_id,
      )
      let (wh, _fw) = alloc_shared_handle_with_source(
        async_state, creator_component_id,
      )
      (rh, wh)
    }
    async_state.future_endpoints.set(handle_key(creator_component_id, rh), {
      future_id,
      is_readable: true,
      creator_component_id,
    })
    async_state.future_endpoints.set(handle_key(creator_component_id, wh), {
      future_id,
      is_readable: false,
      creator_component_id,
    })
    async_state.futures.set(future_id, {
      payload_ty,
      pending_read: None,
      pending_write: None,
      readable_dropped: false,
      writable_dropped: false,
      read_done: false,
      write_succeeded: false,
      write_observed_readable_drop: false,
      wrote_value: false,
    })
    let packed = (wh.to_int64() << 32) | (rh.to_int64() & 0xFFFFFFFFL)
    cache_i64(packed)
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_future_read(
  _tyidx : Int,
  _opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let resources = resolve_canon_resources(_opts, state) catch { e => raise e }
  let async_state = state.async_state
  let caller_component_id = state.resource_table.id
  let is_async = canon_opt_is_async(_opts)
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    let cur = if async_state.call_cursor_stack.length() == 0 {
      0
    } else {
      async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1]
    }
    let per_task = match async_state.call_results.get(task_id) {
      Some(m) => m
      None => {
        let m : Map[Int, Array[@types.Value]] = {}
        async_state.call_results.set(task_id, m)
        m
      }
    }
    match per_task.get(cur) {
      Some(v) => {
        async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1] = cur +
          1
        return v
      }
      None => ()
    }
    fn cache_i32(n : Int) -> Array[@types.Value] {
      let out = [@types.Value::I32(n)]
      per_task.set(cur, out)
      async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1] = cur +
        1
      out
    }
    // Sync future.read blocks the task; the async form returns BLOCKED=-1.
    if !is_async && !async_state.task_can_block[0] {
      trap_canon("cannot block a synchronous task before returning")
      return cache_i32(0)
    }
    match args {
      [@types.Value::I32(handle), @types.Value::I32(ptr)] =>
        match
          async_state.future_endpoints.get(
            handle_key(caller_component_id, handle),
          ) {
          None => {
            trap_canon("unknown future handle index \{handle}")
            cache_i32(0)
          }
          Some(ep) =>
            if !ep.is_readable {
              trap_canon("type mismatch")
              cache_i32(0)
            } else {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown future handle index \{handle}")
                  return cache_i32(0)
                }
              }
              if st0.read_done {
                trap_canon(
                  "cannot read from future after previous read succeeded",
                )
                return cache_i32(0)
              }
              match st0.pending_write {
                Some(pw) => {
                  // Intra-component char futures cannot rendezvous.
                  match st0.payload_ty {
                    Some(Prim(Char)) =>
                      if ep.creator_component_id == caller_component_id {
                        trap_canon(
                          "cannot read from and write to intra-component future",
                        )
                        return [@types.Value::I32(0)]
                      }
                    _ => ()
                  }

                  // Write payload (if any) to memory at `ptr`.
                  match st0.payload_ty {
                    None => ()
                    Some(Prim(U8)) => {
                      let mem = match resources.mem_addr {
                        Some(addr) =>
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [@types.Value::I32(0)]
                        }
                      }
                      mem.store_byte(ptr, trunc_u8(pw.val).to_byte()) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [@types.Value::I32(0)]
                        }
                      }
                    }
                    Some(Prim(Char)) => {
                      if ptr % 4 != 0 {
                        trap_canon("unaligned pointer")
                        return [@types.Value::I32(0)]
                      }
                      let mem = match resources.mem_addr {
                        Some(addr) =>
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [@types.Value::I32(0)]
                        }
                      }
                      mem.store_i32(ptr, pw.val) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [@types.Value::I32(0)]
                        }
                      }
                    }
                    _ => {
                      trap_canon("unsupported future type")
                      return [@types.Value::I32(0)]
                    }
                  }

                  // Completing a pending write unblocks the writer: emit FUTURE_WRITE.
                  if async_state.future_endpoints.get(
                      handle_key(pw.writer_component_id, pw.writer_handle),
                    )
                    is Some(_) {
                    enqueue_waitable_event(
                      async_state,
                      handle_key(pw.writer_component_id, pw.writer_handle),
                      {
                        owner_component_id: pw.writer_component_id,
                        code: 5,
                        index: pw.writer_handle,
                        payload: 0,
                      },
                    )
                  }
                  async_state.futures.set(ep.future_id, {
                    payload_ty: st0.payload_ty,
                    pending_read: None,
                    pending_write: None,
                    readable_dropped: st0.readable_dropped,
                    writable_dropped: st0.writable_dropped,
                    read_done: true,
                    write_succeeded: true,
                    write_observed_readable_drop: st0.write_observed_readable_drop,
                    wrote_value: st0.wrote_value,
                  })
                  cache_i32(0)
                }
                None =>
                  if st0.writable_dropped {
                    async_state.futures.set(ep.future_id, {
                      payload_ty: st0.payload_ty,
                      pending_read: None,
                      pending_write: None,
                      readable_dropped: st0.readable_dropped,
                      writable_dropped: st0.writable_dropped,
                      read_done: true,
                      write_succeeded: st0.write_succeeded,
                      write_observed_readable_drop: st0.write_observed_readable_drop,
                      wrote_value: st0.wrote_value,
                    })
                    cache_i32(1)
                  } else {
                    // Register a pending read and report BLOCKED=-1.
                    async_state.futures.set(ep.future_id, {
                      payload_ty: st0.payload_ty,
                      pending_read: Some({
                        // Remember the reader-side canon memory so a writer from a different
                        // component instance can write into the correct memory.
                        mem_addr: resources.mem_addr,
                        ptr,
                        reader_component_id: caller_component_id,
                        reader_handle: handle,
                      }),
                      pending_write: None,
                      readable_dropped: st0.readable_dropped,
                      writable_dropped: st0.writable_dropped,
                      read_done: st0.read_done,
                      write_succeeded: st0.write_succeeded,
                      write_observed_readable_drop: st0.write_observed_readable_drop,
                      wrote_value: st0.wrote_value,
                    })
                    cache_i32(-1)
                  }
              }
            }
        }
      _ => {
        trap_canon("type mismatch")
        cache_i32(0)
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_future_write(
  _tyidx : Int,
  _opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let resources = resolve_canon_resources(_opts, state) catch { e => raise e }
  let async_state = state.async_state
  let caller_component_id = state.resource_table.id
  let is_async = canon_opt_is_async(_opts)
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    let cur = if async_state.call_cursor_stack.length() == 0 {
      0
    } else {
      async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1]
    }
    let per_task = match async_state.call_results.get(task_id) {
      Some(m) => m
      None => {
        let m : Map[Int, Array[@types.Value]] = {}
        async_state.call_results.set(task_id, m)
        m
      }
    }
    match per_task.get(cur) {
      Some(v) => {
        async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1] = cur +
          1
        return v
      }
      None => ()
    }
    fn cache_i32(n : Int) -> Array[@types.Value] {
      let out = [@types.Value::I32(n)]
      per_task.set(cur, out)
      async_state.call_cursor_stack[async_state.call_cursor_stack.length() - 1] = cur +
        1
      out
    }
    // Sync future.write blocks the task; the async form returns BLOCKED=-1.
    if !is_async && !async_state.task_can_block[0] {
      trap_canon("cannot block a synchronous task before returning")
      return cache_i32(0)
    }
    match args {
      [@types.Value::I32(handle), @types.Value::I32(ptr)] =>
        match
          async_state.future_endpoints.get(
            handle_key(caller_component_id, handle),
          ) {
          None => {
            trap_canon("unknown future handle index \{handle}")
            cache_i32(0)
          }
          Some(ep) =>
            if ep.is_readable {
              trap_canon("type mismatch")
              cache_i32(0)
            } else {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown future handle index \{handle}")
                  return cache_i32(0)
                }
              }
              if st0.write_succeeded {
                trap_canon(
                  "cannot write to future after previous write succeeded",
                )
                return cache_i32(0)
              }
              if st0.write_observed_readable_drop {
                trap_canon(
                  "cannot write to future after previous write succeeded or readable end dropped",
                )
                return cache_i32(0)
              }

              // If the readable end was dropped before any rendezvous, report DROPPED.
              if st0.readable_dropped {
                async_state.futures.set(ep.future_id, {
                  payload_ty: st0.payload_ty,
                  pending_read: None,
                  pending_write: None,
                  readable_dropped: st0.readable_dropped,
                  writable_dropped: st0.writable_dropped,
                  read_done: st0.read_done,
                  write_succeeded: false,
                  write_observed_readable_drop: true,
                  wrote_value: st0.wrote_value,
                })
                return cache_i32(1)
              }
              match st0.pending_read {
                Some(pr) => {
                  // Intra-component char futures cannot rendezvous.
                  match st0.payload_ty {
                    Some(Prim(Char)) =>
                      if ep.creator_component_id == caller_component_id {
                        trap_canon(
                          "cannot read from and write to intra-component future",
                        )
                        return [@types.Value::I32(0)]
                      }
                    _ => ()
                  }

                  // Load payload (if any) from writer memory at `ptr` and write to the
                  // reader memory at `pr.ptr`.
                  match st0.payload_ty {
                    None => ()
                    Some(Prim(U8)) => {
                      let src_mem = match resources.mem_addr {
                        Some(addr) =>
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [@types.Value::I32(0)]
                        }
                      }
                      let dst_mem = match pr.mem_addr {
                        Some(addr) =>
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [@types.Value::I32(0)]
                        }
                      }
                      let b = src_mem.load_byte(ptr) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [@types.Value::I32(0)]
                        }
                      }
                      dst_mem.store_byte(pr.ptr, b) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [@types.Value::I32(0)]
                        }
                      }
                    }
                    Some(Prim(Char)) => {
                      if ptr % 4 != 0 || pr.ptr % 4 != 0 {
                        trap_canon("unaligned pointer")
                        return [@types.Value::I32(0)]
                      }
                      let src_mem = match resources.mem_addr {
                        Some(addr) =>
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [@types.Value::I32(0)]
                        }
                      }
                      let dst_mem = match pr.mem_addr {
                        Some(addr) =>
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [@types.Value::I32(0)]
                        }
                      }
                      let n = src_mem.load_i32(ptr) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [@types.Value::I32(0)]
                        }
                      }
                      // Validate scalar value.
                      (char_from_canon_i32(n) catch {
                        e => {
                          trap_canon(canon_err_message(e))
                          return [@types.Value::I32(0)]
                        }
                      })
                      |> ignore
                      dst_mem.store_i32(pr.ptr, n) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [@types.Value::I32(0)]
                        }
                      }
                    }
                    _ => {
                      trap_canon("unsupported future type")
                      return [@types.Value::I32(0)]
                    }
                  }

                  // Completing a pending read unblocks the reader: emit FUTURE_READ.
                  if async_state.future_endpoints.get(
                      handle_key(pr.reader_component_id, pr.reader_handle),
                    )
                    is Some(_) {
                    enqueue_waitable_event(
                      async_state,
                      handle_key(pr.reader_component_id, pr.reader_handle),
                      {
                        owner_component_id: pr.reader_component_id,
                        code: 4,
                        index: pr.reader_handle,
                        payload: 0,
                      },
                    )
                  }
                  async_state.futures.set(ep.future_id, {
                    payload_ty: st0.payload_ty,
                    pending_read: None,
                    pending_write: None,
                    readable_dropped: st0.readable_dropped,
                    writable_dropped: st0.writable_dropped,
                    read_done: true,
                    write_succeeded: true,
                    write_observed_readable_drop: st0.write_observed_readable_drop,
                    wrote_value: true,
                  })
                  cache_i32(0)
                }
                None => {
                  // Register a pending write by reading the payload once.
                  let write_val : Int = match st0.payload_ty {
                    None => 0
                    Some(Prim(U8)) => {
                      let mem = match resources.mem_addr {
                        Some(addr) =>
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [@types.Value::I32(0)]
                        }
                      }
                      let b = mem.load_byte(ptr) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [@types.Value::I32(0)]
                        }
                      }
                      b.to_int()
                    }
                    Some(Prim(Char)) => {
                      if ptr % 4 != 0 {
                        trap_canon("unaligned pointer")
                        return [@types.Value::I32(0)]
                      }
                      let mem = match resources.mem_addr {
                        Some(addr) =>
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [@types.Value::I32(0)]
                        }
                      }
                      let n = mem.load_i32(ptr) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [@types.Value::I32(0)]
                        }
                      }
                      (char_from_canon_i32(n) catch {
                        e => {
                          trap_canon(canon_err_message(e))
                          return [@types.Value::I32(0)]
                        }
                      })
                      |> ignore
                      n
                    }
                    _ => {
                      trap_canon("unsupported future type")
                      return [@types.Value::I32(0)]
                    }
                  }
                  async_state.futures.set(ep.future_id, {
                    payload_ty: st0.payload_ty,
                    pending_read: None,
                    pending_write: Some({
                      writer_component_id: caller_component_id,
                      writer_handle: handle,
                      val: write_val,
                    }),
                    readable_dropped: st0.readable_dropped,
                    writable_dropped: st0.writable_dropped,
                    read_done: st0.read_done,
                    write_succeeded: st0.write_succeeded,
                    write_observed_readable_drop: st0.write_observed_readable_drop,
                    wrote_value: true,
                  })
                  cache_i32(-1)
                }
              }
            }
        }
      _ => {
        trap_canon("type mismatch")
        cache_i32(0)
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_future_cancel_read(
  _tyidx : Int,
  _is_async : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    if !async_state.task_can_block[0] {
      trap_canon("cannot block a synchronous task before returning")
      return [@types.Value::I32(0)]
    }
    match args {
      [@types.Value::I32(handle)] =>
        match
          async_state.future_endpoints.get(
            handle_key(owner_component_id, handle),
          ) {
          None => {
            trap_canon("unknown future handle index \{handle}")
            [@types.Value::I32(0)]
          }
          Some(ep) =>
            if !ep.is_readable {
              trap_canon("type mismatch")
              [@types.Value::I32(0)]
            } else {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown future handle index \{handle}")
                  return [@types.Value::I32(0)]
                }
              }
              async_state.futures.set(ep.future_id, {
                payload_ty: st0.payload_ty,
                pending_read: None,
                pending_write: st0.pending_write,
                readable_dropped: st0.readable_dropped,
                writable_dropped: st0.writable_dropped,
                read_done: st0.read_done,
                write_succeeded: st0.write_succeeded,
                write_observed_readable_drop: st0.write_observed_readable_drop,
                wrote_value: st0.wrote_value,
              })
              // CANCELLED=2
              [@types.Value::I32(2)]
            }
        }
      _ => {
        trap_canon("type mismatch")
        [@types.Value::I32(0)]
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_future_cancel_write(
  _tyidx : Int,
  _is_async : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    if !async_state.task_can_block[0] {
      trap_canon("cannot block a synchronous task before returning")
      return [@types.Value::I32(0)]
    }
    match args {
      [@types.Value::I32(handle)] =>
        match
          async_state.future_endpoints.get(
            handle_key(owner_component_id, handle),
          ) {
          None => {
            trap_canon("unknown future handle index \{handle}")
            [@types.Value::I32(0)]
          }
          Some(ep) =>
            if ep.is_readable {
              trap_canon("type mismatch")
              [@types.Value::I32(0)]
            } else {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown future handle index \{handle}")
                  return [@types.Value::I32(0)]
                }
              }
              let had_pending = match st0.pending_write {
                Some(_) => true
                None => false
              }
              async_state.futures.set(ep.future_id, {
                payload_ty: st0.payload_ty,
                pending_read: st0.pending_read,
                pending_write: None,
                readable_dropped: st0.readable_dropped,
                writable_dropped: st0.writable_dropped,
                read_done: st0.read_done,
                write_succeeded: st0.write_succeeded,
                write_observed_readable_drop: st0.write_observed_readable_drop,
                // If we cancelled a pending write, treat as "no value written".
                wrote_value: if had_pending {
                  false
                } else {
                  st0.wrote_value
                },
              })
              [@types.Value::I32(2)]
            }
        }
      _ => {
        trap_canon("type mismatch")
        [@types.Value::I32(0)]
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_future_drop_readable(
  _tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  async_state.thread_handle_required.set(owner_component_id, true)
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [@types.Value::I32(handle)] =>
        match
          async_state.future_endpoints.get(
            handle_key(owner_component_id, handle),
          ) {
          Some(ep) =>
            if !ep.is_readable {
              []
            } else {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => return []
              }
              // Dropping readable end may resolve a pending write as DROPPED.
              match st0.pending_write {
                Some(pw) =>
                  if async_state.future_endpoints.get(
                      handle_key(pw.writer_component_id, pw.writer_handle),
                    )
                    is Some(_) {
                    enqueue_waitable_event(
                      async_state,
                      handle_key(pw.writer_component_id, pw.writer_handle),
                      {
                        owner_component_id: pw.writer_component_id,
                        code: 5,
                        index: pw.writer_handle,
                        payload: 1,
                      },
                    )
                  }
                None => ()
              }
              async_state.futures.set(ep.future_id, {
                payload_ty: st0.payload_ty,
                pending_read: None,
                pending_write: None,
                readable_dropped: true,
                writable_dropped: st0.writable_dropped,
                read_done: true,
                write_succeeded: st0.write_succeeded,
                write_observed_readable_drop: st0.pending_write is Some(_) ||
                st0.write_observed_readable_drop,
                wrote_value: st0.wrote_value,
              })

              // Remove from any waitable-set membership and queued events.
              remove_waitable_membership(
                async_state, owner_component_id, handle,
              )
              async_state.future_endpoints.remove(
                handle_key(owner_component_id, handle),
              )
              free_shared_handle(async_state, owner_component_id, handle)
              []
            }
          None => []
        }
      _ => []
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_future_drop_writable(
  _tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [@types.Value::I32(handle)] =>
        match
          async_state.future_endpoints.get(
            handle_key(owner_component_id, handle),
          ) {
          Some(ep) =>
            if ep.is_readable {
              []
            } else {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => return []
              }
              if !st0.wrote_value && !st0.write_succeeded {
                trap_canon(
                  "cannot drop future write end without first writing a value",
                )
                return []
              }
              // Dropping writable end may resolve a pending read as DROPPED.
              match st0.pending_read {
                Some(pr) =>
                  if async_state.future_endpoints.get(
                      handle_key(pr.reader_component_id, pr.reader_handle),
                    )
                    is Some(_) {
                    enqueue_waitable_event(
                      async_state,
                      handle_key(pr.reader_component_id, pr.reader_handle),
                      {
                        owner_component_id: pr.reader_component_id,
                        code: 4,
                        index: pr.reader_handle,
                        payload: 1,
                      },
                    )
                  }
                None => ()
              }
              async_state.futures.set(ep.future_id, {
                payload_ty: st0.payload_ty,
                pending_read: None,
                pending_write: st0.pending_write,
                readable_dropped: st0.readable_dropped,
                writable_dropped: true,
                read_done: st0.pending_read is Some(_) || st0.read_done,
                write_succeeded: st0.write_succeeded,
                write_observed_readable_drop: st0.write_observed_readable_drop,
                wrote_value: st0.wrote_value,
              })
              remove_waitable_membership(
                async_state, owner_component_id, handle,
              )
              async_state.future_endpoints.remove(
                handle_key(owner_component_id, handle),
              )
              free_shared_handle(async_state, owner_component_id, handle)
              []
            }
          None => []
        }
      _ => []
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}
