///|
fn allocate_memory_storage(
  min : Int64,
  max : Int64?,
  memory64 : Bool,
  shared : Bool,
  l2 : Int32,
) -> MemoryDescriptorState {
  Open(
    if !memory64 && l2 == 16 {
      @native_bridge.alloc_guarded_memory_desc(
        min.to_int(),
        max.map(v => v.to_int()),
        is_shared=shared,
      )
    } else {
      @native_bridge.alloc_memory_desc(
        min * (1L << l2),
        max,
        is_memory64=memory64,
        page_size_log2=l2,
        is_shared=shared,
      )
    },
  )
}

///|
fn Memory::ensure_memory_open(self : Memory) -> Unit raise RuntimeError {
  self.require_desc_ptr() |> ignore
}

///|
fn Memory::bind_memory_reservation(
  self : Memory,
  reservation : @jit_ffi.Reservation,
) -> Unit raise RuntimeError {
  guard self.require_desc_ptr().bind_reservation(reservation) else {
    raise InvalidHandle
  }
}

///|
fn Memory::write_bytes_unchecked_at(
  self : Memory,
  offset : Int64,
  data : Bytes,
) -> Unit {
  @native_bridge.memory_descriptor_write_bytes(
    self.desc_ptr(),
    offset,
    data,
    data.length(),
  )
  |> ignore
}

///|
fn Memory::copy_unchecked_at(
  self : Memory,
  offset : Int64,
  source : Memory,
  source_offset : Int64,
  length : Int64,
) -> Unit {
  @native_bridge.memory_descriptor_copy(
    self.desc_ptr(),
    offset,
    source.desc_ptr(),
    source_offset,
    length,
  )
  |> ignore
}

///|
fn Memory::fill_unchecked_at(
  self : Memory,
  offset : Int64,
  value : Byte,
  length : Int64,
) -> Unit {
  @native_bridge.memory_descriptor_fill64(
    self.desc_ptr(),
    offset,
    value.to_int(),
    length,
  )
  |> ignore
}
