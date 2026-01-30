///|
/// Canonical section instantiation helpers.
/// (group: stream)

///|
fn instantiate_canon_stream_new(
  _tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = {
    params: [],
    results: [@types.ValueType::I64],
  }
  let payload_ty : ValType? = match state.types.get(_tyidx) {
    Some(Some(TypeDef::Stream(v))) => v
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

    // Replay-safe: `canon stream.new` can be executed multiple times if the
    // surrounding core function is restarted after a cooperative suspension.
    // Cache the i64 result per task/call cursor so handle numbering remains stable.
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
        set_canon_debug_message("stream.new(replay cur=\{cur})-> \{v}")
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
    })
    table.endpoints.set(handle_key(owner_component_id, wh), {
      stream_id: sid,
      is_readable: false,
      notified_peer_dropped: [false],
    })
    set_canon_debug_message(
      "stream.new(owner=\{owner_component_id})-> rh=\{rh} wh=\{wh}",
    )
    let packed = (wh.to_int64() << 32) | (rh.to_int64() & 0xFFFFFFFFL)
    cache_i64(packed)
  }
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_stream_read(
  _tyidx : Int,
  opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = {
    params: [
      @types.ValueType::I32,
      @types.ValueType::I32,
      @types.ValueType::I32,
    ],
    results: [@types.ValueType::I32],
  }
  let resources = resolve_canon_resources(opts, state) catch { e => raise e }
  let payload_ty : ValType? = match state.types.get(_tyidx) {
    Some(Some(TypeDef::Stream(v))) => v
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
    // Replay-safe: stream.read/write can be re-executed when the surrounding core function is
    // restarted after a cooperative suspension. Cache their return codes per task + cursor so
    // side effects (buffer copies / handle transfers) are not repeated.
    let task_id = current_task_id(async_state)
    let cur = if async_state.stream_cursor_stack.length() == 0 {
      0
    } else {
      async_state.stream_cursor_stack[async_state.stream_cursor_stack.length() -
      1]
    }
    // Callback-style async ABI runs different core functions across steps; their cursors
    // restart at 0 each step, so keep a separate replay map for callbacks to avoid
    // colliding with the initial core function body.
    let per_task = if async_state.in_async_callback[0] {
      match async_state.stream_results_cb.get(task_id) {
        Some(m) => m
        None => {
          let m : Map[Int, Int] = {}
          async_state.stream_results_cb.set(task_id, m)
          m
        }
      }
    } else {
      match async_state.stream_results.get(task_id) {
        Some(m) => m
        None => {
          let m : Map[Int, Int] = {}
          async_state.stream_results.set(task_id, m)
          m
        }
      }
    }
    match per_task.get(cur) {
      Some(code) => {
        set_canon_debug_message("stream.read(replay cur=\{cur})-> \{code}")
        async_state.stream_cursor_stack[async_state.stream_cursor_stack.length() -
        1] = cur + 1
        return [@types.Value::I32(code)]
      }
      None => ()
    }
    fn cache_i32(code : Int) -> Array[@types.Value] {
      per_task.set(cur, code)
      async_state.stream_cursor_stack[async_state.stream_cursor_stack.length() -
      1] = cur + 1
      [@types.Value::I32(code)]
    }

    fn ret_i32(code : Int) -> Array[@types.Value] {
      cache_i32(code)
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
      [
        @types.Value::I32(handle),
        @types.Value::I32(ptr),
        @types.Value::I32(len),
      ] => {
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
                          })
                          // Reserve the adopted handle in the destination allocator.
                          let next = match
                            async_state.next_handle_by_component.get(
                              owner_component_id,
                            ) {
                            Some(a) => a
                            None => {
                              let a = [1]
                              async_state.next_handle_by_component.set(
                                owner_component_id, a,
                              )
                              a
                            }
                          }
                          if next[0] <= handle {
                            next[0] = handle + 1
                          }
                          match
                            async_state.free_handles_by_component.get(
                              owner_component_id,
                            ) {
                            Some(free) => {
                              let mut i = 0
                              while i < free.length() {
                                if free[i] == handle {
                                  free.remove(i) |> ignore
                                } else {
                                  i = i + 1
                                }
                              }
                            }
                            None => ()
                          }
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
                // If re-executing a previously blocking read, return its completion.
                match st0.pending_read {
                  Some(pr0) =>
                    if pr0.reader_handle == handle {
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
                        canon_suspend[0] = Some(CanonSuspend::Yield)
                        raise @runtime.RuntimeError::Unreachable
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
                    // If the pending write has been fully consumed (or is zero-length),
                    // it must not cause reads to "complete" with 0 elements. Treat it as
                    // no available data, but make sure the writer's completion event is
                    // eventually delivered.
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
                        canon_suspend[0] = Some(CanonSuspend::Yield)
                        raise @runtime.RuntimeError::Unreachable
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
                    // When a pending write has been fully consumed, emit STREAM_WRITE and
                    // keep the write around until its event is delivered (notification semantics).
                    let mut event_enqueued = pw.event_enqueued
                    if new_sent >= total_elems && !event_enqueued {
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
                        canon_suspend[0] = Some(CanonSuspend::Yield)
                        raise @runtime.RuntimeError::Unreachable
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
  state.core_funcs.push(alloc_host_core_func(store, core_type, host))
}

///|
fn instantiate_canon_stream_write(
  _tyidx : Int,
  opts : Array[CanonOpt],
  state : BuildState,
  store : @runtime.Store,
) -> Unit raise ComponentRuntimeError {
  let core_type : @types.FuncType = {
    params: [
      @types.ValueType::I32,
      @types.ValueType::I32,
      @types.ValueType::I32,
    ],
    results: [@types.ValueType::I32],
  }
  let resources = resolve_canon_resources(opts, state) catch { e => raise e }
  let payload_ty : ValType? = match state.types.get(_tyidx) {
    Some(Some(TypeDef::Stream(v))) => v
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
    // Replay-safe: stream.read/write can be re-executed when the surrounding core function is
    // restarted after a cooperative suspension. Cache their return codes per task + cursor so
    // side effects (buffer copies / handle transfers) are not repeated.
    let task_id = current_task_id(async_state)
    let cur = if async_state.stream_cursor_stack.length() == 0 {
      0
    } else {
      async_state.stream_cursor_stack[async_state.stream_cursor_stack.length() -
      1]
    }
    // Callback-style async ABI runs different core functions across steps; their cursors
    // restart at 0 each step, so keep a separate replay map for callbacks to avoid
    // colliding with the initial core function body.
    let per_task = if async_state.in_async_callback[0] {
      match async_state.stream_results_cb.get(task_id) {
        Some(m) => m
        None => {
          let m : Map[Int, Int] = {}
          async_state.stream_results_cb.set(task_id, m)
          m
        }
      }
    } else {
      match async_state.stream_results.get(task_id) {
        Some(m) => m
        None => {
          let m : Map[Int, Int] = {}
          async_state.stream_results.set(task_id, m)
          m
        }
      }
    }
    match per_task.get(cur) {
      Some(code) => {
        set_canon_debug_message("stream.write(replay cur=\{cur})-> \{code}")
        async_state.stream_cursor_stack[async_state.stream_cursor_stack.length() -
        1] = cur + 1
        return [@types.Value::I32(code)]
      }
      None => ()
    }
    fn cache_i32(code : Int) -> Array[@types.Value] {
      per_task.set(cur, code)
      async_state.stream_cursor_stack[async_state.stream_cursor_stack.length() -
      1] = cur + 1
      [@types.Value::I32(code)]
    }

    fn ret_i32(code : Int) -> Array[@types.Value] {
      cache_i32(code)
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
      [
        @types.Value::I32(handle),
        @types.Value::I32(ptr),
        @types.Value::I32(len),
      ] => {
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
                // If re-executing a previously blocking write, return its completion.
                match st0.pending_write {
                  Some(pw0) =>
                    if pw0.writer_handle == handle {
                      let elem_size = st0.elem_size
                      let total_elems = pw0.buf.length() / elem_size
                      if st0.readable_dropped || pw0.sent >= total_elems {
                        // Sync stream.write should observe a drop that happens immediately after a
                        // successful rendezvous (read returns to the caller and then the caller
                        // drops the readable end). To model this with cooperative replay, defer
                        // completion by one yield once the write becomes fully consumed.
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
                          canon_suspend[0] = Some(CanonSuspend::Yield)
                          raise @runtime.RuntimeError::Unreachable
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
                        canon_suspend[0] = Some(CanonSuspend::Yield)
                        raise @runtime.RuntimeError::Unreachable
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
                                return [@types.Value::I32(0)]
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
                        canon_suspend[0] = Some(CanonSuspend::Yield)
                        raise @runtime.RuntimeError::Unreachable
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
                              return [@types.Value::I32(0)]
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
                                return [@types.Value::I32(0)]
                              }
                            }
                          None => {
                            trap_canon("missing canon memory")
                            return [@types.Value::I32(0)]
                          }
                        }
                        for i in 0..<n {
                          let writer_handle = src_mem.load_i32(
                            ptr + i * elem_size,
                          ) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
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
                                return [@types.Value::I32(0)]
                              }
                            }
                            if entry.type_id != expected_type_id {
                              trap_canon(
                                "handle index \{writer_handle} used with the wrong type",
                              )
                              return [@types.Value::I32(0)]
                            }
                            pr0.reader_table.alloc(entry)
                          }
                          dst_mem.store_i32(
                            pr0.ptr + (pr0.filled + i) * elem_size,
                            new_handle,
                          ) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          }
                        }
                      }
                      (Some(_), None) => {
                        trap_canon("missing canon memory")
                        return [@types.Value::I32(0)]
                      }
                      (None, Some(_src_mem)) => {
                        let dst_mem = match pr0.mem_addr {
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
                        let bytes_n = n * elem_size
                        let dst_base = pr0.ptr + pr0.filled * elem_size
                        for i in 0..<bytes_n {
                          dst_mem.store_byte(dst_base + i, buf[i]) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          }
                        }
                      }
                      (None, None) => ()
                    }
                    let filled1 = pr0.filled + n
                    let mut event_enqueued = pr0.event_enqueued
                    // Emit STREAM_READ once the whole read buffer is filled (or the peer is dropped).
                    if (filled1 >= pr0.len || st0.writable_dropped) &&
                      !event_enqueued {
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
                              return [@types.Value::I32(0)]
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
                      canon_suspend[0] = Some(CanonSuspend::Yield)
                      raise @runtime.RuntimeError::Unreachable
                    }
                  }
                }
              }
          }
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
fn instantiate_canon_stream_cancel_read(
  _tyidx : Int,
  is_async_cancel : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let table = state.stream_table
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    if !is_async_cancel && !async_state.task_can_block[0] {
      trap_canon("cannot block a synchronous task before returning")
      return [@types.Value::I32(0)]
    }
    match args {
      [@types.Value::I32(handle)] =>
        match table.endpoints.get(handle_key(owner_component_id, handle)) {
          None => {
            trap_canon("unknown stream handle index \{handle}")
            [@types.Value::I32(0)]
          }
          Some(ep) =>
            if !ep.is_readable {
              trap_canon("type mismatch")
              [@types.Value::I32(0)]
            } else {
              let st0 = match table.streams.get(ep.stream_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown stream handle index \{handle}")
                  return [@types.Value::I32(0)]
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
                  [@types.Value::I32(code | (filled << 4))]
                }
                None => [@types.Value::I32(2)]
              }
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
fn instantiate_canon_stream_cancel_write(
  _tyidx : Int,
  is_async_cancel : Bool,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let table = state.stream_table
  let async_state = state.async_state
  let owner_component_id = state.resource_table.id
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    if !is_async_cancel && !async_state.task_can_block[0] {
      trap_canon("cannot block a synchronous task before returning")
      return [@types.Value::I32(0)]
    }
    match args {
      [@types.Value::I32(handle)] =>
        match table.endpoints.get(handle_key(owner_component_id, handle)) {
          None => {
            trap_canon("unknown stream handle index \{handle}")
            [@types.Value::I32(0)]
          }
          Some(ep) =>
            if ep.is_readable {
              trap_canon("type mismatch")
              [@types.Value::I32(0)]
            } else {
              let st0 = match table.streams.get(ep.stream_id) {
                Some(s) => s
                None => {
                  trap_canon("unknown stream handle index \{handle}")
                  return [@types.Value::I32(0)]
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
                  [@types.Value::I32(code | (sent << 4))]
                }
                None => [@types.Value::I32(2)]
              }
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
fn instantiate_canon_stream_drop_readable(
  _tyidx : Int,
  state : BuildState,
  store : @runtime.Store,
) -> Unit {
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
  let table = state.stream_table
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
              free_shared_handle(async_state, owner_component_id, handle)
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
  let core_type : @types.FuncType = {
    params: [@types.ValueType::I32],
    results: [],
  }
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
      [@types.Value::I32(handle)] =>
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
