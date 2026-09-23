///|
pub extern "c" fn c_socket_kind(fd : Int) -> Int = "wasmoon_wasi_socket_kind"

///|
#borrow(buffer, truncated)
extern "c" fn raw_c_p1_recv(
  fd : Int,
  buffer : FixedArray[Byte],
  length : Int,
  flags : Int,
  truncated : FixedArray[Int],
) -> Int = "wasmoon_wasi_p1_recv"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_p1_recv(
  fd : Int,
  buffer : FixedArray[Byte],
  length : Int,
  flags : Int,
  truncated : FixedArray[Int],
) -> Int {
  if length < 0 || length > buffer.length() || truncated.length() < 1 {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_p1_recv(fd, buffer, length, flags, truncated)
}

///|
#borrow(buffer)
extern "c" fn raw_c_p1_send(
  fd : Int,
  buffer : FixedArray[Byte],
  length : Int,
) -> Int = "wasmoon_wasi_p1_send"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_p1_send(fd : Int, buffer : FixedArray[Byte], length : Int) -> Int {
  if length < 0 || length > buffer.length() {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_p1_send(fd, buffer, length)
}
