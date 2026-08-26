///|
priv struct ComponentSocketAddress {
  native : @wasi.NativeSocketAddress
  loopback : Bool
}

///|
fn socket_ok_void() -> @runtime_impl.ComponentValue {
  Variant(0, None)
}

///|
fn socket_ok(
  value : @runtime_impl.ComponentValue,
) -> @runtime_impl.ComponentValue {
  Variant(0, Some(value))
}

///|
fn socket_error_code(index : Int) -> @runtime_impl.ComponentValue {
  Variant(1, Some(Variant(index, None)))
}

///|
fn socket_error_index(preview1_errno : Int) -> Int {
  match preview1_errno {
    2 | 63 => 1
    58 => 2
    5 | 28 => 3
    42 | 48 => 4
    73 => 5
    7 => 6
    6 | 26 => 8
    30 | 53 | 57 => 9
    33 | 41 => 10
    4 => 11
    3 => 12
    23 | 24 | 38 | 39 | 40 => 13
    14 => 14
    15 => 15
    13 => 16
    35 => 17
    _ => 0
  }
}

///|
fn socket_last_error() -> @runtime_impl.ComponentValue {
  socket_error_code(socket_error_index(@wasi.native_last_errno_to_wasi()))
}

///|
fn socket_native_error(errno : Int) -> @runtime_impl.ComponentValue {
  socket_error_code(socket_error_index(@wasi.native_errno_to_wasi(errno)))
}

///|
fn socket_family_arg(
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  if index < 0 || index >= args.length() {
    raise HostCallError("missing socket address family")
  }
  match args[index] {
    Variant(0, None) => 4
    Variant(1, None) => 6
    _ => raise HostCallError("expected socket address family")
  }
}

///|
fn decode_ipv4_tuple(value : @runtime_impl.ComponentValue) -> FixedArray[Byte]? {
  match value {
    Tuple([U8(a), U8(b), U8(c), U8(d)]) if a >= 0 &&
      a <= 255 &&
      b >= 0 &&
      b <= 255 &&
      c >= 0 &&
      c <= 255 &&
      d >= 0 &&
      d <= 255 =>
      Some(
        FixedArray::from_array([
          a.to_byte(),
          b.to_byte(),
          c.to_byte(),
          d.to_byte(),
        ]),
      )
    _ => None
  }
}

///|
fn decode_ipv6_tuple(value : @runtime_impl.ComponentValue) -> FixedArray[Byte]? {
  match value {
    Tuple([U16(a), U16(b), U16(c), U16(d), U16(e), U16(f), U16(g), U16(h)]) => {
      let words = [a, b, c, d, e, f, g, h]
      let bytes = FixedArray::make(16, b'\x00')
      for i, word in words {
        if word < 0 || word > 65535 {
          return None
        }
        bytes[i * 2] = ((word >> 8) & 0xff).to_byte()
        bytes[i * 2 + 1] = (word & 0xff).to_byte()
      }
      Some(bytes)
    }
    _ => None
  }
}

///|
fn decode_socket_address(
  value : @runtime_impl.ComponentValue,
) -> ComponentSocketAddress? {
  match value {
    Variant(0, Some(Tuple([U16(port), address]))) =>
      match decode_ipv4_tuple(address) {
        Some(bytes) =>
          if port < 0 || port > 65535 {
            None
          } else {
            Some({
              native: { family: 4, address: bytes, port, scope_id: 0, },
              loopback: bytes[0] == b'\x7f',
            })
          }
        None => None
      }
    Variant(
      1,
      Some(Tuple([U16(port), U32(_flow_info), address, U32(scope_id)]))
    ) =>
      match decode_ipv6_tuple(address) {
        Some(bytes) =>
          if port < 0 || port > 65535 || scope_id < 0 {
            None
          } else {
            let mut loopback = bytes[15] == b'\x01'
            for i in 0..<15 {
              if bytes[i] != b'\x00' {
                loopback = false
              }
            }
            Some({
              native: { family: 6, address: bytes, port, scope_id, },
              loopback,
            })
          }
        None => None
      }
    _ => None
  }
}

///|
fn encode_socket_address(
  address : @wasi.NativeSocketAddress,
) -> @runtime_impl.ComponentValue {
  if address.family == 4 {
    Variant(
      0,
      Some(
        Tuple([
          U16(address.port),
          Tuple([
            U8(address.address[0].to_int()),
            U8(address.address[1].to_int()),
            U8(address.address[2].to_int()),
            U8(address.address[3].to_int()),
          ]),
        ]),
      ),
    )
  } else {
    let words : Array[@runtime_impl.ComponentValue] = []
    for i in 0..<8 {
      words.push(
        U16(
          (address.address[i * 2].to_int() << 8) |
          address.address[i * 2 + 1].to_int(),
        ),
      )
    }
    Variant(
      1,
      Some(
        Tuple([U16(address.port), U32(0), Tuple(words), U32(address.scope_id)]),
      ),
    )
  }
}

///|
fn network_policy_for(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> WasiNetworkPolicy raise @runtime_impl.ComponentRuntimeError {
  let network_type = host.resolve_resource_type(
    "wasi:sockets@0.2.11/network.network",
  )
  let rep = resource_rep(table, resource_handle_arg(args, index), network_type)
  match host.ctx.get_resource(rep) {
    Some(Network(policy)) => policy
    _ => raise HostCallError("network capability is not live")
  }
}

///|
fn network_allows(
  policy : WasiNetworkPolicy,
  address : ComponentSocketAddress,
) -> Bool {
  match policy {
    DenyAll => false
    LoopbackOnly => address.loopback
    AllowAll => true
  }
}

///|
fn tcp_socket_state(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> TcpSocketState raise @runtime_impl.ComponentRuntimeError {
  let socket_type = host.resolve_resource_type(
    "wasi:sockets@0.2.11/tcp.tcp-socket",
  )
  let rep = resource_rep(table, resource_handle_arg(args, index), socket_type)
  match host.ctx.get_resource(rep) {
    Some(TcpSocket(state)) if !state.closed.val => state
    _ => raise HostCallError("TCP socket is not live")
  }
}

///|
fn new_tcp_socket_handle(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  fd : Int,
  family : Int,
  phase : TcpSocketPhase,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  let rep = host.ctx.insert_resource(
    TcpSocket({
      fd,
      family,
      phase: Ref(phase),
      backlog: Ref(128),
      closed: Ref(false),
    }),
  )
  allocate_resource_handle(
    host.ctx,
    table,
    host.resolve_resource_type("wasi:sockets@0.2.11/tcp.tcp-socket"),
    rep,
  )
}

///|
fn tcp_streams(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  fd : Int,
) -> (Int, Int)? raise @runtime_impl.ComponentRuntimeError {
  match (@wasi.native_dup(fd), @wasi.native_dup(fd)) {
    (Some(input_fd), Some(output_fd)) => {
      let input_rep = host.ctx.insert_resource(
        InputStream({
          bytes: Ref(b""),
          offset: Ref(0),
          native_fd: Some(input_fd),
          file_position: None,
          owns_fd: true,
          closed: Ref(false),
        }),
      )
      let output_rep = host.ctx.insert_resource(
        OutputStream({
          write: fn(_bytes) { true },
          native_fd: Some(output_fd),
          file_position: None,
          append: false,
          owns_fd: true,
          permit: Ref(0L),
          pending: Ref(None),
          failure: Ref(None),
          closed: Ref(false),
        }),
      )
      Some(
        (
          allocate_resource_handle(
            host.ctx,
            table,
            host.resource_types.input_stream,
            input_rep,
          ),
          allocate_resource_handle(
            host.ctx,
            table,
            host.resource_types.output_stream,
            output_rep,
          ),
        ),
      )
    }
    (Some(input_fd), None) => {
      @wasi.native_close(input_fd) |> ignore
      None
    }
    (None, Some(output_fd)) => {
      @wasi.native_close(output_fd) |> ignore
      None
    }
    _ => None
  }
}

///|
fn add_preview2_network_interfaces(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let network_interface = "wasi:sockets@0.2.11/network"
  let network_builder = host.linker.host_instance_builder(
    "wasi:sockets/network@\{preview2_version}",
    host.runtime,
  )
  host.prepare_preview2_interface(network_builder, network_interface)
  host.linker.add_instance(
    "wasi:sockets/network@\{preview2_version}",
    network_builder.finish(),
  )
  let instance_interface = "wasi:sockets@0.2.11/instance-network"
  let instance_builder = host.linker.host_instance_builder(
    "wasi:sockets/instance-network@\{preview2_version}",
    host.runtime,
  )
  host.prepare_preview2_interface(instance_builder, instance_interface)
  instance_builder.add_func(
    "instance-network",
    preview2_func(instance_interface, "instance-network"),
    (_args, table) => {
      let rep = host.ctx.clone_resource(host.ctx.network_rep)
      [
        U32(
          allocate_resource_handle(
            host.ctx,
            table,
            host.resolve_resource_type("wasi:sockets@0.2.11/network.network"),
            rep,
          ),
        ),
      ]
    },
  )
  host.linker.add_instance(
    "wasi:sockets/instance-network@\{preview2_version}",
    instance_builder.finish(),
  )
}

///|
fn add_preview2_tcp_create(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.2.11/tcp-create-socket"
  let builder = host.linker.host_instance_builder(
    "wasi:sockets/tcp-create-socket@\{preview2_version}",
    host.runtime,
  )
  host.prepare_preview2_interface(builder, interface)
  builder.add_func(
    "create-tcp-socket",
    preview2_func(interface, "create-tcp-socket"),
    (args, table) => {
      let family = socket_family_arg(args, 0)
      match @wasi.native_socket_create(family, 1) {
        Some(fd) =>
          [
            socket_ok(
              U32(new_tcp_socket_handle(host, table, fd, family, Unbound)),
            ),
          ]
        None => [socket_last_error()]
      }
    },
  )
  host.linker.add_instance(
    "wasi:sockets/tcp-create-socket@\{preview2_version}",
    builder.finish(),
  )
}

///|
fn socket_u64_arg(
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> Int64 raise @runtime_impl.ComponentRuntimeError {
  if index < 0 || index >= args.length() {
    raise HostCallError("missing socket integer")
  }
  match args[index] {
    U64(value) => value
    _ => raise HostCallError("expected socket u64")
  }
}

///|
fn socket_u32_arg(
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  if index < 0 || index >= args.length() {
    raise HostCallError("missing socket integer")
  }
  match args[index] {
    U32(value) => value
    _ => raise HostCallError("expected socket u32")
  }
}

///|
fn add_tcp_state_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.2.11/tcp"
  builder.add_func(
    "[method]tcp-socket.start-bind",
    preview2_func(interface, "[method]tcp-socket.start-bind"),
    (args, table) => {
      let state = tcp_socket_state(host, table, args, 0)
      let policy = network_policy_for(host, table, args, 1)
      guard decode_socket_address(args[2]) is Some(address) else {
        return [socket_error_code(3)]
      }
      if state.phase.val != Unbound {
        return [socket_error_code(9)]
      }
      if address.native.family != state.family {
        return [socket_error_code(3)]
      }
      if !network_allows(policy, address) {
        return [socket_error_code(1)]
      }
      @wasi.native_socket_option_set(state.fd, state.family, 7, 1) |> ignore
      if @wasi.native_socket_bind(state.fd, address.native) {
        state.phase.val = BindStarted
        [socket_ok_void()]
      } else {
        [socket_last_error()]
      }
    },
  )
  builder.add_func(
    "[method]tcp-socket.finish-bind",
    preview2_func(interface, "[method]tcp-socket.finish-bind"),
    (args, table) => {
      let state = tcp_socket_state(host, table, args, 0)
      if state.phase.val == BindStarted {
        state.phase.val = Bound
        [socket_ok_void()]
      } else {
        [socket_error_code(7)]
      }
    },
  )
  builder.add_func(
    "[method]tcp-socket.start-connect",
    preview2_func(interface, "[method]tcp-socket.start-connect"),
    (args, table) => {
      let state = tcp_socket_state(host, table, args, 0)
      let policy = network_policy_for(host, table, args, 1)
      guard decode_socket_address(args[2]) is Some(address) else {
        return [socket_error_code(3)]
      }
      if state.phase.val != Unbound && state.phase.val != Bound {
        return [socket_error_code(9)]
      }
      if address.native.family != state.family {
        return [socket_error_code(3)]
      }
      if !network_allows(policy, address) {
        return [socket_error_code(1)]
      }
      let result = @wasi.native_socket_connect(state.fd, address.native)
      if result == 0 || result == 1 {
        state.phase.val = ConnectStarted
        [socket_ok_void()]
      } else {
        state.phase.val = Closed
        state.closed.val = true
        @wasi.native_close(state.fd) |> ignore
        [socket_last_error()]
      }
    },
  )
  builder.add_func(
    "[method]tcp-socket.finish-connect",
    preview2_func(interface, "[method]tcp-socket.finish-connect"),
    (args, table) => {
      let state = tcp_socket_state(host, table, args, 0)
      if state.phase.val != ConnectStarted {
        return [socket_error_code(7)]
      }
      match @wasi.native_poll([state.fd], [0x04], 0) {
        Some(result) if result.ready_count == 0 => [socket_error_code(8)]
        Some(_) =>
          match @wasi.native_socket_error(state.fd) {
            Some(0) =>
              match tcp_streams(host, table, state.fd) {
                Some((input, output)) => {
                  state.phase.val = Connected
                  [socket_ok(Tuple([U32(input), U32(output)]))]
                }
                None => [socket_error_code(4)]
              }
            Some(error) => {
              state.phase.val = Closed
              state.closed.val = true
              @wasi.native_close(state.fd) |> ignore
              [socket_native_error(error)]
            }
            None => [socket_last_error()]
          }
        None => [socket_last_error()]
      }
    },
  )
  builder.add_func(
    "[method]tcp-socket.start-listen",
    preview2_func(interface, "[method]tcp-socket.start-listen"),
    (args, table) => {
      let state = tcp_socket_state(host, table, args, 0)
      if state.phase.val != Bound {
        return [socket_error_code(9)]
      }
      if @wasi.native_socket_listen(state.fd, state.backlog.val) {
        state.phase.val = ListenStarted
        [socket_ok_void()]
      } else {
        [socket_last_error()]
      }
    },
  )
  builder.add_func(
    "[method]tcp-socket.finish-listen",
    preview2_func(interface, "[method]tcp-socket.finish-listen"),
    (args, table) => {
      let state = tcp_socket_state(host, table, args, 0)
      if state.phase.val == ListenStarted {
        state.phase.val = Listening
        [socket_ok_void()]
      } else {
        [socket_error_code(7)]
      }
    },
  )
  builder.add_func(
    "[method]tcp-socket.accept",
    preview2_func(interface, "[method]tcp-socket.accept"),
    (args, table) => {
      let state = tcp_socket_state(host, table, args, 0)
      if state.phase.val != Listening {
        return [socket_error_code(9)]
      }
      let fd = @wasi.native_accept(state.fd)
      if fd < 0 {
        return [socket_last_error()]
      }
      match tcp_streams(host, table, fd) {
        Some((input, output)) => {
          let socket = new_tcp_socket_handle(
            host,
            table,
            fd,
            state.family,
            Connected,
          )
          [socket_ok(Tuple([U32(socket), U32(input), U32(output)]))]
        }
        None => {
          @wasi.native_close(fd) |> ignore
          [socket_error_code(4)]
        }
      }
    },
  )
}

///|
fn add_tcp_address_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.2.11/tcp"
  fn address(
    args : Array[@runtime_impl.ComponentValue],
    table : @runtime_impl.ResourceTable,
    peer : Bool,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    let state = tcp_socket_state(host, table, args, 0)
    match @wasi.native_socket_address(state.fd, peer) {
      Some(address) => [socket_ok(encode_socket_address(address))]
      None => [socket_last_error()]
    }
  }

  builder.add_func(
    "[method]tcp-socket.local-address",
    preview2_func(interface, "[method]tcp-socket.local-address"),
    (args, table) => address(args, table, false),
  )
  builder.add_func(
    "[method]tcp-socket.remote-address",
    preview2_func(interface, "[method]tcp-socket.remote-address"),
    (args, table) => address(args, table, true),
  )
  builder.add_func(
    "[method]tcp-socket.is-listening",
    preview2_func(interface, "[method]tcp-socket.is-listening"),
    (args, table) => {
      [Bool(tcp_socket_state(host, table, args, 0).phase.val == Listening)]
    },
  )
  builder.add_func(
    "[method]tcp-socket.address-family",
    preview2_func(interface, "[method]tcp-socket.address-family"),
    (args, table) => {
      [
        Variant(
          if tcp_socket_state(host, table, args, 0).family == 4 {
            0
          } else {
            1
          },
          None,
        ),
      ]
    },
  )
  builder.add_func(
    "[method]tcp-socket.set-listen-backlog-size",
    preview2_func(interface, "[method]tcp-socket.set-listen-backlog-size"),
    (args, table) => {
      let state = tcp_socket_state(host, table, args, 0)
      let value = socket_u64_arg(args, 1)
      if value <= 0L || value > 0x7fffffffL {
        [socket_error_code(3)]
      } else if state.phase.val == Listening ||
        state.phase.val == Connected ||
        state.phase.val == ConnectStarted {
        [socket_error_code(9)]
      } else {
        state.backlog.val = value.to_int()
        [socket_ok_void()]
      }
    },
  )
}

///|
fn socket_option_result(
  state : TcpSocketState,
  option : Int,
  transform : (Int) -> @runtime_impl.ComponentValue,
) -> @runtime_impl.ComponentValue {
  match @wasi.native_socket_option_get(state.fd, state.family, option) {
    Some(value) => socket_ok(transform(value))
    None => socket_last_error()
  }
}

///|
fn set_socket_option_result(
  state : TcpSocketState,
  option : Int,
  value : Int,
) -> @runtime_impl.ComponentValue {
  if @wasi.native_socket_option_set(state.fd, state.family, option, value) {
    socket_ok_void()
  } else {
    socket_last_error()
  }
}

///|
fn duration_seconds(value : Int64) -> Int? {
  if value < 0L {
    None
  } else {
    let seconds = if value == 0L {
      0L
    } else {
      (value - 1L) / 1_000_000_000L + 1L
    }
    if seconds > 0x7fffffffL {
      None
    } else {
      Some(seconds.to_int())
    }
  }
}

///|
fn add_tcp_option_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.2.11/tcp"
  builder.add_func(
    "[method]tcp-socket.keep-alive-enabled",
    preview2_func(interface, "[method]tcp-socket.keep-alive-enabled"),
    (args, table) => {
      [
        socket_option_result(tcp_socket_state(host, table, args, 0), 0, value => {
          Bool(value != 0)
        }),
      ]
    },
  )
  builder.add_func(
    "[method]tcp-socket.set-keep-alive-enabled",
    preview2_func(interface, "[method]tcp-socket.set-keep-alive-enabled"),
    (args, table) => {
      guard args[1] is Bool(enabled) else {
        raise HostCallError("expected keep-alive boolean")
      }
      [
        set_socket_option_result(
          tcp_socket_state(host, table, args, 0),
          0,
          if enabled {
            1
          } else {
            0
          },
        ),
      ]
    },
  )
  fn add_duration_option(
    getter : String,
    setter : String,
    option : Int,
  ) -> Unit raise @runtime_impl.ComponentRuntimeError {
    builder.add_func(getter, preview2_func(interface, getter), (args, table) => {
      [
        socket_option_result(tcp_socket_state(host, table, args, 0), option, value => {
          U64(value.to_int64() * 1_000_000_000L)
        }),
      ]
    })
    builder.add_func(setter, preview2_func(interface, setter), (args, table) => {
      match duration_seconds(socket_u64_arg(args, 1)) {
        Some(value) =>
          [
            set_socket_option_result(
              tcp_socket_state(host, table, args, 0),
              option,
              value,
            ),
          ]
        None => [socket_error_code(3)]
      }
    })
  }

  add_duration_option(
    "[method]tcp-socket.keep-alive-idle-time", "[method]tcp-socket.set-keep-alive-idle-time",
    1,
  )
  add_duration_option(
    "[method]tcp-socket.keep-alive-interval", "[method]tcp-socket.set-keep-alive-interval",
    2,
  )
  builder.add_func(
    "[method]tcp-socket.keep-alive-count",
    preview2_func(interface, "[method]tcp-socket.keep-alive-count"),
    (args, table) => {
      [
        socket_option_result(tcp_socket_state(host, table, args, 0), 3, value => {
          U32(value)
        }),
      ]
    },
  )
  builder.add_func(
    "[method]tcp-socket.set-keep-alive-count",
    preview2_func(interface, "[method]tcp-socket.set-keep-alive-count"),
    (args, table) => {
      let value = socket_u32_arg(args, 1)
      [
        if value <= 0 {
          socket_error_code(3)
        } else {
          set_socket_option_result(
            tcp_socket_state(host, table, args, 0),
            3,
            value,
          )
        },
      ]
    },
  )
  builder.add_func(
    "[method]tcp-socket.hop-limit",
    preview2_func(interface, "[method]tcp-socket.hop-limit"),
    (args, table) => {
      [
        socket_option_result(tcp_socket_state(host, table, args, 0), 4, value => {
          U8(value)
        }),
      ]
    },
  )
  builder.add_func(
    "[method]tcp-socket.set-hop-limit",
    preview2_func(interface, "[method]tcp-socket.set-hop-limit"),
    (args, table) => {
      guard args[1] is U8(value) else {
        raise HostCallError("expected hop limit")
      }
      [
        if value <= 0 || value > 255 {
          socket_error_code(3)
        } else {
          set_socket_option_result(
            tcp_socket_state(host, table, args, 0),
            4,
            value,
          )
        },
      ]
    },
  )
  fn add_buffer_option(
    getter : String,
    setter : String,
    option : Int,
  ) -> Unit raise @runtime_impl.ComponentRuntimeError {
    builder.add_func(getter, preview2_func(interface, getter), (args, table) => {
      [
        socket_option_result(tcp_socket_state(host, table, args, 0), option, value => {
          U64(value.to_int64())
        }),
      ]
    })
    builder.add_func(setter, preview2_func(interface, setter), (args, table) => {
      let value = socket_u64_arg(args, 1)
      [
        if value <= 0L || value > 0x7fffffffL {
          socket_error_code(3)
        } else {
          set_socket_option_result(
            tcp_socket_state(host, table, args, 0),
            option,
            value.to_int(),
          )
        },
      ]
    })
  }

  add_buffer_option(
    "[method]tcp-socket.receive-buffer-size", "[method]tcp-socket.set-receive-buffer-size",
    5,
  )
  add_buffer_option(
    "[method]tcp-socket.send-buffer-size", "[method]tcp-socket.set-send-buffer-size",
    6,
  )
}

///|
fn add_tcp_poll_shutdown_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.2.11/tcp"
  builder.add_func(
    "[method]tcp-socket.subscribe",
    preview2_func(interface, "[method]tcp-socket.subscribe"),
    (args, table) => {
      let state = tcp_socket_state(host, table, args, 0)
      let events = match state.phase.val {
        Listening => 0x01
        ConnectStarted => 0x04
        Connected => 0x05
        _ => 0x05
      }
      let rep = host.ctx.insert_resource(Pollable(Socket(state.fd, events)))
      [
        U32(
          allocate_resource_handle(
            host.ctx,
            table,
            host.resource_types.pollable,
            rep,
          ),
        ),
      ]
    },
  )
  builder.add_func(
    "[method]tcp-socket.shutdown",
    preview2_func(interface, "[method]tcp-socket.shutdown"),
    (args, table) => {
      let state = tcp_socket_state(host, table, args, 0)
      if state.phase.val != Connected {
        return [socket_error_code(9)]
      }
      let how = match args[1] {
        Variant(0, None) => 0
        Variant(1, None) => 1
        Variant(2, None) => 2
        _ => return [socket_error_code(3)]
      }
      [
        if @wasi.native_shutdown(state.fd, how) {
          socket_ok_void()
        } else {
          socket_last_error()
        },
      ]
    },
  )
}

///|
fn add_preview2_tcp(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.2.11/tcp"
  let builder = host.linker.host_instance_builder(
    "wasi:sockets/tcp@\{preview2_version}",
    host.runtime,
  )
  host.prepare_preview2_interface(builder, interface)
  add_tcp_state_methods(host, builder)
  add_tcp_address_methods(host, builder)
  add_tcp_option_methods(host, builder)
  add_tcp_poll_shutdown_methods(host, builder)
  host.linker.add_instance(
    "wasi:sockets/tcp@\{preview2_version}",
    builder.finish(),
  )
}

///|
pub fn WasiComponentHost::add_preview2_sockets(
  self : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  add_preview2_network_interfaces(self)
  add_preview2_tcp_create(self)
  add_preview2_tcp(self)
  add_preview2_udp_sockets(self)
  add_preview2_ip_name_lookup(self)
}
