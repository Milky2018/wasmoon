///|
/// Strip canonical transport provenance only at an embedding boundary.
fn ComponentValue::to_host_value(
  self : ComponentValue,
) -> ComponentValue raise ComponentRuntimeError {
  match self {
    EncodedString(text, _, _) => String(text)
    GuestString(view) =>
      String(
        read_string_from_memory_with_encoding(
          view.memory,
          view.ptr,
          view.len,
          view.encoding,
        ),
      )
    List(values) => List(values.map(ComponentValue::to_host_value))
    Tuple(values) => Tuple(values.map(ComponentValue::to_host_value))
    Variant(tag, value) =>
      Variant(tag, value.map(ComponentValue::to_host_value))
    _ => self
  }
}

///|
fn lower_canonical_string(
  value : ComponentValue,
  destination : StringEncoding,
  store : @runtime.Store,
  memory : @runtime.Memory,
  realloc : CanonicalRealloc,
  memory64 : Bool,
) -> (Int64, Int) raise ComponentRuntimeError {
  let source = CanonicalStringSource::from_value(value)
  let units = source.units.to_int64()
  let source_latin1 = source.encoding == Latin1Utf16 && !source.utf16
  let compact_utf16 = destination == Latin1Utf16 &&
    source.encoding == Latin1Utf16 &&
    source.utf16
  let alignment = if destination == Utf8 { 1 } else { 2 }
  fn resize(
    old_ptr : Int64,
    old_size : Int64,
    size : Int64,
  ) -> Int64 raise ComponentRuntimeError {
    // Canonical strings have a 2 GiB byte limit for either memory width.
    if size < 0L || size > 2147483647L {
      raise CanonCallError("string content out-of-bounds")
    }
    let args : Array[@types.Value] = if memory64 {
      [I64(old_ptr), I64(old_size), I64(alignment.to_int64()), I64(size)]
    } else {
      [
        I32(old_ptr.to_int()),
        I32(old_size.to_int()),
        I32(alignment),
        I32(size.to_int()),
      ]
    }
    let ptr = match realloc.call(store, args) {
      [I32(ptr)] => ptr.to_int64() & 0xffffffffL
      [I64(ptr)] => ptr
      _ => raise CanonCallError("invalid realloc result")
    }
    if ptr % alignment.to_int64() != 0L {
      raise CanonCallError("unaligned pointer")
    }
    if ptr < 0L || ptr > memory.byte_len() || size > memory.byte_len() - ptr {
      raise CanonCallError("string content out-of-bounds")
    }
    ptr
  }
  let mut allocated = if destination == Utf16 || compact_utf16 {
    units * 2L
  } else {
    units
  }
  let mut ptr = resize(0L, 0L, allocated)
  let mut wide = destination == Utf16 || compact_utf16
  let mut utf8_grown = false
  let mut all_latin1 = true
  let mut position = 0
  let mut written = 0L
  fn put(offset : Int64, byte : Int) -> Unit raise ComponentRuntimeError {
    memory.store_byte_at(ptr + offset, byte.to_byte()) catch {
      error => raise CanonCallError(error.to_string())
    }
  }
  fn put_utf16(offset : Int64, unit : Int) -> Unit raise ComponentRuntimeError {
    put(offset, unit & 0xff)
    put(offset + 1L, unit >> 8)
  }
  while position < source.byte_len {
    let compact_scalar = if destination == Latin1Utf16 && !wide {
      source.latin1_scalar(position)
    } else {
      None
    }
    if destination == Latin1Utf16 && !wide && compact_scalar is None {
      let capacity = units * 2L
      ptr = resize(ptr, allocated, capacity)
      allocated = capacity
      // realloc observes the compact prefix; inflate only after it returns.
      for i = written - 1L; i >= 0L; i = i - 1L {
        let byte = memory.load_byte_at(ptr + i) catch {
          error => raise CanonCallError(error.to_string())
        }
        put_utf16(i * 2L, byte.to_int())
      }
      written *= 2L
      wide = true
    }
    let (scalar, consumed) = match compact_scalar {
      Some(pair) => pair
      None => source.scalar(position)
    }
    if scalar >= 256 {
      all_latin1 = false
    }
    if destination == Utf8 &&
      source.encoding != Utf8 &&
      !utf8_grown &&
      scalar >= 128 {
      let capacity = units * (if source_latin1 { 2L } else { 3L })
      ptr = resize(ptr, allocated, capacity)
      allocated = capacity
      utf8_grown = true
    }
    if wide {
      if scalar < 0x10000 {
        put_utf16(written, scalar)
        written += 2L
      } else {
        let pair = scalar - 0x10000
        put_utf16(written, 0xd800 | (pair >> 10))
        put_utf16(written + 2L, 0xdc00 | (pair & 0x3ff))
        written += 4L
      }
    } else if destination == Latin1Utf16 || scalar < 0x80 {
      put(written, scalar)
      written += 1L
    } else if scalar < 0x800 {
      put(written, 0xc0 | (scalar >> 6))
      put(written + 1L, 0x80 | (scalar & 0x3f))
      written += 2L
    } else if scalar < 0x10000 {
      put(written, 0xe0 | (scalar >> 12))
      put(written + 1L, 0x80 | ((scalar >> 6) & 0x3f))
      put(written + 2L, 0x80 | (scalar & 0x3f))
      written += 3L
    } else {
      put(written, 0xf0 | (scalar >> 18))
      put(written + 1L, 0x80 | ((scalar >> 12) & 0x3f))
      put(written + 2L, 0x80 | ((scalar >> 6) & 0x3f))
      put(written + 3L, 0x80 | (scalar & 0x3f))
      written += 4L
    }
    position += consumed
  }
  if compact_utf16 && all_latin1 {
    for i = 0L; i < written / 2L; i = i + 1L {
      let byte = memory.load_byte_at(ptr + i * 2L) catch {
        error => raise CanonCallError(error.to_string())
      }
      put(i, byte.to_int())
    }
    written /= 2L
    wide = false
  }
  if allocated != written {
    ptr = resize(ptr, allocated, written)
  }
  let result_units = if wide {
    (written / 2L).to_int()
  } else {
    written.to_int()
  }
  (
    ptr,
    if destination == Latin1Utf16 && wide {
      result_units | 0x80000000
    } else {
      result_units
    },
  )
}
