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
    let rh = alloc_shared_handle(async_state)
    let wh = alloc_shared_handle(async_state)
    table.endpoints.set(rh, {
      stream_id: sid,
      is_readable: true,
      notified_peer_dropped: [false],
    })
    table.endpoints.set(wh, {
      stream_id: sid,
      is_readable: false,
      notified_peer_dropped: [false],
    })
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
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let mem_opt : @runtime.Memory? = match payload_ty {
      Some(_) =>
        match resources.mem_addr {
          Some(addr) =>
            Some(
              store.get_mem(addr) catch {
                e => {
                  trap_canon(e.to_string())
                  return [@types.Value::I32(0)]
                }
              },
            )
          None => {
            trap_canon("missing canon memory")
            return [@types.Value::I32(0)]
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
          return [@types.Value::I32(0)]
        }
        // BLOCKED=-1, COMPLETED=0 | (n<<4), DROPPED=1 | (n<<4)
        if len < 0 {
          trap_canon("type mismatch")
          [@types.Value::I32(0)]
        } else {
          match table.endpoints.get(handle) {
            None => {
              trap_canon("unknown stream handle index \{handle}")
              [@types.Value::I32(0)]
            }
            Some(ep) =>
              if !ep.is_readable {
                trap_canon("type mismatch")
                [@types.Value::I32(0)]
              } else {
                if ep.notified_peer_dropped[0] {
                  trap_canon(
                    "cannot read from stream after being notified that the writable end dropped",
                  )
                  return [@types.Value::I32(0)]
                }
                let st0 = match table.streams.get(ep.stream_id) {
                  Some(s) => s
                  None => {
                    trap_canon("unknown stream handle index \{handle}")
                    return [@types.Value::I32(0)]
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
                        return [@types.Value::I32(dropped | (pr0.filled << 4))]
                      } else if is_async {
                        return [@types.Value::I32(-1)]
                      } else {
                        if !async_state.task_can_block[0] {
                          trap_canon(
                            "cannot block a synchronous task before returning",
                          )
                          return [@types.Value::I32(0)]
                        }
                        canon_suspend[0] = Some(CanonSuspend::Yield)
                        raise @runtime.RuntimeError::Unreachable
                      }
                    } else {
                      // Another read is already in progress.
                      trap_canon("cannot remove busy stream")
                      return [@types.Value::I32(0)]
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
                        enqueue_waitable_event(async_state, pw.writer_handle, {
                          code: 3,
                          index: pw.writer_handle,
                          payload: (if st0.readable_dropped { 1 } else { 0 }) |
                          (0 << 4),
                        })
                        pw_event_enqueued = true
                      }
                      // And complete this read via an event too.
                      enqueue_waitable_event(async_state, handle, {
                        code: 2,
                        index: handle,
                        payload: (if st0.writable_dropped { 1 } else { 0 }) |
                        (0 << 4),
                      })
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
                        }),
                        readable_dropped: st0.readable_dropped,
                        writable_dropped: st0.writable_dropped,
                      })
                      return [@types.Value::I32(-1)]
                    }
                    let remain = total_elems - pw.sent
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
                                return [@types.Value::I32(0)]
                              }
                            }
                            if entry.type_id != expected_type_id {
                              trap_canon(
                                "handle index \{writer_handle} used with the wrong type",
                              )
                              return [@types.Value::I32(0)]
                            }
                            reader_table.alloc(entry)
                          }
                          mem.store_i32(ptr + i * elem_size, new_handle) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          }
                        }
                      (Some(_), None) => {
                        trap_canon("missing canon memory")
                        return [@types.Value::I32(0)]
                      }
                      (None, Some(mem)) => {
                        let bytes_n = n * elem_size
                        for i in 0..<bytes_n {
                          mem.store_byte(ptr + i, pw.buf[base + i]) catch {
                            e => {
                              trap_canon(e.to_string())
                              return [@types.Value::I32(0)]
                            }
                          }
                        }
                      }
                      (None, None) => ()
                    }
                    let new_sent = pw.sent + n
                    // When a pending write has been fully consumed, emit STREAM_WRITE and
                    // keep the write around until its event is delivered (notification semantics).
                    let mut event_enqueued = pw.event_enqueued
                    if new_sent >= total_elems && !event_enqueued {
                      enqueue_waitable_event(async_state, pw.writer_handle, {
                        code: 3,
                        index: pw.writer_handle,
                        payload: (if st0.readable_dropped { 1 } else { 0 }) |
                        (total_elems << 4),
                      })
                      event_enqueued = true
                    }
                    let pw2 = Some({
                      writer_table: pw.writer_table,
                      buf: pw.buf,
                      sent: new_sent,
                      writer_handle: pw.writer_handle,
                      event_enqueued,
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
                    [@types.Value::I32(dropped | (n << 4))]
                  }
                  None =>
                    if st0.writable_dropped {
                      ep.notified_peer_dropped[0] = true
                      [@types.Value::I32(1)]
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
                        [@types.Value::I32(-1)]
                      } else {
                        if !async_state.task_can_block[0] {
                          trap_canon(
                            "cannot block a synchronous task before returning",
                          )
                          return [@types.Value::I32(0)]
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
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    let mem_opt : @runtime.Memory? = match payload_ty {
      Some(_) =>
        match resources.mem_addr {
          Some(addr) =>
            Some(
              store.get_mem(addr) catch {
                e => {
                  trap_canon(e.to_string())
                  return [@types.Value::I32(0)]
                }
              },
            )
          None => {
            trap_canon("missing canon memory")
            return [@types.Value::I32(0)]
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
          return [@types.Value::I32(0)]
        }
        if len < 0 {
          trap_canon("type mismatch")
          [@types.Value::I32(0)]
        } else {
          match table.endpoints.get(handle) {
            None => {
              trap_canon("unknown stream handle index \{handle}")
              [@types.Value::I32(0)]
            }
            Some(ep) =>
              if ep.is_readable {
                trap_canon("type mismatch")
                [@types.Value::I32(0)]
              } else {
                if ep.notified_peer_dropped[0] {
                  trap_canon(
                    "cannot write to stream after being notified that the readable end dropped",
                  )
                  return [@types.Value::I32(0)]
                }
                let st0 = match table.streams.get(ep.stream_id) {
                  Some(s) => s
                  None => {
                    trap_canon("unknown stream handle index \{handle}")
                    return [@types.Value::I32(0)]
                  }
                }
                // If re-executing a previously blocking write, return its completion.
                match st0.pending_write {
                  Some(pw0) =>
                    if pw0.writer_handle == handle {
                      let elem_size = st0.elem_size
                      let total_elems = pw0.buf.length() / elem_size
                      if st0.readable_dropped || pw0.sent >= total_elems {
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
                        return [@types.Value::I32(dropped | (pw0.sent << 4))]
                      } else if is_async {
                        return [@types.Value::I32(-1)]
                      } else {
                        if !async_state.task_can_block[0] {
                          trap_canon(
                            "cannot block a synchronous task before returning",
                          )
                          return [@types.Value::I32(0)]
                        }
                        canon_suspend[0] = Some(CanonSuspend::Yield)
                        raise @runtime.RuntimeError::Unreachable
                      }
                    } else {
                      trap_canon("cannot drop busy stream")
                      return [@types.Value::I32(0)]
                    }
                  None => ()
                }
                if st0.readable_dropped {
                  ep.notified_peer_dropped[0] = true
                  return [@types.Value::I32(1)]
                }
                match st0.pending_read {
                  Some(pr0) => {
                    // Symmetric zero-length rendezvous: if a zero-length read is pending,
                    // a zero-length write must also complete via events (not eagerly).
                    if is_async && len == 0 && pr0.len == 0 {
                      let mut pr_event_enqueued = pr0.event_enqueued
                      if !pr_event_enqueued {
                        enqueue_waitable_event(async_state, pr0.reader_handle, {
                          code: 2,
                          index: pr0.reader_handle,
                          payload: (if st0.writable_dropped { 1 } else { 0 }) |
                          (0 << 4),
                        })
                        pr_event_enqueued = true
                      }
                      enqueue_waitable_event(async_state, handle, {
                        code: 3,
                        index: handle,
                        payload: (if st0.readable_dropped { 1 } else { 0 }) |
                        (0 << 4),
                      })
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
                        }),
                        readable_dropped: st0.readable_dropped,
                        writable_dropped: st0.writable_dropped,
                      })
                      return [@types.Value::I32(-1)]
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
                        }),
                        readable_dropped: st0.readable_dropped,
                        writable_dropped: st0.writable_dropped,
                      })
                      if is_async {
                        return [@types.Value::I32(-1)]
                      } else {
                        if !async_state.task_can_block[0] {
                          trap_canon(
                            "cannot block a synchronous task before returning",
                          )
                          return [@types.Value::I32(0)]
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
                      enqueue_waitable_event(async_state, pr0.reader_handle, {
                        code: 2,
                        index: pr0.reader_handle,
                        payload: (if st0.writable_dropped { 1 } else { 0 }) |
                        (filled1 << 4),
                      })
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
                    [@types.Value::I32(n << 4)]
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
                      }),
                      readable_dropped: st0.readable_dropped,
                      writable_dropped: st0.writable_dropped,
                    })
                    if is_async {
                      [@types.Value::I32(-1)]
                    } else {
                      if !async_state.task_can_block[0] {
                        trap_canon(
                          "cannot block a synchronous task before returning",
                        )
                        return [@types.Value::I32(0)]
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
        match table.endpoints.get(handle) {
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
        match table.endpoints.get(handle) {
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
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [@types.Value::I32(handle)] =>
        match table.endpoints.get(handle) {
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
                  if pw.event_enqueued {
                    update_waitable_event_payload(
                      async_state,
                      pw.writer_handle,
                      3,
                      payload,
                    )
                  } else {
                    enqueue_waitable_event(async_state, pw.writer_handle, {
                      code: 3,
                      index: pw.writer_handle,
                      payload,
                    })
                  }
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
              remove_waitable_membership(async_state, handle)
              table.free_endpoint(handle)
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
  let host = fn(
    args : Array[@types.Value],
  ) -> Array[@types.Value] raise @runtime.RuntimeError {
    if !canon_may_leave[0] {
      trap_canon("cannot leave component instance")
    }
    match args {
      [@types.Value::I32(handle)] =>
        match table.endpoints.get(handle) {
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
                  if pr.event_enqueued {
                    update_waitable_event_payload(
                      async_state,
                      pr.reader_handle,
                      2,
                      payload,
                    )
                  } else {
                    enqueue_waitable_event(async_state, pr.reader_handle, {
                      code: 2,
                      index: pr.reader_handle,
                      payload,
                    })
                  }
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
              remove_waitable_membership(async_state, handle)
              table.free_endpoint(handle)
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
