///|
/// Canonical section instantiation helpers.
/// (group: stream)

///|
fn instantiate_canon_stream_new(
  _tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [], results: [I64] }
  let payload_ty : ValType? = match state.types.get(_tyidx) {
    Some(Some(Stream(v))) => v
    _ => None
  }
  let (elem_size, own_resource_type_id) = stream_payload_info(
    payload_ty,
    state.types,
  ) catch {
    e => raise e
  }
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
    table.streams.set(sid, {
      elem_size,
      own_resource_type_id,
      pending_read: None,
      pending_write: None,
      readable_dropped: false,
      writable_dropped: false,
    })
    // Handle numbering is observable by component-spec/async tests.
    //
    // Allocate readable first, then writable. The shared allocator already
    // deterministically reuses the smallest freed handle (when available),
    // which is the behavior tests rely on.
    let rh = alloc_shared_handle(async_state, owner_component_id)
    let wh = alloc_shared_handle(async_state, owner_component_id)
    table.endpoints.set(handle_key(owner_component_id, rh), {
      stream_id: sid,
      is_readable: true,
      notified_peer_dropped: [false],
      in_waitable_set: Ref(false),
    })
    table.endpoints.set(handle_key(owner_component_id, wh), {
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
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn store_host_stream_value(
  value : ComponentValue,
  payload_ty : ValType,
  types : Array[TypeDef?],
  resources : CanonResources,
  store : @runtime.Store,
  table : ResourceTable,
  ptr : Int,
) -> Unit raise ComponentRuntimeError {
  let mem = require_memory(resources, store)
  let mem_is_64 = mem.is_memory64()
  let storage = flat_storage_for_valtype(payload_ty, types, mem_is_64)
  if storage.length() > 16 {
    raise HostCallError(
      "typed host stream payload exceeds the canonical flat-value limit",
    )
  }
  let values = component_args_to_core(
    [value],
    {
      is_async: false,
      params: [{ label: "value", ty: payload_ty }],
      result: None,
    },
    types,
    resources,
    store,
    table,
    table,
  )
  if values.length() != storage.length() {
    raise HostCallError("typed host stream payload has an invalid shape")
  }
  let (offsets, _size, alignment) = layout_of_flat_storage_fields(storage)
  if alignment > 1 &&
    ptr.reinterpret_as_uint() % alignment.reinterpret_as_uint() != 0U {
    raise CanonCallError("unaligned pointer")
  }
  for i in 0..<values.length() {
    store_storage_value(mem, ptr + offsets[i], values[i], storage[i])
  }
}

///|
fn poll_host_value_stream(
  source : HostValueStream,
  max_elements : Int,
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
      state.pending_read is Some(read) else {
      continue
    }
    match poll_host_value_stream(source, read.len - read.filled) {
      Pending => ()
      Closed => {
        table.streams.set(stream_id, {
          elem_size: state.elem_size,
          own_resource_type_id: state.own_resource_type_id,
          pending_read: Some({
            mem_addr: read.mem_addr,
            realloc: read.realloc,
            encoding: read.encoding,
            reader_table: read.reader_table,
            ptr: read.ptr,
            len: read.len,
            filled: read.filled,
            reader_handle: read.reader_handle,
            event_enqueued: true,
          }),
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
            read.ptr + (read.filled + i) * state.elem_size,
          )
        }
        let filled = read.filled + values.length()
        table.streams.set(stream_id, {
          elem_size: state.elem_size,
          own_resource_type_id: state.own_resource_type_id,
          pending_read: Some({
            mem_addr: read.mem_addr,
            realloc: read.realloc,
            encoding: read.encoding,
            reader_table: read.reader_table,
            ptr: read.ptr,
            len: read.len,
            filled,
            reader_handle: read.reader_handle,
            event_enqueued: true,
          }),
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
  _tyidx : Int,
  opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32, I32, I32], results: [I32] }
  let resources = resolve_canon_resources(opts, state) catch { e => raise e }
  let payload_ty : ValType? = match state.types.get(_tyidx) {
    Some(Some(Stream(v))) => v
    _ => None
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
    fn ret_i32(code : Int) -> Array[@types.Value] {
      [I32(code)]
    }

    let mem_opt : @runtime.Memory? = match payload_ty {
      Some(_) =>
        match resources.mem_addr {
          Some(addr) =>
            Some(
              store.get_mem(addr) catch {
                e => {
                  trap_canon(e.to_string())
                  return ret_i32(0)
                }
              },
            )
          None => {
            trap_canon("missing canon memory")
            return ret_i32(0)
          }
        }
      None => None
    }
    match args {
      [I32(handle), I32(ptr), I32(len)] => {
        if !is_async {
          resume_sync_waitable_use(
            async_state, owner_component_id, handle, task_id,
          )
          |> ignore
        }
        if !is_async &&
          waitable_is_in_set(async_state, owner_component_id, handle) {
          trap_canon(
            "waitable cannot be used synchronously while added to a waitable set",
          )
          return ret_i32(0)
        }
        if !is_async && !async_state.task_can_block[0] {
          trap_canon("cannot block a synchronous task before returning")
          return ret_i32(0)
        }
        // BLOCKED=-1, COMPLETED=0 | (n<<4), DROPPED=1 | (n<<4)
        if len < 0 {
          trap_canon("type mismatch")
          ret_i32(0)
        } else {
          let key = handle_key(owner_component_id, handle)
          let mut ep_opt = table.endpoints.get(key)
          if ep_opt is None {
            // Cross-component handle transfer bug workaround:
            // If a readable stream endpoint exists under a different component instance id but
            // with the same local handle number, opportunistically "adopt" it into the current
            // component instance. This preserves the numeric handle expected by the core code.
            //
            // This is only attempted when a single readable endpoint match exists globally.
            let mut found_owner : Int? = None
            let mut found_count = 0
            for kv in async_state.stream_table.endpoints.iter() {
              let (k, ep0) = kv
              if (k & 0xFFFFFFFFL).to_int() == handle && ep0.is_readable {
                found_owner = Some((k >> 32).to_int())
                found_count = found_count + 1
              }
            }
            if found_count == 1 {
              match found_owner {
                Some(o) =>
                  if o != owner_component_id &&
                    table.endpoints.get(handle_key(o, handle)) is Some(_) {
                    let from_key = handle_key(o, handle)
                    match table.endpoints.get(from_key) {
                      Some(ep0) =>
                        if ep0.is_readable {
                          remove_waitable_membership(async_state, o, handle)
                          table.endpoints.remove(from_key)
                          table.endpoints.set(key, {
                            stream_id: ep0.stream_id,
                            is_readable: ep0.is_readable,
                            notified_peer_dropped: ep0.notified_peer_dropped,
                            in_waitable_set: ep0.in_waitable_set,
                          })
                          reserve_shared_handle(
                            async_state, owner_component_id, handle,
                          )
                        }
                      None => ()
                    }
                  }
                None => ()
              }
            }
            ep_opt = table.endpoints.get(key)
          }
          match ep_opt {
            None => {
              trap_canon("unknown stream handle index \{handle}")
              ret_i32(0)
            }
            Some(ep) =>
              if !ep.is_readable {
                trap_canon("type mismatch")
                ret_i32(0)
              } else {
                if ep.notified_peer_dropped[0] {
                  trap_canon(
                    "cannot read from stream after being notified that the writable end dropped",
                  )
                  return ret_i32(0)
                }
                let st0 = match table.streams.get(ep.stream_id) {
                  Some(s) => s
                  None => {
                    trap_canon("unknown stream handle index \{handle}")
                    return ret_i32(0)
                  }
                }
                match table.host_values.get(ep.stream_id) {
                  Some(source) => {
                    match st0.pending_read {
                      Some(read) =>
                        if is_async {
                          trap_canon(
                            "cannot have concurrent operations active on a future/stream",
                          )
                          return ret_i32(0)
                        } else if read.reader_handle == handle &&
                          read.event_enqueued {
                          table.streams.set(ep.stream_id, {
                            elem_size: st0.elem_size,
                            own_resource_type_id: st0.own_resource_type_id,
                            pending_read: None,
                            pending_write: st0.pending_write,
                            readable_dropped: st0.readable_dropped,
                            writable_dropped: st0.writable_dropped,
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
                      e => {
                        trap_canon(e.to_string())
                        return ret_i32(0)
                      }
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
                            ptr + i * st0.elem_size,
                          ) catch {
                            e => {
                              trap_canon(e.to_string())
                              return ret_i32(0)
                            }
                          }
                        }
                        return ret_i32(values.length() << 4)
                      }
                      Closed => {
                        ep.notified_peer_dropped[0] = true
                        table.streams.set(ep.stream_id, {
                          elem_size: st0.elem_size,
                          own_resource_type_id: st0.own_resource_type_id,
                          pending_read: None,
                          pending_write: st0.pending_write,
                          readable_dropped: st0.readable_dropped,
                          writable_dropped: true,
                        })
                        return ret_i32(1)
                      }
                      Pending => {
                        table.streams.set(ep.stream_id, {
                          elem_size: st0.elem_size,
                          own_resource_type_id: st0.own_resource_type_id,
                          pending_read: Some({
                            mem_addr: resources.mem_addr,
                            realloc: resources.realloc,
                            encoding: resources.encoding,
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
                        canon_suspend[0] = Some(Yield)
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
                      return ret_i32(0)
                    } else if pr0.reader_handle == handle {
                      if pr0.filled == pr0.len || st0.writable_dropped {
                        let dropped = if st0.writable_dropped { 1 } else { 0 }
                        if dropped == 1 {
                          ep.notified_peer_dropped[0] = true
                        }
                        table.streams.set(ep.stream_id, {
                          elem_size: st0.elem_size,
                          own_resource_type_id: st0.own_resource_type_id,
                          pending_read: None,
                          pending_write: st0.pending_write,
                          readable_dropped: st0.readable_dropped,
                          writable_dropped: st0.writable_dropped,
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
                          return ret_i32(0)
                        }
                        mark_sync_waitable_blocked(
                          async_state, owner_component_id, handle, task_id,
                        )
                        canon_suspend[0] = Some(Yield)
                        raise Unreachable
                      }
                    } else {
                      // Another read is already in progress.
                      trap_canon("cannot remove busy stream")
                      return ret_i32(0)
                    }
                  None => ()
                }
                match st0.pending_write {
                  Some(pw) => {
                    let elem_size = st0.elem_size
                    let total_elems = pw.buf.length() / elem_size
                    // Zero-length reads must block and complete via an event even when a
                    // zero-length write is already pending (component-spec/async/zero-length.wast).
                    if is_async && len == 0 && total_elems == 0 {
                      // Ensure the pending write gets a completion event.
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
                            (0 << 4),
                          },
                        )
                        pw_event_enqueued = true
                      }
                      // And complete this read via an event too.
                      enqueue_waitable_event(
                        async_state,
                        handle_key(owner_component_id, handle),
                        {
                          owner_component_id,
                          code: 2,
                          index: handle,
                          payload: (if st0.writable_dropped { 1 } else { 0 }) |
                          (0 << 4),
                        },
                      )
                      let pr = {
                        mem_addr: resources.mem_addr,
                        realloc: resources.realloc,
                        encoding: resources.encoding,
                        reader_table,
                        ptr,
                        len: 0,
                        filled: 0,
                        reader_handle: handle,
                        event_enqueued: true,
                      }
                      table.streams.set(ep.stream_id, {
                        elem_size: st0.elem_size,
                        own_resource_type_id: st0.own_resource_type_id,
                        pending_read: Some(pr),
                        pending_write: Some({
                          writer_table: pw.writer_table,
                          buf: pw.buf,
                          sent: pw.sent,
                          writer_handle: pw.writer_handle,
                          event_enqueued: pw_event_enqueued,
                          defer_complete: pw.defer_complete,
                        }),
                        readable_dropped: st0.readable_dropped,
                        writable_dropped: st0.writable_dropped,
                      })
                      set_canon_debug_message(
                        "stream.read(handle=\{handle} len=\{len})-> -1",
                      )
                      return ret_i32(-1)
                    }
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
                      table.streams.set(ep.stream_id, {
                        elem_size: st0.elem_size,
                        own_resource_type_id: st0.own_resource_type_id,
                        pending_read: st0.pending_read,
                        pending_write: Some({
                          writer_table: pw.writer_table,
                          buf: pw.buf,
                          sent: pw.sent,
                          writer_handle: pw.writer_handle,
                          event_enqueued: pw_event_enqueued,
                          defer_complete: pw.defer_complete,
                        }),
                        readable_dropped: st0.readable_dropped,
                        writable_dropped: st0.writable_dropped,
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
                        reader_table,
                        ptr,
                        len,
                        filled: 0,
                        reader_handle: handle,
                        event_enqueued: false,
                      }
                      table.streams.set(ep.stream_id, {
                        elem_size: st0.elem_size,
                        own_resource_type_id: st0.own_resource_type_id,
                        pending_read: Some(pr),
                        pending_write: Some({
                          writer_table: pw.writer_table,
                          buf: pw.buf,
                          sent: pw.sent,
                          writer_handle: pw.writer_handle,
                          event_enqueued: pw_event_enqueued,
                          defer_complete: pw.defer_complete,
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
                          return ret_i32(0)
                        }
                        mark_sync_waitable_blocked(
                          async_state, owner_component_id, handle, task_id,
                        )
                        canon_suspend[0] = Some(Yield)
                        raise Unreachable
                      }
                    }
                    let n = if len < remain { len } else { remain }
                    let base = pw.sent * elem_size
                    match (st0.own_resource_type_id, mem_opt) {
                      (Some(expected_type_id), Some(mem)) =>
                        for i in 0..<n {
                          let off = base + i * elem_size
                          // Handle indices are encoded as i32 per element.
                          let writer_handle = read_i32_le_from_bytes(
                            pw.buf,
                            off,
                          )
                          let new_handle = if pw.writer_table.id ==
                            reader_table.id {
                            // Same component instance: no ownership transfer.
                            writer_handle
                          } else {
                            let entry = match
                              pw.writer_table.free(writer_handle) {
                              Some(e) => e
                              None => {
                                trap_canon(
                                  "unknown handle index \{writer_handle}",
                                )
                                return ret_i32(0)
                              }
                            }
                            if entry.type_id != expected_type_id {
                              trap_canon(
                                "handle index \{writer_handle} used with the wrong type",
                              )
                              return ret_i32(0)
                            }
                            reader_table.alloc(entry)
                          }
                          mem.store_i32(ptr + i * elem_size, new_handle) catch {
                            e => {
                              trap_canon(e.to_string())
                              return ret_i32(0)
                            }
                          }
                        }
                      (Some(_), None) => {
                        trap_canon("missing canon memory")
                        return ret_i32(0)
                      }
                      (None, Some(mem)) => {
                        let bytes_n = n * elem_size
                        for i in 0..<bytes_n {
                          mem.store_byte(ptr + i, pw.buf[base + i]) catch {
                            e => {
                              trap_canon(e.to_string())
                              return ret_i32(0)
                            }
                          }
                        }
                        ()
                      }
                      (None, None) => ()
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
                    let pw2 = Some({
                      writer_table: pw.writer_table,
                      buf: pw.buf,
                      sent: new_sent,
                      writer_handle: pw.writer_handle,
                      event_enqueued,
                      defer_complete: pw.defer_complete,
                    })
                    table.streams.set(ep.stream_id, {
                      elem_size: st0.elem_size,
                      own_resource_type_id: st0.own_resource_type_id,
                      pending_read: st0.pending_read,
                      pending_write: pw2,
                      readable_dropped: st0.readable_dropped,
                      writable_dropped: st0.writable_dropped,
                    })
                    let dropped = if st0.writable_dropped { 1 } else { 0 }
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
                        reader_table,
                        ptr,
                        len,
                        filled: 0,
                        reader_handle: handle,
                        event_enqueued: false,
                      }
                      table.streams.set(ep.stream_id, {
                        elem_size: st0.elem_size,
                        own_resource_type_id: st0.own_resource_type_id,
                        pending_read: Some(pr),
                        pending_write: st0.pending_write,
                        readable_dropped: st0.readable_dropped,
                        writable_dropped: st0.writable_dropped,
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
                          return ret_i32(0)
                        }
                        mark_sync_waitable_blocked(
                          async_state, owner_component_id, handle, task_id,
                        )
                        canon_suspend[0] = Some(Yield)
                        raise Unreachable
                      }
                    }
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
    alloc_host_core_func(store, core_type, host, may_suspend=!is_async),
  )
}

///|
fn instantiate_canon_stream_write(
  _tyidx : Int,
  opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = { params: [I32, I32, I32], results: [I32] }
  let resources = resolve_canon_resources(opts, state) catch { e => raise e }
  let payload_ty : ValType? = match state.types.get(_tyidx) {
    Some(Some(Stream(v))) => v
    _ => None
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
    fn ret_i32(code : Int) -> Array[@types.Value] {
      [I32(code)]
    }

    let mem_opt : @runtime.Memory? = match payload_ty {
      Some(_) =>
        match resources.mem_addr {
          Some(addr) =>
            Some(
              store.get_mem(addr) catch {
                e => {
                  trap_canon(e.to_string())
                  return ret_i32(0)
                }
              },
            )
          None => {
            trap_canon("missing canon memory")
            return ret_i32(0)
          }
        }
      None => None
    }
    match args {
      [I32(handle), I32(ptr), I32(len)] => {
        if !is_async {
          resume_sync_waitable_use(
            async_state, owner_component_id, handle, task_id,
          )
          |> ignore
        }
        if !is_async &&
          waitable_is_in_set(async_state, owner_component_id, handle) {
          trap_canon(
            "waitable cannot be used synchronously while added to a waitable set",
          )
          return ret_i32(0)
        }
        if !is_async && !async_state.task_can_block[0] {
          trap_canon("cannot block a synchronous task before returning")
          return ret_i32(0)
        }
        if len < 0 {
          trap_canon("type mismatch")
          ret_i32(0)
        } else {
          match table.endpoints.get(handle_key(owner_component_id, handle)) {
            None => {
              trap_canon("unknown stream handle index \{handle}")
              ret_i32(0)
            }
            Some(ep) =>
              if ep.is_readable {
                trap_canon("type mismatch")
                ret_i32(0)
              } else {
                if ep.notified_peer_dropped[0] {
                  trap_canon(
                    "cannot write to stream after being notified that the readable end dropped",
                  )
                  return ret_i32(0)
                }
                let st0 = match table.streams.get(ep.stream_id) {
                  Some(s) => s
                  None => {
                    trap_canon("unknown stream handle index \{handle}")
                    return ret_i32(0)
                  }
                }
                // A resumed blocking write retries this host instruction with
                // the same pending operation.
                match st0.pending_write {
                  Some(pw0) =>
                    if is_async {
                      trap_canon(
                        "cannot have concurrent operations active on a future/stream",
                      )
                      return ret_i32(0)
                    } else if pw0.writer_handle == handle {
                      let elem_size = st0.elem_size
                      let total_elems = pw0.buf.length() / elem_size
                      if st0.readable_dropped || pw0.sent >= total_elems {
                        // Sync stream.write should observe a drop that happens immediately after a
                        // successful rendezvous (read returns to the caller and then the caller
                        // drops the readable end). Defer completion by one yield
                        // once the write becomes fully consumed.
                        if !is_async &&
                          !st0.readable_dropped &&
                          pw0.sent >= total_elems &&
                          !pw0.defer_complete {
                          table.streams.set(ep.stream_id, {
                            elem_size: st0.elem_size,
                            own_resource_type_id: st0.own_resource_type_id,
                            pending_read: st0.pending_read,
                            pending_write: Some({
                              writer_table: pw0.writer_table,
                              buf: pw0.buf,
                              sent: pw0.sent,
                              writer_handle: pw0.writer_handle,
                              event_enqueued: pw0.event_enqueued,
                              defer_complete: true,
                            }),
                            readable_dropped: st0.readable_dropped,
                            writable_dropped: st0.writable_dropped,
                          })
                          mark_sync_waitable_blocked(
                            async_state, owner_component_id, handle, task_id,
                          )
                          canon_suspend[0] = Some(Yield)
                          raise Unreachable
                        }
                        let dropped = if st0.readable_dropped { 1 } else { 0 }
                        if dropped == 1 {
                          ep.notified_peer_dropped[0] = true
                        }
                        table.streams.set(ep.stream_id, {
                          elem_size: st0.elem_size,
                          own_resource_type_id: st0.own_resource_type_id,
                          pending_read: st0.pending_read,
                          pending_write: None,
                          readable_dropped: st0.readable_dropped,
                          writable_dropped: st0.writable_dropped,
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
                          return ret_i32(0)
                        }
                        mark_sync_waitable_blocked(
                          async_state, owner_component_id, handle, task_id,
                        )
                        canon_suspend[0] = Some(Yield)
                        raise Unreachable
                      }
                    } else {
                      trap_canon("cannot drop busy stream")
                      return ret_i32(0)
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
                    // Symmetric zero-length rendezvous: if a zero-length read is pending,
                    // a zero-length write must also complete via events (not eagerly).
                    if is_async && len == 0 && pr0.len == 0 {
                      let mut pr_event_enqueued = pr0.event_enqueued
                      if !pr_event_enqueued {
                        enqueue_waitable_event(
                          async_state,
                          handle_key(pr0.reader_table.id, pr0.reader_handle),
                          {
                            owner_component_id: pr0.reader_table.id,
                            code: 2,
                            index: pr0.reader_handle,
                            payload: (if st0.writable_dropped { 1 } else { 0 }) |
                            (0 << 4),
                          },
                        )
                        pr_event_enqueued = true
                      }
                      enqueue_waitable_event(
                        async_state,
                        handle_key(owner_component_id, handle),
                        {
                          owner_component_id,
                          code: 3,
                          index: handle,
                          payload: (if st0.readable_dropped { 1 } else { 0 }) |
                          (0 << 4),
                        },
                      )
                      table.streams.set(ep.stream_id, {
                        elem_size: st0.elem_size,
                        own_resource_type_id: st0.own_resource_type_id,
                        pending_read: Some({
                          mem_addr: pr0.mem_addr,
                          realloc: pr0.realloc,
                          encoding: pr0.encoding,
                          reader_table: pr0.reader_table,
                          ptr: pr0.ptr,
                          len: pr0.len,
                          filled: pr0.filled,
                          reader_handle: pr0.reader_handle,
                          event_enqueued: pr_event_enqueued,
                        }),
                        pending_write: Some({
                          writer_table,
                          buf: [],
                          sent: 0,
                          writer_handle: handle,
                          event_enqueued: true,
                          defer_complete: false,
                        }),
                        readable_dropped: st0.readable_dropped,
                        writable_dropped: st0.writable_dropped,
                      })
                      set_canon_debug_message(
                        "stream.write(handle=\{handle} len=\{len})-> -1",
                      )
                      return ret_i32(-1)
                    }
                    let elem_size = st0.elem_size
                    let remain = pr0.len - pr0.filled
                    if remain <= 0 {
                      // The reader's buffer is full (completion not yet acknowledged): block.
                      let buf : Array[Byte] = []
                      let src_bytes = len * elem_size
                      for i in 0..<src_bytes {
                        let b = match mem_opt {
                          Some(mem) =>
                            mem.load_byte(ptr + i) catch {
                              e => {
                                trap_canon(e.to_string())
                                return [I32(0)]
                              }
                            }
                          None => b'\x00'
                        }
                        buf.push(b)
                      }
                      table.streams.set(ep.stream_id, {
                        elem_size: st0.elem_size,
                        own_resource_type_id: st0.own_resource_type_id,
                        pending_read: st0.pending_read,
                        pending_write: Some({
                          writer_table,
                          buf,
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
                          return ret_i32(0)
                        }
                        mark_sync_waitable_blocked(
                          async_state, owner_component_id, handle, task_id,
                        )
                        canon_suspend[0] = Some(Yield)
                        raise Unreachable
                      }
                    }
                    let n = if len < remain { len } else { remain }
                    // Snapshot src bytes first to preserve memmove semantics when regions overlap.
                    let buf : Array[Byte] = []
                    let src_bytes = len * elem_size
                    for i in 0..<src_bytes {
                      let b = match mem_opt {
                        Some(mem) =>
                          mem.load_byte(ptr + i) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [I32(0)]
                            }
                          }
                        None => b'\x00'
                      }
                      buf.push(b)
                    }
                    // Copy into the *reader* memory/buffer, not the writer memory.
                    // For empty streams (no canon memory), `mem_opt` is None and we
                    // must not touch either pointer/memory.
                    match (st0.own_resource_type_id, mem_opt) {
                      (Some(expected_type_id), Some(src_mem)) => {
                        let dst_mem = match pr0.mem_addr {
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
                        for i in 0..<n {
                          let writer_handle = src_mem.load_i32(
                            ptr + i * elem_size,
                          ) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [I32(0)]
                            }
                          }
                          let new_handle = if writer_table.id ==
                            pr0.reader_table.id {
                            writer_handle
                          } else {
                            let entry = match writer_table.free(writer_handle) {
                              Some(e) => e
                              None => {
                                trap_canon(
                                  "unknown handle index \{writer_handle}",
                                )
                                return [I32(0)]
                              }
                            }
                            if entry.type_id != expected_type_id {
                              trap_canon(
                                "handle index \{writer_handle} used with the wrong type",
                              )
                              return [I32(0)]
                            }
                            pr0.reader_table.alloc(entry)
                          }
                          dst_mem.store_i32(
                            pr0.ptr + (pr0.filled + i) * elem_size,
                            new_handle,
                          ) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [I32(0)]
                            }
                          }
                        }
                      }
                      (Some(_), None) => {
                        trap_canon("missing canon memory")
                        return [I32(0)]
                      }
                      (None, Some(_src_mem)) => {
                        let dst_mem = match pr0.mem_addr {
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
                        let bytes_n = n * elem_size
                        let dst_base = pr0.ptr + pr0.filled * elem_size
                        for i in 0..<bytes_n {
                          dst_mem.store_byte(dst_base + i, buf[i]) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [I32(0)]
                            }
                          }
                        }
                      }
                      (None, None) => ()
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
                    let pr1 = {
                      mem_addr: pr0.mem_addr,
                      realloc: pr0.realloc,
                      encoding: pr0.encoding,
                      reader_table: pr0.reader_table,
                      ptr: pr0.ptr,
                      len: pr0.len,
                      filled: filled1,
                      reader_handle: pr0.reader_handle,
                      event_enqueued,
                    }
                    table.streams.set(ep.stream_id, {
                      elem_size: st0.elem_size,
                      own_resource_type_id: st0.own_resource_type_id,
                      pending_read: Some(pr1),
                      pending_write: st0.pending_write,
                      readable_dropped: st0.readable_dropped,
                      writable_dropped: st0.writable_dropped,
                    })
                    let out_code = n << 4
                    set_canon_debug_message(
                      "stream.write(handle=\{handle} len=\{len})-> \{out_code}",
                    )
                    ret_i32(out_code)
                  }
                  None => {
                    // Register a pending write by copying bytes.
                    let buf : Array[Byte] = []
                    let elem_size = st0.elem_size
                    let src_bytes = len * elem_size
                    for i in 0..<src_bytes {
                      let b = match mem_opt {
                        Some(mem) =>
                          mem.load_byte(ptr + i) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [I32(0)]
                            }
                          }
                        None => b'\x00'
                      }
                      buf.push(b)
                    }
                    table.streams.set(ep.stream_id, {
                      elem_size: st0.elem_size,
                      own_resource_type_id: st0.own_resource_type_id,
                      pending_read: st0.pending_read,
                      pending_write: Some({
                        writer_table,
                        buf,
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
                      ret_i32(-1)
                    } else {
                      if !async_state.task_can_block[0] {
                        trap_canon(
                          "cannot block a synchronous task before returning",
                        )
                        return ret_i32(0)
                      }
                      mark_sync_waitable_blocked(
                        async_state, owner_component_id, handle, task_id,
                      )
                      canon_suspend[0] = Some(Yield)
                      raise Unreachable
                    }
                  }
                }
              }
          }
        }
      }
      _ => {
        trap_canon("type mismatch")
        [I32(0)]
      }
    }
  }
  state.core_funcs.push(
    alloc_host_core_func(store, core_type, host, may_suspend=!is_async),
  )
}

///|
fn instantiate_canon_stream_cancel_read(
  _tyidx : Int,
  is_async_cancel : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [I32], results: [I32] }
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
        if !is_async_cancel &&
          waitable_is_in_set(async_state, owner_component_id, handle) {
          trap_canon(
            "waitable cannot be used synchronously while added to a waitable set",
          )
          return [I32(0)]
        }
      _ => ()
    }
    if !is_async_cancel && !async_state.task_can_block[0] {
      trap_canon("cannot block a synchronous task before returning")
      return [I32(0)]
    }
    match args {
      [I32(handle)] =>
        match table.endpoints.get(handle_key(owner_component_id, handle)) {
          None => {
            trap_canon("unknown stream handle index \{handle}")
            [I32(0)]
          }
          Some(ep) =>
            if !ep.is_readable {
              trap_canon("type mismatch")
              [I32(0)]
            } else {
              let st0 = match table.streams.get(ep.stream_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown stream handle index \{handle}")
                  return [I32(0)]
                }
              }
              match st0.pending_read {
                Some(pr) => {
                  let code = if st0.writable_dropped { 1 } else { 2 }
                  let filled = pr.filled
                  table.streams.set(ep.stream_id, {
                    elem_size: st0.elem_size,
                    own_resource_type_id: st0.own_resource_type_id,
                    pending_read: None,
                    pending_write: st0.pending_write,
                    readable_dropped: st0.readable_dropped,
                    writable_dropped: st0.writable_dropped,
                  })
                  [I32(code | (filled << 4))]
                }
                None => [I32(2)]
              }
            }
        }
      _ => {
        trap_canon("type mismatch")
        [I32(0)]
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_stream_cancel_write(
  _tyidx : Int,
  is_async_cancel : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [I32], results: [I32] }
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
        if !is_async_cancel &&
          waitable_is_in_set(async_state, owner_component_id, handle) {
          trap_canon(
            "waitable cannot be used synchronously while added to a waitable set",
          )
          return [I32(0)]
        }
      _ => ()
    }
    if !is_async_cancel && !async_state.task_can_block[0] {
      trap_canon("cannot block a synchronous task before returning")
      return [I32(0)]
    }
    match args {
      [I32(handle)] =>
        match table.endpoints.get(handle_key(owner_component_id, handle)) {
          None => {
            trap_canon("unknown stream handle index \{handle}")
            [I32(0)]
          }
          Some(ep) =>
            if ep.is_readable {
              trap_canon("type mismatch")
              [I32(0)]
            } else {
              let st0 = match table.streams.get(ep.stream_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown stream handle index \{handle}")
                  return [I32(0)]
                }
              }
              match st0.pending_write {
                Some(pw) => {
                  let code = if st0.readable_dropped { 1 } else { 2 }
                  let sent = pw.sent
                  table.streams.set(ep.stream_id, {
                    elem_size: st0.elem_size,
                    own_resource_type_id: st0.own_resource_type_id,
                    pending_read: st0.pending_read,
                    pending_write: None,
                    readable_dropped: st0.readable_dropped,
                    writable_dropped: st0.writable_dropped,
                  })
                  [I32(code | (sent << 4))]
                }
                None => [I32(2)]
              }
            }
        }
      _ => {
        trap_canon("type mismatch")
        [I32(0)]
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_stream_drop_readable(
  _tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [I32], results: [] }
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
          None => {
            trap_canon("unknown stream handle index \{handle}")
            []
          }
          Some(ep) =>
            if !ep.is_readable {
              trap_canon("type mismatch")
              []
            } else {
              let st0 = match table.streams.get(ep.stream_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown stream handle index \{handle}")
                  return []
                }
              }
              // Dropping a readable endpoint is only invalid if there is an
              // active read in progress on that endpoint.
              if st0.pending_read is Some(_) {
                trap_canon("cannot remove busy stream")
                return []
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
                  table.streams.set(ep.stream_id, {
                    elem_size: st0.elem_size,
                    own_resource_type_id: st0.own_resource_type_id,
                    pending_read: st0.pending_read,
                    pending_write: Some({
                      writer_table: pw.writer_table,
                      buf: pw.buf,
                      sent: pw.sent,
                      writer_handle: pw.writer_handle,
                      event_enqueued: true,
                      defer_complete: pw.defer_complete,
                    }),
                    readable_dropped: true,
                    writable_dropped: st0.writable_dropped,
                  })
                }
                None =>
                  table.streams.set(ep.stream_id, {
                    elem_size: st0.elem_size,
                    own_resource_type_id: st0.own_resource_type_id,
                    pending_read: st0.pending_read,
                    pending_write: st0.pending_write,
                    readable_dropped: true,
                    writable_dropped: st0.writable_dropped,
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
      _ => {
        trap_canon("type mismatch")
        []
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_stream_drop_writable(
  _tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = { params: [I32], results: [] }
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
          None => {
            trap_canon("unknown stream handle index \{handle}")
            []
          }
          Some(ep) =>
            if ep.is_readable {
              trap_canon("type mismatch")
              []
            } else {
              let st0 = match table.streams.get(ep.stream_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown stream handle index \{handle}")
                  return []
                }
              }
              // Dropping a writable endpoint is only invalid if there is an
              // active write in progress on that endpoint.
              if st0.pending_write is Some(_) {
                trap_canon("cannot drop busy stream")
                return []
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
                  table.streams.set(ep.stream_id, {
                    elem_size: st0.elem_size,
                    own_resource_type_id: st0.own_resource_type_id,
                    pending_read: Some({
                      mem_addr: pr.mem_addr,
                      realloc: pr.realloc,
                      encoding: pr.encoding,
                      reader_table: pr.reader_table,
                      ptr: pr.ptr,
                      len: pr.len,
                      filled: pr.filled,
                      reader_handle: pr.reader_handle,
                      event_enqueued: true,
                    }),
                    pending_write: st0.pending_write,
                    readable_dropped: st0.readable_dropped,
                    writable_dropped: true,
                  })
                }
                None =>
                  table.streams.set(ep.stream_id, {
                    elem_size: st0.elem_size,
                    own_resource_type_id: st0.own_resource_type_id,
                    pending_read: st0.pending_read,
                    pending_write: st0.pending_write,
                    readable_dropped: st0.readable_dropped,
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
      _ => {
        trap_canon("type mismatch")
        []
      }
    }
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}
