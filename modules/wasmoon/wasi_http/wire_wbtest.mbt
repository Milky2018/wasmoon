///|
async test "HTTP framing rejects ambiguous lengths and invalid trailers" {
  for
    wire in [
      b"Content-Length: 1\r\nContent-Length: 2\r\n\r\n", b"Content-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n",
      b"Content-Length: -1\r\n\r\n", b"Transfer-Encoding: gzip, chunked\r\n\r\n",
      b"Content-Length: 9223372036854775808\r\n\r\n",
    ] {
    let reader = @io.MemoryReader(async fn(writer) { writer.write(wire) })
    defer reader.close()
    let input = HttpInput::{
      reader,
      buffer: b"",
      offset: 0,
      timeout: None,
      between_timeout: None,
    }
    let headers = input.fields()
    try message_framing(headers, false, false) catch {
      _ => ()
    } noraise {
      _ => fail("accepted ambiguous framing")
    }
  }
  for wire in [b"1\r\na\r\n0\r\nContent-Length: 1\r\n\r\n", b"2\r\na", b"z\r\n"] {
    let reader = @io.MemoryReader(async fn(writer) { writer.write(wire) })
    defer reader.close()
    let input = HttpInput::{
      reader,
      buffer: b"",
      offset: 0,
      timeout: None,
      between_timeout: None,
    }
    try input.body(Chunked, fn(_) {  }) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed body")
    }
  }
}

///|
async test "HTTP framing accepts duplicate equal lengths and close-delimited responses" {
  let reader = @io.MemoryReader(async fn(writer) {
    writer.write(b"Content-Length: 3, 3\r\n\r\nabc")
  })
  defer reader.close()
  let input = HttpInput::{
    reader,
    buffer: b"",
    offset: 0,
    timeout: None,
    between_timeout: None,
  }
  let headers = input.fields()
  assert_true(message_framing(headers, false, false) is Length(3L))
  let data : Array[Byte] = []
  input.body(UntilClose, fn(bytes) { data.append(bytes.to_array()) }) |> ignore
  assert_eq(Bytes::from_array(data), b"abc")
}

///|
test "HTTP authority validation rejects invalid setters before network access" {
  for
    invalid in [
      "", "user@host", "host/path", "host:65536", "[bad]", "a:b:c", "host:bad", "host\r\nInjected: x",
    ] {
    assert_false(
      attribute_valid("authority", Variant(1, Some(String(invalid)))),
    )
  }
  for valid in ["localhost", "localhost:80", "127.0.0.1:0", "[::1]:443"] {
    assert_true(attribute_valid("authority", Variant(1, Some(String(valid)))))
  }
}

///|
async test "HTTP body read timeout wakes without readiness polling" {
  let reader = @io.MemoryReader(async fn(_) { @async.sleep(10000) })
  defer reader.close()
  let input = HttpInput::{
    reader,
    buffer: b"",
    offset: 0,
    timeout: Some(1),
    between_timeout: Some(1),
  }
  try input.read(1) catch {
    HttpTransportError(9, _) => ()
    error => fail("unexpected timeout error: \{error}")
  } noraise {
    _ => fail("missing read timeout")
  }
}
