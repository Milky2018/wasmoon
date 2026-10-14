///|
pub extern "c" fn c_allocate(
  fd : Int32,
  offset : Int64,
  length : Int64,
) -> Int32 = "wasmoon_wasi_allocate"
