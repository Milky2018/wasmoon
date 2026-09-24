///|
#borrow(descriptor)
pub extern "c" fn atomic_counter_start(
  descriptor : @jit_ffi.MemoryDescriptor,
  width : Int,
  iterations : Int,
) -> Int64 = "wasmoon_test_atomic_counter_start"

///|
pub extern "c" fn atomic_counter_finish(worker : Int64, cancel : Int) -> Unit = "wasmoon_test_atomic_counter_finish"

///|
#borrow(descriptor)
pub extern "c" fn memory_growth_start(
  descriptor : @jit_ffi.MemoryDescriptor,
  iterations : Int,
) -> Int64 = "wasmoon_test_memory_growth_start"

///|
pub extern "c" fn memory_growth_finish(worker : Int64, cancel : Int) -> Int64 = "wasmoon_test_memory_growth_finish"

///|
#borrow(descriptor)
pub extern "c" fn atomic_notify_start(
  descriptor : @jit_ffi.MemoryDescriptor,
  offset : Int64,
) -> Int64 = "wasmoon_test_atomic_notify_start"

///|
pub extern "c" fn atomic_notify_finish(worker : Int64) -> Int = "wasmoon_test_atomic_notify_finish"

///|
pub extern "c" fn sparse_table(count : Int) -> @jit_ffi.NativeTableHandle = "wasmoon_test_sparse_table"
