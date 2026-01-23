///|
/// Minimal helpers for recognizing WebAssembly Component Model binaries.
///
/// For the first incremental step, we only sniff the standard wasm magic plus
/// a known version number to distinguish core modules vs components.

///|
pub(all) enum BinaryKind {
  CoreModule
  Component
  UnknownPreamble(Int, Int)
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
  // Component Model splits the legacy 32-bit "version" field into:
  // - version: u16
  // - layer: u16 (0 = core module, 1 = component)
  let version = bytes[4].to_int() | (bytes[5].to_int() << 8)
  let layer = bytes[6].to_int() | (bytes[7].to_int() << 8)
  if layer == 0 && version == 0x01 {
    Some(CoreModule)
  } else if layer == 1 {
    Some(Component)
  } else {
    Some(UnknownPreamble(version, layer))
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
  layer : Int
  sections : Array[Section]
} derive(Show, Eq)

///|
pub suberror ComponentParseError {
  InvalidMagic
  UnexpectedEndOfInput
  Leb128TooLarge
  NotAComponent
  UnsupportedComponentPreamble(Int, Int)
  InvalidTypeSection
  InvalidInstanceSection
  InvalidAliasSection
  InvalidCanonSection
  InvalidStartSection
  UnsupportedCanonOpcode(Int)
  InvalidUtf8
  UnsupportedTypeOpcode(Int)
}

///|
fn ComponentParseError::to_string(self : ComponentParseError) -> String {
  match self {
    InvalidMagic => "invalid wasm magic"
    UnexpectedEndOfInput => "unexpected end of input"
    Leb128TooLarge => "leb128 value too large"
    NotAComponent => "input is not a component binary"
    UnsupportedComponentPreamble(version, layer) =>
      "unsupported component preamble: version=\{version} layer=\{layer}"
    InvalidTypeSection => "invalid type section"
    InvalidInstanceSection => "invalid instance section"
    InvalidAliasSection => "invalid alias section"
    InvalidCanonSection => "invalid canon section"
    InvalidStartSection => "invalid start section"
    UnsupportedCanonOpcode(op) => "unsupported canon opcode: \{op}"
    InvalidUtf8 => "invalid utf-8"
    UnsupportedTypeOpcode(op) => "unsupported component type opcode: \{op}"
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
fn decode_utf8_validated(bytes : Bytes) -> String raise ComponentParseError {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < bytes.length() {
    let b = bytes[i].to_int()
    if b < 0x80 {
      buf.write_char(b.unsafe_to_char())
      i = i + 1
    } else if b < 0xC0 {
      raise InvalidUtf8
    } else if b < 0xE0 {
      if i + 1 >= bytes.length() {
        raise InvalidUtf8
      }
      let b2 = bytes[i + 1].to_int()
      if (b2 & 0xC0) != 0x80 {
        raise InvalidUtf8
      }
      let cp = ((b & 0x1F) << 6) | (b2 & 0x3F)
      if cp < 0x80 {
        raise InvalidUtf8
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 2
    } else if b < 0xF0 {
      if i + 2 >= bytes.length() {
        raise InvalidUtf8
      }
      let b2 = bytes[i + 1].to_int()
      let b3 = bytes[i + 2].to_int()
      if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 {
        raise InvalidUtf8
      }
      let cp = ((b & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
      if cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF) {
        raise InvalidUtf8
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 3
    } else if b < 0xF8 {
      if i + 3 >= bytes.length() {
        raise InvalidUtf8
      }
      let b2 = bytes[i + 1].to_int()
      let b3 = bytes[i + 2].to_int()
      let b4 = bytes[i + 3].to_int()
      if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 || (b4 & 0xC0) != 0x80 {
        raise InvalidUtf8
      }
      let cp = ((b & 0x07) << 18) |
        ((b2 & 0x3F) << 12) |
        ((b3 & 0x3F) << 6) |
        (b4 & 0x3F)
      if cp < 0x10000 || cp > 0x10FFFF {
        raise InvalidUtf8
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 4
    } else {
      raise InvalidUtf8
    }
  }
  buf.to_string()
}

///|
fn Reader::read_name(self : Reader) -> String raise ComponentParseError {
  let len = self.read_leb_u32()
  let bytes = self.read_bytes(len)
  decode_utf8_validated(bytes)
}

///|
fn Reader::read_u16_le(self : Reader) -> Int raise ComponentParseError {
  let b0 = self.read_u8()
  let b1 = self.read_u8()
  b0 | (b1 << 8)
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
fn Reader::read_sleb_i32(self : Reader) -> Int raise ComponentParseError {
  loop (0, 0) {
    (result, shift) => {
      if shift >= 35 {
        raise Leb128TooLarge
      }
      let b = self.read_u8()
      let low = b & 0x7F
      let new_result = result | (low << shift)
      if (b & 0x80) == 0 {
        let value = if shift < 32 && (b & 0x40) != 0 {
          new_result | (-1 << (shift + 7))
        } else {
          new_result
        }
        value
      } else {
        continue (new_result, shift + 7)
      }
    }
  }
}

///|
fn Reader::read_typeidx(self : Reader) -> Int raise ComponentParseError {
  let idx = self.read_sleb_i32()
  if idx < 0 {
    raise InvalidTypeSection
  }
  idx
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
  let version = reader.read_u16_le()
  let layer = reader.read_u16_le()
  if layer != 1 {
    raise NotAComponent
  }
  // Pre-standard versions start at 0x0d and increment; the final standard
  // version is expected to be 0x01.
  if version != 0x01 && version < 0x0d {
    raise UnsupportedComponentPreamble(version, layer)
  }
  // Section framing: id (u8), size (leb u32), payload (bytes).
  let sections : Array[Section] = []
  while !reader.is_eof() {
    let id = reader.read_u8()
    let size = reader.read_leb_u32()
    let payload = reader.read_bytes(size)
    sections.push({ id, payload })
  }
  { version, layer, sections }
}
