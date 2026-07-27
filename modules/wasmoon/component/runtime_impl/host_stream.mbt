///|
pub(all) enum HostByteStreamRead {
  Pending
  Data(Bytes)
  Closed
} derive(Debug)

///|
fn HostRuntimeState::new_closed_host_stream(
  self : HostRuntimeState,
  table : ResourceTable,
  element_size : Int,
  bytes : Bytes,
) -> Int {
  let stream_id = self.stream_table.next_stream_id[0]
  self.stream_table.next_stream_id[0] = stream_id + 1
  let readable = alloc_shared_handle(self.async_state, table.id)
  let buffer : Array[Byte] = []
  for byte in bytes {
    buffer.push(byte)
  }
  self.stream_table.streams.set(stream_id, {
    elem_size: element_size,
    own_resource_type_id: None,
    pending_read: None,
    pending_write: Some({
      writer_table: table,
      buf: buffer,
      sent: 0,
      writer_handle: 0,
      event_enqueued: true,
      defer_complete: false,
    }),
    readable_dropped: false,
    writable_dropped: true,
  })
  self.stream_table.endpoints.set(handle_key(table.id, readable), {
    stream_id,
    is_readable: true,
    notified_peer_dropped: [false],
    in_waitable_set: Ref(false),
  })
  readable
}

///|
/// Create a finite `stream<u8>` owned by `table`.
///
/// The returned readable handle yields all supplied bytes and then reports the
/// writable end as dropped.
pub fn HostRuntimeState::new_host_byte_stream(
  self : HostRuntimeState,
  table : ResourceTable,
  bytes : Bytes,
) -> Int {
  self.new_closed_host_stream(table, 1, bytes)
}

///|
/// Create a completed `future<result<_, E>>` containing `ok(())`.
///
/// Canonical memory represents this two-case result as a zero discriminant
/// followed by zeroed payload storage.
pub fn HostRuntimeState::new_host_unit_result_future(
  self : HostRuntimeState,
  table : ResourceTable,
  element_type : ValType,
  types : Array[TypeDef?],
  error_case? : Int,
) -> Int raise ComponentRuntimeError {
  let (canonical_element_size, own_resource_type) = stream_payload_info(
    Some(element_type),
    types,
  )
  if own_resource_type is Some(_) {
    raise HostCallError("unit result future cannot own a resource payload")
  }
  let bytes = Array::make(canonical_element_size, b'\x00')
  match error_case {
    Some(error_case) => {
      guard resolve_valtype(element_type, types) is TypeIdx(result_index) &&
        types.get(result_index) is Some(Some(Result(None, Some(error_type)))) &&
        resolve_valtype(error_type, types) is TypeIdx(error_index) &&
        types.get(error_index) is Some(Some(Enum(cases))) &&
        error_case >= 0 &&
        error_case < cases.length() else {
        raise HostCallError("future error does not match unit result type")
      }
      bytes[0] = b'\x01'
      let (payload_size, payload_alignment) = canonical_stream_layout(
        error_type, types,
      )
      let payload_offset = align_to(1, payload_alignment)
      for i in 0..<payload_size {
        bytes[payload_offset + i] = ((error_case >> (i * 8)) & 0xff).to_byte()
      }
    }
    None => ()
  }
  self.new_closed_host_stream(
    table,
    canonical_element_size,
    Bytes::from_array(bytes),
  )
}

///|
/// Consume bytes currently offered by a component-owned `stream<u8>`.
///
/// This method never blocks. `Pending` means the embedding must drive the
/// component task or its external reactor before polling again.
pub fn HostRuntimeState::read_host_byte_stream(
  self : HostRuntimeState,
  table : ResourceTable,
  readable : Int,
) -> HostByteStreamRead raise ComponentRuntimeError {
  let key = handle_key(table.id, readable)
  guard self.stream_table.endpoints.get(key) is Some(endpoint) &&
    endpoint.is_readable &&
    self.stream_table.streams.get(endpoint.stream_id) is Some(state) else {
    raise HostCallError("host byte stream is not live")
  }
  match state.pending_write {
    Some(write) => {
      let remaining = write.buf.length() - write.sent
      if remaining > 0 {
        let bytes : Array[Byte] = []
        for i in write.sent..<write.buf.length() {
          bytes.push(write.buf[i])
        }
        let sent = write.buf.length()
        if write.writer_handle > 0 && !write.event_enqueued {
          enqueue_waitable_event(
            self.async_state,
            handle_key(write.writer_table.id, write.writer_handle),
            {
              owner_component_id: write.writer_table.id,
              code: 3,
              index: write.writer_handle,
              payload: sent << 4,
            },
          )
        }
        self.stream_table.streams.set(endpoint.stream_id, {
          elem_size: state.elem_size,
          own_resource_type_id: state.own_resource_type_id,
          pending_read: state.pending_read,
          pending_write: Some({
            writer_table: write.writer_table,
            buf: write.buf,
            sent,
            writer_handle: write.writer_handle,
            event_enqueued: true,
            defer_complete: write.defer_complete,
          }),
          readable_dropped: state.readable_dropped,
          writable_dropped: state.writable_dropped,
        })
        Data(Bytes::from_array(bytes))
      } else if state.writable_dropped {
        Closed
      } else {
        Pending
      }
    }
    None => if state.writable_dropped { Closed } else { Pending }
  }
}

///|
/// Drop an embedding-owned readable stream endpoint.
pub fn HostRuntimeState::drop_host_readable_stream(
  self : HostRuntimeState,
  table : ResourceTable,
  readable : Int,
) -> Unit raise ComponentRuntimeError {
  let key = handle_key(table.id, readable)
  guard self.stream_table.endpoints.get(key) is Some(endpoint) &&
    endpoint.is_readable &&
    self.stream_table.streams.get(endpoint.stream_id) is Some(state) else {
    raise HostCallError("host byte stream is not live")
  }
  if state.pending_read is Some(_) {
    raise HostCallError("cannot remove busy host byte stream")
  }
  let pending_write = match state.pending_write {
    Some(write) => {
      if write.writer_handle > 0 {
        remove_waitable_events_for(
          self.async_state,
          write.writer_table.id,
          write.writer_handle,
          3,
        )
        enqueue_waitable_event(
          self.async_state,
          handle_key(write.writer_table.id, write.writer_handle),
          {
            owner_component_id: write.writer_table.id,
            code: 3,
            index: write.writer_handle,
            payload: 1 | (write.sent << 4),
          },
        )
      }
      Some({
        writer_table: write.writer_table,
        buf: write.buf,
        sent: write.sent,
        writer_handle: write.writer_handle,
        event_enqueued: true,
        defer_complete: write.defer_complete,
      })
    }
    None => None
  }
  self.stream_table.streams.set(endpoint.stream_id, {
    elem_size: state.elem_size,
    own_resource_type_id: state.own_resource_type_id,
    pending_read: state.pending_read,
    pending_write,
    readable_dropped: true,
    writable_dropped: state.writable_dropped,
  })
  remove_waitable_membership(self.async_state, table.id, readable)
  self.stream_table.endpoints.remove(key)
  free_shared_handle(self.async_state, table.id, readable)
}
