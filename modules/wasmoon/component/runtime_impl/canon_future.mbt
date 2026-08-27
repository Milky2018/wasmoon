///|
/// Canonical section instantiation helpers.
/// (group: future)

///|
fn instantiate_canon_future_new(
  _tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [], results: [I64], }
  let async_state = state.async_state
  let creator_component_id = state.resource_table.id
  let payload_ty : ValType? = match state.types.get(_tyidx) {
    Some(Some(Future(v))) => v
    _ => None
  }
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
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
      in_waitable_set: Ref(false),
    })
    async_state.future_endpoints.set(handle_key(creator_component_id, wh), {
      future_id,
      is_readable: false,
      creator_component_id,
      in_waitable_set: Ref(false),
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
    [I64(packed)]
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_future_read(
  _tyidx : Int,
  _opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32, I32], results: [I32], }
  let resources = resolve_canon_resources(_opts, state)
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
    fn ret_i32(n : Int) -> Array[@types.Value] {
      [I32(n)]
    }
    let resumed_sync = match args {
      [I32(handle), _] => {
        let resumed = if !is_async {
          resume_sync_waitable_use(
            async_state, caller_component_id, handle, task_id,
          )
        } else {
          false
        }
        if !is_async &&
          waitable_is_in_set(async_state, caller_component_id, handle) {
          trap_canon(
            "waitable cannot be used synchronously while added to a waitable set",
          )
          return ret_i32(0)
        }
        resumed
      }
      _ => false
    }
    match args {
      [I32(handle), I32(ptr)] =>
        match
          async_state.future_endpoints.get(
            handle_key(caller_component_id, handle),
          ) {
          None => {
            if !is_async && !async_state.task_can_block[0] {
              trap_canon("cannot block a synchronous task before returning")
            } else {
              trap_canon("unknown future handle index \{handle}")
            }
            ret_i32(0)
          }
          Some(ep) =>
            if !ep.is_readable {
              if !is_async && !async_state.task_can_block[0] {
                trap_canon("cannot block a synchronous task before returning")
              } else {
                trap_canon("type mismatch")
              }
              ret_i32(0)
            } else {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown future handle index \{handle}")
                  return ret_i32(0)
                }
              }
              match async_state.host_future_values.get(ep.future_id) {
                Some(host_value) => {
                  if st0.read_done {
                    trap_canon(
                      "cannot read from future after previous read succeeded",
                    )
                    return ret_i32(0)
                  }
                  let polled = poll_host_future_value(host_value) catch {
                    e => {
                      trap_canon(e.to_string())
                      return ret_i32(0)
                    }
                  }
                  match polled {
                    Ready(value) => {
                      store_host_stream_value(
                        value,
                        host_value.payload_ty,
                        host_value.types,
                        resources,
                        store,
                        state.resource_table,
                        ptr,
                      ) catch {
                        e => {
                          trap_canon(e.to_string())
                          return ret_i32(0)
                        }
                      }
                      async_state.host_future_values.remove(ep.future_id)
                      async_state.futures.set(ep.future_id, {
                        payload_ty: st0.payload_ty,
                        pending_read: None,
                        pending_write: None,
                        readable_dropped: st0.readable_dropped,
                        writable_dropped: true,
                        read_done: true,
                        write_succeeded: true,
                        write_observed_readable_drop: false,
                        wrote_value: true,
                      })
                      return ret_i32(0)
                    }
                    Pending => ()
                  }
                }
                None => ()
              }
              if st0.read_done {
                // A completed synchronous read resumes by retrying this host
                // instruction after the peer has already written its buffer.
                if resumed_sync {
                  return ret_i32(0)
                }
                trap_canon(
                  "cannot read from future after previous read succeeded",
                )
                return ret_i32(0)
              }
              if st0.pending_read is Some(_) {
                if is_async {
                  trap_canon(
                    "cannot have concurrent operations active on a future/stream",
                  )
                  return ret_i32(0)
                }
                if !async_state.task_can_block[0] {
                  trap_canon("cannot block a synchronous task before returning")
                  return ret_i32(0)
                }
                mark_sync_waitable_blocked(
                  async_state, caller_component_id, handle, task_id,
                )
                canon_suspend[0] = Some(Yield)
                raise Unreachable
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
                        return [I32(0)]
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
                              return [I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [I32(0)]
                        }
                      }
                      mem.store_byte(ptr, trunc_u8(pw.val).to_byte()) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [I32(0)]
                        }
                      }
                    }
                    Some(Prim(Char)) => {
                      if ptr % 4 != 0 {
                        trap_canon("unaligned pointer")
                        return [I32(0)]
                      }
                      let mem = match resources.mem_addr {
                        Some(addr) =>
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [I32(0)]
                        }
                      }
                      mem.store_i32(ptr, pw.val) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [I32(0)]
                        }
                      }
                    }
                    _ => {
                      trap_canon("unsupported future type")
                      return [I32(0)]
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
                  ret_i32(0)
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
                    ret_i32(1)
                  } else {
                    // Register a pending read and report BLOCKED=-1.
                    async_state.futures.set(ep.future_id, {
                      payload_ty: st0.payload_ty,
                      pending_read: Some({
                        // Remember the reader-side canon memory so a writer from a different
                        // component instance can write into the correct memory.
                        mem_addr: resources.mem_addr,
                        realloc: resources.realloc,
                        encoding: resources.encoding,
                        reader_table: state.resource_table,
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
                    if is_async {
                      ret_i32(-1)
                    } else {
                      mark_sync_waitable_blocked(
                        async_state, caller_component_id, handle, task_id,
                      )
                      canon_suspend[0] = Some(Yield)
                      raise Unreachable
                    }
                  }
              }
            }
        }
      _ => {
        trap_canon("type mismatch")
        ret_i32(0)
      }
    }
  }
  state.core_funcs.push(
    alloc_component_host_core_func(
      store,
      core_type,
      host,
      may_suspend=!is_async,
    ),
  )
}

///|
fn poll_host_future_value(
  source : HostFutureValue,
) -> HostFutureValuePoll raise ComponentRuntimeError {
  match source.value.val {
    Some(value) => Ready(value)
    None =>
      match source.pull {
        Some(pull) =>
          match pull() {
            Ready(value) => {
              source.value.val = Some(value)
              Ready(value)
            }
            Pending => Pending
          }
        None => Pending
      }
  }
}

///|
fn progress_host_future_sources(
  async_state : AsyncState,
  store : @runtime.Store,
) -> Bool raise ComponentRuntimeError {
  let mut progressed = false
  for item in async_state.host_future_values.iter() {
    let (future_id, source) = item
    guard async_state.futures.get(future_id) is Some(state) &&
      state.pending_read is Some(read) else {
      continue
    }
    match poll_host_future_value(source) {
      Pending => ()
      Ready(value) => {
        store_host_stream_value(
          value,
          source.payload_ty,
          source.types,
          {
            mem_addr: read.mem_addr,
            realloc: read.realloc,
            post_return: None,
            encoding: read.encoding,
          },
          store,
          read.reader_table,
          read.ptr,
        )
        async_state.host_future_values.remove(future_id)
        async_state.futures.set(future_id, {
          payload_ty: state.payload_ty,
          pending_read: None,
          pending_write: None,
          readable_dropped: state.readable_dropped,
          writable_dropped: true,
          read_done: true,
          write_succeeded: true,
          write_observed_readable_drop: state.write_observed_readable_drop,
          wrote_value: true,
        })
        if async_state.future_endpoints.get(
            handle_key(read.reader_component_id, read.reader_handle),
          )
          is Some(_) {
          enqueue_waitable_event(
            async_state,
            handle_key(read.reader_component_id, read.reader_handle),
            {
              owner_component_id: read.reader_component_id,
              code: 4,
              index: read.reader_handle,
              payload: 0,
            },
          )
        }
        progressed = true
      }
    }
  }
  progressed
}

///|
fn instantiate_canon_future_write(
  _tyidx : Int,
  _opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32, I32], results: [I32], }
  let resources = resolve_canon_resources(_opts, state)
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
    fn ret_i32(n : Int) -> Array[@types.Value] {
      [I32(n)]
    }
    match args {
      [I32(handle), _] => {
        if !is_async {
          resume_sync_waitable_use(
            async_state, caller_component_id, handle, task_id,
          )
          |> ignore
        }
        if !is_async &&
          waitable_is_in_set(async_state, caller_component_id, handle) {
          trap_canon(
            "waitable cannot be used synchronously while added to a waitable set",
          )
          return ret_i32(0)
        }
      }
      _ => ()
    }
    match args {
      [I32(handle), I32(ptr)] =>
        match
          async_state.future_endpoints.get(
            handle_key(caller_component_id, handle),
          ) {
          None => {
            if !is_async && !async_state.task_can_block[0] {
              trap_canon("cannot block a synchronous task before returning")
            } else {
              trap_canon("unknown future handle index \{handle}")
            }
            ret_i32(0)
          }
          Some(ep) =>
            if ep.is_readable {
              if !is_async && !async_state.task_can_block[0] {
                trap_canon("cannot block a synchronous task before returning")
              } else {
                trap_canon("type mismatch")
              }
              ret_i32(0)
            } else {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown future handle index \{handle}")
                  return ret_i32(0)
                }
              }
              if st0.write_succeeded {
                trap_canon(
                  "cannot write to future after previous write succeeded",
                )
                return ret_i32(0)
              }
              if st0.write_observed_readable_drop {
                trap_canon(
                  "cannot write to future after previous write succeeded or readable end dropped",
                )
                return ret_i32(0)
              }
              if st0.pending_write is Some(_) {
                if is_async {
                  trap_canon(
                    "cannot have concurrent operations active on a future/stream",
                  )
                  return ret_i32(0)
                }
                if !async_state.task_can_block[0] {
                  trap_canon("cannot block a synchronous task before returning")
                  return ret_i32(0)
                }
                mark_sync_waitable_blocked(
                  async_state, caller_component_id, handle, task_id,
                )
                canon_suspend[0] = Some(Yield)
                raise Unreachable
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
                return ret_i32(1)
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
                        return [I32(0)]
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
                              return [I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [I32(0)]
                        }
                      }
                      let dst_mem = match pr.mem_addr {
                        Some(addr) =>
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [I32(0)]
                        }
                      }
                      let b = src_mem.load_byte(ptr) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [I32(0)]
                        }
                      }
                      dst_mem.store_byte(pr.ptr, b) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [I32(0)]
                        }
                      }
                    }
                    Some(Prim(Char)) => {
                      if ptr % 4 != 0 || pr.ptr % 4 != 0 {
                        trap_canon("unaligned pointer")
                        return [I32(0)]
                      }
                      let src_mem = match resources.mem_addr {
                        Some(addr) =>
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [I32(0)]
                        }
                      }
                      let dst_mem = match pr.mem_addr {
                        Some(addr) =>
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [I32(0)]
                        }
                      }
                      let n = src_mem.load_i32(ptr) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [I32(0)]
                        }
                      }
                      // Validate scalar value.
                      (char_from_canon_i32(n) catch {
                        e => {
                          trap_canon(canon_err_message(e))
                          return [I32(0)]
                        }
                      })
                      |> ignore
                      dst_mem.store_i32(pr.ptr, n) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [I32(0)]
                        }
                      }
                    }
                    _ => {
                      trap_canon("unsupported future type")
                      return [I32(0)]
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
                  ret_i32(0)
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
                              return [I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [I32(0)]
                        }
                      }
                      let b = mem.load_byte(ptr) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [I32(0)]
                        }
                      }
                      b.to_int()
                    }
                    Some(Prim(Char)) => {
                      if ptr % 4 != 0 {
                        trap_canon("unaligned pointer")
                        return [I32(0)]
                      }
                      let mem = match resources.mem_addr {
                        Some(addr) =>
                          store.get_mem(addr) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [I32(0)]
                            }
                          }
                        None => {
                          trap_canon("missing canon memory")
                          return [I32(0)]
                        }
                      }
                      let n = mem.load_i32(ptr) catch {
                        e => {
                          trap_canon(e.to_string())
                          return [I32(0)]
                        }
                      }
                      (char_from_canon_i32(n) catch {
                        e => {
                          trap_canon(canon_err_message(e))
                          return [I32(0)]
                        }
                      })
                      |> ignore
                      n
                    }
                    _ => {
                      trap_canon("unsupported future type")
                      return [I32(0)]
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
                  if is_async {
                    ret_i32(-1)
                  } else {
                    mark_sync_waitable_blocked(
                      async_state, caller_component_id, handle, task_id,
                    )
                    canon_suspend[0] = Some(Yield)
                    raise Unreachable
                  }
                }
              }
            }
        }
      _ => {
        trap_canon("type mismatch")
        ret_i32(0)
      }
    }
  }
  state.core_funcs.push(
    alloc_component_host_core_func(
      store,
      core_type,
      host,
      may_suspend=!is_async,
    ),
  )
}

///|
fn instantiate_canon_future_cancel_read(
  _tyidx : Int,
  is_async_cancel : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32], results: [I32], }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [I32(handle)] =>
        if !is_async_cancel &&
          waitable_is_in_set(async_state, owner_component_id, handle) {
          trap_canon(
            "waitable cannot be used synchronously while added to a waitable set",
          )
          return [I32(0)]
        }
      _ => ()
    }
    match args {
      [I32(handle)] =>
        match
          async_state.future_endpoints.get(
            handle_key(owner_component_id, handle),
          ) {
          None => {
            if !is_async_cancel && !async_state.task_can_block[0] {
              trap_canon("cannot block a synchronous task before returning")
            } else {
              trap_canon("unknown future handle index \{handle}")
            }
            [I32(0)]
          }
          Some(ep) =>
            if !ep.is_readable {
              if !is_async_cancel && !async_state.task_can_block[0] {
                trap_canon("cannot block a synchronous task before returning")
              } else {
                trap_canon("type mismatch")
              }
              [I32(0)]
            } else {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown future handle index \{handle}")
                  return [I32(0)]
                }
              }
              // If the read already completed, cancellation observes the terminal
              // status instead of reporting CANCELLED.
              if st0.read_done {
                remove_waitable_events_for(
                  async_state, owner_component_id, handle, 4,
                )
                let code = if st0.write_succeeded {
                  0
                } else if st0.writable_dropped {
                  1
                } else {
                  2
                }
                [I32(code)]
              } else if st0.pending_read is Some(_) {
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
                [I32(2)]
              } else {
                [I32(2)]
              }
            }
        }
      _ => {
        trap_canon("type mismatch")
        [I32(0)]
      }
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_future_cancel_write(
  _tyidx : Int,
  is_async_cancel : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32], results: [I32], }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [I32(handle)] =>
        if !is_async_cancel &&
          waitable_is_in_set(async_state, owner_component_id, handle) {
          trap_canon(
            "waitable cannot be used synchronously while added to a waitable set",
          )
          return [I32(0)]
        }
      _ => ()
    }
    match args {
      [I32(handle)] =>
        match
          async_state.future_endpoints.get(
            handle_key(owner_component_id, handle),
          ) {
          None => {
            if !is_async_cancel && !async_state.task_can_block[0] {
              trap_canon("cannot block a synchronous task before returning")
            } else {
              trap_canon("unknown future handle index \{handle}")
            }
            [I32(0)]
          }
          Some(ep) =>
            if ep.is_readable {
              if !is_async_cancel && !async_state.task_can_block[0] {
                trap_canon("cannot block a synchronous task before returning")
              } else {
                trap_canon("type mismatch")
              }
              [I32(0)]
            } else {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown future handle index \{handle}")
                  return [I32(0)]
                }
              }
              // If the write already completed (or the readable end already
              // dropped), cancellation observes that terminal status.
              if st0.write_succeeded {
                remove_waitable_events_for(
                  async_state, owner_component_id, handle, 5,
                )
                [I32(0)]
              } else if st0.readable_dropped || st0.write_observed_readable_drop {
                remove_waitable_events_for(
                  async_state, owner_component_id, handle, 5,
                )
                [I32(1)]
              } else {
                let had_pending = match st0.pending_write {
                  Some(_) => true
                  None => false
                }
                if had_pending {
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
                    wrote_value: false,
                  })
                }
                [I32(2)]
              }
            }
        }
      _ => {
        trap_canon("type mismatch")
        [I32(0)]
      }
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_future_drop_readable(
  _tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32], results: [], }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [I32(handle)] =>
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
              match async_state.host_future_values.get(ep.future_id) {
                Some(source) =>
                  match source.cancel {
                    Some(cancel) =>
                      cancel() catch {
                        e => {
                          trap_canon(canon_err_message(e))
                          return []
                        }
                      }
                    None => ()
                  }
                None => ()
              }
              async_state.host_future_values.remove(ep.future_id)

              // Remove from any waitable-set membership and queued events.
              remove_waitable_membership(
                async_state, owner_component_id, handle,
              )
              async_state.future_endpoints.remove(
                handle_key(owner_component_id, handle),
              )
              free_shared_handle(async_state, owner_component_id, handle)
              cleanup_closed_future(async_state, ep.future_id)
              []
            }
          None => []
        }
      _ => []
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_future_drop_writable(
  _tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32], results: [], }
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [I32(handle)] =>
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
              cleanup_closed_future(async_state, ep.future_id)
              []
            }
          None => []
        }
      _ => []
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}
