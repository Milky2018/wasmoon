///|
pub extern "c" fn c_socket_kind(fd : Int) -> Int = "wasmoon_wasi_socket_kind"

///|
#borrow(buffer, truncated)
pub extern "c" fn c_p1_recv(
  fd : Int,
  buffer : FixedArray[Byte],
  length : Int,
  flags : Int,
  truncated : FixedArray[Int],
) -> Int = "wasmoon_wasi_p1_recv"

///|
#borrow(buffer)
pub extern "c" fn c_p1_send(
  fd : Int,
  buffer : FixedArray[Byte],
  length : Int,
) -> Int = "wasmoon_wasi_p1_send"
