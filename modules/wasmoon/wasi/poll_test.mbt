///|
test "native poll: null device is readable and invalid fd stays invalid" {
  guard @wasi.native_open_read("/dev/null") is Some(fd) else {
    fail("could not open /dev/null")
  }
  defer @wasi.native_close(fd) |> ignore
  guard @wasi.native_poll([fd], [1], 0) is Some(result) else {
    fail("poll failed")
  }
  inspect(result.ready_count, content="1")
  inspect(result.revents[0] & 1, content="1")
  inspect(result.revents[0] & 32, content="0")
  guard @wasi.native_poll([2147483647], [1], 0) is Some(invalid) else {
    fail("invalid fd must produce an event")
  }
  inspect(invalid.revents[0] & 32, content="32")
}
