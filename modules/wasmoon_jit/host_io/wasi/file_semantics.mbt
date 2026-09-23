///|
pub extern "c" fn c_allocate(fd : Int, offset : Int64, length : Int64) -> Int = "wasmoon_wasi_allocate"
