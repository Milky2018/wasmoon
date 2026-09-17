///|
/// Advance transfers without blocking. Each body holds at most one 64 KiB chunk;
/// subsequent reads wait until the consumer drains that chunk.
pub fn HttpHost::poll(
  self : HttpHost,
) -> Bool raise @runtime_impl.ComponentRuntimeError {
  let mut progressed = false
  for body in self.bodies {
    if body.completion.val is Some(_) {
      continue
    }
    if !body.cancelled.val && body.receipt is Some(receipt) {
      match self.runtime.read_host_value_future(body.table, receipt) {
        Pending => ()
        Ready(result) => {
          self.runtime.drop_host_readable_future(body.table, receipt)
          body.receipt = None
          if result is Variant(1, _) {
            body.completion.val = Some(result)
            body.cancelled.val = true
          }
          progressed = true
        }
      }
    }
    if body.cancelled.val {
      if body.contents is Some(handle) {
        self.runtime.drop_host_readable_stream(body.table, handle)
        body.contents = None
      }
      if body.trailers is Some(handle) {
        self.runtime.drop_host_readable_future(body.table, handle)
        body.trailers = None
      }
      if body.receipt is Some(handle) {
        self.runtime.drop_host_readable_future(body.table, handle)
        body.receipt = None
      }
      self.discard_trailers(body.trailer_result)
      body.buffer.clear()
      body.closed.val = true
      if body.completion.val is None {
        body.completion.val = Some(http_error(7))
      }
      body.trailer_result.val = body.completion.val
      body.trailer_status.val = body.completion.val
      progressed = true
      continue
    }
    if !body.consumed {
      continue
    }
    if body.buffer.is_empty() && !body.closed.val {
      if body.contents is Some(handle) {
        match self.runtime.read_host_byte_stream(body.table, handle) {
          Pending => ()
          Data(bytes) => {
            for byte in bytes {
              body.buffer.push(U8(byte.to_int()))
            }
            progressed = true
          }
          Closed => {
            self.runtime.drop_host_readable_stream(body.table, handle)
            body.contents = None
            body.closed.val = true
            progressed = true
          }
        }
      } else {
        body.closed.val = true
        progressed = true
      }
    }
    if body.closed.val && body.trailers is Some(handle) {
      match self.runtime.read_host_value_future(body.table, handle) {
        Pending => ()
        Ready(value) => {
          body.trailer_result.val = Some(value)
          body.trailer_status.val = Some(
            match value {
              Variant(0, _) => Variant(0, None)
              error => error
            },
          )
          self.runtime.drop_host_readable_future(body.table, handle)
          body.trailers = None
          progressed = true
        }
      }
    }
    if body.observed_closed.val &&
      body.trailer_status.val is Some(result) &&
      body.receipt is None {
      body.completion.val = Some(
        match result {
          Variant(0, _) => Variant(0, None)
          error => error
        },
      )
      progressed = true
    }
  }
  let active = self.bodies.filter(fn(body) { body.completion.val is None })
  self.bodies.clear()
  self.bodies.append(active)
  progressed
}

///|
fn HttpHost::discard_trailers(
  self : HttpHost,
  value : Ref[@runtime_impl.ComponentValue?],
) -> Unit {
  if value.val is Some(Variant(0, Some(Variant(1, Some(handle))))) {
    try
      self.take(self.runtime.resource_table(), handle, "fields") |> ignore
    catch {
      _ => ()
    }
  }
  value.val = None
}
