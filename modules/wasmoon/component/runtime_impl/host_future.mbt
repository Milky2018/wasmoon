///|
/// Read a future at an embedding boundary without blocking. A closed writer
/// without a value is an error; successful reads transfer owned payload handles.
pub fn HostRuntimeState::read_host_value_future(
  self : HostRuntimeState,
  table : ResourceTable,
  readable : Int,
) -> HostFutureValuePoll raise ComponentRuntimeError {
  guard self.async_state.future_endpoints.get(handle_key(table.id, readable))
    is Some(endpoint) &&
    endpoint.is_readable &&
    self.async_state.futures.get(endpoint.future_id) is Some(state) else {
    raise HostCallError("host future is not live")
  }
  if state.read_done || state.pending_read is Some(_) {
    raise HostCallError("host future already read or busy")
  }
  let host_source = self.async_state.host_future_values.get(endpoint.future_id)
  let value = if host_source is Some(source) {
    match poll_host_future_value(source) {
      Pending => return Pending
      Ready(value) => {
        let value = transfer_stream_future_value(
          source.payload_ty,
          value,
          source.types,
          self.async_state,
          endpoint.creator_component_id,
          table.id,
        ).to_host_value()
        self.async_state.host_future_values.remove(endpoint.future_id)
        value
      }
    }
  } else if state.pending_write is Some(write) {
    let value = match write.payload.values {
      [] => Tuple([])
      [value] =>
        match write.payload.payload_type.ty {
          Some(ty) =>
            transfer_stream_future_value(
              ty,
              value,
              write.payload.payload_type.types,
              self.async_state,
              write.writer_component_id,
              table.id,
            ).to_host_value()
          None => value.to_host_value()
        }
      _ => raise HostCallError("invalid future payload arity")
    }
    if self.async_state.future_endpoints.get(
        handle_key(write.writer_component_id, write.writer_handle),
      )
      is Some(_) {
      enqueue_waitable_event(
        self.async_state,
        handle_key(write.writer_component_id, write.writer_handle),
        {
          owner_component_id: write.writer_component_id,
          code: 5,
          index: write.writer_handle,
          payload: 0,
        },
      )
    }
    value
  } else if state.writable_dropped {
    raise HostCallError("future writer closed without a value")
  } else {
    return Pending
  }
  self.async_state.futures.replace(endpoint.future_id, {
    payload_ty: state.payload_ty,
    pending_read: None,
    pending_write: None,
    readable_dropped: state.readable_dropped,
    writable_dropped: host_source is Some(_) || state.writable_dropped,
    read_done: true,
    write_succeeded: true,
    write_observed_readable_drop: false,
    wrote_value: true,
  })
  Ready(value)
}
