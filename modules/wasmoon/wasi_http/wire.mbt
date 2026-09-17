///|
priv suberror HttpTransportError {
  HttpTransportError(Int, String)
} derive(Debug)

///|
priv struct HttpInput {
  reader : &@io.Reader
  mut buffer : Bytes
  mut offset : Int
  mut timeout : Int?
  between_timeout : Int?
}

///|
async fn HttpInput::read(self : HttpInput, maximum : Int) -> Bytes? {
  if self.offset == self.buffer.length() {
    let result = match self.timeout {
      Some(millis) =>
        @async.with_timeout(
          millis,
          async fn() { self.reader.read_some(max_len=65536) },
          error=HttpTransportError(9, "HTTP read timeout"),
        )
      None => self.reader.read_some(max_len=65536)
    }
    self.timeout = self.between_timeout
    guard result is Some(bytes) else { return None }
    self.buffer = bytes
    self.offset = 0
  }
  let count = Int::min(maximum, self.buffer.length() - self.offset)
  let bytes = self.buffer[self.offset:self.offset + count].to_owned()
  self.offset += count
  Some(bytes)
}

///|
async fn HttpInput::line(self : HttpInput) -> Bytes {
  let bytes : Array[Byte] = []
  while true {
    guard self.read(1) is Some(byte) else {
      raise HttpTransportError(25, "unexpected end of HTTP message")
    }
    if byte[0] == 10 {
      if bytes.last() != Some(b'\r') {
        raise HttpTransportError(35, "HTTP requires CRLF")
      }
      bytes.pop() |> ignore
      return Bytes::from_array(bytes)
    }
    bytes.push(byte[0])
    if bytes.length() > 65536 {
      raise HttpTransportError(26, "HTTP line limit exceeded")
    }
  }
  abort("unreachable")
}

///|
fn ascii_text(bytes : Bytes) -> String raise {
  for byte in bytes {
    if byte >= 128 {
      raise HttpTransportError(35, "non-ASCII HTTP syntax")
    }
  }
  @utf8.decode(bytes)
}

///|
async fn HttpInput::fields(self : HttpInput) -> HttpFields {
  let entries : Array[(String, Bytes)] = []
  let mut total = 0
  while true {
    let line = self.line()
    if line.is_empty() {
      return { entries, immutable: true, }
    }
    total += line.length() + 2
    if total > 65536 || entries.length() >= 1024 {
      raise HttpTransportError(26, "HTTP field section limit exceeded")
    }
    let mut colon = -1
    for i in 0..<line.length() {
      if line[i] == 58 {
        colon = i
        break
      }
    }
    if colon <= 0 {
      raise HttpTransportError(35, "invalid HTTP field")
    }
    let name = ascii_text(line[:colon].to_owned())
    if !field_token(name) {
      raise HttpTransportError(35, "invalid HTTP field name")
    }
    let mut start = colon + 1
    let mut end = line.length()
    while start < end && (line[start] == 32 || line[start] == 9) {
      start += 1
    }
    while end > start && (line[end - 1] == 32 || line[end - 1] == 9) {
      end -= 1
    }
    let value = line[start:end].to_owned()
    if !field_valid(value) {
      raise HttpTransportError(35, "invalid HTTP field value")
    }
    entries.push((name, value))
  }
  abort("unreachable")
}

///|
priv enum HttpFraming {
  Length(Int64)
  Chunked
  UntilClose
}

///|
fn decimal_length(text : String) -> Int64 raise {
  if text.is_empty() {
    raise HttpTransportError(35, "empty content length")
  }
  let mut result = 0L
  for char in text {
    if !(char is ('0'..='9')) {
      raise HttpTransportError(35, "invalid content length")
    }
    let digit = (char.to_int() - 48).to_int64()
    if result > (0x7fffffffffffffffL - digit) / 10L {
      raise HttpTransportError(35, "content length overflow")
    }
    result = result * 10L + digit
  }
  result
}

///|
fn message_framing(
  fields : HttpFields,
  response : Bool,
  no_body : Bool,
) -> HttpFraming raise {
  if no_body {
    return Length(0L)
  }
  let encodings = fields.get("transfer-encoding")
  let lengths = fields.get("content-length")
  if !encodings.is_empty() {
    if !lengths.is_empty() ||
      encodings.length() != 1 ||
      ascii_text(encodings[0]).to_lower() != "chunked" {
      raise HttpTransportError(35, "ambiguous or unsupported HTTP framing")
    }
    return Chunked
  }
  let mut length : Int64? = None
  for value in lengths {
    for part in ascii_text(value).split(",") {
      let current = decimal_length(part.trim().to_owned())
      if length is Some(previous) && previous != current {
        raise HttpTransportError(35, "conflicting content lengths")
      }
      length = Some(current)
    }
  }
  match length {
    Some(value) => Length(value)
    None => if response { UntilClose } else { Length(0L) }
  }
}

///|
fn chunk_length(line : Bytes) -> Int64 raise {
  let mut index = 0
  let mut length = 0L
  while index < line.length() {
    let digit = match line[index] {
      b'0'..=b'9' => line[index].to_int() - 48
      b'a'..=b'f' => line[index].to_int() - 87
      b'A'..=b'F' => line[index].to_int() - 55
      _ => break
    }
    if length > (0x7fffffffffffffffL - digit.to_int64()) / 16L {
      raise HttpTransportError(35, "chunk size overflow")
    }
    length = length * 16L + digit.to_int64()
    index += 1
  }
  if index == 0 {
    raise HttpTransportError(35, "invalid chunk size")
  }
  while index < line.length() {
    while index < line.length() && (line[index] == 32 || line[index] == 9) {
      index += 1
    }
    if index >= line.length() || line[index] != 59 {
      raise HttpTransportError(35, "invalid chunk extension")
    }
    index += 1
    while index < line.length() && (line[index] == 32 || line[index] == 9) {
      index += 1
    }
    let start = index
    while index < line.length() && chunk_token_byte(line[index]) {
      index += 1
    }
    if index == start {
      raise HttpTransportError(35, "missing chunk extension name")
    }
    let after_name = index
    while index < line.length() && (line[index] == 32 || line[index] == 9) {
      index += 1
    }
    if index >= line.length() || line[index] != 61 {
      // Whitespace belongs to the next extension's leading BWS.
      index = after_name
      continue
    }
    index += 1
    while index < line.length() && (line[index] == 32 || line[index] == 9) {
      index += 1
    }
    if index < line.length() && line[index] == 34 {
      index += 1
      while index < line.length() && line[index] != 34 {
        if line[index] == 92 {
          index += 1
          if index >= line.length() {
            raise HttpTransportError(35, "truncated quoted extension")
          }
        }
        if (line[index] < 32 && line[index] != 9) || line[index] == 127 {
          raise HttpTransportError(35, "invalid quoted extension")
        }
        index += 1
      }
      if index >= line.length() {
        raise HttpTransportError(35, "unterminated quoted extension")
      }
      index += 1
    } else {
      let start = index
      while index < line.length() && chunk_token_byte(line[index]) {
        index += 1
      }
      if index == start {
        raise HttpTransportError(35, "missing chunk extension value")
      }
    }
  }
  length
}

///|
fn chunk_token_byte(byte : Byte) -> Bool {
  byte
  is (b'a'..=b'z'
  | b'A'..=b'Z'
  | b'0'..=b'9'
  | b'!'
  | b'#'
  | b'$'
  | b'%'
  | b'&'
  | b'\''
  | b'*'
  | b'+'
  | b'-'
  | b'.'
  | b'^'
  | b'_'
  | b'`'
  | b'|'
  | b'~')
}

///|
async fn HttpInput::body(
  self : HttpInput,
  framing : HttpFraming,
  consume : async (Bytes) -> Unit,
) -> HttpFields {
  let mut remaining = match framing {
    Length(n) => n
    _ => 0L
  }
  while true {
    if framing is Chunked && remaining == 0L {
      remaining = chunk_length(self.line())
      if remaining == 0L {
        let trailers = self.fields()
        for entry in trailers.entries {
          if field_forbidden(entry.0) ||
            ["content-length", "host", "trailer"].contains(entry.0.to_lower()) {
            raise HttpTransportError(35, "forbidden trailer")
          }
        }
        return trailers
      }
    }
    if framing is Length(_) && remaining == 0L {
      return HttpFields::from_list().unwrap()
    }
    let count = if framing is UntilClose {
      65536
    } else {
      Int64::min(remaining, 65536L).to_int()
    }
    guard self.read(count) is Some(bytes) else {
      if framing is UntilClose {
        return HttpFields::from_list().unwrap()
      }
      raise HttpTransportError(25, "truncated HTTP body")
    }
    consume(bytes)
    if !(framing is UntilClose) {
      remaining -= bytes.length().to_int64()
    }
    if framing is Chunked && remaining == 0L {
      if !self.line().is_empty() {
        raise HttpTransportError(35, "invalid chunk terminator")
      }
    }
  }
  abort("unreachable")
}

///|
async fn write_fields(writer : &@io.Writer, fields : HttpFields) -> Unit {
  for entry in fields.entries {
    if !field_token(entry.0) || !field_valid(entry.1) {
      raise HttpTransportError(35, "invalid outgoing HTTP field")
    }
    writer.write(entry.0)
    writer.write(": ")
    writer.write(entry.1)
    writer.write("\r\n")
  }
}
