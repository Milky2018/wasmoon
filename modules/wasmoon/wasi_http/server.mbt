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
  let target = parts[1].to_owned()
  let headers = input.fields()
  guard headers.get("host") is [authority_bytes] else {
    raise HttpTransportError(19, "HTTP/1.1 requires exactly one Host field")
  }
  let (path, authority, scheme) = request_target(
    verb,
    target,
    ascii_text(authority_bytes),
  )
  let framing = message_framing(headers, false, false)
  let expectations = headers.get("expect")
  if !expectations.is_empty() {
    if !continue_expected(expectations) {
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
      ("scheme", Variant(1, Some(scheme))),
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

///|
fn continue_expected(values : Array[Bytes]) -> Bool raise {
  let mut found = false
  for value in values {
    for expectation in ascii_text(value).split(",") {
      let expectation = expectation.trim().to_owned().to_lower()
      if expectation.is_empty() {
        continue
      }
      if expectation != "100-continue" {
        return false
      }
      found = true
    }
  }
  found
}

///|
fn request_target(
  verb : String,
  target : String,
  host : String,
) -> (String, String, @runtime_impl.ComponentValue) raise {
  if target.is_empty() || !uri_part_valid(target, false) {
    raise HttpTransportError(19, "invalid request target")
  }
  if target.has_prefix("/") || (target == "*" && verb == "OPTIONS") {
    authority_host_port(host, false) |> ignore
    return (target, host, Variant(0, None))
  }
  guard target.find("://") is Some(separator) else {
    raise HttpTransportError(19, "invalid request target")
  }
  let scheme = target[:separator].to_owned().to_lower()
  if !scheme_valid(scheme) {
    raise HttpTransportError(19, "invalid request scheme")
  }
  let start = separator + 3
  let mut end = start
  while end < target.length() && target[end] != '/' && target[end] != '?' {
    end += 1
  }
  let authority = target[start:end].to_owned()
  authority_host_port(authority, scheme == "https") |> ignore
  let path = if end == target.length() {
    if verb == "OPTIONS" {
      "*"
    } else {
      "/"
    }
  } else if target[end] == '?' {
    "/" + target[end:].to_owned()
  } else {
    target[end:].to_owned()
  }
  let scheme = match scheme {
    "http" => @runtime_impl.ComponentValue::Variant(0, None)
    "https" => Variant(1, None)
    other => Variant(2, Some(String(other)))
  }
  (path, authority, scheme)
}
