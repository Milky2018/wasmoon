///|
/// Strip canonical transport provenance only at an embedding boundary.
fn ComponentValue::to_host_value(self : ComponentValue) -> ComponentValue {
  match self {
    EncodedString(text, _, _) => String(text)
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
) -> (Int, Int) raise ComponentRuntimeError {
  let (text, source, tagged_units) = match value {
    String(text) =>
      (text, StringEncoding::Utf8, encode_utf8_string(text).length())
    EncodedString(text, encoding, units) => (text, encoding, units)
    _ => raise HostCallError("expected string")
  }
  let source_latin1 = source == Latin1Utf16 && tagged_units >= 0
  let units = if source == Latin1Utf16 {
    tagged_units & 0x7fffffff
  } else {
    tagged_units
  }
  let (bytes, result_units, alignment) = encode_string_for_canon(
    text, destination,
  )
  fn resize(
    old_ptr : Int,
    old_size : Int,
    size : Int,
    alignment : Int,
  ) -> Int raise ComponentRuntimeError {
    if size < 0 {
      raise CanonCallError("string content out-of-bounds")
    }
    let args : Array[@types.Value] = if memory64 {
      [
        I64(old_ptr.to_int64()),
        I64(old_size.to_int64()),
        I64(alignment.to_int64()),
        I64(size.to_int64()),
      ]
    } else {
      [I32(old_ptr), I32(old_size), I32(alignment), I32(size)]
    }
    let ptr = match realloc.call(store, args) {
      [I32(ptr)] => ptr
      [I64(ptr)] => {
        if ptr < 0L || ptr > 2147483647L {
          raise CanonCallError("string content out-of-bounds")
        }
        ptr.to_int()
      }
      _ => raise CanonCallError("invalid realloc result")
    }
    if ptr % alignment != 0 {
      raise CanonCallError("unaligned pointer")
    }
    if ptr < 0 || ptr.to_int64() + size.to_int64() > memory.byte_len() {
      raise CanonCallError("string content out-of-bounds")
    }
    ptr
  }
  fn write(
    ptr : Int,
    bytes : Bytes,
    start : Int,
    end : Int,
  ) -> Unit raise ComponentRuntimeError {
    for i in start..<end {
      memory.store_byte(ptr + i, bytes[i]) catch {
        error => raise CanonCallError(error.to_string())
      }
    }
  }
  let mut initial_size = bytes.length()
  let mut grow_size = 0
  let mut prefix = 0
  if destination == Utf16 && source == Utf8 {
    initial_size = units * 2
  } else if destination == Utf8 && source != Utf8 {
    initial_size = units
    for c in text {
      if c.to_int() >= 128 {
        break
      }
      prefix += 1
    }
    if prefix != text.length() {
      grow_size = units * (if source_latin1 { 2 } else { 3 })
    }
  } else if destination == Latin1Utf16 && !source_latin1 {
    if source == Latin1Utf16 {
      initial_size = units * 2
    } else {
      initial_size = units
      for c in text {
        if c.to_int() >= 256 {
          break
        }
        prefix += 1
      }
      if result_units < 0 {
        grow_size = units * 2
      }
    }
  }
  let mut ptr = resize(0, 0, initial_size, alignment)
  let mut allocated = initial_size
  if grow_size != 0 {
    // realloc observes the prefix copied before the first non-fitting character.
    let mut i = 0
    for c in text {
      if i == prefix {
        break
      }
      memory.store_byte(ptr + i, c.to_int().to_byte()) catch {
        error => raise CanonCallError(error.to_string())
      }
      i += 1
    }
    ptr = resize(ptr, allocated, grow_size, alignment)
    allocated = grow_size
  }
  if grow_size != 0 && destination == Latin1Utf16 {
    for i = prefix - 1; i >= 0; i = i - 1 {
      let byte = memory.load_byte(ptr + i) catch {
        error => raise CanonCallError(error.to_string())
      }
      memory.store_byte(ptr + 2 * i, byte) catch {
        error => raise CanonCallError(error.to_string())
      }
      memory.store_byte(ptr + 2 * i + 1, 0) catch {
        error => raise CanonCallError(error.to_string())
      }
    }
    write(ptr, bytes, 2 * prefix, bytes.length())
  } else if grow_size != 0 {
    write(ptr, bytes, prefix, bytes.length())
  } else if destination == Latin1Utf16 &&
    source == Latin1Utf16 &&
    !source_latin1 {
    let (utf16_bytes, _, _) = encode_string_for_canon(text, Utf16)
    write(ptr, utf16_bytes, 0, utf16_bytes.length())
    if result_units >= 0 {
      for i in 0..<bytes.length() {
        let byte = memory.load_byte(ptr + 2 * i) catch {
          error => raise CanonCallError(error.to_string())
        }
        memory.store_byte(ptr + i, byte) catch {
          error => raise CanonCallError(error.to_string())
        }
      }
    }
  } else {
    write(ptr, bytes, 0, bytes.length())
  }
  if allocated != bytes.length() {
    ptr = resize(ptr, allocated, bytes.length(), alignment)
  }
  (ptr, result_units)
}
