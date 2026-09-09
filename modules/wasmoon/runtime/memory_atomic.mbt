///|
pub(all) enum AtomicRmwOp {
  Add
  Sub
  And
  Or
  Xor
  Exchange
}

///|
fn Memory::checked_atomic_descriptor(
  self : Memory,
  offset : Int64,
  width : Int,
) -> Int64 raise RuntimeError {
  let descriptor = self.require_desc_ptr()
  if width != 1 && width != 2 && width != 4 && width != 8 {
    raise Unreachable
  }
  if offset % width.to_int64() != 0L {
    raise UnalignedAtomic
  }
  if offset < 0L || offset > self.byte_len() - width.to_int64() {
    raise OutOfBoundsMemoryAccess
  }
  descriptor
}

///|
pub fn Memory::atomic_load(
  self : Memory,
  offset : Int64,
  width : Int,
) -> Int64 raise RuntimeError {
  @wasmoon_jit.memory_atomic_load(
    self.checked_atomic_descriptor(offset, width),
    offset,
    width,
  )
}

///|
pub fn Memory::atomic_store(
  self : Memory,
  offset : Int64,
  width : Int,
  value : Int64,
) -> Unit raise RuntimeError {
  @wasmoon_jit.memory_atomic_store(
    self.checked_atomic_descriptor(offset, width),
    offset,
    width,
    value,
  )
}

///|
pub fn Memory::atomic_rmw(
  self : Memory,
  operation : AtomicRmwOp,
  offset : Int64,
  width : Int,
  value : Int64,
) -> Int64 raise RuntimeError {
  let code = match operation {
    Add => 0
    Sub => 1
    And => 2
    Or => 3
    Xor => 4
    Exchange => 5
  }
  @wasmoon_jit.memory_atomic_rmw(
    self.checked_atomic_descriptor(offset, width),
    offset,
    width,
    code,
    value,
  )
}

///|
pub fn Memory::atomic_compare_exchange(
  self : Memory,
  offset : Int64,
  width : Int,
  expected : Int64,
  replacement : Int64,
) -> Int64 raise RuntimeError {
  @wasmoon_jit.memory_atomic_compare_exchange(
    self.checked_atomic_descriptor(offset, width),
    offset,
    width,
    expected,
    replacement,
  )
}

///|
pub fn atomic_fence() -> Unit {
  @wasmoon_jit.atomic_fence()
}
