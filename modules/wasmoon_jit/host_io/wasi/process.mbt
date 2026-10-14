///|
pub extern "c" fn c_cpu_clock(thread : Bool, resolution : Bool) -> Int64 = "wasmoon_wasi_cpu_clock"

///|
pub extern "c" fn c_yield() -> Int32 = "wasmoon_wasi_yield"

///|
pub extern "c" fn c_raise_signal(signal : Int32) -> Int32 = "wasmoon_wasi_raise_signal"
