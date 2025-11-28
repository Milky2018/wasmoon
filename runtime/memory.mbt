///|
/// WebAssembly linear memory (64KB pages)
struct Memory {
  data : Array[Byte]
  mut size : Int // current size in pages
  max : Int? // max size in pages
} derive(Show)

///|
pub fn Memory::new(min : Int, max : Int?) -> Memory {
  let page_size = 65536 // 64KB
  let initial_size = min * page_size
  let data : Array[Byte] = []
  for _ in 0..<initial_size {
    data.push(b'\x00')
  }
  { data, size: min, max }
}

///|
pub fn Memory::load_byte(self : Memory, addr : Int) -> Byte raise RuntimeError {
  if addr < 0 || addr >= self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  self.data[addr]
}

///|
pub fn Memory::store_byte(
  self : Memory,
  addr : Int,
  value : Byte,
) -> Unit raise RuntimeError {
  if addr < 0 || addr >= self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  self.data[addr] = value
}

///|
pub fn Memory::load_i32(self : Memory, addr : Int) -> Int raise RuntimeError {
  if addr + 4 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  let b0 = self.data[addr].to_int()
  let b1 = self.data[addr + 1].to_int()
  let b2 = self.data[addr + 2].to_int()
  let b3 = self.data[addr + 3].to_int()
  // Little-endian
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
pub fn Memory::store_i32(
  self : Memory,
  addr : Int,
  value : Int,
) -> Unit raise RuntimeError {
  if addr + 4 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  self.store_byte(addr, value.land(0xFF).to_byte())
  self.store_byte(addr + 1, (value >> 8).land(0xFF).to_byte())
  self.store_byte(addr + 2, (value >> 16).land(0xFF).to_byte())
  self.store_byte(addr + 3, (value >> 24).land(0xFF).to_byte())
}

///|
pub fn Memory::load_i64(self : Memory, addr : Int) -> Int64 raise RuntimeError {
  if addr + 8 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  let b0 = self.data[addr].to_int64()
  let b1 = self.data[addr + 1].to_int64()
  let b2 = self.data[addr + 2].to_int64()
  let b3 = self.data[addr + 3].to_int64()
  let b4 = self.data[addr + 4].to_int64()
  let b5 = self.data[addr + 5].to_int64()
  let b6 = self.data[addr + 6].to_int64()
  let b7 = self.data[addr + 7].to_int64()
  // Little-endian
  b0 |
  (b1 << 8) |
  (b2 << 16) |
  (b3 << 24) |
  (b4 << 32) |
  (b5 << 40) |
  (b6 << 48) |
  (b7 << 56)
}

///|
pub fn Memory::store_i64(
  self : Memory,
  addr : Int,
  value : Int64,
) -> Unit raise RuntimeError {
  if addr + 8 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  for i in 0..<8 {
    let byte_val = (value >> (i * 8)).land(0xFFL).to_int()
    self.store_byte(addr + i, byte_val.to_byte())
  }
}

///|
pub fn Memory::load_f32(self : Memory, addr : Int) -> Float raise RuntimeError {
  let bits = self.load_i32(addr)
  bits.reinterpret_as_float()
}

///|
pub fn Memory::store_f32(
  self : Memory,
  addr : Int,
  value : Float,
) -> Unit raise RuntimeError {
  let bits = value.reinterpret_as_int()
  self.store_i32(addr, bits)
}

///|
pub fn Memory::load_f64(self : Memory, addr : Int) -> Double raise RuntimeError {
  let bits = self.load_i64(addr)
  bits.reinterpret_as_double()
}

///|
pub fn Memory::store_f64(
  self : Memory,
  addr : Int,
  value : Double,
) -> Unit raise RuntimeError {
  let bits = value.reinterpret_as_int64()
  self.store_i64(addr, bits)
}

///|
/// Load 8-bit signed integer, sign-extend to i32
pub fn Memory::load_i32_8s(self : Memory, addr : Int) -> Int raise RuntimeError {
  let byte = self.load_byte(addr).to_int()
  // Sign extend from 8 bits
  if byte >= 128 {
    byte - 256
  } else {
    byte
  }
}

///|
/// Load 8-bit unsigned integer, zero-extend to i32
pub fn Memory::load_i32_8u(self : Memory, addr : Int) -> Int raise RuntimeError {
  self.load_byte(addr).to_int()
}

///|
/// Load 16-bit signed integer, sign-extend to i32
pub fn Memory::load_i32_16s(
  self : Memory,
  addr : Int,
) -> Int raise RuntimeError {
  if addr + 2 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  let b0 = self.data[addr].to_int()
  let b1 = self.data[addr + 1].to_int()
  let value = b0 | (b1 << 8)
  // Sign extend from 16 bits
  if value >= 32768 {
    value - 65536
  } else {
    value
  }
}

///|
/// Load 16-bit unsigned integer, zero-extend to i32
pub fn Memory::load_i32_16u(
  self : Memory,
  addr : Int,
) -> Int raise RuntimeError {
  if addr + 2 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  let b0 = self.data[addr].to_int()
  let b1 = self.data[addr + 1].to_int()
  b0 | (b1 << 8)
}

///|
/// Load 8-bit signed integer, sign-extend to i64
pub fn Memory::load_i64_8s(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  let byte = self.load_byte(addr).to_int64()
  // Sign extend from 8 bits
  if byte >= 128L {
    byte - 256L
  } else {
    byte
  }
}

///|
/// Load 8-bit unsigned integer, zero-extend to i64
pub fn Memory::load_i64_8u(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  self.load_byte(addr).to_int64()
}

///|
/// Load 16-bit signed integer, sign-extend to i64
pub fn Memory::load_i64_16s(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  if addr + 2 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  let b0 = self.data[addr].to_int64()
  let b1 = self.data[addr + 1].to_int64()
  let value = b0 | (b1 << 8)
  // Sign extend from 16 bits
  if value >= 32768L {
    value - 65536L
  } else {
    value
  }
}

///|
/// Load 16-bit unsigned integer, zero-extend to i64
pub fn Memory::load_i64_16u(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  if addr + 2 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  let b0 = self.data[addr].to_int64()
  let b1 = self.data[addr + 1].to_int64()
  b0 | (b1 << 8)
}

///|
/// Load 32-bit signed integer, sign-extend to i64
pub fn Memory::load_i64_32s(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  let value = self.load_i32(addr)
  value.to_int64() // Int.to_int64 does sign extension
}

///|
/// Load 32-bit unsigned integer, zero-extend to i64
pub fn Memory::load_i64_32u(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  let value = self.load_i32(addr)
  value.reinterpret_as_uint().to_uint64().reinterpret_as_int64()
}

///|
/// Store low 8 bits of i32
pub fn Memory::store_i32_8(
  self : Memory,
  addr : Int,
  value : Int,
) -> Unit raise RuntimeError {
  self.store_byte(addr, value.land(0xFF).to_byte())
}

///|
/// Store low 16 bits of i32
pub fn Memory::store_i32_16(
  self : Memory,
  addr : Int,
  value : Int,
) -> Unit raise RuntimeError {
  if addr + 2 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  self.store_byte(addr, value.land(0xFF).to_byte())
  self.store_byte(addr + 1, (value >> 8).land(0xFF).to_byte())
}

///|
/// Store low 8 bits of i64
pub fn Memory::store_i64_8(
  self : Memory,
  addr : Int,
  value : Int64,
) -> Unit raise RuntimeError {
  self.store_byte(addr, value.land(0xFFL).to_int().to_byte())
}

///|
/// Store low 16 bits of i64
pub fn Memory::store_i64_16(
  self : Memory,
  addr : Int,
  value : Int64,
) -> Unit raise RuntimeError {
  if addr + 2 > self.data.length() {
    raise OutOfBoundsMemoryAccess
  }
  self.store_byte(addr, value.land(0xFFL).to_int().to_byte())
  self.store_byte(addr + 1, (value >> 8).land(0xFFL).to_int().to_byte())
}

///|
/// Store low 32 bits of i64
pub fn Memory::store_i64_32(
  self : Memory,
  addr : Int,
  value : Int64,
) -> Unit raise RuntimeError {
  self.store_i32(addr, value.to_int())
}

///|
pub fn Memory::size_pages(self : Memory) -> Int {
  self.size
}

///|
pub fn Memory::grow(self : Memory, delta : Int) -> Int {
  let old_size = self.size
  let new_size = old_size + delta

  // Check max limit
  match self.max {
    Some(max) => if new_size > max { return -1 }
    None => ()
  }

  // Check absolute limit (65536 pages = 4GB)
  if new_size > 65536 {
    return -1
  }

  // Grow the memory
  let page_size = 65536
  let new_data_size = delta * page_size
  for _ in 0..<new_data_size {
    self.data.push(b'\x00')
  }
  self.size = new_size
  old_size
}
