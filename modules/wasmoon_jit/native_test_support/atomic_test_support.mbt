///|
pub extern "c" fn atomic_counter_start(
  descriptor : Int64,
  width : Int,
  iterations : Int,
) -> Int64 = "wasmoon_test_atomic_counter_start"

///|
pub extern "c" fn atomic_counter_finish(worker : Int64, cancel : Int) -> Unit = "wasmoon_test_atomic_counter_finish"

///|
pub extern "c" fn memory_growth_start(
  descriptor : Int64,
  iterations : Int,
) -> Int64 = "wasmoon_test_memory_growth_start"

///|
pub extern "c" fn memory_growth_finish(worker : Int64, cancel : Int) -> Int64 = "wasmoon_test_memory_growth_finish"

///|
pub extern "c" fn atomic_notify_start(
  descriptor : Int64,
  offset : Int64,
) -> Int64 = "wasmoon_test_atomic_notify_start"

///|
pub extern "c" fn atomic_notify_finish(worker : Int64) -> Int = "wasmoon_test_atomic_notify_finish"

///|
pub extern "c" fn memory_owner_count(descriptor : Int64) -> Int64 = "wasmoon_test_memory_owner_count"
