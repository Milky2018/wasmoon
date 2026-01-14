///|
/// WebAssembly linear memory.
///
/// Physical storage is a sparse map of 64KiB chunks, but the *logical* WebAssembly
/// page size may vary under the custom-page-sizes proposal.
struct Memory {
  pages : @hashmap.HashMap[Int, Array[Byte]]
  mut size : Int // current size in logical pages
  max : Int? // max size in logical pages
  is_memory64 : Bool // true for memory64 (i64-indexed)
  page_size_log2 : Int
  page_size_bytes : Int64
} derive(Show)

///|
/// Physical chunk size for sparse storage.
const PAGE_SIZE : Int = 65536

///|
const PAGE_SIZE_BYTES : Int64 = 65536L

///|
pub fn Memory::byte_len(self : Memory) -> Int64 {
  self.size.to_int64() * self.page_size_bytes
}

///|
pub fn Memory::page_size_bytes(self : Memory) -> Int64 {
  self.page_size_bytes
}

///|
fn Memory::check_bounds(
  self : Memory,
  addr : Int,
  len : Int,
) -> Unit raise RuntimeError {
  if addr < 0 || len < 0 {
    raise OutOfBoundsMemoryAccess
  }
  let end = addr.to_int64() + len.to_int64()
  if end > self.byte_len() {
    raise OutOfBoundsMemoryAccess
  }
}

///|
fn Memory::load_byte_unchecked(self : Memory, addr : Int) -> Byte {
  let page_idx = addr / PAGE_SIZE
  let off = addr % PAGE_SIZE
  match self.pages.get(page_idx) {
    Some(p) => p[off]
    None => b'\x00'
  }
}

///|
fn Memory::store_byte_unchecked(
  self : Memory,
  addr : Int,
  value : Byte,
) -> Unit {
  let page_idx = addr / PAGE_SIZE
  let off = addr % PAGE_SIZE
  let page = match self.pages.get(page_idx) {
    Some(p) => p
    None => {
      let p = Array::make(PAGE_SIZE, b'\x00')
      self.pages.set(page_idx, p)
      p
    }
  }
  page[off] = value
}

///|
pub fn Memory::new(
  min : Int,
  max : Int?,
  is_memory64? : Bool = false,
  page_size_log2? : Int = 16,
) -> Memory {
  let l2 = page_size_log2
  if l2 < 0 || l2 > 30 {
    abort("invalid memory page size")
  }
  let page_size_bytes : Int64 = 1L << l2
  {
    pages: @hashmap.new(),
    size: min,
    max,
    is_memory64,
    page_size_log2: l2,
    page_size_bytes,
  }
}

///|
pub fn Memory::load_byte(self : Memory, addr : Int) -> Byte raise RuntimeError {
  self.check_bounds(addr, 1)
  self.load_byte_unchecked(addr)
}

///|
pub fn Memory::store_byte(
  self : Memory,
  addr : Int,
  value : Byte,
) -> Unit raise RuntimeError {
  self.check_bounds(addr, 1)
  self.store_byte_unchecked(addr, value)
}

///|
pub fn Memory::load_i32(self : Memory, addr : Int) -> Int raise RuntimeError {
  self.check_bounds(addr, 4)
  let b0 = self.load_byte_unchecked(addr).to_int()
  let b1 = self.load_byte_unchecked(addr + 1).to_int()
  let b2 = self.load_byte_unchecked(addr + 2).to_int()
  let b3 = self.load_byte_unchecked(addr + 3).to_int()
  // Little-endian
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
pub fn Memory::store_i32(
  self : Memory,
  addr : Int,
  value : Int,
) -> Unit raise RuntimeError {
  self.check_bounds(addr, 4)
  self.store_byte_unchecked(addr, value.land(0xFF).to_byte())
  self.store_byte_unchecked(addr + 1, (value >> 8).land(0xFF).to_byte())
  self.store_byte_unchecked(addr + 2, (value >> 16).land(0xFF).to_byte())
  self.store_byte_unchecked(addr + 3, (value >> 24).land(0xFF).to_byte())
}

///|
pub fn Memory::load_i64(self : Memory, addr : Int) -> Int64 raise RuntimeError {
  self.check_bounds(addr, 8)
  let b0 = self.load_byte_unchecked(addr).to_int64()
  let b1 = self.load_byte_unchecked(addr + 1).to_int64()
  let b2 = self.load_byte_unchecked(addr + 2).to_int64()
  let b3 = self.load_byte_unchecked(addr + 3).to_int64()
  let b4 = self.load_byte_unchecked(addr + 4).to_int64()
  let b5 = self.load_byte_unchecked(addr + 5).to_int64()
  let b6 = self.load_byte_unchecked(addr + 6).to_int64()
  let b7 = self.load_byte_unchecked(addr + 7).to_int64()
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
  self.check_bounds(addr, 8)
  for i in 0..<8 {
    let byte_val = (value >> (i * 8)).land(0xFFL).to_int()
    self.store_byte_unchecked(addr + i, byte_val.to_byte())
  }
}

///|
pub fn Memory::load_f32(self : Memory, addr : Int) -> Float raise RuntimeError {
  let bits = self.load_i32(addr)
  Float::reinterpret_from_int(bits)
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
  self.check_bounds(addr, 2)
  let b0 = self.load_byte_unchecked(addr).to_int()
  let b1 = self.load_byte_unchecked(addr + 1).to_int()
  let value = b0 | (b1 << 8)
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
  self.check_bounds(addr, 2)
  let b0 = self.load_byte_unchecked(addr).to_int()
  let b1 = self.load_byte_unchecked(addr + 1).to_int()
  b0 | (b1 << 8)
}

///|
/// Load 8-bit signed integer, sign-extend to i64
pub fn Memory::load_i64_8s(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  let byte = self.load_byte(addr).to_int64()
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
  self.check_bounds(addr, 2)
  let b0 = self.load_byte_unchecked(addr).to_int64()
  let b1 = self.load_byte_unchecked(addr + 1).to_int64()
  let value = b0 | (b1 << 8)
  if value >= 32768L {
    value - PAGE_SIZE_BYTES
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
  self.check_bounds(addr, 2)
  let b0 = self.load_byte_unchecked(addr).to_int64()
  let b1 = self.load_byte_unchecked(addr + 1).to_int64()
  b0 | (b1 << 8)
}

///|
/// Load 32-bit signed integer, sign-extend to i64
pub fn Memory::load_i64_32s(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  let value = self.load_i32(addr)
  value.to_int64()
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
  self.check_bounds(addr, 2)
  self.store_byte_unchecked(addr, value.land(0xFF).to_byte())
  self.store_byte_unchecked(addr + 1, (value >> 8).land(0xFF).to_byte())
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
  self.check_bounds(addr, 2)
  self.store_byte_unchecked(addr, value.land(0xFFL).to_int().to_byte())
  self.store_byte_unchecked(
    addr + 1,
    (value >> 8).land(0xFFL).to_int().to_byte(),
  )
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
pub fn Memory::is_memory64(self : Memory) -> Bool {
  self.is_memory64
}

///|
/// Returns sorted list of allocated (touched) pages.
/// Each page is always exactly 64KB.
pub fn Memory::allocated_pages(self : Memory) -> Array[(Int, Bytes)] {
  let keys : Array[Int] = []
  for entry in self.pages.iter() {
    let (k, _) = entry
    keys.push(k)
  }
  keys.sort()
  let result : Array[(Int, Bytes)] = []
  for k in keys {
    match self.pages.get(k) {
      Some(p) => result.push((k, Bytes::from_array(p)))
      None => ()
    }
  }
  result
}

///|
pub fn Memory::grow(self : Memory, delta : Int) -> Int {
  let old_size = self.size
  if delta < 0 {
    return -1
  }
  let old_u = old_size.reinterpret_as_uint()
  let delta_u = delta.reinterpret_as_uint()
  let new_u = old_u + delta_u
  if new_u < old_u {
    return -1
  }
  let new_size = new_u.reinterpret_as_int()
  if self.max is Some(max) && new_size > max {
    return -1
  }

  // Spec max: memory32 has a 32-bit address space (4GiB bytes).
  // With custom-page-sizes, the max number of logical pages depends on the page size.
  let max_pages = if self.is_memory64 {
    2147483647
  } else {
    let max_bytes = 4294967296L
    (max_bytes / self.page_size_bytes).to_int()
  }
  if new_size > max_pages {
    return -1
  }
  self.size = new_size
  old_size
}

///|
/// Initialize memory with data segment
pub fn Memory::init_data(
  self : Memory,
  dest : Int,
  data : Bytes,
) -> Unit raise RuntimeError {
  let len = data.length()
  self.check_bounds(dest, len)
  for i in 0..<len {
    self.store_byte_unchecked(dest + i, data[i])
  }
}

///|
/// Copy memory within the same memory instance
/// Handles overlapping regions correctly
pub fn Memory::copy(
  self : Memory,
  dest : Int,
  src : Int,
  len : Int,
) -> Unit raise RuntimeError {
  self.check_bounds(dest, len)
  self.check_bounds(src, len)
  if len == 0 {
    return
  }
  if dest <= src {
    for i in 0..<len {
      let b = self.load_byte_unchecked(src + i)
      self.store_byte_unchecked(dest + i, b)
    }
  } else {
    for i = len - 1; i >= 0; i = i - 1 {
      let b = self.load_byte_unchecked(src + i)
      self.store_byte_unchecked(dest + i, b)
    }
  }
}

///|
/// Fill memory region with a byte value
pub fn Memory::fill(
  self : Memory,
  dest : Int,
  value : Byte,
  len : Int,
) -> Unit raise RuntimeError {
  self.check_bounds(dest, len)
  if len == 0 {
    return
  }
  for i in 0..<len {
    self.store_byte_unchecked(dest + i, value)
  }
}

///|
/// Read i32 from memory (non-raising version for WASI)
pub fn Memory::read_i32(self : Memory, addr : Int) -> Int {
  if addr < 0 || addr.to_int64() + 4L > self.byte_len() {
    return 0
  }
  let b0 = self.load_byte_unchecked(addr).to_int()
  let b1 = self.load_byte_unchecked(addr + 1).to_int()
  let b2 = self.load_byte_unchecked(addr + 2).to_int()
  let b3 = self.load_byte_unchecked(addr + 3).to_int()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
/// Write i32 to memory (non-raising version for WASI)
pub fn Memory::write_i32(self : Memory, addr : Int, value : Int) -> Unit {
  if addr < 0 || addr.to_int64() + 4L > self.byte_len() {
    return
  }
  self.store_byte_unchecked(addr, value.land(0xFF).to_byte())
  self.store_byte_unchecked(addr + 1, (value >> 8).land(0xFF).to_byte())
  self.store_byte_unchecked(addr + 2, (value >> 16).land(0xFF).to_byte())
  self.store_byte_unchecked(addr + 3, (value >> 24).land(0xFF).to_byte())
}

///|
/// Read i64 from memory (non-raising version for WASI)
pub fn Memory::read_i64(self : Memory, addr : Int) -> Int64 {
  if addr < 0 || addr.to_int64() + 8L > self.byte_len() {
    return 0L
  }
  let mut result = 0L
  for i in 0..<8 {
    result = result | (self.load_byte_unchecked(addr + i).to_int64() << (i * 8))
  }
  result
}

///|
/// Write i64 to memory (non-raising version for WASI)
pub fn Memory::write_i64(self : Memory, addr : Int, value : Int64) -> Unit {
  if addr < 0 || addr.to_int64() + 8L > self.byte_len() {
    return
  }
  for i in 0..<8 {
    let byte_val = (value >> (i * 8)).land(0xFFL).to_int()
    self.store_byte_unchecked(addr + i, byte_val.to_byte())
  }
}

///|
/// Read a byte from memory (non-raising version for WASI)
pub fn Memory::read_byte(self : Memory, addr : Int) -> Byte {
  if addr < 0 || addr.to_int64() >= self.byte_len() {
    return b'\x00'
  }
  self.load_byte_unchecked(addr)
}

///|
/// Write a byte to memory (non-raising version for WASI)
pub fn Memory::write_byte(self : Memory, addr : Int, value : Byte) -> Unit {
  if addr < 0 || addr.to_int64() >= self.byte_len() {
    return
  }
  self.store_byte_unchecked(addr, value)
}

///|
/// Read bytes from memory (non-raising version for WASI)
pub fn Memory::read_bytes(self : Memory, addr : Int, len : Int) -> Bytes {
  if addr < 0 || len < 0 || addr.to_int64() + len.to_int64() > self.byte_len() {
    return b""
  }
  let arr : Array[Byte] = Array::make(len, b'\x00')
  for i in 0..<len {
    arr[i] = self.load_byte_unchecked(addr + i)
  }
  Bytes::from_array(arr)
}

///|
/// Get memory limits (min, max) for type checking
pub fn Memory::get_limits(self : Memory) -> (Int, Int?) {
  (self.size, self.max)
}
