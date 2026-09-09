///|
/// A synchronous adapter borrows the span only until its destination arguments
/// have been lowered. Async payload loading never constructs this value.
struct CanonicalGuestString {
  memory : @runtime.Memory
  ptr : Int64
  len : Int64
  encoding : StringEncoding
} derive(Debug)

///|
pub extend CanonicalGuestString with @debug.Debug::{to_repr}

///|
/// Transport views compare by location; embedding boundaries materialize text.
impl Eq for CanonicalGuestString with fn equal(a, b) {
  a.memory.desc_ptr() == b.memory.desc_ptr() &&
  a.ptr == b.ptr &&
  a.len == b.len &&
  a.encoding == b.encoding
}

///|
priv enum CanonicalStringBytes {
  Owned(Bytes)
  Guest(@runtime.Memory, Int64)
}

///|
priv struct CanonicalStringSource {
  bytes : CanonicalStringBytes
  encoding : StringEncoding
  units : Int
  byte_len : Int
  utf16 : Bool
}

///|
fn CanonicalStringSource::from_value(
  value : ComponentValue,
) -> CanonicalStringSource raise ComponentRuntimeError {
  match value {
    GuestString(view) => {
      let (units, utf16, byte_len) = check_canonical_string_span(
        view.memory,
        view.ptr,
        view.len,
        view.encoding,
      )
      {
        bytes: Guest(view.memory, view.ptr),
        encoding: view.encoding,
        units,
        byte_len,
        utf16,
      }
    }
    String(text) => {
      let bytes = encode_utf8_string(text)
      {
        bytes: Owned(bytes),
        encoding: Utf8,
        units: bytes.length(),
        byte_len: bytes.length(),
        utf16: false,
      }
    }
    EncodedString(text, encoding, tagged_units) => {
      let utf16 = encoding == Utf16 ||
        (encoding == Latin1Utf16 && tagged_units < 0)
      let units = if encoding == Latin1Utf16 {
        tagged_units & 0x7fffffff
      } else {
        tagged_units
      }
      let (bytes, _, _) = encode_string_for_canon(
        text,
        if utf16 {
          Utf16
        } else {
          encoding
        },
      )
      { bytes: Owned(bytes), encoding, units, byte_len: bytes.length(), utf16, }
    }
    _ => raise HostCallError("expected string")
  }
}

///|
fn CanonicalStringSource::byte(
  self : CanonicalStringSource,
  index : Int,
) -> Int raise ComponentRuntimeError {
  match self.bytes {
    Owned(bytes) => bytes[index].to_int()
    Guest(memory, ptr) => {
      let byte = memory.load_byte_at(ptr + index.to_int64()) catch {
        error => raise CanonCallError(error.to_string())
      }
      byte.to_int()
    }
  }
}

///|
/// Decode one scalar without reading or allocating the remainder of the string.
fn CanonicalStringSource::scalar(
  self : CanonicalStringSource,
  position : Int,
) -> (Int, Int) raise ComponentRuntimeError {
  let first = self.byte(position)
  if self.utf16 {
    let unit = first | (self.byte(position + 1) << 8)
    if unit >= 0xd800 && unit <= 0xdbff && position + 3 < self.byte_len {
      let second = self.byte(position + 2) | (self.byte(position + 3) << 8)
      if second >= 0xdc00 && second <= 0xdfff {
        return (0x10000 + ((unit - 0xd800) << 10) + second - 0xdc00, 4)
      }
    }
    if unit >= 0xd800 && unit <= 0xdfff {
      raise CanonCallError("invalid utf16 encoding")
    }
    return (unit, 2)
  }
  if self.encoding == Latin1Utf16 || first < 0x80 {
    return (first, 1)
  }
  let (count, mask, minimum) = if first >= 0xc0 && first < 0xe0 {
    (2, 0x1f, 0x80)
  } else if first >= 0xe0 && first < 0xf0 {
    (3, 0x0f, 0x800)
  } else if first >= 0xf0 && first < 0xf8 {
    (4, 0x07, 0x10000)
  } else {
    raise CanonCallError("invalid utf8 encoding")
  }
  if count > self.byte_len - position {
    raise CanonCallError("invalid utf8 encoding")
  }
  let mut scalar = first & mask
  for i in 1..<count {
    let byte = self.byte(position + i)
    if (byte & 0xc0) != 0x80 {
      raise CanonCallError("invalid utf8 encoding")
    }
    scalar = (scalar << 6) | (byte & 0x3f)
  }
  if scalar < minimum ||
    scalar > 0x10ffff ||
    (scalar >= 0xd800 && scalar <= 0xdfff) {
    raise CanonCallError("invalid utf8 encoding")
  }
  (scalar, count)
}

///|
/// The optimistic compact pass stops before decoding a non-Latin1 scalar.
/// In particular, malformed input is diagnosed only after the UTF-16 growth.
fn CanonicalStringSource::latin1_scalar(
  self : CanonicalStringSource,
  position : Int,
) -> (Int, Int)? raise ComponentRuntimeError {
  let first = self.byte(position)
  if self.utf16 {
    if self.byte(position + 1) == 0 {
      Some((first, 2))
    } else {
      None
    }
  } else if self.encoding == Latin1Utf16 || first < 0x80 {
    Some((first, 1))
  } else if (first == 0xc2 || first == 0xc3) && self.byte_len - position >= 2 {
    let second = self.byte(position + 1)
    if (second & 0xc0) == 0x80 {
      Some((((first & 3) << 6) | (second & 0x3f), 2))
    } else {
      None
    }
  } else {
    None
  }
}
