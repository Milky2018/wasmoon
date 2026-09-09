///|
/// Type indices always travel with their defining component environment.
struct CanonicalPayloadType {
  ty : ValType?
  types : Array[TypeDef?]
} derive(Debug)

///|
struct CanonicalPayload {
  payload_type : CanonicalPayloadType
  values : Array[ComponentValue]
} derive(Debug)

///|
fn CanonicalPayloadType::layout(
  self : CanonicalPayloadType,
  resources : CanonResources,
  store : @runtime.Store,
) -> (Int, Int) raise ComponentRuntimeError {
  guard self.ty is Some(ty) else { return (0, 1) }
  let memory = require_memory(resources, store)
  canonical_memory_layout(ty, self.types, memory.is_memory64())
}

///|
fn CanonicalPayloadType::check_transmit_buffer(
  self : CanonicalPayloadType,
  resources : CanonResources,
  store : @runtime.Store,
  ptr : Int,
  count : Int,
) -> Unit raise ComponentRuntimeError {
  if count.reinterpret_as_uint() > 0x0fffffffU {
    raise CanonCallError("stream read/write count too large")
  }
  let (size, _) = self.layout(resources, store)
  if size == 0 || count == 0 {
    return
  }
  let memory = require_memory(resources, store)
  let offset = ptr.to_int64() & 0xffffffffL
  let length = size.to_int64() * count.to_int64()
  if offset > memory.byte_len() || length > memory.byte_len() - offset {
    raise CanonCallError("read pointer out of bounds of memory")
  }
}

///|
fn CanonicalPayloadType::load(
  self : CanonicalPayloadType,
  resources : CanonResources,
  store : @runtime.Store,
  ptr : Int,
  count : Int,
  resource_table : ResourceTable,
) -> CanonicalPayload raise ComponentRuntimeError {
  let values : Array[ComponentValue] = []
  let (size, alignment) = self.layout(resources, store)
  guard self.ty is Some(ty) && size != 0 && count != 0 else {
    return { payload_type: self, values, }
  }
  let memory = require_memory(resources, store)
  let offset = ptr.to_int64() & 0xffffffffL
  let length = size.to_int64() * count.to_int64()
  if offset % alignment.to_int64() != 0L {
    raise CanonCallError("unaligned pointer")
  }
  if count < 0 ||
    offset > memory.byte_len() ||
    length > memory.byte_len() - offset {
    raise CanonCallError("out of bounds memory access")
  }
  let budget = CanonicalCopyBudget::new()
  budget.consume(count, 32)
  for i in 0..<count {
    let flat = load_flat_component_value_from_memory(
      memory,
      ptr + i * size,
      ty,
      self.types,
      memory.is_memory64(),
    )
    values.push(
      lift_component_value_from_flat(
        ty,
        flat,
        self.types,
        Some(memory),
        memory.is_memory64(),
        resources.encoding,
        resource_table,
        budget~,
      ),
    )
  }
  { payload_type: self, values, }
}

///|
fn CanonicalPayload::store(
  self : CanonicalPayload,
  start : Int,
  count : Int,
  source_table : ResourceTable,
  destination : CanonicalPayloadType,
  resources : CanonResources,
  store : @runtime.Store,
  table : ResourceTable,
  async_state : AsyncState,
  ptr : Int,
) -> Unit raise ComponentRuntimeError {
  let (size, alignment) = destination.layout(resources, store)
  guard destination.ty is Some(ty) && size != 0 && count != 0 else { return }
  let memory = require_memory(resources, store)
  let offset = ptr.to_int64() & 0xffffffffL
  let length = size.to_int64() * count.to_int64()
  if offset % alignment.to_int64() != 0L {
    raise CanonCallError("unaligned pointer")
  }
  if count < 0 ||
    offset > memory.byte_len() ||
    length > memory.byte_len() - offset {
    raise CanonCallError("out of bounds memory access")
  }
  for i in 0..<count {
    guard self.values.get(start + i) is Some(value) else {
      raise HostCallError("missing payload value")
    }
    let value = match self.payload_type.ty {
      Some(source_ty) =>
        transfer_stream_future_value(
          source_ty,
          value,
          self.payload_type.types,
          async_state,
          source_table.id,
          table.id,
        )
      None => value
    }
    let flat = lower_component_value_to_flat(
      value,
      ty,
      destination.types,
      resources,
      store,
      (table, table),
    )
    store_flat_component_value_to_memory(
      memory,
      ptr + i * size,
      ty,
      flat,
      destination.types,
      memory.is_memory64(),
    )
  }
}
