///|
/// WebAssembly linear memory.
///
/// This implementation uses a shared C-side `wasmoon_memory_t` descriptor as the
/// single source of truth for both interpreter and JIT.
struct Memory {
  mem_desc_ptr : Int64
  max : Int? // max size in logical pages
  is_memory64 : Bool // true for memory64 (i64-indexed)
  page_size_log2 : Int
  page_size_bytes : Int64
} derive(Show)

///|
pub fn Memory::desc_ptr(self : Memory) -> Int64 {
  self.mem_desc_ptr
}

///|
pub fn Memory::byte_len(self : Memory) -> Int64 {
  if self.mem_desc_ptr == 0L {
    0L
  } else {
    @jit_ffi.c_mem_desc_get_len(self.mem_desc_ptr)
  }
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
fn Memory::read_fixed(self : Memory, addr : Int, len : Int) -> FixedArray[Byte] {
  if self.mem_desc_ptr == 0L || len <= 0 {
    return FixedArray::make(0, b'\x00')
  }
  let out = FixedArray::make(len, b'\x00')
  let _ = @jit_ffi.c_mem_desc_read(self.mem_desc_ptr, addr.to_int64(), out, len)
  out
}

///|
fn Memory::write_fixed(
  self : Memory,
  addr : Int,
  data : FixedArray[Byte],
  len : Int,
) -> Unit {
  if self.mem_desc_ptr == 0L || len <= 0 {
    return
  }
  let _ = @jit_ffi.c_mem_desc_write(
    self.mem_desc_ptr,
    addr.to_int64(),
    data,
    len,
  )

}

///|
fn Memory::load_byte_unchecked(self : Memory, addr : Int) -> Byte {
  let bytes = self.read_fixed(addr, 1)
  if bytes.length() == 1 {
    bytes[0]
  } else {
    b'\x00'
  }
}

///|
fn Memory::store_byte_unchecked(
  self : Memory,
  addr : Int,
  value : Byte,
) -> Unit {
  let data = FixedArray::make(1, value)
  self.write_fixed(addr, data, 1)
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
  let size_bytes = min.to_int64() * page_size_bytes
  let mem_desc_ptr = if !is_memory64 && l2 == 16 {
    // Guard pages are required for JIT memory0 correctness.
    @jit.alloc_guarded_memory_desc(min, max)
  } else {
    @jit.alloc_memory_desc(
      size_bytes,
      max,
      is_memory64~,
      page_size_log2=l2,
      is_shared=false,
    )
  }
  { mem_desc_ptr, max, is_memory64, page_size_log2: l2, page_size_bytes }
}

///|
/// Allocate a guarded (reserved) memory for memory32 memory0.
/// This is required for JIT guard-page-based trapping.
pub fn Memory::new_guarded_memory0(min : Int, max : Int?) -> Memory {
  let initial_pages = min
  let mem_desc_ptr = @jit.alloc_guarded_memory_desc(initial_pages, max)
  {
    mem_desc_ptr,
    max,
    is_memory64: false,
    page_size_log2: 16,
    page_size_bytes: 65536L,
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
  let b = self.read_fixed(addr, 4)
  let b0 = b[0].to_int()
  let b1 = b[1].to_int()
  let b2 = b[2].to_int()
  let b3 = b[3].to_int()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
pub fn Memory::store_i32(
  self : Memory,
  addr : Int,
  value : Int,
) -> Unit raise RuntimeError {
  self.check_bounds(addr, 4)
  let data = FixedArray::make(4, b'\x00')
  data[0] = value.land(0xFF).to_byte()
  data[1] = (value >> 8).land(0xFF).to_byte()
  data[2] = (value >> 16).land(0xFF).to_byte()
  data[3] = (value >> 24).land(0xFF).to_byte()
  self.write_fixed(addr, data, 4)
}

///|
pub fn Memory::load_i64(self : Memory, addr : Int) -> Int64 raise RuntimeError {
  self.check_bounds(addr, 8)
  let b = self.read_fixed(addr, 8)
  let mut result = 0L
  for i in 0..<8 {
    result = result | (b[i].to_int64() << (i * 8))
  }
  result
}

///|
pub fn Memory::store_i64(
  self : Memory,
  addr : Int,
  value : Int64,
) -> Unit raise RuntimeError {
  self.check_bounds(addr, 8)
  let data = FixedArray::make(8, b'\x00')
  for i in 0..<8 {
    data[i] = (value >> (i * 8)).land(0xFFL).to_int().to_byte()
  }
  self.write_fixed(addr, data, 8)
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
  let b = self.read_fixed(addr, 2)
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
pub fn Memory::load_i32_16u(
  self : Memory,
  addr : Int,
) -> Int raise RuntimeError {
  self.check_bounds(addr, 2)
  let b = self.read_fixed(addr, 2)
  let b0 = b[0].to_int()
  let b1 = b[1].to_int()
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
  let v = self.load_i32_16s(addr)
  v.to_int64()
}

///|
/// Load 16-bit unsigned integer, zero-extend to i64
pub fn Memory::load_i64_16u(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  let v = self.load_i32_16u(addr)
  v.to_int64()
}

///|
/// Load 32-bit signed integer, sign-extend to i64
pub fn Memory::load_i64_32s(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  self.load_i32(addr).to_int64()
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
  let data = FixedArray::make(2, b'\x00')
  data[0] = value.land(0xFF).to_byte()
  data[1] = (value >> 8).land(0xFF).to_byte()
  self.write_fixed(addr, data, 2)
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
  let data = FixedArray::make(2, b'\x00')
  data[0] = value.land(0xFFL).to_int().to_byte()
  data[1] = (value >> 8).land(0xFFL).to_int().to_byte()
  self.write_fixed(addr, data, 2)
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
  let bytes = self.byte_len()
  if self.page_size_bytes <= 0L {
    0
  } else {
    (bytes / self.page_size_bytes).to_int()
  }
}

///|
pub fn Memory::is_memory64(self : Memory) -> Bool {
  self.is_memory64
}

///|
pub fn Memory::grow(self : Memory, delta : Int) -> Int {
  if delta < 0 {
    return -1
  }
  let max_pages = self.max.unwrap_or(-1)
  if self.mem_desc_ptr == 0L {
    return -1
  }
  @jit_ffi.c_mem_desc_grow(self.mem_desc_ptr, delta, max_pages)
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
  if len == 0 {
    return
  }
  let fixed = FixedArray::make(len, b'\x00')
  for i in 0..<len {
    fixed[i] = data[i]
  }
  let _ = @jit_ffi.c_mem_desc_write(
    self.mem_desc_ptr,
    dest.to_int64(),
    fixed,
    len,
  )

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
  let _ = @jit_ffi.c_mem_desc_memmove(
    self.mem_desc_ptr,
    dest.to_int64(),
    src.to_int64(),
    len,
  )

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
  let _ = @jit_ffi.c_mem_desc_memset(
    self.mem_desc_ptr,
    dest.to_int64(),
    value.to_int(),
    len,
  )

}

///|
/// Read i32 from memory (non-raising version for WASI)
pub fn Memory::read_i32(self : Memory, addr : Int) -> Int {
  if addr < 0 || addr.to_int64() + 4L > self.byte_len() {
    return 0
  }
  self.load_i32(addr) catch {
    _ => 0
  }
}

///|
/// Write i32 to memory (non-raising version for WASI)
pub fn Memory::write_i32(self : Memory, addr : Int, value : Int) -> Unit {
  if addr < 0 || addr.to_int64() + 4L > self.byte_len() {
    return
  }
  try self.store_i32(addr, value) |> ignore catch {
    _ => ()
  }
}

///|
/// Read i64 from memory (non-raising version for WASI)
pub fn Memory::read_i64(self : Memory, addr : Int) -> Int64 {
  if addr < 0 || addr.to_int64() + 8L > self.byte_len() {
    return 0L
  }
  self.load_i64(addr) catch {
    _ => 0L
  }
}

///|
/// Write i64 to memory (non-raising version for WASI)
pub fn Memory::write_i64(self : Memory, addr : Int, value : Int64) -> Unit {
  if addr < 0 || addr.to_int64() + 8L > self.byte_len() {
    return
  }
  try self.store_i64(addr, value) |> ignore catch {
    _ => ()
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
  if len == 0 {
    return b""
  }
  let fixed = FixedArray::make(len, b'\x00')
  let rc = @jit_ffi.c_mem_desc_read(
    self.mem_desc_ptr,
    addr.to_int64(),
    fixed,
    len,
  )
  if rc != 0 {
    return b""
  }
  let arr : Array[Byte] = Array::make(len, b'\x00')
  for i in 0..<len {
    arr[i] = fixed[i]
  }
  Bytes::from_array(arr)
}

///|
/// Get memory limits (min(current), max) for type checking
pub fn Memory::get_limits(self : Memory) -> (Int, Int?) {
  (self.size_pages(), self.max)
}
