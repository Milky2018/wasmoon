///|
/// Canonical section instantiation helpers.
/// (group: future)

///|
fn instantiate_canon_future_new(
  _tyidx : Int32,
  state : ComponentInstance,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [], results: [I64], }
  let async_state = state.async_state
  let creator_component_id = state.resource_table.id
  let payload_ty : ValType? = match state.types.get(_tyidx) {
    Some(Some(Future(v))) => v.map(ty => resolve_valtype(ty, state.types))
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
    errdefer {
      async_state.future_endpoints.remove(handle_key(creator_component_id, rh))
      async_state.future_endpoints.remove(handle_key(creator_component_id, wh))
      async_state.futures.remove(future_id)
      free_shared_handle(async_state, creator_component_id, rh)
      free_shared_handle(async_state, creator_component_id, wh)
    }
    async_state.future_endpoints.set_core(
      handle_key(creator_component_id, rh),
      {
        future_id,
        is_readable: true,
        creator_component_id,
        in_waitable_set: Ref(false),
      },
    )
    async_state.future_endpoints.set_core(
      handle_key(creator_component_id, wh),
      {
        future_id,
        is_readable: false,
        creator_component_id,
        in_waitable_set: Ref(false),
      },
    )
    async_state.futures.set_core(future_id, {
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
  _tyidx : Int32,
  _opts : Array[CanonOpt],
  state : ComponentInstance,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32, I32], results: [I32], }
  let resources = resolve_canon_resources(_opts, state)
  let async_state = state.async_state
  let caller_component_id = state.resource_table.id
  let is_async = canon_opt_is_async(_opts)
  let payload_type : CanonicalPayloadType = {
    ty: match state.types.get(_tyidx) {
      Some(Some(Future(ty))) => ty
      _ => None
    },
    types: state.types,
  }
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    fn ret_i32(n : Int32) -> Array[@types.Value] {
      [I32(n)]
    }
    match args {
      [I32(_), I32(ptr)] =>
        payload_type.check_transmit_buffer(
          resources,
          store,
          ptr.to_int64() & 0xffffffffL,
          1,
        ) catch {
          error => trap_canon(canon_err_message(error))
        }
      _ => ()
    }
    let resumed_sync = match args {
      [I32(handle), _] =>
        async_state.resume_transmit_use(
          caller_component_id, handle, task_id, is_async,
        )
      _ => false
    }
    match args {
      [I32(handle), I32(ptr)] =>
        match
          async_state.future_endpoints.get(
            handle_key(caller_component_id, handle),
          ) {
          None => trap_canon("unknown future handle index \{handle}")
          Some(ep) =>
            if !ep.is_readable {
              trap_canon("type mismatch")
            } else {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => trap_canon("unknown future handle index \{handle}")
              }
              match async_state.host_future_values.get(ep.future_id) {
                Some(host_value) => {
                  if st0.read_done {
                    trap_canon(
                      "cannot read from future after previous read succeeded",
                    )
                  }
                  let polled = poll_host_future_value(host_value) catch {
                    e => trap_canon(e.to_string())
                  }
                  match polled {
                    Ready(value) => {
                      let value = transfer_stream_future_value(
                        host_value.payload_ty,
                        value,
                        host_value.types,
                        async_state,
                        ep.creator_component_id,
                        caller_component_id,
                      ) catch {
                        e => trap_canon(e.to_string())
                      }
                      store_host_stream_value(
                        value,
                        host_value.payload_ty,
                        host_value.types,
                        resources,
                        store,
                        state.resource_table,
                        ptr.to_int64() & 0xffffffffL,
                      ) catch {
                        e => trap_canon(e.to_string())
                      }
                      async_state.host_future_values.remove(ep.future_id)
                      async_state.futures.replace(ep.future_id, {
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
              }
              if st0.pending_read is Some(_) {
                if is_async {
                  trap_canon(
                    "cannot have concurrent operations active on a future/stream",
                  )
                }
                if !async_state.task_can_block[0] {
                  trap_canon("cannot block a synchronous task before returning")
                }
                mark_sync_waitable_blocked(
                  async_state, caller_component_id, handle, task_id,
                )
                @core.set_suspension(Some(Yield))
                raise Unreachable
              }
              match st0.pending_write {
                Some(pw) => {
                  if pw.writer_component_id == caller_component_id &&
                    !payload_allows_intra_component_transfer(st0.payload_ty) {
                    trap_canon(
                      "cannot read from and write to intra-component future/stream with non-numeric payload",
                    )
                  }
                  store_future_payload(
                    pw.payload,
                    pw.writer_component_id,
                    payload_type,
                    async_state,
                    store,
                    resources,
                    state.resource_table,
                    ptr.to_int64() & 0xffffffffL,
                  ) catch {
                    error => trap_canon(canon_err_message(error))
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
                  async_state.futures.replace(ep.future_id, {
                    ..st0,
                    pending_read: None,
                    pending_write: None,
                    read_done: true,
                    write_succeeded: true,
                  })
                  ret_i32(0)
                }
                None =>
                  if st0.writable_dropped {
                    async_state.futures.replace(ep.future_id, {
                      ..st0,
                      pending_read: None,
                      pending_write: None,
                      read_done: true,
                    })
                    ret_i32(1)
                  } else {
                    // Register a pending read and report BLOCKED=-1.
                    if !is_async && !async_state.task_can_block[0] {
                      trap_canon(
                        "cannot block a synchronous task before returning",
                      )
                    }
                    async_state.futures.replace(ep.future_id, {
                      ..st0,
                      pending_read: Some({
                        // Remember the reader-side canon memory so a writer from a different
                        // component instance can write into the correct memory.
                        mem_addr: resources.mem_addr,
                        realloc: resources.realloc,
                        encoding: resources.encoding,
                        payload_type,
                        reader_table: state.resource_table,
                        ptr: ptr.to_int64() & 0xffffffffL,
                        reader_component_id: caller_component_id,
                        reader_handle: handle,
                      }),
                      pending_write: None,
                    })
                    if is_async {
                      ret_i32(-1)
                    } else {
                      mark_sync_waitable_blocked(
                        async_state, caller_component_id, handle, task_id,
                      )
                      @core.set_suspension(Some(Yield))
                      raise Unreachable
                    }
                  }
              }
            }
        }
      _ => trap_canon("type mismatch")
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
        guard async_state.future_endpoints.get(
            handle_key(read.reader_component_id, read.reader_handle),
          )
          is Some(endpoint) else {
          raise CanonCallError("pending future reader is not live")
        }
        let value = transfer_stream_future_value(
          source.payload_ty,
          value,
          source.types,
          async_state,
          endpoint.creator_component_id,
          read.reader_component_id,
        )
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
        async_state.futures.replace(future_id, {
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
  _tyidx : Int32,
  _opts : Array[CanonOpt],
  state : ComponentInstance,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32, I32], results: [I32], }
  let resources = resolve_canon_resources(_opts, state)
  let async_state = state.async_state
  let caller_component_id = state.resource_table.id
  let writer_table = state.resource_table
  let is_async = canon_opt_is_async(_opts)
  let payload_type : CanonicalPayloadType = {
    ty: match state.types.get(_tyidx) {
      Some(Some(Future(ty))) => ty
      _ => None
    },
    types: state.types,
  }
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    fn ret_i32(n : Int32) -> Array[@types.Value] {
      [I32(n)]
    }
    match args {
      [I32(_), I32(ptr)] =>
        payload_type.check_transmit_buffer(
          resources,
          store,
          ptr.to_int64() & 0xffffffffL,
          1,
        ) catch {
          error => trap_canon(canon_err_message(error))
        }
      _ => ()
    }
    let resumed_sync = match args {
      [I32(handle), _] =>
        async_state.resume_transmit_use(
          caller_component_id, handle, task_id, is_async,
        )
      _ => false
    }
    match args {
      [I32(handle), I32(ptr)] =>
        match
          async_state.future_endpoints.get(
            handle_key(caller_component_id, handle),
          ) {
          None => trap_canon("unknown future handle index \{handle}")
          Some(ep) =>
            if ep.is_readable {
              trap_canon("type mismatch")
            } else {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => trap_canon("unknown future handle index \{handle}")
              }
              if st0.write_succeeded {
                if resumed_sync {
                  remove_waitable_events_for(
                    async_state, caller_component_id, handle, 5,
                  )
                  return ret_i32(0)
                }
                trap_canon(
                  "cannot write to future after previous write succeeded or readable end dropped",
                )
              }
              if st0.write_observed_readable_drop {
                if resumed_sync {
                  remove_waitable_events_for(
                    async_state, caller_component_id, handle, 5,
                  )
                  return ret_i32(1)
                }
                trap_canon(
                  "cannot write after being notified that the readable end dropped",
                )
              }
              if st0.pending_write is Some(_) {
                if is_async {
                  trap_canon(
                    "cannot have concurrent operations active on a future/stream",
                  )
                }
                if !async_state.task_can_block[0] {
                  trap_canon("cannot block a synchronous task before returning")
                }
                mark_sync_waitable_blocked(
                  async_state, caller_component_id, handle, task_id,
                )
                @core.set_suspension(Some(Yield))
                raise Unreachable
              }

              // If the readable end was dropped before any rendezvous, report DROPPED.
              if st0.readable_dropped {
                async_state.futures.replace(ep.future_id, {
                  ..st0,
                  pending_read: None,
                  pending_write: None,
                  write_succeeded: false,
                  write_observed_readable_drop: true,
                })
                return ret_i32(1)
              }
              match st0.pending_read {
                Some(pr) => {
                  if pr.reader_component_id == caller_component_id &&
                    !payload_allows_intra_component_transfer(st0.payload_ty) {
                    trap_canon(
                      "cannot read from and write to intra-component future/stream with non-numeric payload",
                    )
                  }
                  let payload = payload_type.load(
                    resources,
                    store,
                    ptr.to_int64() & 0xffffffffL,
                    1,
                    writer_table,
                  ) catch {
                    error => trap_canon(canon_err_message(error))
                  }
                  store_future_payload(
                    payload,
                    caller_component_id,
                    pr.payload_type,
                    async_state,
                    store,
                    {
                      mem_addr: pr.mem_addr,
                      realloc: pr.realloc,
                      encoding: pr.encoding,
                      post_return: None,
                    },
                    pr.reader_table,
                    pr.ptr,
                  ) catch {
                    error => trap_canon(canon_err_message(error))
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
                  async_state.futures.replace(ep.future_id, {
                    ..st0,
                    pending_read: None,
                    pending_write: None,
                    read_done: true,
                    write_succeeded: true,
                    wrote_value: true,
                  })
                  ret_i32(0)
                }
                None => {
                  // Register a pending write by reading the payload once.
                  if !is_async && !async_state.task_can_block[0] {
                    trap_canon(
                      "cannot block a synchronous task before returning",
                    )
                  }
                  let payload = payload_type.load(
                    resources,
                    store,
                    ptr.to_int64() & 0xffffffffL,
                    1,
                    writer_table,
                  ) catch {
                    error => trap_canon(canon_err_message(error))
                  }
                  async_state.futures.replace(ep.future_id, {
                    ..st0,
                    pending_read: None,
                    pending_write: Some({
                      writer_component_id: caller_component_id,
                      writer_handle: handle,
                      payload,
                    }),
                    wrote_value: true,
                  })
                  if is_async {
                    ret_i32(-1)
                  } else {
                    mark_sync_waitable_blocked(
                      async_state, caller_component_id, handle, task_id,
                    )
                    @core.set_suspension(Some(Yield))
                    raise Unreachable
                  }
                }
              }
            }
        }
      _ => trap_canon("type mismatch")
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
fn instantiate_canon_future_cancel(
  is_async_cancel : Bool,
  state : ComponentInstance,
  store : @runtime.Store,
  readable~ : Bool,
) -> Unit raise ComponentRuntimeError {
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  instantiate_waitable_cancel(state, store, is_async_cancel, fn(
    handle : Int32,
  ) -> Int32 raise @runtime.RuntimeError {
    guard async_state.future_endpoints.get(
        handle_key(owner_component_id, handle),
      )
      is Some(ep) else {
      trap_canon("unknown future handle index \{handle}")
    }
    guard ep.is_readable == readable else { trap_canon("type mismatch") }
    guard async_state.futures.get(ep.future_id) is Some(st) else {
      trap_canon("unknown future handle index \{handle}")
    }
    // Completed operations report their terminal status when cancelled.
    if readable {
      if st.read_done {
        remove_waitable_events_for(async_state, owner_component_id, handle, 4)
        if st.write_succeeded {
          0
        } else if st.writable_dropped {
          1
        } else {
          2
        }
      } else {
        if st.pending_read is Some(_) {
          async_state.futures.replace(ep.future_id, {
            ..st,
            pending_read: None,
          })
        }
        2
      }
    } else if st.write_succeeded {
      remove_waitable_events_for(async_state, owner_component_id, handle, 5)
      0
    } else if st.readable_dropped || st.write_observed_readable_drop {
      remove_waitable_events_for(async_state, owner_component_id, handle, 5)
      1
    } else {
      if st.pending_write is Some(_) {
        async_state.futures.replace(ep.future_id, {
          ..st,
          pending_write: None,
          wrote_value: false,
        })
      }
      2
    }
  })
}

///|
fn instantiate_canon_future_drop_readable(
  _tyidx : Int32,
  state : ComponentInstance,
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
              trap_canon("type mismatch")
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
              async_state.futures.replace(ep.future_id, {
                ..st0,
                pending_read: None,
                pending_write: None,
                readable_dropped: true,
                read_done: true,
                write_observed_readable_drop: st0.pending_write is Some(_) ||
                st0.write_observed_readable_drop,
              })
              match async_state.host_future_values.get(ep.future_id) {
                Some(source) =>
                  match source.cancel {
                    Some(cancel) =>
                      cancel() catch {
                        e => trap_canon(canon_err_message(e))
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
          None => trap_canon("unknown future handle index \{handle}")
        }
      _ => []
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_future_drop_writable(
  _tyidx : Int32,
  state : ComponentInstance,
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
              trap_canon("type mismatch")
            } else {
              let st0 = match async_state.futures.get(ep.future_id) {
                Some(s) => s
                None => return []
              }
              if !st0.wrote_value && !st0.write_succeeded {
                trap_canon(
                  "cannot drop future write end without first writing a value",
                )
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
              async_state.futures.replace(ep.future_id, {
                ..st0,
                pending_read: None,
                writable_dropped: true,
                read_done: st0.pending_read is Some(_) || st0.read_done,
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
          None => trap_canon("unknown future handle index \{handle}")
        }
      _ => []
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}
