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
  for i = 0; i < initial_size; i = i + 1 {
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
  for i = 0; i < 8; i = i + 1 {
    let byte_val = (value >> (i * 8)).land(0xFFL).to_int()
    self.store_byte(addr + i, byte_val.to_byte())
  }
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
  for i = 0; i < new_data_size; i = i + 1 {
    self.data.push(b'\x00')
  }
  self.size = new_size
  old_size
}
