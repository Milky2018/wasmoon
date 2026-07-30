///|
fn native_socket_address_equal(
  left : @wasi.NativeSocketAddress,
  right : @wasi.NativeSocketAddress,
) -> Bool {
  if left.family != right.family ||
    left.port != right.port ||
    left.scope_id != right.scope_id {
    return false
  }
  let length = if left.family == 4 { 4 } else { 16 }
  for i in 0..<length {
    if left.address[i] != right.address[i] {
      return false
    }
  }
  true
}

///|
fn component_bytes(value : @runtime_impl.ComponentValue) -> FixedArray[Byte]? {
  guard value is List(values) else { return None }
  let bytes = FixedArray::make(values.length(), b'\x00')
  for i, value in values {
    guard value is U8(byte) && byte >= 0 && byte <= 255 else { return None }
    bytes[i] = byte.to_byte()
  }
  Some(bytes)
}

///|
fn encode_component_bytes(bytes : Bytes) -> @runtime_impl.ComponentValue {
  let values : Array[@runtime_impl.ComponentValue] = []
  for byte in bytes {
    values.push(U8(byte.to_int()))
  }
  List(values)
}

///|
fn decode_optional_socket_address(
  value : @runtime_impl.ComponentValue,
) -> ComponentSocketAddress?? {
  match value {
    Variant(0, None) => Some(None)
    Variant(1, Some(value)) =>
      match decode_socket_address(value) {
        Some(address) => Some(Some(address))
        None => None
      }
    _ => None
  }
}

///|
fn udp_socket_state(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> UdpSocketState raise @runtime_impl.ComponentRuntimeError {
  let resource_type = host.resolve_resource_type(
    "wasi:sockets@0.2.11/udp.udp-socket",
  )
  let rep = resource_rep(table, resource_handle_arg(args, index), resource_type)
  match host.ctx.get_resource(rep) {
    Some(UdpSocket(state)) if !state.closed.val => state
    _ => raise HostCallError("UDP socket is not live")
  }
}

///|
fn incoming_datagram_stream_state(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> IncomingDatagramStreamState raise @runtime_impl.ComponentRuntimeError {
  let resource_type = host.resolve_resource_type(
    "wasi:sockets@0.2.11/udp.incoming-datagram-stream",
  )
  let rep = resource_rep(table, resource_handle_arg(args, index), resource_type)
  match host.ctx.get_resource(rep) {
    Some(IncomingDatagramStream(state)) if !state.closed.val &&
      state.generation.val == state.expected_generation => state
    _ => raise HostCallError("incoming datagram stream is not live")
  }
}

///|
fn outgoing_datagram_stream_state(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> OutgoingDatagramStreamState raise @runtime_impl.ComponentRuntimeError {
  let resource_type = host.resolve_resource_type(
    "wasi:sockets@0.2.11/udp.outgoing-datagram-stream",
  )
  let rep = resource_rep(table, resource_handle_arg(args, index), resource_type)
  match host.ctx.get_resource(rep) {
    Some(OutgoingDatagramStream(state)) if !state.closed.val &&
      state.generation.val == state.expected_generation => state
    _ => raise HostCallError("outgoing datagram stream is not live")
  }
}

///|
fn new_udp_socket_handle(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  fd : Int,
  family : Int,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  let rep = host.ctx.insert_resource(
    UdpSocket({
      fd,
      family,
      phase: Ref(UdpUnbound),
      generation: Ref(0),
      remote: Ref(None),
      policy: Ref(DenyAll),
      closed: Ref(false),
    }),
  )
  allocate_resource_handle(
    host.ctx,
    table,
    host.resolve_resource_type("wasi:sockets@0.2.11/udp.udp-socket"),
    rep,
  )
}

///|
fn add_preview2_udp_create(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.2.11/udp-create-socket"
  let builder = host.linker.host_instance_builder(
    "wasi:sockets/udp-create-socket@\{preview2_version}",
    host.runtime,
  )
  host.prepare_preview2_interface(builder, interface)
  builder.add_func(
    "create-udp-socket",
    preview2_func(interface, "create-udp-socket"),
    (args, table) => {
      let family = socket_family_arg(args, 0)
      match @wasi.native_socket_create(family, 2) {
        Some(fd) =>
          [socket_ok(U32(new_udp_socket_handle(host, table, fd, family)))]
        None => [socket_last_error()]
      }
    },
  )
  host.linker.add_instance(
    "wasi:sockets/udp-create-socket@\{preview2_version}",
    builder.finish(),
  )
}

///|
fn add_udp_bind_stream_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.2.11/udp"
  builder.add_func(
    "[method]udp-socket.start-bind",
    preview2_func(interface, "[method]udp-socket.start-bind"),
    (args, table) => {
      let state = udp_socket_state(host, table, args, 0)
      let policy = network_policy_for(host, table, args, 1)
      guard decode_socket_address(args[2]) is Some(address) else {
        return [socket_error_code(3)]
      }
      if state.phase.val != UdpUnbound {
        return [socket_error_code(9)]
      }
      if address.native.family != state.family {
        return [socket_error_code(3)]
      }
      if !network_allows(policy, address) {
        return [socket_error_code(1)]
      }
      if @wasi.native_socket_bind(state.fd, address.native) {
        state.policy.val = policy
        state.phase.val = UdpBindStarted
        [socket_ok_void()]
      } else {
        [socket_last_error()]
      }
    },
  )
  builder.add_func(
    "[method]udp-socket.finish-bind",
    preview2_func(interface, "[method]udp-socket.finish-bind"),
    (args, table) => {
      let state = udp_socket_state(host, table, args, 0)
      if state.phase.val == UdpBindStarted {
        state.phase.val = UdpBound
        [socket_ok_void()]
      } else {
        [socket_error_code(7)]
      }
    },
  )
  builder.add_func(
    "[method]udp-socket.stream",
    preview2_func(interface, "[method]udp-socket.stream"),
    (args, table) => {
      let state = udp_socket_state(host, table, args, 0)
      if state.phase.val != UdpBound {
        return [socket_error_code(9)]
      }
      guard decode_optional_socket_address(args[1]) is Some(remote) else {
        return [socket_error_code(3)]
      }
      match remote {
        Some(address) => {
          if address.native.family != state.family ||
            !network_allows(state.policy.val, address) {
            return [socket_error_code(3)]
          }
          match state.remote.val {
            Some(_) =>
              if !@wasi.native_socket_disconnect(state.fd) {
                return [socket_last_error()]
              }
            None => ()
          }
          let result = @wasi.native_socket_connect(state.fd, address.native)
          if result != 0 {
            return [socket_last_error()]
          }
          state.remote.val = Some(address.native)
        }
        None => {
          match state.remote.val {
            Some(_) =>
              if !@wasi.native_socket_disconnect(state.fd) {
                return [socket_last_error()]
              }
            None => ()
          }
          state.remote.val = None
        }
      }
      state.generation.val = state.generation.val + 1
      let generation = state.generation.val
      match (@wasi.native_dup(state.fd), @wasi.native_dup(state.fd)) {
        (Some(input_fd), Some(output_fd)) => {
          let input_rep = host.ctx.insert_resource(
            IncomingDatagramStream({
              fd: input_fd,
              generation: state.generation,
              expected_generation: generation,
              closed: Ref(false),
            }),
          )
          let output_rep = host.ctx.insert_resource(
            OutgoingDatagramStream({
              fd: output_fd,
              family: state.family,
              generation: state.generation,
              expected_generation: generation,
              remote: state.remote.val,
              permit: Ref(0L),
              closed: Ref(false),
            }),
          )
          [
            socket_ok(
              Tuple([
                U32(
                  allocate_resource_handle(
                    host.ctx,
                    table,
                    host.resolve_resource_type(
                      "wasi:sockets@0.2.11/udp.incoming-datagram-stream",
                    ),
                    input_rep,
                  ),
                ),
                U32(
                  allocate_resource_handle(
                    host.ctx,
                    table,
                    host.resolve_resource_type(
                      "wasi:sockets@0.2.11/udp.outgoing-datagram-stream",
                    ),
                    output_rep,
                  ),
                ),
              ]),
            ),
          ]
        }
        (Some(input_fd), None) => {
          @wasi.native_close(input_fd) |> ignore
          [socket_error_code(4)]
        }
        (None, Some(output_fd)) => {
          @wasi.native_close(output_fd) |> ignore
          [socket_error_code(4)]
        }
        _ => [socket_error_code(4)]
      }
    },
  )
}

///|
fn udp_option_result(
  state : UdpSocketState,
  option : Int,
  transform : (Int) -> @runtime_impl.ComponentValue,
) -> @runtime_impl.ComponentValue {
  match @wasi.native_socket_option_get(state.fd, state.family, option) {
    Some(value) => socket_ok(transform(value))
    None => socket_last_error()
  }
}

///|
fn set_udp_option_result(
  state : UdpSocketState,
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
fn add_udp_address_option_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.2.11/udp"
  fn address(
    args : Array[@runtime_impl.ComponentValue],
    table : @runtime_impl.ResourceTable,
    peer : Bool,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    let state = udp_socket_state(host, table, args, 0)
    if state.phase.val != UdpBound {
      return [socket_error_code(9)]
    }
    match @wasi.native_socket_address(state.fd, peer) {
      Some(address) => [socket_ok(encode_socket_address(address))]
      None => [socket_last_error()]
    }
  }

  builder.add_func(
    "[method]udp-socket.local-address",
    preview2_func(interface, "[method]udp-socket.local-address"),
    (args, table) => address(args, table, false),
  )
  builder.add_func(
    "[method]udp-socket.remote-address",
    preview2_func(interface, "[method]udp-socket.remote-address"),
    (args, table) => address(args, table, true),
  )
  builder.add_func(
    "[method]udp-socket.address-family",
    preview2_func(interface, "[method]udp-socket.address-family"),
    (args, table) => {
      [
        Variant(
          if udp_socket_state(host, table, args, 0).family == 4 {
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
    "[method]udp-socket.unicast-hop-limit",
    preview2_func(interface, "[method]udp-socket.unicast-hop-limit"),
    (args, table) => {
      [
        udp_option_result(udp_socket_state(host, table, args, 0), 4, value => {
          U8(value)
        }),
      ]
    },
  )
  builder.add_func(
    "[method]udp-socket.set-unicast-hop-limit",
    preview2_func(interface, "[method]udp-socket.set-unicast-hop-limit"),
    (args, table) => {
      guard args[1] is U8(value) else {
        raise HostCallError("expected hop limit")
      }
      [
        if value <= 0 || value > 255 {
          socket_error_code(3)
        } else {
          set_udp_option_result(
            udp_socket_state(host, table, args, 0),
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
        udp_option_result(udp_socket_state(host, table, args, 0), option, value => {
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
          set_udp_option_result(
            udp_socket_state(host, table, args, 0),
            option,
            value.to_int(),
          )
        },
      ]
    })
  }

  add_buffer_option(
    "[method]udp-socket.receive-buffer-size", "[method]udp-socket.set-receive-buffer-size",
    5,
  )
  add_buffer_option(
    "[method]udp-socket.send-buffer-size", "[method]udp-socket.set-send-buffer-size",
    6,
  )
  builder.add_func(
    "[method]udp-socket.subscribe",
    preview2_func(interface, "[method]udp-socket.subscribe"),
    (args, table) => {
      let state = udp_socket_state(host, table, args, 0)
      let rep = host.ctx.insert_resource(Pollable(Socket(state.fd, 0x05)))
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
}

///|
fn add_incoming_datagram_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.2.11/udp"
  builder.add_func(
    "[method]incoming-datagram-stream.receive",
    preview2_func(interface, "[method]incoming-datagram-stream.receive"),
    (args, table) => {
      let state = incoming_datagram_stream_state(host, table, args, 0)
      let requested = socket_u64_arg(args, 1)
      if requested <= 0L {
        return [socket_ok(List([]))]
      }
      let limit = if requested > 64L { 64 } else { requested.to_int() }
      let datagrams : Array[@runtime_impl.ComponentValue] = []
      for _ in 0..<limit {
        match @wasi.native_socket_recv_from(state.fd, 65535) {
          Some(datagram) =>
            datagrams.push(
              Tuple([
                encode_component_bytes(datagram.data),
                encode_socket_address(datagram.address),
              ]),
            )
          None => {
            if @wasi.native_last_errno_to_wasi() == 6 {
              break
            }
            if datagrams.length() == 0 {
              return [socket_last_error()]
            }
            break
          }
        }
      }
      [socket_ok(List(datagrams))]
    },
  )
  builder.add_func(
    "[method]incoming-datagram-stream.subscribe",
    preview2_func(interface, "[method]incoming-datagram-stream.subscribe"),
    (args, table) => {
      let state = incoming_datagram_stream_state(host, table, args, 0)
      let rep = host.ctx.insert_resource(Pollable(Socket(state.fd, 0x01)))
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
}

///|
fn decode_outgoing_datagram(
  value : @runtime_impl.ComponentValue,
) -> (FixedArray[Byte], ComponentSocketAddress?)? {
  guard value is Tuple([data, address]) &&
    component_bytes(data) is Some(bytes) &&
    decode_optional_socket_address(address) is Some(remote) else {
    return None
  }
  Some((bytes, remote))
}

///|
fn add_outgoing_datagram_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.2.11/udp"
  builder.add_func(
    "[method]outgoing-datagram-stream.check-send",
    preview2_func(interface, "[method]outgoing-datagram-stream.check-send"),
    (args, table) => {
      let state = outgoing_datagram_stream_state(host, table, args, 0)
      match @wasi.native_poll([state.fd], [0x04], 0) {
        Some(result) => {
          let permit = if result.ready_count > 0 { 64L } else { 0L }
          state.permit.val = permit
          [socket_ok(U64(permit))]
        }
        None => [socket_last_error()]
      }
    },
  )
  builder.add_func(
    "[method]outgoing-datagram-stream.send",
    preview2_func(interface, "[method]outgoing-datagram-stream.send"),
    (args, table) => {
      let state = outgoing_datagram_stream_state(host, table, args, 0)
      guard args[1] is List(values) else {
        raise HostCallError("expected outgoing datagram list")
      }
      if values.length().to_int64() > state.permit.val {
        raise HostCallError("UDP send exceeds check-send permission")
      }
      state.permit.val = 0L
      let mut sent = 0
      for value in values {
        guard decode_outgoing_datagram(value) is Some((data, remote)) else {
          if sent == 0 {
            return [socket_error_code(3)]
          }
          break
        }
        let destination = match (state.remote, remote) {
          (Some(expected), Some(actual)) =>
            if native_socket_address_equal(expected, actual.native) {
              None
            } else {
              if sent == 0 {
                return [socket_error_code(3)]
              }
              break
            }
          (Some(_), None) => None
          (None, Some(address)) =>
            if address.native.family == state.family {
              Some(address.native)
            } else {
              if sent == 0 {
                return [socket_error_code(3)]
              }
              break
            }
          (None, None) => {
            if sent == 0 {
              return [socket_error_code(3)]
            }
            break
          }
        }
        let result = @wasi.native_socket_send_to(state.fd, data, destination)
        if result == data.length().to_int64() {
          sent = sent + 1
        } else if result < 0L && @wasi.native_last_errno_to_wasi() == 6 {
          break
        } else if sent == 0 {
          return [socket_last_error()]
        } else {
          break
        }
      }
      [socket_ok(U64(sent.to_int64()))]
    },
  )
  builder.add_func(
    "[method]outgoing-datagram-stream.subscribe",
    preview2_func(interface, "[method]outgoing-datagram-stream.subscribe"),
    (args, table) => {
      let state = outgoing_datagram_stream_state(host, table, args, 0)
      let rep = host.ctx.insert_resource(Pollable(Socket(state.fd, 0x04)))
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
}

///|
fn add_preview2_udp(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.2.11/udp"
  let builder = host.linker.host_instance_builder(
    "wasi:sockets/udp@\{preview2_version}",
    host.runtime,
  )
  host.prepare_preview2_interface(builder, interface)
  add_udp_bind_stream_methods(host, builder)
  add_udp_address_option_methods(host, builder)
  add_incoming_datagram_methods(host, builder)
  add_outgoing_datagram_methods(host, builder)
  host.linker.add_instance(
    "wasi:sockets/udp@\{preview2_version}",
    builder.finish(),
  )
}

///|
fn add_preview2_udp_sockets(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  add_preview2_udp_create(host)
  add_preview2_udp(host)
}
