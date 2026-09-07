///|
enum FuturePayload {
  Scalar(Bytes)
  Text(String)
} derive(Debug)

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
  align? : Int = size,
) -> @runtime.Memory raise ComponentRuntimeError {
  guard mem_addr is Some(addr) else { raise MissingCanonMemory }
  let mem = store.get_mem(addr) catch {
    error => raise CanonCallError(error.to_string())
  }
  let offset = ptr.to_int64() & 0xffffffffL
  if offset % align.to_int64() != 0L {
    raise CanonCallError("unaligned pointer")
  }
  if offset > mem.byte_len() || size.to_int64() > mem.byte_len() - offset {
    raise CanonCallError("out of bounds memory access")
  }
  mem
}

///|
fn load_future_payload(
  ty : ValType?,
  store : @runtime.Store,
  resources : CanonResources,
  ptr : Int,
) -> FuturePayload raise ComponentRuntimeError {
  if ty == Some(Prim(String)) {
    let mem = require_memory(resources, store)
    let width = if mem.is_memory64() { 8 } else { 4 }
    future_payload_memory(
      store,
      resources.mem_addr,
      ptr,
      width * 2,
      align=width,
    )
    |> ignore
    let flat = load_flat_component_value_from_memory(
      mem,
      ptr,
      Prim(String),
      [],
      mem.is_memory64(),
    )
    let value = lift_component_value_from_flat(
      Prim(String),
      flat,
      [],
      Some(mem),
      mem.is_memory64(),
      resources.encoding,
    )
    guard value is String(text) else {
      raise CanonCallError("invalid string payload")
    }
    return Text(text)
  }
  let size = future_scalar_payload_size(ty)
  if size == 0 {
    return Scalar(b"")
  }
  let mem = future_payload_memory(store, resources.mem_addr, ptr, size)
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
  Scalar(Bytes::from_array(bytes))
}

///|
fn store_future_payload(
  payload : FuturePayload,
  store : @runtime.Store,
  resources : CanonResources,
  table : ResourceTable,
  ptr : Int,
) -> Unit raise ComponentRuntimeError {
  match payload {
    Text(text) => {
      let mem = require_memory(resources, store)
      let width = if mem.is_memory64() { 8 } else { 4 }
      future_payload_memory(
        store,
        resources.mem_addr,
        ptr,
        width * 2,
        align=width,
      )
      |> ignore
      store_host_stream_value(
        String(text),
        Prim(String),
        [],
        resources,
        store,
        table,
        ptr,
      )
    }
    Scalar(bytes) => {
      if bytes.is_empty() {
        return
      }
      let mem = future_payload_memory(
        store,
        resources.mem_addr,
        ptr,
        bytes.length(),
      )
      mem.init_data(ptr, bytes) catch {
        error => raise CanonCallError(error.to_string())
      }
    }
  }
}
