///|
pub extern "c" fn c_socket_kind(fd : Int32) -> Int32 = "wasmoon_wasi_socket_kind"

///|
#borrow(buffer, truncated)
extern "c" fn raw_c_p1_recv(
  fd : Int32,
  buffer : FixedArray[Byte],
  length : Int32,
  flags : Int32,
  truncated : FixedArray[Int32],
) -> Int32 = "wasmoon_wasi_p1_recv"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_p1_recv(
  fd : Int32,
  buffer : FixedArray[Byte],
  length : Int32,
  flags : Int32,
  truncated : FixedArray[Int32],
) -> Int32 {
  if length < 0 || length > buffer.length() || truncated.length() < 1 {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_p1_recv(fd, buffer, length, flags, truncated)
}

///|
#borrow(buffer)
extern "c" fn raw_c_p1_send(
  fd : Int32,
  buffer : FixedArray[Byte],
  length : Int32,
) -> Int32 = "wasmoon_wasi_p1_send"

///|
/// Reject invalid buffer extents before entering the native ABI.
pub fn c_p1_send(
  fd : Int32,
  buffer : FixedArray[Byte],
  length : Int32,
) -> Int32 {
  if length < 0 || length > buffer.length() {
    c_set_errno_invalid_argument()
    return -1
  }
  raw_c_p1_send(fd, buffer, length)
}
