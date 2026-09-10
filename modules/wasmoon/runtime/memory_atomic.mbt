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
  self.check_bounds_at(offset, width.to_int64())
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

///|
/// Register a wait without blocking the embedding thread. The returned owner
/// keeps the native shared memory live until cancellation or finalization.
pub fn Memory::atomic_wait_begin(
  self : Memory,
  offset : Int64,
  width : Int,
  expected : Int64,
  timeout : Int64,
) -> @wasmoon_jit.NativeAtomicWait raise RuntimeError {
  if width != 4 && width != 8 {
    raise Unreachable
  }
  let descriptor = self.checked_atomic_descriptor(offset, width)
  if !self.is_shared {
    raise AtomicWaitNonSharedMemory
  }
  match
    @wasmoon_jit.atomic_wait_begin(descriptor, offset, width, expected, timeout) {
    Some(waiter) => waiter
    None => raise OutOfMemory
  }
}

///|
pub fn Memory::atomic_notify(
  self : Memory,
  offset : Int64,
  count : UInt,
) -> UInt raise RuntimeError {
  @wasmoon_jit.atomic_notify(
    self.checked_atomic_descriptor(offset, 4),
    offset,
    count.reinterpret_as_int(),
  ).reinterpret_as_uint()
}
