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
