///|
fn loopback_address() -> @wasi.NativeSocketAddress {
  {
    family: 4,
    address: [b'\x7f', b'\x00', b'\x00', b'\x01'],
    port: 0,
    scope_id: 0,
  }
}

///|
test "Preview 1 datagrams preserve message boundaries, peek and truncation" {
  let left = @wasi.native_socket_create(4, 2).unwrap()
  let right = @wasi.native_socket_create(4, 2).unwrap()
  assert_true(@wasi.native_socket_bind(left, loopback_address()))
  assert_true(@wasi.native_socket_bind(right, loopback_address()))
  inspect(
    @wasi.native_socket_connect(
      left,
      @wasi.native_socket_address(right, false).unwrap(),
    ),
    content="0",
  )
  inspect(
    @wasi.native_socket_connect(
      right,
      @wasi.native_socket_address(left, false).unwrap(),
    ),
    content="0",
  )
  let ctx = @wasi.WasiContextBuilder::WasiContextBuilder().build()
  let sender = ctx.take_socket(left).unwrap()
  let receiver = ctx.take_socket(right).unwrap()
  defer ctx.close_fd(sender) |> ignore
  defer ctx.close_fd(receiver) |> ignore
  let store = @runtime.Store::Store()
  defer store.close()
  let mem = @runtime.Memory::Memory(1, None)
  store.alloc_mem(mem) |> ignore
  mem.write_i32(0, 100)
  mem.write_i32(4, 2)
  mem.write_i32(8, 120)
  mem.write_i32(12, 3)
  for i, byte in b"ab" {
    mem.write_byte(100 + i, byte)
  }
  for i, byte in b"cde" {
    mem.write_byte(120 + i, byte)
  }
  inspect(@wasi.sock_send_impl(ctx, mem, sender, 0, 2, 0, 200), content="0")
  inspect(mem.read_i32(200), content="5")
  assert_true(@wasi.native_poll([right], [1], 1000).unwrap().ready_count > 0)
  mem.write_i32(12, 1)
  inspect(
    @wasi.sock_recv_impl(ctx, mem, receiver, 0, 2, 1, 200, 204),
    content="0",
  )
  inspect(mem.read_i32(200), content="3")
  inspect(mem.read_byte(204).to_int(), content="1")
  inspect(mem.read_bytes(100, 2), content="b\"ab\"")
  inspect(mem.read_byte(120) == b'c', content="true")
  inspect(
    @wasi.sock_recv_impl(ctx, mem, receiver, 65535, 1, 0, 200, 204),
    content="21",
  )
  inspect(
    @wasi.sock_recv_impl(ctx, mem, receiver, 0, 2, 4, 200, 204),
    content="28",
  )
  mem.write_i32(12, 3)
  inspect(
    @wasi.sock_recv_impl(ctx, mem, receiver, 0, 2, 0, 200, 204),
    content="0",
  )
  inspect(mem.read_i32(200), content="5")
  inspect(mem.read_byte(204).to_int(), content="0")
  inspect(mem.read_bytes(120, 3), content="b\"cde\"")
  inspect(
    @wasi.sock_recv_impl(ctx, mem, receiver, 0, 2, 0, 200, 204),
    content="6",
  )
  inspect(@wasi.sock_send_impl(ctx, mem, sender, 0, 0, 0, 200), content="0")
  assert_true(@wasi.native_poll([right], [1], 1000).unwrap().ready_count > 0)
  inspect(
    @wasi.sock_recv_impl(ctx, mem, receiver, 0, 2, 0, 200, 204),
    content="0",
  )
  inspect(mem.read_i32(200), content="0")
  inspect(@wasi.fd_fdstat_get(ctx, mem, receiver, 300), content="0")
  inspect(mem.read_byte(300).to_int(), content="5")
  inspect(@wasi.fd_filestat_get_impl(ctx, mem, receiver, 300), content="0")
  inspect(mem.read_byte(316).to_int(), content="5")
  inspect(@wasi.fd_fdstat_set_rights_impl(ctx, sender, 0L, 0L), content="0")
  inspect(@wasi.sock_send_impl(ctx, mem, sender, 0, 2, 0, 200), content="76")
}

///|
test "Preview 1 accepts streams with independent flags, waitall, EOF and rights" {
  let listener = @wasi.native_socket_create(4, 1).unwrap()
  assert_true(@wasi.native_socket_bind(listener, loopback_address()))
  assert_true(@wasi.native_socket_listen(listener, 1))
  let client = @wasi.native_socket_create(4, 1).unwrap()
  assert_true(
    @wasi.native_fcntl_setfl(
      client,
      @wasi.native_fcntl_getfl(client).unwrap() &
      @wasi.native_o_nonblock().lnot(),
    ),
  )
  inspect(
    @wasi.native_socket_connect(
      client,
      @wasi.native_socket_address(listener, false).unwrap(),
    ),
    content="0",
  )
  let ctx = @wasi.WasiContextBuilder::WasiContextBuilder().build()
  let listening_fd = ctx
    .take_socket(listener, rights_inheriting=0x10000042L)
    .unwrap()
  let sending_fd = ctx.take_socket(client).unwrap()
  defer ctx.close_fd(listening_fd) |> ignore
  defer ctx.close_fd(sending_fd) |> ignore
  let store = @runtime.Store::Store()
  defer store.close()
  let mem = @runtime.Memory::Memory(1, None)
  store.alloc_mem(mem) |> ignore
  assert_true(@wasi.native_poll([listener], [1], 1000).unwrap().ready_count > 0)
  inspect(@wasi.sock_accept_impl(ctx, mem, listening_fd, 16, 100), content="28")
  inspect(@wasi.sock_accept_impl(ctx, mem, listening_fd, 0, 100), content="0")
  let accepted = mem.read_i32(100)
  defer ctx.close_fd(accepted) |> ignore
  inspect(ctx.get_file(accepted).unwrap().flags, content="0")
  inspect(ctx.get_file(accepted).unwrap().rights_base, content="268435522")
  inspect(@wasi.fd_fdstat_set_flags_impl(ctx, accepted, 4), content="76")
  mem.write_i32(0, 200)
  mem.write_i32(4, 5)
  for i, byte in b"hello" {
    mem.write_byte(200 + i, byte)
  }
  inspect(
    @wasi.sock_send_impl(ctx, mem, sending_fd, 0, 1, 1, 100),
    content="28",
  )
  inspect(@wasi.sock_send_impl(ctx, mem, sending_fd, 0, 1, 0, 100), content="0")
  inspect(
    @wasi.sock_recv_impl(ctx, mem, accepted, 0, 1, 3, 100, 104),
    content="0",
  )
  inspect(mem.read_i32(100), content="5")
  inspect(
    @wasi.sock_recv_impl(ctx, mem, accepted, 0, 1, 2, 100, 104),
    content="0",
  )
  inspect(mem.read_bytes(200, 5), content="b\"hello\"")
  inspect(@wasi.sock_shutdown_impl(ctx, sending_fd, 2), content="0")
  inspect(
    @wasi.sock_recv_impl(ctx, mem, accepted, 0, 1, 0, 100, 104),
    content="0",
  )
  inspect(mem.read_i32(100), content="0")
  inspect(@wasi.sock_shutdown_impl(ctx, accepted, 0), content="28")
  // Darwin may already report ENOTCONN after receiving the peer FIN.
  assert_true([0, 53].contains(@wasi.sock_shutdown_impl(ctx, accepted, 3)))
  inspect(ctx.close_fd(accepted), content="true")
  inspect(
    @wasi.sock_recv_impl(ctx, mem, accepted, 0, 1, 0, 100, 104),
    content="8",
  )
}
