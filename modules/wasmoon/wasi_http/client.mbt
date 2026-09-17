///|
fn request_timeout(message : HttpMessage, index : Int) -> Int {
  match message.options {
    Some(options) =>
      match options.values[index] {
        Variant(1, Some(U64(ns))) =>
          if ns < 0L {
            2147483647
          } else {
            Int64::min(
              ns / 1000000L + (if ns % 1000000L == 0L { 0L } else { 1L }),
              2147483647L,
            ).to_int()
          }
        _ => 30000
      }
    None => 30000
  }
}

///|
async fn HttpHost::exchange(
  self : HttpHost,
  reader : &@io.Reader,
  writer : &@io.Writer,
  message : HttpMessage,
  authority : String,
  result : Ref[Array[@runtime_impl.ComponentValue]?],
) -> Unit {
  let verb = request_method(message)
  if verb == "CONNECT" {
    raise HttpTransportError(15, "CONNECT tunnels are not HTTP message bodies")
  }
  let path = match message.attributes.get("path-with-query") {
    Some(Variant(1, Some(String(path)))) if !path.is_empty() => path
    _ => "/"
  }
  if !path_query_valid(path) ||
    (!path.has_prefix("/") && !(path == "*" && verb == "OPTIONS")) {
    raise HttpTransportError(19, "invalid request target")
  }
  // Validate length metadata before emitting headers. Chunking preserves trailers.
  message_framing(message.headers, false, false) |> ignore
  writer.write(verb + " " + path + " HTTP/1.1\r\nHost: " + authority + "\r\n")
  write_fields(writer, outgoing_fields(message.headers))
  writer.write("Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n")
  let input = {
    reader,
    buffer: b"",
    offset: 0,
    timeout: Some(request_timeout(message, 2)),
    first_byte: Some(Timer(request_timeout(message, 1))),
  }
  @async.with_task_group(async fn(group) {
    let upload = group.spawn(async fn() {
      self.write_body(writer, message, false)
    })
    defer upload.cancel()
    let mut status = 0
    let mut fields = HttpFields::from_list().unwrap()
    let mut informational = 0
    while true {
      let line = ascii_text(input.line())
      let parts = line.split(" ").to_array()
      if parts.length() < 2 ||
        !(parts[0] == "HTTP/1.1" || parts[0] == "HTTP/1.0") ||
        parts[1].length() != 3 {
        raise HttpTransportError(35, "invalid HTTP response line")
      }
      status = decimal_length(parts[1].to_owned()).to_int()
      if status < 100 || status > 999 {
        raise HttpTransportError(35, "invalid response status")
      }
      fields = input.fields()
      if status >= 200 {
        break
      }
      if status == 101 {
        raise HttpTransportError(34, "protocol upgrade is not supported")
      }
      informational += 1
      if informational > 16 {
        raise HttpTransportError(35, "too many informational responses")
      }
    }
    let framing = message_framing(
      fields,
      true,
      verb == "HEAD" || status == 204 || status == 304,
    )
    let (response, body) = self.incoming(
      incoming_fields(fields),
      true,
      Map([("status-code", U16(status))]),
    )
    result.val = Some([Variant(0, Some(response))])
    self.wake.broadcast()
    self.receive_body(input, framing, body)
  })
}

///|
/// Install the network client with an explicit authority capability policy.
/// TLS uses system trust roots. Each exchange owns its connection and streams.
pub fn HttpHost::add_network_client(
  self : HttpHost,
  allow : (String) -> Bool,
  allow_address? : (@socket.Addr) -> Bool = _ => true,
  trust? : @tls.TrustedRoot = SystemRoot,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  self.add_client((args, table) => {
    guard args is [handle] &&
      self.take(table, handle, "request") is Message(message) else {
      raise HostCallError("expected HTTP request")
    }
    guard self.spawn.val is Some(spawn) else {
      raise HostCallError("HTTP host must be running before client.send")
    }
    let result = Ref(None)
    let wake = self.wake
    let task = spawn(async fn() {
      try {
        let authority = request_authority(message)
        if !allow(authority) {
          raise HttpTransportError(15, "outgoing authority is not permitted")
        }
        let secure = match message.attributes.get("scheme") {
          Some(Variant(0, None)) | Some(Variant(1, Some(Variant(0, None)))) =>
            false
          Some(Variant(1, Some(Variant(1, None)))) => true
          Some(Variant(1, Some(Variant(2, Some(String(scheme)))))) if scheme.to_lower() ==
            "http" => false
          Some(Variant(1, Some(Variant(2, Some(String(scheme)))))) if scheme.to_lower() ==
            "https" => true
          _ => raise HttpTransportError(19, "unsupported URI scheme")
        }
        let (host, port) = authority_host_port(authority, secure)
        let socket = @async.with_timeout(
          request_timeout(message, 0),
          async fn() {
            let address = @socket.Addr::resolve(host, port~)
            if !allow_address(address) {
              raise HttpTransportError(
                4, "destination address is not permitted",
              )
            }
            @socket.Tcp::connect(address)
          },
          error=HttpTransportError(8, "connection timeout"),
        )
        defer socket.close()
        if secure {
          let tls = @async.with_timeout(
            request_timeout(message, 0),
            async fn() { @tls.Tls::client(socket, host~, trust~) },
            error=HttpTransportError(8, "TLS handshake timeout"),
          )
          defer tls.close()
          self.exchange(tls, tls, message, authority, result)
        } else {
          self.exchange(socket, socket, message, authority, result)
        }
      } catch {
        error => {
          if result.val is None {
            result.val = Some([transport_error(error)])
          }
          message.body.cancelled.val = true
        }
      }
      wake.broadcast()
    })
    HostFuture(
      () => {
        match result.val {
          Some([Variant(0, Some(U32(handle)))]) => {
            let source = self.runtime.resource_table()
            let moved = if source.id == table.id {
              handle
            } else {
              guard source.get(handle) is Some(resource) &&
                resource.own &&
                resource.num_lends[0] == 0 else {
                raise HostCallError("invalid client response resource")
              }
              source.free(handle) |> ignore
              table.alloc(resource)
            }
            result.val = None
            Ready([Variant(0, Some(U32(moved)))])
          }
          Some(value) => {
            result.val = None
            Ready(value)
          }
          None => Pending
        }
      },
      () => {
        task.cancel()
        message.body.cancelled.val = true
        if result.val is Some([Variant(0, Some(handle))]) {
          try
            self.take(self.runtime.resource_table(), handle, "response")
          catch {
            _ => ()
          } noraise {
            Message(response) => response.body.cancelled.val = true
            _ => ()
          }
        }
        result.val = None
        wake.broadcast()
      },
    )
  })
}
