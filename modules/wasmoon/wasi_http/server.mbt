///|
fn method_value(verb : String) -> @runtime_impl.ComponentValue {
  let methods = [
    "GET", "HEAD", "POST", "PUT", "DELETE", "CONNECT", "OPTIONS", "TRACE", "PATCH",
  ]
  for index, known in methods {
    if verb == known {
      return Variant(index, None)
    }
  }
  Variant(9, Some(String(verb)))
}

///|
/// Handle one HTTP/1.1 connection with a service instance. The caller owns the
/// socket and runs this operation inside `HttpHost::run`.
async fn HttpHost::serve_exchange(
  self : HttpHost,
  socket : @socket.Tcp,
  instance : @runtime_impl.ComponentInstance,
  started : Ref[Bool],
  error_status : Ref[Int],
) -> Unit {
  let input = HttpInput::{
    reader: socket,
    buffer: b"",
    offset: 0,
    timeout: Some(30000),
    between_timeout: Some(30000),
  }
  let line = ascii_text(input.line())
  let parts = line.split(" ").to_array()
  if parts.length() != 3 ||
    !field_token(parts[0].to_owned()) ||
    parts[2] != "HTTP/1.1" {
    raise HttpTransportError(35, "invalid HTTP/1.1 request line")
  }
  let verb = parts[0].to_owned()
  let path = parts[1].to_owned()
  if !uri_part_valid(path, false) ||
    (!path.has_prefix("/") && !(path == "*" && verb == "OPTIONS")) {
    raise HttpTransportError(19, "invalid request target")
  }
  let headers = input.fields()
  guard headers.get("host") is [authority_bytes] else {
    raise HttpTransportError(19, "HTTP/1.1 requires exactly one Host field")
  }
  let authority = ascii_text(authority_bytes)
  authority_host_port(authority, false) |> ignore
  let framing = message_framing(headers, false, false)
  let expectations = headers.get("expect")
  if !expectations.is_empty() {
    if expectations != [b"100-continue"] {
      started.val = true
      socket.write(
        "HTTP/1.1 417 Expectation Failed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
      )
      return
    }
    socket.write("HTTP/1.1 100 Continue\r\n\r\n")
  }
  error_status.val = 500
  let (request, body) = self.incoming(
    incoming_fields(headers),
    false,
    Map([
      ("method", method_value(verb)),
      ("path-with-query", Variant(1, Some(String(path)))),
      ("scheme", Variant(1, Some(Variant(0, None)))),
      ("authority", Variant(1, Some(String(authority)))),
    ]),
  )
  let handler = match instance.exports.get("wasi:http/handler@0.3.0") {
    Some(Instance(handler)) => handler
    _ => instance
  }
  @async.with_task_group(async fn(group) {
    let download = group.spawn(async fn() {
      self.receive_body(input, framing, body)
    })
    defer download.cancel()
    let values = self.invoke(handler, "handle", [request])
    let table = self.runtime.resource_table()
    guard values is [Variant(0, Some(response))] &&
      self.take(table, response, "response") is Message(message) else {
      started.val = true
      socket.write(
        "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
      )
      return
    }
    guard message.attributes.get("status-code") is Some(U16(status)) else {
      raise HttpTransportError(35, "invalid response status")
    }
    if status < 200 || status > 999 {
      raise HttpTransportError(35, "handler must return a final response")
    }
    let no_body = verb == "HEAD" ||
      status == 204 ||
      status == 205 ||
      status == 304
    let framing = message_framing(message.headers, false, false)
    started.val = true
    socket.write("HTTP/1.1 \{status} Response\r\n")
    write_fields(socket, outgoing_fields(message.headers))
    if !no_body {
      socket.write("Transfer-Encoding: chunked\r\n")
    } else if status == 205 {
      socket.write("Content-Length: 0\r\n")
    } else if status != 204 &&
      message.headers.has("content-length") &&
      framing is Length(length) {
      socket.write("Content-Length: \{length}\r\n")
    }
    socket.write("Connection: close\r\n\r\n")
    self.write_body(socket, message, no_body)
  })
}

///|
/// Handle one HTTP/1.1 connection. Each call runs inside `HttpHost::run`; the
/// caller owns the socket. Malformed requests receive 400 before guest dispatch.
pub async fn HttpHost::serve_connection(
  self : HttpHost,
  socket : @socket.Tcp,
  instance : @runtime_impl.ComponentInstance,
) -> Unit {
  let started = Ref(false)
  let error_status = Ref(400)
  errdefer (if !started.val {
    socket.write(
      "HTTP/1.1 \{error_status.val} Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
    ) catch {
      _ => ()
    }
  })
  self.serve_exchange(socket, instance, started, error_status)
}
