///|
test "resolver managed handle closes repeatedly and rejects later reads" {
  // Deliberately omit the C terminator: the public wrapper supplies it.
  let (resolver, fd) = @wasi.c_resolver_start([
    b'1', b'2', b'7', b'.', b'0', b'.', b'0', b'.', b'1',
  ])
  assert_true(fd >= 0)
  defer @wasi.c_resolver_drop(resolver)
  let events : FixedArray[Int] = [0]
  assert_eq(@wasi.c_poll([fd], [1], events, 1, 5000), 1)
  let family = FixedArray::make(1, b'\x00')
  let address = FixedArray::make(16, b'\x00')
  let scope = FixedArray::make(1, 0U)
  assert_eq(@wasi.c_resolver_next(resolver, family, address, scope), 0)
  inspect(family[0].to_int(), content="4")
  inspect(address[0].to_int(), content="127")
  @wasi.c_resolver_drop(resolver)
  @wasi.c_resolver_drop(resolver)
  inspect(@wasi.c_resolver_next(resolver, family, address, scope), content="5")
}

///|
test "resolver notification integrates with the native reactor" {
  let (resolver, fd) = @wasi.c_resolver_start([
    b'1', b'2', b'7', b'.', b'0', b'.', b'0', b'.', b'1',
  ])
  assert_true(fd >= 0)
  defer @wasi.c_resolver_drop(resolver)
  let reactor = @reactor.NativeReactor::try_new()
  defer reactor.close()
  let registration = reactor.register_read(fd)
  defer registration.cancel()
  reactor.wait(Some(5000000000L)) |> ignore
  assert_true(registration.is_ready())
  let family = FixedArray::make(1, b'\x00')
  let address = FixedArray::make(16, b'\x00')
  let scope = FixedArray::make(1, 0U)
  assert_eq(@wasi.c_resolver_next(resolver, family, address, scope), 0)
}
