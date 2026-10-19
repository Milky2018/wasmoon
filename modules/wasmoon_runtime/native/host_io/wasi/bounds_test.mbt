///|
test "native buffer bounds reject negative and oversized counts" {
  let buffer : FixedArray[Byte] = [b'x']
  for count in [-1, 2] {
    inspect(@wasi.c_read(-1, buffer, count), content="-1")
    inspect(@wasi.c_errno_to_wasi(@wasi.c_get_errno()), content="28")
    inspect(@wasi.c_write(-1, buffer, count), content="-1")
    inspect(@wasi.c_errno_to_wasi(@wasi.c_get_errno()), content="28")
    inspect(@wasi.c_pread(-1, buffer, count, 0L), content="-1")
    inspect(@wasi.c_errno_to_wasi(@wasi.c_get_errno()), content="28")
    inspect(@wasi.c_pwrite(-1, buffer, count, 0L), content="-1")
    inspect(@wasi.c_errno_to_wasi(@wasi.c_get_errno()), content="28")
    inspect(@wasi.c_getrandom(buffer, count), content="-1")
    inspect(@wasi.c_errno_to_wasi(@wasi.c_get_errno()), content="28")
    inspect(@wasi.c_send(-1, buffer, count.to_int64(), 0), content="-1")
    inspect(@wasi.c_errno_to_wasi(@wasi.c_get_errno()), content="28")
    inspect(@wasi.c_recv(-1, buffer, count.to_int64(), 0), content="-1")
    inspect(@wasi.c_errno_to_wasi(@wasi.c_get_errno()), content="28")
  }
  inspect(buffer[0].to_int(), content="120")
}

///|
test "native polling rejects mismatched parallel arrays" {
  inspect(@wasi.c_poll([0], [], [0], 1, 0), content="-1")
  inspect(@wasi.c_errno_to_wasi(@wasi.c_get_errno()), content="28")
  inspect(@wasi.c_poll([], [], [], -1, 0), content="-1")
  inspect(@wasi.c_errno_to_wasi(@wasi.c_get_errno()), content="28")
}

///|
test "native output buffers are checked before descriptor access" {
  inspect(@wasi.c_socket_address_get(-1, 0, [], [], [], []), content="-1")
  inspect(@wasi.c_errno_to_wasi(@wasi.c_get_errno()), content="28")
  inspect(@wasi.c_p1_recv(-1, [], 0, 0, []), content="-1")
  inspect(@wasi.c_errno_to_wasi(@wasi.c_get_errno()), content="28")
  inspect(@wasi.c_fstat(-1, [], [], [], [], [], [], [], []), content="-1")
  inspect(@wasi.c_errno_to_wasi(@wasi.c_get_errno()), content="28")
}
