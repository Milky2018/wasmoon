// Canonical linear-memory access uses 64-bit byte offsets on every engine.

///|
fn Memory::check_bounds_at(
  self : Memory,
  offset : Int64,
  length : Int64,
) -> Unit raise RuntimeError {
  self.require_desc_ptr() |> ignore
  if offset < 0L ||
    length < 0L ||
    length > self.byte_len() ||
    offset > self.byte_len() - length {
    raise OutOfBoundsMemoryAccess
  }
}

///|
fn Memory::read_fixed_at(
  self : Memory,
  addr : Int64,
  len : Int,
) -> FixedArray[Byte] {
  let pointer = self.desc_ptr()
  if pointer == 0L || len <= 0 {
    return FixedArray::make(0, b'\x00')
  }
  let out = FixedArray::make(len, b'\x00')
  @wasmoon_jit.memory_descriptor_read(pointer, addr, out, len) |> ignore
  out
}

///|
fn Memory::write_fixed_at(
  self : Memory,
  addr : Int64,
  data : FixedArray[Byte],
  len : Int,
) -> Unit {
  let pointer = self.desc_ptr()
  if pointer == 0L || len <= 0 {
    return
  }
  @wasmoon_jit.memory_descriptor_write(pointer, addr, data, len) |> ignore
}

///|
fn Memory::load_byte_unchecked_at(self : Memory, addr : Int64) -> Byte {
  let bytes = self.read_fixed_at(addr, 1)
  if bytes.length() == 1 {
    bytes[0]
  } else {
    b'\x00'
  }
}

///|
fn Memory::store_byte_unchecked_at(
  self : Memory,
  addr : Int64,
  value : Byte,
) -> Unit {
  let data = FixedArray::make(1, value)
  self.write_fixed_at(addr, data, 1)
}

///|
pub fn Memory::load_byte_at(
  self : Memory,
  addr : Int64,
) -> Byte raise RuntimeError {
  self.check_bounds_at(addr, 1)
  self.load_byte_unchecked_at(addr)
}

///|
pub fn Memory::store_byte_at(
  self : Memory,
  addr : Int64,
  value : Byte,
) -> Unit raise RuntimeError {
  self.check_bounds_at(addr, 1)
  self.store_byte_unchecked_at(addr, value)
}

///|
pub fn Memory::load_i32_at(
  self : Memory,
  addr : Int64,
) -> Int raise RuntimeError {
  self.check_bounds_at(addr, 4)
  let b = self.read_fixed_at(addr, 4)
  let b0 = b[0].to_int()
  let b1 = b[1].to_int()
  let b2 = b[2].to_int()
  let b3 = b[3].to_int()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
pub fn Memory::store_i32_at(
  self : Memory,
  addr : Int64,
  value : Int,
) -> Unit raise RuntimeError {
  self.check_bounds_at(addr, 4)
  let data = FixedArray::make(4, b'\x00')
  data[0] = value.land(0xFF).to_byte()
  data[1] = (value >> 8).land(0xFF).to_byte()
  data[2] = (value >> 16).land(0xFF).to_byte()
  data[3] = (value >> 24).land(0xFF).to_byte()
  self.write_fixed_at(addr, data, 4)
}

///|
pub fn Memory::load_i64_at(
  self : Memory,
  addr : Int64,
) -> Int64 raise RuntimeError {
  self.check_bounds_at(addr, 8)
  let b = self.read_fixed_at(addr, 8)
  let mut result = 0L
  for i in 0..<8 {
    result = result | (b[i].to_int64() << (i * 8))
  }
  result
}

///|
pub fn Memory::store_i64_at(
  self : Memory,
  addr : Int64,
  value : Int64,
) -> Unit raise RuntimeError {
  self.check_bounds_at(addr, 8)
  let data = FixedArray::make(8, b'\x00')
  for i in 0..<8 {
    data[i] = (value >> (i * 8)).land(0xFFL).to_int().to_byte()
  }
  self.write_fixed_at(addr, data, 8)
}

///|
pub fn Memory::load_f32_at(
  self : Memory,
  addr : Int64,
) -> Float raise RuntimeError {
  let bits = self.load_i32_at(addr)
  Float::reinterpret_from_int(bits)
}

///|
pub fn Memory::store_f32_at(
  self : Memory,
  addr : Int64,
  value : Float,
) -> Unit raise RuntimeError {
  let bits = value.reinterpret_as_int()
  self.store_i32_at(addr, bits)
}

///|
pub fn Memory::load_f64_at(
  self : Memory,
  addr : Int64,
) -> Double raise RuntimeError {
  let bits = self.load_i64_at(addr)
  bits.reinterpret_as_double()
}

///|
pub fn Memory::store_f64_at(
  self : Memory,
  addr : Int64,
  value : Double,
) -> Unit raise RuntimeError {
  let bits = value.reinterpret_as_int64()
  self.store_i64_at(addr, bits)
}

///|
/// Load 8-bit signed integer, sign-extend to i32
pub fn Memory::load_i32_8s_at(
  self : Memory,
  addr : Int64,
) -> Int raise RuntimeError {
  let byte = self.load_byte_at(addr).to_int()
  if byte >= 128 {
    byte - 256
  } else {
    byte
  }
}

///|
/// Load 8-bit unsigned integer, zero-extend to i32
pub fn Memory::load_i32_8u_at(
  self : Memory,
  addr : Int64,
) -> Int raise RuntimeError {
  self.load_byte_at(addr).to_int()
}

///|
/// Load 16-bit signed integer, sign-extend to i32
pub fn Memory::load_i32_16s_at(
  self : Memory,
  addr : Int64,
) -> Int raise RuntimeError {
  self.check_bounds_at(addr, 2)
  let b = self.read_fixed_at(addr, 2)
  let b0 = b[0].to_int()
  let b1 = b[1].to_int()
  let value = b0 | (b1 << 8)
  if value >= 32768 {
    value - 65536
  } else {
    value
  }
}

///|
/// Load 16-bit unsigned integer, zero-extend to i32
pub fn Memory::load_i32_16u_at(
  self : Memory,
  addr : Int64,
) -> Int raise RuntimeError {
  self.check_bounds_at(addr, 2)
  let b = self.read_fixed_at(addr, 2)
  let b0 = b[0].to_int()
  let b1 = b[1].to_int()
  b0 | (b1 << 8)
}

///|
/// Load 8-bit signed integer, sign-extend to i64
pub fn Memory::load_i64_8s_at(
  self : Memory,
  addr : Int64,
) -> Int64 raise RuntimeError {
  let byte = self.load_byte_at(addr).to_int64()
  if byte >= 128L {
    byte - 256L
  } else {
    byte
  }
}

///|
/// Load 8-bit unsigned integer, zero-extend to i64
pub fn Memory::load_i64_8u_at(
  self : Memory,
  addr : Int64,
) -> Int64 raise RuntimeError {
  self.load_byte_at(addr).to_int64()
}

///|
/// Load 16-bit signed integer, sign-extend to i64
pub fn Memory::load_i64_16s_at(
  self : Memory,
  addr : Int64,
) -> Int64 raise RuntimeError {
  let v = self.load_i32_16s_at(addr)
  v.to_int64()
}

///|
/// Load 16-bit unsigned integer, zero-extend to i64
pub fn Memory::load_i64_16u_at(
  self : Memory,
  addr : Int64,
) -> Int64 raise RuntimeError {
  let v = self.load_i32_16u_at(addr)
  v.to_int64()
}

///|
/// Load 32-bit signed integer, sign-extend to i64
pub fn Memory::load_i64_32s_at(
  self : Memory,
  addr : Int64,
) -> Int64 raise RuntimeError {
  self.load_i32_at(addr).to_int64()
}

///|
/// Load 32-bit unsigned integer, zero-extend to i64
pub fn Memory::load_i64_32u_at(
  self : Memory,
  addr : Int64,
) -> Int64 raise RuntimeError {
  let value = self.load_i32_at(addr)
  value.reinterpret_as_uint().to_uint64().reinterpret_as_int64()
}

///|
/// Store low 8 bits of i32
pub fn Memory::store_i32_8_at(
  self : Memory,
  addr : Int64,
  value : Int,
) -> Unit raise RuntimeError {
  self.store_byte_at(addr, value.land(0xFF).to_byte())
}

///|
/// Store low 16 bits of i32
pub fn Memory::store_i32_16_at(
  self : Memory,
  addr : Int64,
  value : Int,
) -> Unit raise RuntimeError {
  self.check_bounds_at(addr, 2)
  let data = FixedArray::make(2, b'\x00')
  data[0] = value.land(0xFF).to_byte()
  data[1] = (value >> 8).land(0xFF).to_byte()
  self.write_fixed_at(addr, data, 2)
}

///|
/// Store low 8 bits of i64
pub fn Memory::store_i64_8_at(
  self : Memory,
  addr : Int64,
  value : Int64,
) -> Unit raise RuntimeError {
  self.store_byte_at(addr, value.land(0xFFL).to_int().to_byte())
}

///|
/// Store low 16 bits of i64
pub fn Memory::store_i64_16_at(
  self : Memory,
  addr : Int64,
  value : Int64,
) -> Unit raise RuntimeError {
  self.check_bounds_at(addr, 2)
  let data = FixedArray::make(2, b'\x00')
  data[0] = value.land(0xFFL).to_int().to_byte()
  data[1] = (value >> 8).land(0xFFL).to_int().to_byte()
  self.write_fixed_at(addr, data, 2)
}

///|
/// Store low 32 bits of i64
pub fn Memory::store_i64_32_at(
  self : Memory,
  addr : Int64,
  value : Int64,
) -> Unit raise RuntimeError {
  self.store_i32_at(addr, value.to_int())
}

///|
pub fn Memory::init_data_at(
  self : Memory,
  destination : Int64,
  data : Bytes,
) -> Unit raise RuntimeError {
  self.check_bounds_at(destination, data.length().to_int64())
  if data.length() > 0 {
    @wasmoon_jit.memory_descriptor_write_bytes(
      self.require_desc_ptr(),
      destination,
      data,
      data.length(),
    )
    |> ignore
  }
}

///|
/// Copy bytes after checking both ranges, including zero-length copies.
/// Native memmove also handles aliases imported under different memory indices.
pub fn Memory::copy_from(
  self : Memory,
  destination : Int64,
  source : Memory,
  source_offset : Int64,
  length : Int64,
) -> Unit raise RuntimeError {
  self.check_bounds_at(destination, length)
  source.check_bounds_at(source_offset, length)
  if length > 0L {
    @wasmoon_jit.memory_descriptor_copy(
      self.require_desc_ptr(),
      destination,
      source.require_desc_ptr(),
      source_offset,
      length,
    )
    |> ignore
  }
}

///|
pub fn Memory::copy_at(
  self : Memory,
  destination : Int64,
  source : Int64,
  length : Int64,
) -> Unit raise RuntimeError {
  self.copy_from(destination, self, source, length)
}

///|
pub fn Memory::fill_at(
  self : Memory,
  destination : Int64,
  value : Byte,
  length : Int64,
) -> Unit raise RuntimeError {
  self.check_bounds_at(destination, length)
  if length > 0L {
    @wasmoon_jit.memory_descriptor_fill64(
      self.require_desc_ptr(),
      destination,
      value.to_int(),
      length,
    )
    |> ignore
  }
}
