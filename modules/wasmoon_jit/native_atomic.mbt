///|
/// The descriptor must remain live; its offset, width and alignment must have
/// been checked by the linear-memory owner before entering these primitives.
#borrow(descriptor)
pub extern "c" fn memory_atomic_load(
  descriptor : MemoryDescriptor,
  offset : Int64,
  width : Int,
) -> Int64 = "wasmoon_memory_atomic_load"

///|
#borrow(descriptor)
pub extern "c" fn memory_atomic_store(
  descriptor : MemoryDescriptor,
  offset : Int64,
  width : Int,
  value : Int64,
) -> Unit = "wasmoon_memory_atomic_store"

///|
#borrow(descriptor)
pub extern "c" fn memory_atomic_rmw(
  descriptor : MemoryDescriptor,
  offset : Int64,
  width : Int,
  operation : Int,
  value : Int64,
) -> Int64 = "wasmoon_memory_atomic_rmw"

///|
#borrow(descriptor)
pub extern "c" fn memory_atomic_compare_exchange(
  descriptor : MemoryDescriptor,
  offset : Int64,
  width : Int,
  expected : Int64,
  replacement : Int64,
) -> Int64 = "wasmoon_memory_atomic_compare_exchange"

///|
pub extern "c" fn atomic_fence() -> Unit = "wasmoon_atomic_fence"
