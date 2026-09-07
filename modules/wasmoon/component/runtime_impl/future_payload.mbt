///|
fn future_payload_is_numeric(ty : ValType?) -> Bool {
  match ty {
    None => true
    Some(Prim(S8 | U8 | S16 | U16 | S32 | U32 | S64 | U64 | F32 | F64)) => true
    _ => false
  }
}

///|
fn future_scalar_payload_size(ty : ValType?) -> Int raise ComponentRuntimeError {
  match ty {
    None => 0
    Some(Prim(Bool | S8 | U8)) => 1
    Some(Prim(S16 | U16)) => 2
    Some(Prim(S32 | U32 | F32 | Char)) => 4
    Some(Prim(S64 | U64 | F64)) => 8
    _ => raise CanonCallError("unsupported future type")
  }
}

///|
fn future_payload_memory(
  store : @runtime.Store,
  mem_addr : Int?,
  ptr : Int,
  size : Int,
) -> @runtime.Memory raise ComponentRuntimeError {
  guard mem_addr is Some(addr) else { raise MissingCanonMemory }
  let mem = store.get_mem(addr) catch {
    error => raise CanonCallError(error.to_string())
  }
  let offset = ptr.to_int64() & 0xffffffffL
  if offset % size.to_int64() != 0L {
    raise CanonCallError("unaligned pointer")
  }
  if offset > mem.byte_len() || size.to_int64() > mem.byte_len() - offset {
    raise CanonCallError("out of bounds memory access")
  }
  mem
}

///|
fn load_future_scalar_payload(
  ty : ValType?,
  store : @runtime.Store,
  mem_addr : Int?,
  ptr : Int,
) -> Bytes raise ComponentRuntimeError {
  let size = future_scalar_payload_size(ty)
  if size == 0 {
    return b""
  }
  let mem = future_payload_memory(store, mem_addr, ptr, size)
  let bytes : Array[Byte] = []
  for i in 0..<size {
    bytes.push(
      mem.load_byte(ptr + i) catch {
        error => raise CanonCallError(error.to_string())
      },
    )
  }
  match ty {
    Some(Prim(Bool)) =>
      bytes[0] = if bytes[0] == b'\x00' { b'\x00' } else { b'\x01' }
    Some(Prim(Char)) => {
      let value = mem.load_i32(ptr) catch {
        error => raise CanonCallError(error.to_string())
      }
      char_from_canon_i32(value) |> ignore
    }
    _ => ()
  }
  Bytes::from_array(bytes)
}

///|
fn store_future_scalar_payload(
  payload : Bytes,
  store : @runtime.Store,
  mem_addr : Int?,
  ptr : Int,
) -> Unit raise ComponentRuntimeError {
  if payload.is_empty() {
    return
  }
  let mem = future_payload_memory(store, mem_addr, ptr, payload.length())
  mem.init_data(ptr, payload) catch {
    error => raise CanonCallError(error.to_string())
  }
}
