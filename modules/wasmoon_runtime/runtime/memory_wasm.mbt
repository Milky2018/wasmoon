///|
priv struct ManagedMemory {
  mut bytes : FixedArray[Byte]
  mut reservation : @jit_ffi.Reservation?
}

///|
priv enum MemoryDescriptorState {
  Open(ManagedMemory)
  Closed
}

///|
// The wasm backend uses contiguous MoonBit bytes with checked 64-bit guest offsets.
const MANAGED_MEMORY_MAX_BYTES : Int64 = 0x7FFF_FFF0L

///|
fn allocate_memory_storage(
  min : Int64,
  _max : Int64?,
  _memory64 : Bool,
  shared : Bool,
  l2 : Int32,
) -> MemoryDescriptorState raise RuntimeError {
  if shared {
    raise UnsupportedHostCapability("shared memory")
  }
  let length = min * (1L << l2)
  guard length <= MANAGED_MEMORY_MAX_BYTES else { raise OutOfMemory }
  Open({ bytes: FixedArray::make(length.to_int(), b'\x00'), reservation: None, })
}

///|
fn Memory::managed_storage(self : Memory) -> ManagedMemory raise RuntimeError {
  if self.descriptor_state.val is Closed {
    raise MemoryClosed
  }
  check_resource_open(self.binding)
  match self.descriptor_state.val {
    Open(storage) => storage
    Closed => raise MemoryClosed
  }
}

///|
fn Memory::ensure_memory_open(self : Memory) -> Unit raise RuntimeError {
  self.managed_storage() |> ignore
}

///|
pub fn Memory::byte_len(self : Memory) -> Int64 {
  self.managed_storage().bytes.length().to_int64() catch {
    _ => 0L
  }
}

///|
fn Memory::bind_memory_reservation(
  self : Memory,
  reservation : @jit_ffi.Reservation,
) -> Unit raise RuntimeError {
  let storage = self.managed_storage()
  guard storage.reservation is None else { raise InvalidHandle }
  storage.reservation = Some(reservation)
}

///|
pub fn Memory::grow64(self : Memory, delta : Int64) -> Int64 {
  let storage = self.managed_storage() catch { _ => return -1L }
  let old = storage.bytes.length().to_int64()
  let pages = old / self.page_size_bytes
  if delta < 0L ||
    delta > (MANAGED_MEMORY_MAX_BYTES - old) / self.page_size_bytes {
    return -1L
  }
  let next_pages = pages + delta
  if self.max is Some(max) &&
    next_pages.reinterpret_as_uint64() > max.reinterpret_as_uint64() {
    return -1L
  }
  if !self.is_memory64 && next_pages > 0x1_0000_0000L / self.page_size_bytes {
    return -1L
  }
  if delta == 0L {
    return pages
  }
  let next = next_pages * self.page_size_bytes
  if storage.reservation is Some(reservation) && !reservation.resize(next) {
    return -1L
  }
  let bytes = FixedArray::make(next.to_int(), b'\x00')
  for i in 0..<storage.bytes.length() {
    bytes[i] = storage.bytes[i]
  }
  storage.bytes = bytes
  pages
}

///|
fn Memory::read_fixed_at(
  self : Memory,
  offset : Int64,
  length : Int32,
) -> FixedArray[Byte] {
  let storage = self.managed_storage() catch { _ => return [] }
  if length <= 0 {
    return []
  }
  FixedArray::makei(length, i => storage.bytes[offset.to_int() + i])
}

///|
fn Memory::write_fixed_at(
  self : Memory,
  offset : Int64,
  data : FixedArray[Byte],
  length : Int32,
) -> Unit {
  let storage = self.managed_storage() catch { _ => return }
  for i in 0..<length {
    storage.bytes[offset.to_int() + i] = data[i]
  }
}

///|
fn Memory::write_bytes_unchecked_at(
  self : Memory,
  offset : Int64,
  data : Bytes,
) -> Unit {
  let storage = self.managed_storage() catch { _ => return }
  for i in 0..<data.length() {
    storage.bytes[offset.to_int() + i] = data[i]
  }
}

///|
fn Memory::copy_unchecked_at(
  self : Memory,
  offset : Int64,
  source : Memory,
  source_offset : Int64,
  length : Int64,
) -> Unit {
  let destination = self.managed_storage() catch { _ => return }
  let source = source.managed_storage() catch { _ => return }
  if physical_equal(destination, source) && offset > source_offset {
    for i = length; i > 0L; i = i - 1L {
      destination.bytes[(offset + i - 1L).to_int()] = source.bytes[(source_offset +
        i -
        1L).to_int()]
    }
  } else {
    for i = 0L; i < length; i = i + 1L {
      destination.bytes[(offset + i).to_int()] = source.bytes[(source_offset + i).to_int()]
    }
  }
}

///|
fn Memory::fill_unchecked_at(
  self : Memory,
  offset : Int64,
  value : Byte,
  length : Int64,
) -> Unit {
  let storage = self.managed_storage() catch { _ => return }
  for i = 0L; i < length; i = i + 1L {
    storage.bytes[(offset + i).to_int()] = value
  }
}

///|
impl Debug for MemoryDescriptorState with fn to_repr(self) {
  match self {
    Open(storage) =>
      @debug.Repr::literal("ManagedMemory(\{storage.bytes.length()} bytes)")
    Closed => @debug.Repr::literal("MemoryClosed")
  }
}

///|
pub fn Memory::close(self : Memory) -> Unit {
  if self.descriptor_state.val is Open(storage) {
    if storage.reservation is Some(reservation) {
      reservation.close()
    }
    storage.reservation = None
    storage.bytes = []
  }
  if self.binding is Some(binding) {
    binding.active.val = false
  }
  self.descriptor_state.val = Closed
}

///|
fn Memory::share(_self : Memory) -> Memory raise RuntimeError {
  raise UnsupportedHostCapability("shared memory")
}
