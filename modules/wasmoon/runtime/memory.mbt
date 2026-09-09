///|
/// WebAssembly linear memory.
///
/// This implementation uses a shared C-side `wasmoon_memory_t` descriptor as the
/// single source of truth for both interpreter and JIT.
priv enum MemoryDescriptorState {
  Open(Int64)
  Closed
} derive(Debug)

///|
struct Memory {
  descriptor_state : Ref[MemoryDescriptorState]
  max : Int? // max size in logical pages
  is_memory64 : Bool // true for memory64 (i64-indexed)
  is_shared : Bool
  page_size_log2 : Int
  page_size_bytes : Int64
} derive(Debug)

///|
/// Return the borrowed native descriptor pointer.
///
/// The pointer is valid only while the owning Store remains open. Do not retain
/// it across `Store::close`; this method returns zero after shared invalidation.
pub fn Memory::desc_ptr(self : Memory) -> Int64 {
  match self.descriptor_state.val {
    Open(pointer) => pointer
    Closed => 0L
  }
}

///|
fn Memory::require_desc_ptr(self : Memory) -> Int64 raise RuntimeError {
  match self.descriptor_state.val {
    Open(pointer) if pointer != 0L => pointer
    Open(_) => raise OutOfMemory
    Closed => raise MemoryClosed
  }
}

///|
fn Memory::close(self : Memory) -> Unit {
  match self.descriptor_state.val {
    Open(pointer) => {
      self.descriptor_state.val = Closed
      if pointer != 0L {
        @wasmoon_jit.free_memory_desc(pointer)
      }
    }
    Closed => ()
  }
}

///|
pub fn Memory::byte_len(self : Memory) -> Int64 {
  let pointer = self.desc_ptr()
  if pointer == 0L {
    0L
  } else {
    @wasmoon_jit.memory_descriptor_length(pointer)
  }
}

///|
pub fn Memory::page_size_bytes(self : Memory) -> Int64 {
  self.page_size_bytes
}

///|
/// Convert a WASM address to a byte offset.
///
/// For memory32, addresses are u32, so negative Int values represent large
/// addresses (high bit set) and must be treated as unsigned.
fn Memory::addr_to_offset(self : Memory, addr : Int) -> Int64 {
  if self.is_memory64 {
    addr.to_int64()
  } else {
    // Interpret as u32 and widen to i64.
    addr.to_int64() & 0xFFFF_FFFFL
  }
}

///|
pub fn Memory::Memory(
  min : Int,
  max : Int?,
  is_memory64? : Bool = false,
  is_shared? : Bool = false,
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
    @wasmoon_jit.alloc_guarded_memory_desc(min, max, is_shared~)
  } else {
    @wasmoon_jit.alloc_memory_desc(
      size_bytes,
      max,
      is_memory64~,
      page_size_log2=l2,
      is_shared~,
    )
  }
  {
    descriptor_state: Ref(Open(mem_desc_ptr)),
    max,
    is_memory64,
    is_shared,
    page_size_log2: l2,
    page_size_bytes,
  }
}

///|
/// Allocate a guarded (reserved) memory for memory32 memory0.
/// This is required for JIT guard-page-based trapping.
pub fn Memory::new_guarded_memory0(
  min : Int,
  max : Int?,
  is_shared? : Bool = false,
) -> Memory {
  let initial_pages = min
  let mem_desc_ptr = @wasmoon_jit.alloc_guarded_memory_desc(
    initial_pages,
    max,
    is_shared~,
  )
  {
    descriptor_state: Ref(Open(mem_desc_ptr)),
    max,
    is_memory64: false,
    is_shared,
    page_size_log2: 16,
    page_size_bytes: @types.WASM_PAGE_SIZE_BYTES,
  }
}

// Compatibility entry points for callers that hold 32-bit addresses.
// All typed accesses use the checked 64-bit byte-offset implementation.

///|
pub fn Memory::load_byte(self : Memory, addr : Int) -> Byte raise RuntimeError {
  self.load_byte_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::store_byte(
  self : Memory,
  addr : Int,
  value : Byte,
) -> Unit raise RuntimeError {
  self.store_byte_at(self.addr_to_offset(addr), value)
}

///|
pub fn Memory::load_i32(self : Memory, addr : Int) -> Int raise RuntimeError {
  self.load_i32_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::store_i32(
  self : Memory,
  addr : Int,
  value : Int,
) -> Unit raise RuntimeError {
  self.store_i32_at(self.addr_to_offset(addr), value)
}

///|
pub fn Memory::load_i64(self : Memory, addr : Int) -> Int64 raise RuntimeError {
  self.load_i64_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::store_i64(
  self : Memory,
  addr : Int,
  value : Int64,
) -> Unit raise RuntimeError {
  self.store_i64_at(self.addr_to_offset(addr), value)
}

///|
pub fn Memory::load_f32(self : Memory, addr : Int) -> Float raise RuntimeError {
  self.load_f32_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::store_f32(
  self : Memory,
  addr : Int,
  value : Float,
) -> Unit raise RuntimeError {
  self.store_f32_at(self.addr_to_offset(addr), value)
}

///|
pub fn Memory::load_f64(self : Memory, addr : Int) -> Double raise RuntimeError {
  self.load_f64_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::store_f64(
  self : Memory,
  addr : Int,
  value : Double,
) -> Unit raise RuntimeError {
  self.store_f64_at(self.addr_to_offset(addr), value)
}

///|
pub fn Memory::load_i32_8s(self : Memory, addr : Int) -> Int raise RuntimeError {
  self.load_i32_8s_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::load_i32_8u(self : Memory, addr : Int) -> Int raise RuntimeError {
  self.load_i32_8u_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::load_i32_16s(
  self : Memory,
  addr : Int,
) -> Int raise RuntimeError {
  self.load_i32_16s_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::load_i32_16u(
  self : Memory,
  addr : Int,
) -> Int raise RuntimeError {
  self.load_i32_16u_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::load_i64_8s(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  self.load_i64_8s_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::load_i64_8u(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  self.load_i64_8u_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::load_i64_16s(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  self.load_i64_16s_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::load_i64_16u(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  self.load_i64_16u_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::load_i64_32s(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  self.load_i64_32s_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::load_i64_32u(
  self : Memory,
  addr : Int,
) -> Int64 raise RuntimeError {
  self.load_i64_32u_at(self.addr_to_offset(addr))
}

///|
pub fn Memory::store_i32_8(
  self : Memory,
  addr : Int,
  value : Int,
) -> Unit raise RuntimeError {
  self.store_i32_8_at(self.addr_to_offset(addr), value)
}

///|
pub fn Memory::store_i32_16(
  self : Memory,
  addr : Int,
  value : Int,
) -> Unit raise RuntimeError {
  self.store_i32_16_at(self.addr_to_offset(addr), value)
}

///|
pub fn Memory::store_i64_8(
  self : Memory,
  addr : Int,
  value : Int64,
) -> Unit raise RuntimeError {
  self.store_i64_8_at(self.addr_to_offset(addr), value)
}

///|
pub fn Memory::store_i64_16(
  self : Memory,
  addr : Int,
  value : Int64,
) -> Unit raise RuntimeError {
  self.store_i64_16_at(self.addr_to_offset(addr), value)
}

///|
pub fn Memory::store_i64_32(
  self : Memory,
  addr : Int,
  value : Int64,
) -> Unit raise RuntimeError {
  self.store_i64_32_at(self.addr_to_offset(addr), value)
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
  let pointer = self.desc_ptr()
  if pointer == 0L {
    return -1
  }
  @wasmoon_jit.memory_descriptor_grow(pointer, delta, max_pages)
}

///|
/// Initialize memory with data segment
pub fn Memory::init_data(
  self : Memory,
  dest : Int,
  data : Bytes,
) -> Unit raise RuntimeError {
  self.init_data_at(self.addr_to_offset(dest), data)
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
  self.copy_at(
    self.addr_to_offset(dest),
    self.addr_to_offset(src),
    len.to_int64(),
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
  self.fill_at(self.addr_to_offset(dest), value, len.to_int64())
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
  self.load_byte_unchecked_at(self.addr_to_offset(addr))
}

///|
/// Write a byte to memory (non-raising version for WASI)
pub fn Memory::write_byte(self : Memory, addr : Int, value : Byte) -> Unit {
  if addr < 0 || addr.to_int64() >= self.byte_len() {
    return
  }
  self.store_byte_unchecked_at(self.addr_to_offset(addr), value)
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
  let rc = @wasmoon_jit.memory_descriptor_read(
    self.desc_ptr(),
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

///|
pub fn Memory::is_shared(self : Memory) -> Bool {
  self.is_shared
}

///|
fn Memory::share(self : Memory) -> Memory raise RuntimeError {
  let pointer = self.require_desc_ptr()
  if !self.is_shared {
    raise LinkErrorDetail("only shared memory can be imported across Stores")
  }
  @wasmoon_jit.retain_memory_desc(pointer)
  {
    descriptor_state: Ref(Open(pointer)),
    max: self.max,
    is_memory64: self.is_memory64,
    is_shared: true,
    page_size_log2: self.page_size_log2,
    page_size_bytes: self.page_size_bytes,
  }
}
