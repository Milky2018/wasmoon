///|
struct NetworkBody {
  bytes : Ref[Bytes?]
  offset : Ref[Int]
  eof : Ref[Bool]
  trailers : Ref[@runtime_impl.ComponentValue?]
  cancelled : Ref[Bool]
  wake : @async.CondVar
}

///|
fn NetworkBody::NetworkBody(wake : @async.CondVar) -> NetworkBody {
  {
    bytes: Ref(None),
    offset: Ref(0),
    eof: Ref(false),
    trailers: Ref(None),
    cancelled: Ref(false),
    wake,
  }
}

///|
fn NetworkBody::pull(
  self : NetworkBody,
  maximum : Int,
) -> @runtime_impl.HostValueStreamPoll {
  if self.bytes.val is Some(bytes) {
    let end = Int::min(bytes.length(), self.offset.val + maximum)
    let values : Array[@runtime_impl.ComponentValue] = []
    for index in self.offset.val..<end {
      values.push(U8(bytes[index].to_int()))
    }
    self.offset.val = end
    if end == bytes.length() {
      self.bytes.val = None
      self.offset.val = 0
      self.wake.broadcast()
    }
    Values(values)
  } else if self.eof.val {
    Closed
  } else {
    Pending
  }
}

///|
async fn NetworkBody::put(self : NetworkBody, bytes : Bytes) -> Unit {
  while self.bytes.val is Some(_) && !self.cancelled.val {
    self.wake.wait()
  }
  if self.cancelled.val {
    raise @runtime_impl.Cancelled
  }
  self.bytes.val = Some(bytes)
  self.wake.broadcast()
}

///|
fn HttpHost::incoming(
  self : HttpHost,
  fields : HttpFields,
  response : Bool,
  attributes : Map[String, @runtime_impl.ComponentValue],
) -> (@runtime_impl.ComponentValue, NetworkBody) raise @runtime_impl.ComponentRuntimeError {
  let table = self.runtime.resource_table()
  let body = NetworkBody(self.wake)
  let stream = self.runtime.new_host_value_stream_source(
    table,
    Prim(U8),
    [],
    maximum => body.pull(maximum),
    () => {
      body.cancelled.val = true
      body.wake.broadcast()
    },
  )
  let trailers = self.runtime.new_host_value_future_source(
    table,
    self.future_payload(1),
    self.types,
    () => {
      match body.trailers.val {
        Some(value) => {
          body.trailers.val = None
          Ready(value)
        }
        None => Pending
      }
    },
    () => {
      body.cancelled.val = true
      self.discard_trailers(body.trailers)
      body.wake.broadcast()
    },
  )
  let headers = self.allocate(table, "fields", Fields(fields))
  let args = [
    headers,
    @runtime_impl.ComponentValue::Variant(1, Some(U32(stream))),
    U32(trailers),
  ]
  if !response {
    args.push(Variant(0, None))
  }
  guard self.new_message(response, args, table)
    is Tuple([handle, U32(completion)]) else {
    raise HostCallError("invalid HTTP construction")
  }
  // The transport reports body failures through trailers; no producer awaits
  // the component-facing transmission receipt on an incoming network message.
  self.runtime.drop_host_readable_future(table, completion)
  guard self.get(table, handle, if response { "response" } else { "request" })
    is Message(message) else {
    raise HostCallError("missing incoming message")
  }
  for name, value in attributes {
    message.attributes.set(name, value)
  }
  (handle, body)
}

///|
async fn HttpHost::receive_body(
  self : HttpHost,
  input : HttpInput,
  framing : HttpFraming,
  body : NetworkBody,
) -> Unit {
  try {
    let trailers = input.body(framing, async fn(bytes) { body.put(bytes) })
    if body.cancelled.val {
      return
    }
    let value = if trailers.entries.is_empty() {
      @runtime_impl.ComponentValue::Variant(0, None)
    } else {
      Variant(
        1,
        Some(
          self.allocate(
            self.runtime.resource_table(),
            "fields",
            Fields(trailers),
          ),
        ),
      )
    }
    body.trailers.val = Some(Variant(0, Some(value)))
  } catch {
    error => body.trailers.val = Some(transport_error(error))
  }
  body.eof.val = true
  body.wake.broadcast()
}

///|
fn transport_error(error : Error) -> @runtime_impl.ComponentValue {
  match error {
    HttpTransportError(code, _) => http_error(code)
    @socket.ResolveHostnameError(_) => http_error(1)
    @os_error.OSError(_, ..) as error =>
      if error.is_ECONNREFUSED() {
        http_error(6)
      } else {
        http_error(7)
      }
    @tls.TlsError(_) => http_error(12)
    _ => http_error(7)
  }
}

///|
async fn HttpHost::read_body(
  self : HttpHost,
  table : @runtime_impl.ResourceTable,
  handle : Int,
) -> Bytes? {
  while true {
    match self.runtime.read_host_byte_stream(table, handle) {
      Data(bytes) => {
        self.wake.broadcast()
        return Some(bytes)
      }
      Closed => {
        self.wake.broadcast()
        return None
      }
      Pending => self.wake.wait()
    }
  }
  abort("unreachable")
}

///|
async fn HttpHost::read_future(
  self : HttpHost,
  table : @runtime_impl.ResourceTable,
  handle : Int,
) -> @runtime_impl.ComponentValue {
  while true {
    match self.runtime.read_host_value_future(table, handle) {
      Ready(value) => {
        self.wake.broadcast()
        return value
      }
      Pending => self.wake.wait()
    }
  }
  abort("unreachable")
}

///|
async fn HttpHost::write_body(
  self : HttpHost,
  writer : &@io.Writer,
  message : HttpMessage,
  no_body : Bool,
) -> Unit {
  let table = self.runtime.resource_table()
  let outcome = Ref(None)
  let receipt = self.runtime.new_host_value_future_source(
    table,
    self.future_payload(0),
    self.types,
    () => {
      match outcome.val {
        Some(result) => Ready(result)
        None => Pending
      }
    },
    () => (),
  )
  guard self.consume_body(message, receipt, table)
    is Tuple([U32(stream), U32(trailer_future)]) else {
    raise @runtime_impl.HostCallError("missing body handles")
  }
  defer {
    self.runtime.drop_host_readable_stream(table, stream) catch {
      _ => ()
    }
    self.runtime.drop_host_readable_future(table, trailer_future) catch {
      _ => ()
    }
    self.wake.broadcast()
  }
  self.wake.broadcast()
  try {
    let mut count = 0L
    while self.read_body(table, stream) is Some(bytes) {
      count += bytes.length().to_int64()
      if !no_body && !bytes.is_empty() {
        writer.write(bytes.length().to_string(radix=16) + "\r\n")
        writer.write(bytes)
        writer.write("\r\n")
      }
    }
    let result = self.read_future(table, trailer_future)
    guard result is Variant(0, Some(optional)) else {
      raise HttpTransportError(7, "body producer failed")
    }
    let trailers = match optional {
      Variant(0, None) => HttpFields::from_list().unwrap()
      Variant(1, Some(handle)) => {
        guard self.take(table, handle, "fields") is Fields(fields) else {
          raise @runtime_impl.HostCallError("invalid trailers")
        }
        fields
      }
      _ => raise @runtime_impl.HostCallError("invalid trailers result")
    }
    if !no_body {
      let declared = message_framing(message.headers, false, false)
      if declared is Length(expected) &&
        message.headers.has("content-length") &&
        count != expected {
        raise HttpTransportError(
          35, "body length does not match content-length",
        )
      }
      for entry in trailers.entries {
        if field_forbidden(entry.0) ||
          ["content-length", "host", "trailer"].contains(entry.0.to_lower()) {
          raise HttpTransportError(35, "forbidden trailer")
        }
      }
      writer.write("0\r\n")
      write_fields(writer, trailers)
      writer.write("\r\n")
    }
    outcome.val = Some(Variant(0, None))
    self.poll() |> ignore
  } catch {
    error => {
      outcome.val = Some(transport_error(error))
      self.wake.broadcast()
      raise error
    }
  }
  self.wake.broadcast()
}

///|
fn outgoing_fields(fields : HttpFields) -> HttpFields {
  {
    entries: fields.entries.filter(fn(entry) {
      !field_forbidden(entry.0) &&
      entry.0.to_lower() != "content-length" &&
      entry.0.to_lower() != "host"
    }),
    immutable: true,
  }
}

///|
fn request_method(message : HttpMessage) -> String raise {
  match message.attributes.get("method") {
    Some(Variant(9, Some(String(verb)))) => verb
    Some(Variant(index, None)) if index >= 0 && index < 9 =>
      [
        "GET", "HEAD", "POST", "PUT", "DELETE", "CONNECT", "OPTIONS", "TRACE", "PATCH",
      ][index]
    _ => raise HttpTransportError(18, "invalid method")
  }
}

///|
fn request_authority(message : HttpMessage) -> String raise {
  match message.attributes.get("authority") {
    Some(Variant(1, Some(String(authority)))) if !authority.is_empty() &&
      uri_part_valid(authority, true) &&
      !authority.contains("@") => authority
    _ => raise HttpTransportError(19, "missing or invalid authority")
  }
}

///|
fn authority_host_port(
  authority : String,
  secure : Bool,
) -> (String, Int) raise {
  if authority.is_empty() ||
    !uri_part_valid(authority, true) ||
    authority.contains("@") {
    raise HttpTransportError(19, "invalid authority")
  }
  let default_port = if secure { 443 } else { 80 }
  if authority.has_prefix("[") {
    guard authority.find("]") is Some(end) else {
      raise HttpTransportError(19, "invalid IPv6 authority")
    }
    let host = authority[1:end].to_owned()
    if !host.contains(":") {
      raise HttpTransportError(19, "invalid IPv6 literal")
    }
    @socket.Addr::parse("[" + host + "]:0") |> ignore
    let suffix = authority[end + 1:].to_owned()
    if suffix.is_empty() {
      return (host, default_port)
    }
    if !suffix.has_prefix(":") {
      raise HttpTransportError(19, "invalid authority suffix")
    }
    let port = decimal_length(suffix[1:].to_owned())
    if port < 0L || port > 65535L {
      raise HttpTransportError(19, "invalid port")
    }
    return (host, port.to_int())
  }
  let parts = authority.split(":").to_array()
  if parts.length() > 2 || parts[0].is_empty() {
    raise HttpTransportError(19, "invalid authority")
  }
  let port = if parts.length() == 2 {
    decimal_length(parts[1].to_owned())
  } else {
    default_port.to_int64()
  }
  if port < 0L || port > 65535L {
    raise HttpTransportError(19, "invalid port")
  }
  (parts[0].to_owned(), port.to_int())
}

///|
fn incoming_fields(fields : HttpFields) -> HttpFields raise {
  let connection_fields : Array[String] = []
  for value in fields.get("connection") {
    for name in ascii_text(value).split(",") {
      let name = name.trim().to_owned().to_lower()
      if !field_token(name) {
        raise HttpTransportError(35, "invalid Connection field")
      }
      connection_fields.push(name)
    }
  }
  {
    entries: fields.entries.filter(fn(entry) {
      !field_forbidden(entry.0) &&
      !connection_fields.contains(entry.0.to_lower())
    }),
    immutable: true,
  }
}
