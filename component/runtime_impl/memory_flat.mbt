///|
fn read_string_from_memory_with_encoding(
  mem : @runtime.Memory,
  ptr : Int,
  len : Int,
  encoding : StringEncoding,
) -> String raise ComponentRuntimeError {
  if ptr < 0 {
    raise CanonCallError(
      "string content out-of-bounds (string pointer/length out of bounds of memory)",
    )
  }
  // latin1+utf16 uses the top bit of `len` as an encoding discriminator, so a
  // valid encoded length may appear negative when represented as signed i32.
  if encoding != Latin1Utf16 && len < 0 {
    raise CanonCallError(
      "string content out-of-bounds (string pointer/length out of bounds of memory)",
    )
  }
  // Pointer alignment requirements:
  // - utf16 and latin1+utf16 require 2-byte alignment.
  if (encoding is Utf16 || encoding is Latin1Utf16) &&
    (ptr.reinterpret_as_uint() & 1U) != 0U {
    raise CanonCallError("unaligned pointer")
  }
  let mem_len = mem.byte_len()
  let mut byte_len = len
  let mut latin1 = false
  if encoding == Utf16 {
    byte_len = len * 2
  } else if encoding == Latin1Utf16 {
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
  if encoding == Utf8 || latin1 {
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
    [I64(0L), I64(0L), I64(align.to_int64()), I64(len.to_int64())]
  } else {
    [I32(0), I32(0), I32(align), I32(len)]
  }
  let results = call_core_func(store, realloc, args)
  let ptr = match results {
    [I32(n)] => n
    [I64(n)] => n.to_int()
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
    I32 | F32 => 4
    I64 | F64 => 8
    _ => 4
  }
}

///|
fn core_valtype_size(vt : @types.ValueType) -> Int {
  match vt {
    I32 | F32 => 4
    I64 | F64 => 8
    _ => 4
  }
}

///|
struct FlatStorageField {
  vt : @types.ValueType
  size : Int
  align : Int
} derive(Debug)

///|
fn default_flat_storage_field(vt : @types.ValueType) -> FlatStorageField {
  { vt, size: core_valtype_size(vt), align: core_valtype_align(vt) }
}

///|
fn append_default_flat_storage_for_valtype(
  out : Array[FlatStorageField],
  ty : ValType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> Unit raise ComponentRuntimeError {
  for vt in core_types_for_valtype(ty, types, mem_is_64) {
    out.push(default_flat_storage_field(vt))
  }
}

///|
fn append_flat_storage_for_valtype(
  out : Array[FlatStorageField],
  ty : ValType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> Unit raise ComponentRuntimeError {
  let ptr_size = if mem_is_64 { 8 } else { 4 }
  let ptr_vt = if mem_is_64 { @types.ValueType::I64 } else { I32 }
  match resolve_valtype(ty, types) {
    Prim(p) =>
      match p {
        Bool | S8 | U8 => out.push({ vt: I32, size: 1, align: 1 })
        S16 | U16 => out.push({ vt: I32, size: 2, align: 2 })
        S32 | U32 | Char => out.push({ vt: I32, size: 4, align: 4 })
        S64 | U64 => out.push({ vt: I64, size: 8, align: 8 })
        F32 => out.push({ vt: F32, size: 4, align: 4 })
        F64 => out.push({ vt: F64, size: 8, align: 8 })
        String | ErrorContext => {
          out.push({ vt: ptr_vt, size: ptr_size, align: ptr_size })
          out.push({ vt: ptr_vt, size: ptr_size, align: ptr_size })
        }
      }
    TypeIdx(ti) =>
      match types.get(ti) {
        Some(Some(Tuple(tys))) =>
          for t in tys {
            append_flat_storage_for_valtype(out, t, types, mem_is_64)
          }
        Some(Some(Record(fields))) =>
          for field in fields {
            append_flat_storage_for_valtype(out, field.ty, types, mem_is_64)
          }
        Some(Some(List(_elem_ty))) => {
          out.push({ vt: ptr_vt, size: ptr_size, align: ptr_size })
          out.push({ vt: ptr_vt, size: ptr_size, align: ptr_size })
        }
        Some(Some(Enum(labels))) => {
          let n = labels.length()
          let size = if n <= 0x100 { 1 } else if n <= 0x10000 { 2 } else { 4 }
          out.push({ vt: I32, size, align: size })
        }
        Some(Some(Flags(labels))) => {
          let nbits = labels.length()
          if nbits <= 8 {
            out.push({ vt: I32, size: 1, align: 1 })
          } else if nbits <= 16 {
            out.push({ vt: I32, size: 2, align: 2 })
          } else if nbits <= 32 {
            out.push({ vt: I32, size: 4, align: 4 })
          } else {
            out.push({ vt: I64, size: 8, align: 8 })
          }
        }
        Some(Some(Own(_)))
        | Some(Some(Borrow(_)))
        | Some(Some(ResourceType(_, _, _, _)))
        | Some(Some(Stream(_)))
        | Some(Some(Future(_))) => out.push({ vt: I32, size: 4, align: 4 })
        Some(Some(DefValType(p))) =>
          append_flat_storage_for_valtype(out, Prim(p), types, mem_is_64)
        _ => append_default_flat_storage_for_valtype(out, ty, types, mem_is_64)
      }
  }
}

///|
fn flat_storage_for_valtype(
  ty : ValType,
  types : Array[TypeDef?],
  mem_is_64 : Bool,
) -> Array[FlatStorageField] raise ComponentRuntimeError {
  let out : Array[FlatStorageField] = []
  append_flat_storage_for_valtype(out, ty, types, mem_is_64)
  out
}

///|
fn layout_of_flat_storage_fields(
  fields : Array[FlatStorageField],
) -> (Array[Int], Int, Int) {
  let offsets : Array[Int] = []
  let mut off = 0
  let mut struct_align = 1
  for field in fields {
    let a = field.align
    if a > struct_align {
      struct_align = a
    }
    off = align_to(off, a)
    offsets.push(off)
    off += field.size
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
    [I64(0L), I64(0L), I64(align.to_int64()), I64(size.to_int64())]
  } else {
    [I32(0), I32(0), I32(align), I32(size)]
  }
  let results = call_core_func(store, realloc, args)
  let ptr = match results {
    [I32(n)] => n
    [I64(n)] => n.to_int()
    _ => raise CanonCallError("invalid realloc result")
  }
  let mem_len = mem.byte_len().to_int()
  if ptr < 0 || ptr > mem_len || ptr + size > mem_len {
    raise CanonCallError("realloc return: beyond end of memory")
  }
  ptr
}

///|
fn load_storage_value(
  mem : @runtime.Memory,
  addr : Int,
  field : FlatStorageField,
) -> @types.Value raise ComponentRuntimeError {
  match field.vt {
    I32 =>
      if field.size == 1 {
        I32(
          mem.load_i32_8u(addr) catch {
            e => raise CanonCallError(e.to_string())
          },
        )
      } else if field.size == 2 {
        I32(
          mem.load_i32_16u(addr) catch {
            e => raise CanonCallError(e.to_string())
          },
        )
      } else {
        I32(
          mem.load_i32(addr) catch {
            e => raise CanonCallError(e.to_string())
          },
        )
      }
    I64 =>
      if field.size == 4 {
        I64(
          mem.load_i64_32u(addr) catch {
            e => raise CanonCallError(e.to_string())
          },
        )
      } else {
        I64(
          mem.load_i64(addr) catch {
            e => raise CanonCallError(e.to_string())
          },
        )
      }
    F32 =>
      F32(mem.load_f32(addr) catch { e => raise CanonCallError(e.to_string()) })
    F64 =>
      F64(mem.load_f64(addr) catch { e => raise CanonCallError(e.to_string()) })
    _ => load_flat_value(mem, addr, field.vt)
  }
}

///|
fn store_storage_value(
  mem : @runtime.Memory,
  addr : Int,
  val : @types.Value,
  field : FlatStorageField,
) -> Unit raise ComponentRuntimeError {
  match (field.vt, val) {
    (I32, I32(n)) =>
      if field.size == 1 {
        mem.store_i32_8(addr, n) catch {
          e => raise CanonCallError(e.to_string())
        }
      } else if field.size == 2 {
        mem.store_i32_16(addr, n) catch {
          e => raise CanonCallError(e.to_string())
        }
      } else {
        mem.store_i32(addr, n) catch {
          e => raise CanonCallError(e.to_string())
        }
      }
    (I64, I64(n)) =>
      if field.size == 4 {
        mem.store_i64_32(addr, n) catch {
          e => raise CanonCallError(e.to_string())
        }
      } else {
        mem.store_i64(addr, n) catch {
          e => raise CanonCallError(e.to_string())
        }
      }
    (F32, F32(f)) =>
      mem.store_f32(addr, f) catch {
        e => raise CanonCallError(e.to_string())
      }
    (F64, F64(f)) =>
      mem.store_f64(addr, f) catch {
        e => raise CanonCallError(e.to_string())
      }
    _ => store_flat_value(mem, addr, val)
  }
}

///|
fn load_flat_value(
  mem : @runtime.Memory,
  addr : Int,
  vt : @types.ValueType,
) -> @types.Value raise ComponentRuntimeError {
  match vt {
    I32 =>
      I32(mem.load_i32(addr) catch { e => raise CanonCallError(e.to_string()) })
    I64 =>
      I64(mem.load_i64(addr) catch { e => raise CanonCallError(e.to_string()) })
    F32 =>
      F32(mem.load_f32(addr) catch { e => raise CanonCallError(e.to_string()) })
    F64 =>
      F64(mem.load_f64(addr) catch { e => raise CanonCallError(e.to_string()) })
    _ =>
      I32(mem.load_i32(addr) catch { e => raise CanonCallError(e.to_string()) })
  }
}

///|
fn store_flat_value(
  mem : @runtime.Memory,
  addr : Int,
  val : @types.Value,
) -> Unit raise ComponentRuntimeError {
  match val {
    I32(n) =>
      mem.store_i32(addr, n) catch {
        e => raise CanonCallError(e.to_string())
      }
    I64(n) =>
      mem.store_i64(addr, n) catch {
        e => raise CanonCallError(e.to_string())
      }
    F32(f) =>
      mem.store_f32(addr, f) catch {
        e => raise CanonCallError(e.to_string())
      }
    F64(f) =>
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
    I32 => I32(0)
    I64 => I64(0L)
    F32 => F32(0.0)
    F64 => F64(0.0)
    _ => I32(0)
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
    (F32, I32, F32(f)) => I32(f.reinterpret_as_int())
    (I32, F32, I32(n)) => F32(Float::reinterpret_from_int(n))
    (F64, I64, F64(f)) => I64(f.reinterpret_as_int64())
    (I64, F64, I64(n)) => F64(n.reinterpret_as_double())
    (I32, I64, I32(n)) => {
      let bits = n.reinterpret_as_uint().to_uint64().reinterpret_as_int64()
      I64(bits)
    }
    (I64, I32, I64(n)) =>
      I32(
        (n.reinterpret_as_uint64() & 0xFFFF_FFFFUL)
        .to_uint()
        .reinterpret_as_int(),
      )
    (I64, F32, I64(n)) => {
      let bits = (n.reinterpret_as_uint64() & 0xFFFF_FFFFUL)
        .to_uint()
        .reinterpret_as_int()
      F32(Float::reinterpret_from_int(bits))
    }
    (F32, I64, F32(f)) => {
      let bits = f
        .reinterpret_as_int()
        .reinterpret_as_uint()
        .to_uint64()
        .reinterpret_as_int64()
      I64(bits)
    }
    _ => raise HostCallError("type mismatch")
  }
}

///|
