///|
/// Minimal helpers for recognizing WebAssembly Component Model binaries.
///
/// For the first incremental step, we only sniff the standard wasm magic plus
/// a known version number to distinguish core modules vs components.

///|
#derive(Debug, Eq)
pub(all) enum BinaryKind {
  CoreModule
  Component
  UnknownPreamble(Int32, Int32)
}

///|
pub impl Show for BinaryKind with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

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
  } else if layer == 1 && version == 0x0D {
    Some(Component)
  } else {
    Some(UnknownPreamble(version, layer))
  }
}

///|
#derive(Debug, Eq)
pub struct Section {
  id : Int32
  payload : Bytes
}

///|
#derive(Debug, Eq)
pub struct ComponentBinary {
  version : Int32
  layer : Int32
  sections : Array[Section]
}

///|
pub suberror ComponentParseError {
  InvalidMagic
  UnexpectedEndOfInput
  Leb128TooLarge
  NotAComponent
  UnsupportedComponentPreamble(Int32, Int32)
  InvalidTypeSection
  InvalidInstanceSection
  InvalidAliasSection
  InvalidCanonSection
  InvalidStartSection
  UnsupportedCanonOpcode(Int32)
  InvalidUtf8
  UnsupportedTypeOpcode(Int32)
}

///|
pub fn ComponentParseError::to_string(self : ComponentParseError) -> String {
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
pub impl Show for ComponentParseError with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
priv struct Reader {
  data : Bytes
  mut pos : Int32
}

///|
fn Reader::Reader(data : Bytes) -> Reader {
  { data, pos: 0, }
}

///|
fn Reader::is_eof(self : Reader) -> Bool {
  self.pos >= self.data.length()
}

///|
fn Reader::read_u8(self : Reader) -> Int32 raise ComponentParseError {
  if self.pos >= self.data.length() {
    raise UnexpectedEndOfInput
  }
  let b = self.data[self.pos].to_int()
  self.pos += 1
  b
}

///|
fn Reader::read_view(
  self : Reader,
  n : Int32,
) -> BytesView raise ComponentParseError {
  let start = self.pos
  if n < 0 || n > self.data.length() - start {
    raise UnexpectedEndOfInput
  }
  self.pos += n
  self.data[start:self.pos]
}

///|
fn Reader::read_bytes(
  self : Reader,
  n : Int32,
) -> Bytes raise ComponentParseError {
  self.read_view(n).to_owned()
}

///|
fn Reader::read_blob(self : Reader) -> Bytes raise ComponentParseError {
  self.read_bytes(self.read_leb_u32())
}

///|
fn Reader::read_name(self : Reader) -> String raise ComponentParseError {
  let bytes = self.read_view(self.read_leb_u32())
  @utf8.decode(bytes, ignore_bom=false) catch {
    _ => raise InvalidUtf8
  }
}

///|
fn Reader::read_count(self : Reader) -> Int32 raise ComponentParseError {
  let count = self.read_leb_u32()
  if count < 0 {
    raise UnexpectedEndOfInput
  }
  count
}

///|
fn[A] Reader::read_vector(
  self : Reader,
  read_entry : (Reader) -> A raise ComponentParseError,
) -> Array[A] raise ComponentParseError {
  let count = self.read_count()
  let entries = []
  for _ in 0..<count {
    entries.push(read_entry(self))
  }
  entries
}

///|
fn[A] Reader::read_optional(
  self : Reader,
  read_entry : (Reader) -> A raise ComponentParseError,
) -> A? raise ComponentParseError {
  match self.read_u8() {
    0 => None
    1 => Some(read_entry(self))
    _ => raise InvalidTypeSection
  }
}

///|
fn[A] parse_vector_section(
  payload : Bytes,
  read_entry : (Reader) -> A raise ComponentParseError,
  invalid : ComponentParseError,
) -> Array[A] raise ComponentParseError {
  let reader = Reader(payload)
  let entries = reader.read_vector(read_entry)
  if !reader.is_eof() {
    raise invalid
  }
  entries
}

///|
fn Reader::read_u16_le(self : Reader) -> Int32 raise ComponentParseError {
  let b0 = self.read_u8()
  let b1 = self.read_u8()
  b0 | (b1 << 8)
}

///|
fn Reader::read_leb_u32(self : Reader) -> Int32 raise ComponentParseError {
  @binary.read_u32(self, Reader::read_u8, () => Leb128TooLarge)
}

///|
fn Reader::read_s33(self : Reader) -> Int64 raise ComponentParseError {
  @binary.read_s33(self, Reader::read_u8, () => Leb128TooLarge)
}

///|
fn Reader::read_typeidx(self : Reader) -> Int32 raise ComponentParseError {
  self.read_leb_u32()
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
  let reader = Reader::Reader(bytes)
  // Skip magic.
  reader.pos = 4
  let version = reader.read_u16_le()
  let layer = reader.read_u16_le()
  if layer != 1 {
    raise NotAComponent
  }
  if version != 0x0D {
    raise UnsupportedComponentPreamble(version, layer)
  }
  // Section framing: id (u8), size (leb u32), payload (bytes).
  let sections : Array[Section] = []
  while !reader.is_eof() {
    let id = reader.read_u8()
    let size = reader.read_leb_u32()
    let payload = reader.read_bytes(size)
    sections.push({ id, payload, })
  }
  { version, layer, sections, }
}
