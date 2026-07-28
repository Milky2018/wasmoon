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
/// Create a finite typed stream produced by the embedding.
///
/// Values are lowered into the reader's canonical memory when `stream.read`
/// runs. This is required for payloads such as records containing strings:
/// storing writer-side canonical bytes would leave pointers referring to the
/// wrong component memory.
pub fn HostRuntimeState::new_host_value_stream(
  self : HostRuntimeState,
  table : ResourceTable,
  payload_ty : ValType,
  types : Array[TypeDef?],
  values : Array[ComponentValue],
) -> Int raise ComponentRuntimeError {
  let (element_size, own_resource_type) = stream_payload_info(
    Some(payload_ty),
    types,
  )
  let stream_id = self.stream_table.next_stream_id[0]
  self.stream_table.next_stream_id[0] = stream_id + 1
  let readable = alloc_shared_handle(self.async_state, table.id)
  self.stream_table.streams.set(stream_id, {
    elem_size: element_size,
    own_resource_type_id: own_resource_type,
    pending_read: None,
    pending_write: None,
    readable_dropped: false,
    writable_dropped: true,
  })
  self.stream_table.host_values.set(stream_id, {
    payload_ty,
    types,
    values: values.copy(),
    next: Ref(0),
    pull: None,
    cancel: None,
    closed: Ref(true),
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
/// Create a typed stream whose values are produced on demand by the embedding.
///
/// `pull` must be non-blocking. Returning `Pending` delegates waiting to the
/// embedding event loop installed on `HostRuntimeState`; after that loop
/// reports progress, the runtime polls the source again and completes the
/// pending canonical read.
pub fn HostRuntimeState::new_host_value_stream_source(
  self : HostRuntimeState,
  table : ResourceTable,
  payload_ty : ValType,
  types : Array[TypeDef?],
  pull : (Int) -> HostValueStreamPoll raise ComponentRuntimeError,
  cancel : () -> Unit,
) -> Int raise ComponentRuntimeError {
  let (element_size, own_resource_type) = stream_payload_info(
    Some(payload_ty),
    types,
  )
  let stream_id = self.stream_table.next_stream_id[0]
  self.stream_table.next_stream_id[0] = stream_id + 1
  let readable = alloc_shared_handle(self.async_state, table.id)
  self.stream_table.streams.set(stream_id, {
    elem_size: element_size,
    own_resource_type_id: own_resource_type,
    pending_read: None,
    pending_write: None,
    readable_dropped: false,
    writable_dropped: false,
  })
  self.stream_table.host_values.set(stream_id, {
    payload_ty,
    types,
    values: [],
    next: Ref(0),
    pull: Some(pull),
    cancel: Some(cancel),
    closed: Ref(false),
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
/// Create a completed typed future produced by the embedding.
pub fn HostRuntimeState::new_host_value_future(
  self : HostRuntimeState,
  table : ResourceTable,
  element_type : ValType,
  types : Array[TypeDef?],
  value : ComponentValue,
) -> Int raise ComponentRuntimeError {
  stream_payload_info(Some(element_type), types) |> ignore
  let future_id = self.async_state.next_future_id[0]
  self.async_state.next_future_id[0] = future_id + 1
  let readable = alloc_shared_handle(self.async_state, table.id)
  self.async_state.future_endpoints.set(handle_key(table.id, readable), {
    future_id,
    is_readable: true,
    creator_component_id: table.id,
    in_waitable_set: Ref(false),
  })
  self.async_state.futures.set(future_id, {
    payload_ty: Some(element_type),
    pending_read: None,
    pending_write: None,
    readable_dropped: false,
    writable_dropped: true,
    read_done: false,
    write_succeeded: true,
    write_observed_readable_drop: false,
    wrote_value: true,
  })
  self.async_state.host_future_values.set(future_id, {
    payload_ty: element_type,
    types,
    value: Ref(Some(value)),
    pull: None,
    cancel: None,
  })
  readable
}

///|
/// Create a typed future whose value is produced on demand by the embedding.
///
/// `pull` must be non-blocking. Returning `Pending` delegates waiting to the
/// embedding event loop installed on `HostRuntimeState`.
pub fn HostRuntimeState::new_host_value_future_source(
  self : HostRuntimeState,
  table : ResourceTable,
  element_type : ValType,
  types : Array[TypeDef?],
  pull : () -> HostFutureValuePoll raise ComponentRuntimeError,
  cancel : () -> Unit,
) -> Int raise ComponentRuntimeError {
  stream_payload_info(Some(element_type), types) |> ignore
  let future_id = self.async_state.next_future_id[0]
  self.async_state.next_future_id[0] = future_id + 1
  let readable = alloc_shared_handle(self.async_state, table.id)
  self.async_state.future_endpoints.set(handle_key(table.id, readable), {
    future_id,
    is_readable: true,
    creator_component_id: table.id,
    in_waitable_set: Ref(false),
  })
  self.async_state.futures.set(future_id, {
    payload_ty: Some(element_type),
    pending_read: None,
    pending_write: None,
    readable_dropped: false,
    writable_dropped: false,
    read_done: false,
    write_succeeded: false,
    write_observed_readable_drop: false,
    wrote_value: false,
  })
  self.async_state.host_future_values.set(future_id, {
    payload_ty: element_type,
    types,
    value: Ref(None),
    pull: Some(pull),
    cancel: Some(cancel),
  })
  readable
}

///|
/// Create a completed `future<result<_, E>>` containing `ok(())` or one
/// structured error-code case.
pub fn HostRuntimeState::new_host_unit_result_future(
  self : HostRuntimeState,
  table : ResourceTable,
  element_type : ValType,
  types : Array[TypeDef?],
  error_case? : Int,
) -> Int raise ComponentRuntimeError {
  let value = match error_case {
    Some(error_case) => {
      guard resolve_valtype(element_type, types) is TypeIdx(result_index) &&
        types.get(result_index) is Some(Some(Result(None, Some(error_type)))) &&
        resolve_valtype(error_type, types) is TypeIdx(error_index) &&
        types.get(error_index) is Some(Some(Enum(cases))) &&
        error_case >= 0 &&
        error_case < cases.length() else {
        raise HostCallError("future error does not match unit result type")
      }
      Variant(1, Some(U32(error_case)))
    }
    None => Variant(0, None)
  }
  self.new_host_value_future(table, element_type, types, value)
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
  match self.stream_table.host_values.get(endpoint.stream_id) {
    Some(source) =>
      match source.cancel {
        Some(cancel) => cancel()
        None => ()
      }
    None => ()
  }
  self.stream_table.host_values.remove(endpoint.stream_id)
  free_shared_handle(self.async_state, table.id, readable)
  cleanup_closed_stream(self.stream_table, endpoint.stream_id)
}

///|
/// Drop an embedding-owned readable future endpoint.
///
/// Host-created futures have no live writable endpoint. Busy component-owned
/// futures must be dropped through their canonical ABI operation instead.
pub fn HostRuntimeState::drop_host_readable_future(
  self : HostRuntimeState,
  table : ResourceTable,
  readable : Int,
) -> Unit raise ComponentRuntimeError {
  let key = handle_key(table.id, readable)
  guard self.async_state.future_endpoints.get(key) is Some(endpoint) &&
    endpoint.is_readable &&
    self.async_state.futures.get(endpoint.future_id) is Some(state) else {
    raise HostCallError("host future is not live")
  }
  if state.pending_read is Some(_) || state.pending_write is Some(_) {
    raise HostCallError("cannot remove busy host future")
  }
  match self.async_state.host_future_values.get(endpoint.future_id) {
    Some(source) =>
      match source.cancel {
        Some(cancel) => cancel()
        None => ()
      }
    None => ()
  }
  self.async_state.host_future_values.remove(endpoint.future_id)
  self.async_state.futures.set(endpoint.future_id, {
    payload_ty: state.payload_ty,
    pending_read: None,
    pending_write: None,
    readable_dropped: true,
    writable_dropped: true,
    read_done: true,
    write_succeeded: state.write_succeeded,
    write_observed_readable_drop: state.write_observed_readable_drop,
    wrote_value: state.wrote_value,
  })
  remove_waitable_membership(self.async_state, table.id, readable)
  self.async_state.future_endpoints.remove(key)
  free_shared_handle(self.async_state, table.id, readable)
  cleanup_closed_future(self.async_state, endpoint.future_id)
}
