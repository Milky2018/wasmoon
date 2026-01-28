///|
fn read_string_from_memory_with_encoding(
  mem : @runtime.Memory,
  ptr : Int,
  len : Int,
  encoding : StringEncoding,
) -> String raise ComponentRuntimeError {
  if ptr < 0 || len < 0 {
    raise CanonCallError(
      "string content out-of-bounds (string pointer/length out of bounds of memory)",
    )
  }
  // Pointer alignment requirements:
  // - utf16 and latin1+utf16 require 2-byte alignment.
  match encoding {
    Utf16 | Latin1Utf16 =>
      if (ptr.reinterpret_as_uint() & 1U) != 0U {
        raise CanonCallError("unaligned pointer")
      }
    Utf8 => ()
  }
  let mem_len = mem.byte_len()
  let mut byte_len = len
  let mut latin1 = false
  if encoding == StringEncoding::Utf16 {
    byte_len = len * 2
  } else if encoding == StringEncoding::Latin1Utf16 {
    // In the canonical ABI, latin1+utf16 uses the high bit of the length to
    // indicate latin1 vs utf16.
    let ulen = len.reinterpret_as_uint()
    if (ulen & 0x8000_0000U) != 0U {
      latin1 = true
      byte_len = (ulen & 0x7FFF_FFFFU).reinterpret_as_int()
    } else {
      byte_len = len * 2
    }
  }
  if ptr.to_int64() + byte_len.to_int64() > mem_len {
    raise CanonCallError(
      "string content out-of-bounds (string pointer/length out of bounds of memory)",
    )
  }
  if encoding == StringEncoding::Utf8 || latin1 {
    let bytes : Array[Byte] = []
    for i in 0..<byte_len {
      let b = mem.load_byte(ptr + i) catch {
        e => raise CanonCallError(e.to_string())
      }
      bytes.push(b)
    }
    if latin1 {
      // Latin1 is a byte-for-codepoint mapping.
      let buf = StringBuilder::new()
      for b in bytes {
        buf.write_char(b.to_int().unsafe_to_char())
      }
      buf.to_string()
    } else {
      decode_utf8_runtime(Bytes::from_array(bytes))
    }
  } else {
    // UTF-16LE decode.
    let buf = StringBuilder::new()
    let mut i = 0
    while i < byte_len {
      let b0 = mem.load_byte(ptr + i) catch {
        e => raise CanonCallError(e.to_string())
      }
      let b1 = mem.load_byte(ptr + i + 1) catch {
        e => raise CanonCallError(e.to_string())
      }
      let cu = b0.to_int() | (b1.to_int() << 8)
      // Surrogates: minimal handling sufficient for current tests.
      if cu >= 0xD800 && cu <= 0xDBFF && i + 3 < byte_len {
        let b2 = mem.load_byte(ptr + i + 2) catch {
          e => raise CanonCallError(e.to_string())
        }
        let b3 = mem.load_byte(ptr + i + 3) catch {
          e => raise CanonCallError(e.to_string())
        }
        let cu2 = b2.to_int() | (b3.to_int() << 8)
        if cu2 >= 0xDC00 && cu2 <= 0xDFFF {
          let high = cu - 0xD800
          let low = cu2 - 0xDC00
          let cp = 0x10000 + ((high << 10) | low)
          buf.write_char(cp.unsafe_to_char())
          i = i + 4
          continue
        }
      }
      buf.write_char(cu.unsafe_to_char())
      i = i + 2
    }
    buf.to_string()
  }
}

///|
fn write_bytes_to_memory_with_align(
  store : @runtime.Store,
  mem : @runtime.Memory,
  realloc : CoreFuncRef,
  mem_is_64 : Bool,
  bytes : Bytes,
  align : Int,
) -> Int raise ComponentRuntimeError {
  let len = bytes.length()
  let args : Array[@types.Value] = if mem_is_64 {
    [
      @types.Value::I64(0L),
      @types.Value::I64(0L),
      @types.Value::I64(align.to_int64()),
      @types.Value::I64(len.to_int64()),
    ]
  } else {
    [
      @types.Value::I32(0),
      @types.Value::I32(0),
      @types.Value::I32(align),
      @types.Value::I32(len),
    ]
  }
  let results = call_core_func(store, realloc, args)
  let ptr = match results {
    [@types.Value::I32(n)] => n
    [@types.Value::I64(n)] => n.to_int()
    _ => raise CanonCallError("invalid realloc result")
  }
  // Even for zero-sized allocations we must validate the returned pointer.
  let mem_len = mem.byte_len().to_int()
  if ptr < 0 || ptr > mem_len || ptr + len > mem_len {
    raise CanonCallError("realloc return: beyond end of memory")
  }
  for i in 0..<bytes.length() {
    mem.store_byte(ptr + i, bytes[i]) catch {
      e => raise CanonCallError(e.to_string())
    }
  }
  ptr
}

///|
fn align_to(n : Int, align : Int) -> Int {
  if align <= 1 {
    return n
  }
  let rem = n % align
  if rem == 0 {
    n
  } else {
    n + (align - rem)
  }
}

///|
fn core_valtype_align(vt : @types.ValueType) -> Int {
  match vt {
    @types.ValueType::I32 | @types.ValueType::F32 => 4
    @types.ValueType::I64 | @types.ValueType::F64 => 8
    _ => 4
  }
}

///|
fn core_valtype_size(vt : @types.ValueType) -> Int {
  match vt {
    @types.ValueType::I32 | @types.ValueType::F32 => 4
    @types.ValueType::I64 | @types.ValueType::F64 => 8
    _ => 4
  }
}

///|
fn layout_of_flat_types(
  tys : Array[@types.ValueType],
) -> (Array[Int], Int, Int) {
  let offsets : Array[Int] = []
  let mut off = 0
  let mut struct_align = 1
  for t in tys {
    let a = core_valtype_align(t)
    if a > struct_align {
      struct_align = a
    }
    off = align_to(off, a)
    offsets.push(off)
    off += core_valtype_size(t)
  }
  (offsets, off, struct_align)
}

///|
fn alloc_realloc_area(
  store : @runtime.Store,
  mem : @runtime.Memory,
  realloc : CoreFuncRef,
  mem_is_64 : Bool,
  size : Int,
  align : Int,
) -> Int raise ComponentRuntimeError {
  let args : Array[@types.Value] = if mem_is_64 {
    [
      @types.Value::I64(0L),
      @types.Value::I64(0L),
      @types.Value::I64(align.to_int64()),
      @types.Value::I64(size.to_int64()),
    ]
  } else {
    [
      @types.Value::I32(0),
      @types.Value::I32(0),
      @types.Value::I32(align),
      @types.Value::I32(size),
    ]
  }
  let results = call_core_func(store, realloc, args)
  let ptr = match results {
    [@types.Value::I32(n)] => n
    [@types.Value::I64(n)] => n.to_int()
    _ => raise CanonCallError("invalid realloc result")
  }
  let mem_len = mem.byte_len().to_int()
  if ptr < 0 || ptr > mem_len || ptr + size > mem_len {
    raise CanonCallError("realloc return: beyond end of memory")
  }
  ptr
}

///|
fn load_flat_value(
  mem : @runtime.Memory,
  addr : Int,
  vt : @types.ValueType,
) -> @types.Value raise ComponentRuntimeError {
  match vt {
    @types.ValueType::I32 =>
      @types.Value::I32(
        mem.load_i32(addr) catch {
          e => raise CanonCallError(e.to_string())
        },
      )
    @types.ValueType::I64 =>
      @types.Value::I64(
        mem.load_i64(addr) catch {
          e => raise CanonCallError(e.to_string())
        },
      )
    @types.ValueType::F32 =>
      @types.Value::F32(
        mem.load_f32(addr) catch {
          e => raise CanonCallError(e.to_string())
        },
      )
    @types.ValueType::F64 =>
      @types.Value::F64(
        mem.load_f64(addr) catch {
          e => raise CanonCallError(e.to_string())
        },
      )
    _ =>
      @types.Value::I32(
        mem.load_i32(addr) catch {
          e => raise CanonCallError(e.to_string())
        },
      )
  }
}

///|
fn store_flat_value(
  mem : @runtime.Memory,
  addr : Int,
  val : @types.Value,
) -> Unit raise ComponentRuntimeError {
  match val {
    @types.Value::I32(n) =>
      mem.store_i32(addr, n) catch {
        e => raise CanonCallError(e.to_string())
      }
    @types.Value::I64(n) =>
      mem.store_i64(addr, n) catch {
        e => raise CanonCallError(e.to_string())
      }
    @types.Value::F32(f) =>
      mem.store_f32(addr, f) catch {
        e => raise CanonCallError(e.to_string())
      }
    @types.Value::F64(f) =>
      mem.store_f64(addr, f) catch {
        e => raise CanonCallError(e.to_string())
      }
    _ =>
      mem.store_i32(addr, 0) catch {
        e => raise CanonCallError(e.to_string())
      }
  }
}

///|
fn require_memory(
  resources : CanonResources,
  store : @runtime.Store,
) -> @runtime.Memory raise ComponentRuntimeError {
  match resources.mem_addr {
    Some(addr) =>
      store.get_mem(addr) catch {
        e => raise CanonCallError(e.to_string())
      }
    None => raise MissingCanonMemory
  }
}

///|
fn trunc_u8(n : Int) -> Int {
  (n.reinterpret_as_uint() & 0xFFU).reinterpret_as_int()
}

///|
fn trunc_s8(n : Int) -> Int {
  let masked = n.reinterpret_as_uint() & 0xFFU
  if masked >= 0x80U {
    masked.reinterpret_as_int() - 0x100
  } else {
    masked.reinterpret_as_int()
  }
}

///|
fn trunc_u16(n : Int) -> Int {
  (n.reinterpret_as_uint() & 0xFFFFU).reinterpret_as_int()
}

///|
fn trunc_s16(n : Int) -> Int {
  let masked = n.reinterpret_as_uint() & 0xFFFFU
  if masked >= 0x8000U {
    masked.reinterpret_as_int() - 0x10000
  } else {
    masked.reinterpret_as_int()
  }
}

///|
fn trunc_u32(n : Int) -> Int {
  n.reinterpret_as_uint().reinterpret_as_int()
}

///|
fn char_from_canon_i32(n : Int) -> Char raise ComponentRuntimeError {
  // Component model `char` values are Unicode scalar values.
  if n < 0 || n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF) {
    raise CanonCallError("invalid `char` bit pattern")
  }
  n.unsafe_to_char()
}

///|
fn zero_flat_value(vt : @types.ValueType) -> @types.Value {
  match vt {
    @types.ValueType::I32 => @types.Value::I32(0)
    @types.ValueType::I64 => @types.Value::I64(0L)
    @types.ValueType::F32 => @types.Value::F32(0.0)
    @types.ValueType::F64 => @types.Value::F64(0.0)
    _ => @types.Value::I32(0)
  }
}

///|
fn coerce_flat_value(
  v : @types.Value,
  from_vt : @types.ValueType,
  to_vt : @types.ValueType,
) -> @types.Value raise ComponentRuntimeError {
  if from_vt == to_vt {
    return v
  }
  match (from_vt, to_vt, v) {
    (@types.ValueType::F32, @types.ValueType::I32, @types.Value::F32(f)) =>
      @types.Value::I32(f.reinterpret_as_int())
    (@types.ValueType::I32, @types.ValueType::F32, @types.Value::I32(n)) =>
      @types.Value::F32(Float::reinterpret_from_int(n))
    (@types.ValueType::F64, @types.ValueType::I64, @types.Value::F64(f)) =>
      @types.Value::I64(f.reinterpret_as_int64())
    (@types.ValueType::I64, @types.ValueType::F64, @types.Value::I64(n)) =>
      @types.Value::F64(n.reinterpret_as_double())
    (@types.ValueType::I32, @types.ValueType::I64, @types.Value::I32(n)) => {
      let bits = n.reinterpret_as_uint().to_uint64().reinterpret_as_int64()
      @types.Value::I64(bits)
    }
    (@types.ValueType::I64, @types.ValueType::I32, @types.Value::I64(n)) =>
      @types.Value::I32(
        (n.reinterpret_as_uint64() & 0xFFFF_FFFFUL)
        .to_uint()
        .reinterpret_as_int(),
      )
    (@types.ValueType::I64, @types.ValueType::F32, @types.Value::I64(n)) => {
      let bits = (n.reinterpret_as_uint64() & 0xFFFF_FFFFUL)
        .to_uint()
        .reinterpret_as_int()
      @types.Value::F32(Float::reinterpret_from_int(bits))
    }
    (@types.ValueType::F32, @types.ValueType::I64, @types.Value::F32(f)) => {
      let bits = f
        .reinterpret_as_int()
        .reinterpret_as_uint()
        .to_uint64()
        .reinterpret_as_int64()
      @types.Value::I64(bits)
    }
    _ => raise HostCallError("type mismatch")
  }
}

///|
