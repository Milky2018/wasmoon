///|
/// Minimal helpers for recognizing WebAssembly Component Model binaries.
///
/// For the first incremental step, we only sniff the standard wasm magic plus
/// a known version number to distinguish core modules vs components.

///|
pub(all) enum BinaryKind {
  CoreModule
  Component
  UnknownVersion(Int)
} derive(Show, Eq)

///|
pub fn sniff_binary_kind(bytes : Bytes) -> BinaryKind? {
  if bytes.length() < 8 {
    return None
  }
  if bytes[0].to_int() != 0x00 ||
    bytes[1].to_int() != 0x61 ||
    bytes[2].to_int() != 0x73 ||
    bytes[3].to_int() != 0x6d {
    return None
  }
  let version = bytes[4].to_int() |
    (bytes[5].to_int() << 8) |
    (bytes[6].to_int() << 16) |
    (bytes[7].to_int() << 24)
  if version == 0x01 {
    Some(CoreModule)
  } else if version == 0x0a {
    // Component Model (current toolchains generally emit version 0x0a).
    Some(Component)
  } else {
    Some(UnknownVersion(version))
  }
}

///|
pub struct Section {
  id : Int
  payload : Bytes
} derive(Show, Eq)

///|
pub struct ComponentBinary {
  version : Int
  sections : Array[Section]
} derive(Show, Eq)

///|
pub suberror ComponentParseError {
  InvalidMagic
  UnexpectedEndOfInput
  Leb128TooLarge
  NotAComponent
}

///|
fn ComponentParseError::to_string(self : ComponentParseError) -> String {
  match self {
    InvalidMagic => "invalid wasm magic"
    UnexpectedEndOfInput => "unexpected end of input"
    Leb128TooLarge => "leb128 value too large"
    NotAComponent => "input is not a component binary"
  }
}

///|
pub impl Show for ComponentParseError with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
priv struct Reader {
  data : Bytes
  mut pos : Int
}

///|
fn Reader::new(data : Bytes) -> Reader {
  { data, pos: 0 }
}

///|
fn Reader::is_eof(self : Reader) -> Bool {
  self.pos >= self.data.length()
}

///|
fn Reader::read_u8(self : Reader) -> Int raise ComponentParseError {
  if self.pos >= self.data.length() {
    raise UnexpectedEndOfInput
  }
  let b = self.data[self.pos].to_int()
  self.pos += 1
  b
}

///|
fn Reader::read_bytes(
  self : Reader,
  n : Int,
) -> Bytes raise ComponentParseError {
  if self.pos + n > self.data.length() {
    raise UnexpectedEndOfInput
  }
  let bytes = loop ([], 0) {
    (acc, i) =>
      if i >= n {
        acc
      } else {
        acc.push(self.data[self.pos + i])
        continue (acc, i + 1)
      }
  }
  self.pos += n
  Bytes::from_array(bytes)
}

///|
fn Reader::read_u32_le(self : Reader) -> Int raise ComponentParseError {
  let b0 = self.read_u8()
  let b1 = self.read_u8()
  let b2 = self.read_u8()
  let b3 = self.read_u8()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
fn Reader::read_leb_u32(self : Reader) -> Int raise ComponentParseError {
  loop (0, 0) {
    (result, shift) => {
      if shift > 28 {
        raise Leb128TooLarge
      }
      let byte = self.read_u8()
      if shift == 28 && (byte & 0x7F) > 0x0F {
        raise Leb128TooLarge
      }
      let new_result = result | ((byte & 0x7F) << shift)
      if (byte & 0x80) == 0 {
        new_result
      } else {
        continue (new_result, shift + 7)
      }
    }
  }
}

///|
pub fn parse_component_binary(
  bytes : Bytes,
) -> ComponentBinary raise ComponentParseError {
  if bytes.length() < 8 {
    raise UnexpectedEndOfInput
  }
  if bytes[0].to_int() != 0x00 ||
    bytes[1].to_int() != 0x61 ||
    bytes[2].to_int() != 0x73 ||
    bytes[3].to_int() != 0x6d {
    raise InvalidMagic
  }
  let reader = Reader::new(bytes)
  // Skip magic.
  reader.read_bytes(4) |> ignore
  let version = reader.read_u32_le()
  if version != 0x0a {
    raise NotAComponent
  }
  // Section framing: id (u8), size (leb u32), payload (bytes).
  let sections : Array[Section] = []
  while !reader.is_eof() {
    let id = reader.read_u8()
    let size = reader.read_leb_u32()
    let payload = reader.read_bytes(size)
    sections.push({ id, payload })
  }
  { version, sections }
}
