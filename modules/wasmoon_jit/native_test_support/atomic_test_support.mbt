///|
pub extern "c" fn atomic_counter_start(
  descriptor : Int64,
  width : Int,
  iterations : Int,
) -> Int64 = "wasmoon_test_atomic_counter_start"

///|
pub extern "c" fn atomic_counter_finish(worker : Int64, cancel : Int) -> Unit = "wasmoon_test_atomic_counter_finish"
