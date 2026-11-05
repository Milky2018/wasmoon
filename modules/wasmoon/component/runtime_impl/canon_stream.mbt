///|
/// Canonical section instantiation helpers.
/// (group: stream)

///|
fn instantiate_canon_stream_new(
  _tyidx : Int32,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [], results: [I64], }
  let payload_ty : ValType? = match state.types.get(_tyidx) {
    Some(Some(Stream(v))) => v
    _ => None
  }
  let allows_intra_component = payload_allows_intra_component_transfer(
    payload_ty.map(ty => resolve_valtype(ty, state.types)),
  )
  let table = state.stream_table
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    _args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }

    let sid = table.next_stream_id[0]
    table.next_stream_id[0] = sid + 1
    errdefer table.streams.remove(sid)
    table.streams.set_core(sid, {
      allows_intra_component,
      pending_read: None,
      pending_write: None,
      readable_dropped: false,
      writable_dropped: false,
    })
    // Handle numbering is observable by tests/upstream/component-model/upstream/async tests.
    //
    // Allocate readable first, then writable. The shared allocator already
    // deterministically reuses the smallest freed handle (when available),
    // which is the behavior tests rely on.
    let rh = alloc_shared_handle(async_state, owner_component_id)
    let wh = alloc_shared_handle(async_state, owner_component_id)
    errdefer {
      table.endpoints.remove(handle_key(owner_component_id, rh))
      table.endpoints.remove(handle_key(owner_component_id, wh))
      free_shared_handle(async_state, owner_component_id, rh)
      free_shared_handle(async_state, owner_component_id, wh)
    }
    table.endpoints.set_core(handle_key(owner_component_id, rh), {
      stream_id: sid,
      is_readable: true,
      notified_peer_dropped: [false],
      in_waitable_set: Ref(false),
    })
    table.endpoints.set_core(handle_key(owner_component_id, wh), {
      stream_id: sid,
      is_readable: false,
      notified_peer_dropped: [false],
      in_waitable_set: Ref(false),
    })
    set_canon_debug_message(
      "stream.new(owner=\{owner_component_id})-> rh=\{rh} wh=\{wh}",
    )
    let packed = (wh.to_int64() << 32) | (rh.to_int64() & 0xFFFFFFFFL)
    [I64(packed)]
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn store_host_stream_value(
  value : ComponentValue,
  payload_ty : ValType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
  table : ResourceTable,
  ptr : Int64,
) -> Unit raise ComponentRuntimeError {
  let mem = require_memory(resources, store)
  let mem_is_64 = mem.is_memory64()
  let values = lower_component_value_to_flat(
    value,
    payload_ty,
    types,
    resources,
    store,
    (table, table),
  )
  store_flat_component_value_to_memory(
    mem, ptr, payload_ty, values, types, mem_is_64,
  )
}

///|
fn poll_host_value_stream(
  source : HostValueStream,
  max_elements : Int32,
) -> HostValueStreamPoll raise ComponentRuntimeError {
  let remaining = source.values.length() - source.next.val
  if remaining > 0 {
    let count = if max_elements < remaining { max_elements } else { remaining }
    let values : Array[ComponentValue] = []
    for i in 0..<count {
      values.push(source.values[source.next.val + i])
    }
    source.next.val = source.next.val + count
    Values(values)
  } else if source.closed.val {
    Closed
  } else {
    match source.pull {
      Some(pull) =>
        match pull(max_elements) {
          Closed => {
            source.closed.val = true
            Closed
          }
          result => result
        }
      None => {
        source.closed.val = true
        Closed
      }
    }
  }
}

///|
fn progress_host_stream_sources(
  async_state : AsyncState,
  store : @runtime.Store,
) -> Bool raise ComponentRuntimeError {
  let table = async_state.stream_table
  let mut progressed = false
  for item in table.host_values.iter() {
    let (stream_id, source) = item
    guard table.streams.get(stream_id) is Some(state) &&
      state.pending_read is Some(read) &&
      !read.event_enqueued else {
      continue
    }
    match poll_host_value_stream(source, read.len - read.filled) {
      Pending => ()
      Closed => {
        table.streams.replace(stream_id, {
          allows_intra_component: state.allows_intra_component,
          pending_read: Some({ ..read, event_enqueued: true, }),
          pending_write: state.pending_write,
          readable_dropped: state.readable_dropped,
          writable_dropped: true,
        })
        enqueue_waitable_event(
          async_state,
          handle_key(read.reader_table.id, read.reader_handle),
          {
            owner_component_id: read.reader_table.id,
            code: 2,
            index: read.reader_handle,
            payload: 1 | (read.filled << 4),
          },
        )
        progressed = true
      }
      Values(values) => {
        let resources : CanonResources = {
          mem_addr: read.mem_addr,
          realloc: read.realloc,
          post_return: None,
          encoding: read.encoding,
        }
        for i, value in values {
          store_host_stream_value(
            value,
            source.payload_ty,
            source.types,
            resources,
            store,
            read.reader_table,
            read.ptr +
            (read.filled.to_int64() + i.to_int64()) *
            read.payload_type.layout(resources, store).0.to_int64(),
          )
        }
        let filled = read.filled + values.length()
        table.streams.replace(stream_id, {
          allows_intra_component: state.allows_intra_component,
          pending_read: Some({ ..read, filled, event_enqueued: true, }),
          pending_write: state.pending_write,
          readable_dropped: state.readable_dropped,
          writable_dropped: false,
        })
        enqueue_waitable_event(
          async_state,
          handle_key(read.reader_table.id, read.reader_handle),
          {
            owner_component_id: read.reader_table.id,
            code: 2,
            index: read.reader_handle,
            payload: filled << 4,
          },
        )
        progressed = true
      }
    }
  }
  progressed
}

///|
fn instantiate_canon_stream_read(
  _tyidx : Int32,
  opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32, I32, I32], results: [I32], }
  let resources = resolve_canon_resources(opts, state)
  let payload_ty : ValType? = match state.types.get(_tyidx) {
    Some(Some(Stream(v))) => v
    _ => None
  }
  let payload_type : CanonicalPayloadType = {
    ty: payload_ty,
    types: state.types,
  }
  let is_async = canon_opt_is_async(opts)
  let reader_table = state.resource_table
  let table = state.stream_table
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    fn ret_i32(code : Int32) -> Array[@types.Value] {
      [I32(code)]
    }

    let (elem_size, _) = payload_type.layout(resources, store) catch {
      error => trap_canon(canon_err_message(error))
    }
    match args {
      [I32(handle), I32(ptr), I32(len)] => {
        let ptr = ptr.to_int64() & 0xffffffffL
        payload_type.check_transmit_buffer(resources, store, ptr, len) catch {
          error => trap_canon(canon_err_message(error))
        }
        if table.endpoints.get(handle_key(owner_component_id, handle))
          is Some(ep) &&
          ep.notified_peer_dropped[0] {
          trap_canon(
            "cannot read after being notified that the writable end dropped",
          )
        }
        async_state.resume_transmit_use(
          owner_component_id, handle, task_id, is_async,
        )
        |> ignore
        // BLOCKED=-1, COMPLETED=0 | (n<<4), DROPPED=1 | (n<<4)
        if len.reinterpret_as_uint() > 0x0fffffffU {
          trap_canon("stream read/write count too large")
        } else {
          let key = handle_key(owner_component_id, handle)
          match table.endpoints.get(key) {
            None => trap_canon("unknown stream handle index \{handle}")
            Some(ep) =>
              if !ep.is_readable {
                trap_canon("type mismatch")
              } else {
                let st0 = match table.streams.get(ep.stream_id) {
                  Some(s) => s
                  None => trap_canon("unknown stream handle index \{handle}")
                }
                match table.host_values.get(ep.stream_id) {
                  Some(source) => {
                    match st0.pending_read {
                      Some(read) =>
                        if is_async {
                          trap_canon(
                            "cannot have concurrent operations active on a future/stream",
                          )
                        } else if read.reader_handle == handle &&
                          read.event_enqueued {
                          table.streams.replace(ep.stream_id, {
                            ..st0,
                            pending_read: None,
                          })
                          if st0.writable_dropped {
                            ep.notified_peer_dropped[0] = true
                          }
                          return ret_i32(
                            (if st0.writable_dropped { 1 } else { 0 }) |
                            (read.filled << 4),
                          )
                        } else {
                          return ret_i32(-1)
                        }
                      None => ()
                    }
                    let poll_result = poll_host_value_stream(source, len) catch {
                      e => trap_canon(e.to_string())
                    }
                    match poll_result {
                      Values(values) => {
                        for i, value in values {
                          store_host_stream_value(
                            value,
                            source.payload_ty,
                            source.types,
                            resources,
                            store,
                            reader_table,
                            ptr + i.to_int64() * elem_size.to_int64(),
                          ) catch {
                            e => trap_canon(e.to_string())
                          }
                        }
                        return ret_i32(values.length() << 4)
                      }
                      Closed => {
                        ep.notified_peer_dropped[0] = true
                        table.streams.replace(ep.stream_id, {
                          allows_intra_component: st0.allows_intra_component,
                          pending_read: None,
                          pending_write: st0.pending_write,
                          readable_dropped: st0.readable_dropped,
                          writable_dropped: true,
                        })
                        return ret_i32(1)
                      }
                      Pending => {
                        table.streams.replace(ep.stream_id, {
                          allows_intra_component: st0.allows_intra_component,
                          pending_read: Some({
                            mem_addr: resources.mem_addr,
                            realloc: resources.realloc,
                            encoding: resources.encoding,
                            payload_type,
                            reader_table,
                            ptr,
                            len,
                            filled: 0,
                            reader_handle: handle,
                            event_enqueued: false,
                          }),
                          pending_write: st0.pending_write,
                          readable_dropped: st0.readable_dropped,
                          writable_dropped: false,
                        })
                        if is_async {
                          return ret_i32(-1)
                        }
                        mark_sync_waitable_blocked(
                          async_state, owner_component_id, handle, task_id,
                        )
                        @core.set_suspension(Some(Yield))
                        raise Unreachable
                      }
                    }
                  }
                  None => ()
                }
                // If re-executing a previously blocking read, return its completion.
                match st0.pending_read {
                  Some(pr0) =>
                    if is_async {
                      trap_canon(
                        "cannot have concurrent operations active on a future/stream",
                      )
                    } else if pr0.reader_handle == handle {
                      if pr0.filled == pr0.len || st0.writable_dropped {
                        let dropped = if st0.writable_dropped { 1 } else { 0 }
                        if dropped == 1 {
                          ep.notified_peer_dropped[0] = true
                        }
                        table.streams.replace(ep.stream_id, {
                          ..st0,
                          pending_read: None,
                        })
                        let out_code = dropped | (pr0.filled << 4)
                        set_canon_debug_message(
                          "stream.read(handle=\{handle} len=\{len})-> \{out_code}",
                        )
                        return ret_i32(out_code)
                      } else if is_async {
                        set_canon_debug_message(
                          "stream.read(handle=\{handle} len=\{len})-> -1",
                        )
                        return ret_i32(-1)
                      } else {
                        if !async_state.task_can_block[0] {
                          trap_canon(
                            "cannot block a synchronous task before returning",
                          )
                        }
                        mark_sync_waitable_blocked(
                          async_state, owner_component_id, handle, task_id,
                        )
                        @core.set_suspension(Some(Yield))
                        raise Unreachable
                      }
                    } else {
                      // Another read is already in progress.
                      trap_canon("cannot remove busy stream")
                    }
                  None => ()
                }
                match st0.pending_write {
                  Some(pw) => {
                    if pw.writer_table.id == owner_component_id &&
                      !st0.allows_intra_component {
                      trap_canon(
                        "cannot read from and write to intra-component future/stream with non-numeric payload",
                      )
                    }

                    let total_elems = pw.count
                    let remain = total_elems - pw.sent
                    if remain <= 0 {
                      let mut pw_event_enqueued = pw.event_enqueued
                      if !pw_event_enqueued {
                        enqueue_waitable_event(
                          async_state,
                          handle_key(pw.writer_table.id, pw.writer_handle),
                          {
                            owner_component_id: pw.writer_table.id,
                            code: 3,
                            index: pw.writer_handle,
                            payload: (if st0.readable_dropped { 1 } else { 0 }) |
                            (total_elems << 4),
                          },
                        )
                        pw_event_enqueued = true
                      }
                      // Persist the updated `event_enqueued` bit and then behave as if there is
                      // no pending data for readers.
                      table.streams.replace(ep.stream_id, {
                        ..st0,
                        pending_write: Some({
                          ..pw,
                          event_enqueued: pw_event_enqueued,
                        }),
                      })
                      if st0.writable_dropped {
                        ep.notified_peer_dropped[0] = true
                        set_canon_debug_message(
                          "stream.read(handle=\{handle} len=\{len})-> 1",
                        )
                        return ret_i32(1)
                      }
                      let pr = {
                        mem_addr: resources.mem_addr,
                        realloc: resources.realloc,
                        encoding: resources.encoding,
                        payload_type,
                        reader_table,
                        ptr,
                        len,
                        filled: 0,
                        reader_handle: handle,
                        event_enqueued: false,
                      }
                      table.streams.replace(ep.stream_id, {
                        allows_intra_component: st0.allows_intra_component,
                        pending_read: Some(pr),
                        pending_write: Some({
                          ..pw,
                          event_enqueued: pw_event_enqueued,
                        }),
                        readable_dropped: st0.readable_dropped,
                        writable_dropped: st0.writable_dropped,
                      })
                      if is_async {
                        set_canon_debug_message(
                          "stream.read(handle=\{handle} len=\{len})-> -1",
                        )
                        return ret_i32(-1)
                      } else {
                        if !async_state.task_can_block[0] {
                          trap_canon(
                            "cannot block a synchronous task before returning",
                          )
                        }
                        mark_sync_waitable_blocked(
                          async_state, owner_component_id, handle, task_id,
                        )
                        @core.set_suspension(Some(Yield))
                        raise Unreachable
                      }
                    }
                    let n = if len < remain { len } else { remain }
                    pw.buf.store(
                      pw.sent,
                      n,
                      pw.writer_table,
                      payload_type,
                      resources,
                      store,
                      reader_table,
                      async_state,
                      ptr,
                    ) catch {
                      error => trap_canon(canon_err_message(error))
                    }
                    let new_sent = pw.sent + n
                    // Publish cumulative progress. Further reads may extend
                    // the same pending write before the event is observed, in
                    // which case the queued event is replaced.
                    let mut event_enqueued = pw.event_enqueued
                    if n > 0 {
                      if event_enqueued {
                        remove_waitable_events_for(
                          async_state,
                          pw.writer_table.id,
                          pw.writer_handle,
                          3,
                        )
                      }
                      enqueue_waitable_event(
                        async_state,
                        handle_key(pw.writer_table.id, pw.writer_handle),
                        {
                          owner_component_id: pw.writer_table.id,
                          code: 3,
                          index: pw.writer_handle,
                          payload: (if st0.readable_dropped { 1 } else { 0 }) |
                          (new_sent << 4),
                        },
                      )
                      event_enqueued = true
                    }
                    let pw2 = Some({ ..pw, sent: new_sent, event_enqueued, })
                    table.streams.replace(ep.stream_id, {
                      ..st0,
                      pending_write: pw2,
                    })
                    let dropped = if st0.writable_dropped &&
                      new_sent == pw.count {
                      1
                    } else {
                      0
                    }
                    let out_code = dropped | (n << 4)
                    set_canon_debug_message(
                      "stream.read(handle=\{handle} len=\{len})-> \{out_code}",
                    )
                    ret_i32(out_code)
                  }
                  None =>
                    if st0.writable_dropped {
                      ep.notified_peer_dropped[0] = true
                      set_canon_debug_message(
                        "stream.read(handle=\{handle} len=\{len})-> 1",
                      )
                      ret_i32(1)
                    } else {
                      // Register a pending read and report BLOCKED.
                      let pr = {
                        mem_addr: resources.mem_addr,
                        realloc: resources.realloc,
                        encoding: resources.encoding,
                        payload_type,
                        reader_table,
                        ptr,
                        len,
                        filled: 0,
                        reader_handle: handle,
                        event_enqueued: false,
                      }
                      table.streams.replace(ep.stream_id, {
                        ..st0,
                        pending_read: Some(pr),
                      })
                      if is_async {
                        set_canon_debug_message(
                          "stream.read(handle=\{handle} len=\{len})-> -1",
                        )
                        ret_i32(-1)
                      } else {
                        if !async_state.task_can_block[0] {
                          trap_canon(
                            "cannot block a synchronous task before returning",
                          )
                        }
                        mark_sync_waitable_blocked(
                          async_state, owner_component_id, handle, task_id,
                        )
                        @core.set_suspension(Some(Yield))
                        raise Unreachable
                      }
                    }
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
fn instantiate_canon_stream_write(
  _tyidx : Int32,
  opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32, I32, I32], results: [I32], }
  let resources = resolve_canon_resources(opts, state)
  let payload_ty : ValType? = match state.types.get(_tyidx) {
    Some(Some(Stream(v))) => v
    _ => None
  }
  let payload_type : CanonicalPayloadType = {
    ty: payload_ty,
    types: state.types,
  }
  let is_async = canon_opt_is_async(opts)
  let writer_table = state.resource_table
  let table = state.stream_table
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let task_id = current_task_id(async_state)
    fn ret_i32(code : Int32) -> Array[@types.Value] {
      [I32(code)]
    }

    let _ = payload_type.layout(resources, store) catch {
      error => trap_canon(canon_err_message(error))
    }
    match args {
      [I32(handle), I32(ptr), I32(len)] => {
        let ptr = ptr.to_int64() & 0xffffffffL
        payload_type.check_transmit_buffer(resources, store, ptr, len) catch {
          error => trap_canon(canon_err_message(error))
        }
        async_state.resume_transmit_use(
          owner_component_id, handle, task_id, is_async,
        )
        |> ignore
        if len.reinterpret_as_uint() > 0x0fffffffU {
          trap_canon("stream read/write count too large")
        } else {
          match table.endpoints.get(handle_key(owner_component_id, handle)) {
            None => trap_canon("unknown stream handle index \{handle}")
            Some(ep) =>
              if ep.is_readable {
                trap_canon("type mismatch")
              } else {
                if ep.notified_peer_dropped[0] {
                  trap_canon(
                    "cannot write after being notified that the readable end dropped",
                  )
                }
                let st0 = match table.streams.get(ep.stream_id) {
                  Some(s) => s
                  None => trap_canon("unknown stream handle index \{handle}")
                }
                // A resumed blocking write retries this host instruction with
                // the same pending operation.
                match st0.pending_write {
                  Some(pw0) =>
                    if is_async {
                      trap_canon(
                        "cannot have concurrent operations active on a future/stream",
                      )
                    } else if pw0.writer_handle == handle {
                      let total_elems = pw0.count
                      if st0.readable_dropped || pw0.sent >= total_elems {
                        // Sync stream.write should observe a drop that happens immediately after a
                        // successful rendezvous (read returns to the caller and then the caller
                        // drops the readable end). Defer completion by one yield
                        // once the write becomes fully consumed.
                        if !is_async &&
                          !st0.readable_dropped &&
                          pw0.sent >= total_elems &&
                          !pw0.defer_complete {
                          table.streams.replace(ep.stream_id, {
                            ..st0,
                            pending_write: Some({ ..pw0, defer_complete: true, }),
                          })
                          mark_sync_waitable_blocked(
                            async_state, owner_component_id, handle, task_id,
                          )
                          @core.set_suspension(Some(Yield))
                          raise Unreachable
                        }
                        let dropped = if st0.readable_dropped { 1 } else { 0 }
                        if dropped == 1 {
                          ep.notified_peer_dropped[0] = true
                        }
                        table.streams.replace(ep.stream_id, {
                          ..st0,
                          pending_write: None,
                        })
                        let code = dropped | (pw0.sent << 4)
                        set_canon_debug_message(
                          "stream.write(handle=\{handle} len=\{len})-> \{code}",
                        )
                        return ret_i32(code)
                      } else if is_async {
                        set_canon_debug_message(
                          "stream.write(handle=\{handle} len=\{len})-> -1",
                        )
                        return ret_i32(-1)
                      } else {
                        if !async_state.task_can_block[0] {
                          trap_canon(
                            "cannot block a synchronous task before returning",
                          )
                        }
                        mark_sync_waitable_blocked(
                          async_state, owner_component_id, handle, task_id,
                        )
                        @core.set_suspension(Some(Yield))
                        raise Unreachable
                      }
                    } else {
                      trap_canon("cannot drop busy stream")
                    }
                  None => ()
                }
                if st0.readable_dropped {
                  ep.notified_peer_dropped[0] = true
                  set_canon_debug_message(
                    "stream.write(handle=\{handle} len=\{len})-> 1",
                  )
                  return ret_i32(1)
                }
                match st0.pending_read {
                  Some(pr0) => {
                    if pr0.reader_table.id == owner_component_id &&
                      !st0.allows_intra_component {
                      trap_canon(
                        "cannot read from and write to intra-component future/stream with non-numeric payload",
                      )
                    }
                    // A zero-length write reports readiness without completing the reader.
                    if len == 0 {
                      return ret_i32(0)
                    }

                    let remain = pr0.len - pr0.filled
                    if remain <= 0 {
                      // A pending zero-length read completes when a nonempty write arrives.
                      // Keep the write pending until a subsequent read consumes its data.
                      let pending_read = if pr0.len == 0 && !pr0.event_enqueued {
                        enqueue_waitable_event(
                          async_state,
                          handle_key(pr0.reader_table.id, pr0.reader_handle),
                          {
                            owner_component_id: pr0.reader_table.id,
                            code: 2,
                            index: pr0.reader_handle,
                            payload: 0,
                          },
                        )
                        Some({ ..pr0, event_enqueued: true, })
                      } else {
                        st0.pending_read
                      }
                      let buf = payload_type.load(
                        resources, store, ptr, len, writer_table,
                      ) catch {
                        error => trap_canon(canon_err_message(error))
                      }
                      table.streams.replace(ep.stream_id, {
                        allows_intra_component: st0.allows_intra_component,
                        pending_read,
                        pending_write: Some({
                          writer_table,
                          buf,
                          count: len,
                          sent: 0,
                          writer_handle: handle,
                          event_enqueued: false,
                          defer_complete: false,
                        }),
                        readable_dropped: st0.readable_dropped,
                        writable_dropped: st0.writable_dropped,
                      })
                      if is_async {
                        set_canon_debug_message(
                          "stream.write(handle=\{handle} len=\{len})-> -1",
                        )
                        return ret_i32(-1)
                      } else {
                        if !async_state.task_can_block[0] {
                          trap_canon(
                            "cannot block a synchronous task before returning",
                          )
                        }
                        mark_sync_waitable_blocked(
                          async_state, owner_component_id, handle, task_id,
                        )
                        @core.set_suspension(Some(Yield))
                        raise Unreachable
                      }
                    }
                    let n = if len < remain { len } else { remain }
                    // Snapshot src bytes first to preserve memmove semantics when regions overlap.
                    let buf = payload_type.load(
                      resources, store, ptr, len, writer_table,
                    ) catch {
                      error => trap_canon(canon_err_message(error))
                    }
                    let reader_resources : CanonResources = {
                      mem_addr: pr0.mem_addr,
                      realloc: pr0.realloc,
                      encoding: pr0.encoding,
                      post_return: None,
                    }
                    let (reader_size, _) = pr0.payload_type.layout(
                      reader_resources, store,
                    ) catch {
                      error => trap_canon(canon_err_message(error))
                    }
                    buf.store(
                      0,
                      n,
                      writer_table,
                      pr0.payload_type,
                      reader_resources,
                      store,
                      pr0.reader_table,
                      async_state,
                      pr0.ptr + pr0.filled.to_int64() * reader_size.to_int64(),
                    ) catch {
                      error => trap_canon(canon_err_message(error))
                    }
                    let filled1 = pr0.filled + n
                    let mut event_enqueued = pr0.event_enqueued
                    // Publish cumulative progress, replacing an earlier event
                    // if another write arrives before it is observed.
                    if n > 0 || st0.writable_dropped {
                      if event_enqueued {
                        remove_waitable_events_for(
                          async_state,
                          pr0.reader_table.id,
                          pr0.reader_handle,
                          2,
                        )
                      }
                      enqueue_waitable_event(
                        async_state,
                        handle_key(pr0.reader_table.id, pr0.reader_handle),
                        {
                          owner_component_id: pr0.reader_table.id,
                          code: 2,
                          index: pr0.reader_handle,
                          payload: (if st0.writable_dropped { 1 } else { 0 }) |
                          (filled1 << 4),
                        },
                      )
                      event_enqueued = true
                    }
                    let pr1 = { ..pr0, filled: filled1, event_enqueued, }
                    table.streams.replace(ep.stream_id, {
                      ..st0,
                      pending_read: Some(pr1),
                    })
                    let out_code = n << 4
                    set_canon_debug_message(
                      "stream.write(handle=\{handle} len=\{len})-> \{out_code}",
                    )
                    ret_i32(out_code)
                  }
                  None => {
                    // Register a pending write by copying bytes.
                    let buf = payload_type.load(
                      resources, store, ptr, len, writer_table,
                    ) catch {
                      error => trap_canon(canon_err_message(error))
                    }
                    table.streams.replace(ep.stream_id, {
                      ..st0,
                      pending_write: Some({
                        writer_table,
                        buf,
                        count: len,
                        sent: 0,
                        writer_handle: handle,
                        event_enqueued: false,
                        defer_complete: false,
                      }),
                    })
                    if is_async {
                      set_canon_debug_message(
                        "stream.write(handle=\{handle} len=\{len})-> -1",
                      )
                      ret_i32(-1)
                    } else {
                      if !async_state.task_can_block[0] {
                        trap_canon(
                          "cannot block a synchronous task before returning",
                        )
                      }
                      mark_sync_waitable_blocked(
                        async_state, owner_component_id, handle, task_id,
                      )
                      @core.set_suspension(Some(Yield))
                      raise Unreachable
                    }
                  }
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
fn instantiate_canon_stream_cancel(
  is_async_cancel : Bool,
  state : BuildState,
  store : @runtime.Store,
  readable~ : Bool,
) -> Unit raise ComponentRuntimeError {
  let table = state.stream_table
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  instantiate_waitable_cancel(state, store, is_async_cancel, fn(
    handle : Int32,
  ) -> Int32 raise @runtime.RuntimeError {
    guard table.endpoints.get(handle_key(owner_component_id, handle))
      is Some(ep) else {
      trap_canon("unknown stream handle index \{handle}")
    }
    guard ep.is_readable == readable else { trap_canon("type mismatch") }
    guard table.streams.get(ep.stream_id) is Some(st) else {
      trap_canon("unknown stream handle index \{handle}")
    }
    let (event_code, payload) = if readable {
      guard st.pending_read is Some(read) else {
        trap_canon("stream or future read cancelled when no read is pending")
      }
      (2, (if st.writable_dropped { 1 } else { 2 }) | (read.filled << 4))
    } else {
      guard st.pending_write is Some(write) else {
        trap_canon("stream or future write cancelled when no write is pending")
      }
      (3, (if st.readable_dropped { 1 } else { 2 }) | (write.sent << 4))
    }
    remove_waitable_events_for(
      async_state, owner_component_id, handle, event_code,
    )
    acknowledge_waitable_event(async_state, {
      owner_component_id,
      code: event_code,
      index: handle,
      payload,
    })
    payload
  })
}

///|
fn instantiate_canon_stream_drop_readable(
  _tyidx : Int32,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32], results: [], }
  let table = state.stream_table
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
        match table.endpoints.get(handle_key(owner_component_id, handle)) {
          None => trap_canon("unknown stream handle index \{handle}")
          Some(ep) =>
            if !ep.is_readable {
              trap_canon("type mismatch")
            } else {
              let st0 = match table.streams.get(ep.stream_id) {
                Some(s) => s
                None => trap_canon("unknown stream handle index \{handle}")
              }
              // Dropping a readable endpoint is only invalid if there is an
              // active read in progress on that endpoint.
              if st0.pending_read is Some(_) {
                trap_canon("cannot remove busy stream")
              }
              // Dropping readable may resolve a pending write as DROPPED.
              match st0.pending_write {
                Some(pw) => {
                  let payload = 1 | (pw.sent << 4)
                  // Overwrite any previously queued STREAM_WRITE completion event so the
                  // writer observes the dropped bit (Wasmtime's `update_event` behavior).
                  remove_waitable_events_for(
                    async_state,
                    pw.writer_table.id,
                    pw.writer_handle,
                    3,
                  )
                  enqueue_waitable_event(
                    async_state,
                    handle_key(pw.writer_table.id, pw.writer_handle),
                    {
                      owner_component_id: pw.writer_table.id,
                      code: 3,
                      index: pw.writer_handle,
                      payload,
                    },
                  )
                  table.streams.replace(ep.stream_id, {
                    allows_intra_component: st0.allows_intra_component,
                    pending_read: st0.pending_read,
                    pending_write: Some({ ..pw, event_enqueued: true, }),
                    readable_dropped: true,
                    writable_dropped: st0.writable_dropped,
                  })
                }
                None =>
                  table.streams.replace(ep.stream_id, {
                    ..st0,
                    readable_dropped: true,
                  })
              }
              // Remove from any waitable-set membership and queued events.
              remove_waitable_membership(
                async_state, owner_component_id, handle,
              )
              table.endpoints.remove(handle_key(owner_component_id, handle))
              match table.host_values.get(ep.stream_id) {
                Some(source) =>
                  match source.cancel {
                    Some(cancel) => cancel()
                    None => ()
                  }
                None => ()
              }
              table.host_values.remove(ep.stream_id)
              free_shared_handle(async_state, owner_component_id, handle)
              cleanup_closed_stream(table, ep.stream_id)
              []
            }
        }
      _ => trap_canon("type mismatch")
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_stream_drop_writable(
  _tyidx : Int32,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32], results: [], }
  let table = state.stream_table
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
        match table.endpoints.get(handle_key(owner_component_id, handle)) {
          None => trap_canon("unknown stream handle index \{handle}")
          Some(ep) =>
            if ep.is_readable {
              trap_canon("type mismatch")
            } else {
              let st0 = match table.streams.get(ep.stream_id) {
                Some(s) => s
                None => trap_canon("unknown stream handle index \{handle}")
              }
              // Dropping a writable endpoint is only invalid if there is an
              // active write in progress on that endpoint.
              if st0.pending_write is Some(_) {
                trap_canon("cannot drop busy stream")
              }
              // Dropping writable may resolve a pending read as DROPPED.
              match st0.pending_read {
                Some(pr) => {
                  let payload = 1 | (pr.filled << 4)
                  // Overwrite any previously queued STREAM_READ completion event so the
                  // reader observes the dropped bit.
                  remove_waitable_events_for(
                    async_state,
                    pr.reader_table.id,
                    pr.reader_handle,
                    2,
                  )
                  enqueue_waitable_event(
                    async_state,
                    handle_key(pr.reader_table.id, pr.reader_handle),
                    {
                      owner_component_id: pr.reader_table.id,
                      code: 2,
                      index: pr.reader_handle,
                      payload,
                    },
                  )
                  table.streams.replace(ep.stream_id, {
                    allows_intra_component: st0.allows_intra_component,
                    pending_read: Some({ ..pr, event_enqueued: true, }),
                    pending_write: st0.pending_write,
                    readable_dropped: st0.readable_dropped,
                    writable_dropped: true,
                  })
                }
                None =>
                  table.streams.replace(ep.stream_id, {
                    ..st0,
                    writable_dropped: true,
                  })
              }
              // Remove from any waitable-set membership and queued events.
              remove_waitable_membership(
                async_state, owner_component_id, handle,
              )
              table.endpoints.remove(handle_key(owner_component_id, handle))
              free_shared_handle(async_state, owner_component_id, handle)
              cleanup_closed_stream(table, ep.stream_id)
              []
            }
        }
      _ => trap_canon("type mismatch")
    }
  }
  state.core_funcs.push(alloc_component_host_core_func(store, core_type, host))
}
