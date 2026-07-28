///|
let preview3_sockets_interface : String = "wasi:sockets@0.3.0/types"

///|
fn preview3_socket_error_case(preview1_errno : Int) -> Int {
  if preview1_errno == 64 {
    return 10
  }
  match socket_error_index(preview1_errno) {
    1 => 0
    2 => 1
    3 => 2
    4 | 10 => 3
    5 => 4
    6 | 7 | 9 => 5
    11 => 6
    12 => 7
    13 => 8
    14 => 9
    15 => 11
    16 => 12
    17 => 13
    _ => 14
  }
}

///|
fn preview3_socket_error() -> @runtime_impl.ComponentValue {
  preview3_socket_error_code(
    preview3_socket_error_case(@wasi.native_last_errno_to_wasi()),
  )
}

///|
fn preview3_socket_native_error(errno : Int) -> @runtime_impl.ComponentValue {
  preview3_socket_error_code(
    preview3_socket_error_case(@wasi.native_errno_to_wasi(errno)),
  )
}

///|
fn preview3_socket_error_code(index : Int) -> @runtime_impl.ComponentValue {
  Variant(
    1,
    Some(
      if index == 14 {
        Variant(14, Some(Variant(0, None)))
      } else {
        Variant(index, None)
      },
    ),
  )
}

///|
fn preview3_socket_ok_void() -> @runtime_impl.ComponentValue {
  Variant(0, None)
}

///|
fn preview3_socket_ok(
  value : @runtime_impl.ComponentValue,
) -> @runtime_impl.ComponentValue {
  Variant(0, Some(value))
}

///|
fn preview3_socket_family(
  value : @runtime_impl.ComponentValue,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  match value {
    U32(0) => 4
    U32(1) => 6
    _ => raise HostCallError("expected Preview 3 IP address family")
  }
}

///|
fn preview3_network_policy(
  host : WasiComponentHost,
) -> WasiNetworkPolicy raise @runtime_impl.ComponentRuntimeError {
  match host.ctx.get_resource(host.ctx.network_rep) {
    Some(Network(policy)) => policy
    _ => raise HostCallError("network capability is not live")
  }
}

///|
fn preview3_tcp_socket_state(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> TcpSocketState raise @runtime_impl.ComponentRuntimeError {
  let resource_type = host.resolve_resource_type(
    "wasi:sockets@0.3.0/types.tcp-socket",
  )
  let rep = resource_rep(table, resource_handle_arg(args, index), resource_type)
  match host.ctx.get_resource(rep) {
    Some(TcpSocket(state)) if !state.closed.val => state
    _ => raise HostCallError("Preview 3 TCP socket is not live")
  }
}

///|
fn preview3_udp_socket_state(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> UdpSocketState raise @runtime_impl.ComponentRuntimeError {
  let resource_type = host.resolve_resource_type(
    "wasi:sockets@0.3.0/types.udp-socket",
  )
  let rep = resource_rep(table, resource_handle_arg(args, index), resource_type)
  match host.ctx.get_resource(rep) {
    Some(UdpSocket(state)) if !state.closed.val => state
    _ => raise HostCallError("Preview 3 UDP socket is not live")
  }
}

///|
fn preview3_new_tcp_socket(
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
    host.resolve_resource_type("wasi:sockets@0.3.0/types.tcp-socket"),
    rep,
  )
}

///|
fn preview3_new_udp_socket(
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
      policy: Ref(preview3_network_policy(host)),
      closed: Ref(false),
    }),
  )
  allocate_resource_handle(
    host.ctx,
    table,
    host.resolve_resource_type("wasi:sockets@0.3.0/types.udp-socket"),
    rep,
  )
}

///|
fn preview3_socket_address_allowed(
  host : WasiComponentHost,
  address : ComponentSocketAddress,
) -> Bool raise @runtime_impl.ComponentRuntimeError {
  network_allows(preview3_network_policy(host), address)
}

///|
fn preview3_socket_fd_future(
  ctx : WasiComponentCtx,
  fd : Int,
  events : Int,
  step : () -> @runtime_impl.ComponentValue? raise @runtime_impl.ComponentRuntimeError,
  cancel : () -> Unit,
) -> @runtime_impl.HostFuture {
  let operation : Ref[Int?] = Ref(None)
  let done = Ref(false)
  fn cleanup() {
    match operation.val {
      Some(id) => ctx.cancel_async_fd(id)
      None => ()
    }
    operation.val = None
  }
  HostFuture(
    () => {
      if done.val {
        return Ready([preview3_socket_error_code(5)])
      }
      match operation.val {
        Some(id) =>
          if ctx.async_fd_ready(id) {
            operation.val = None
          } else {
            return Pending
          }
        None => ()
      }
      match step() {
        Some(value) => {
          done.val = true
          cleanup()
          Ready([value])
        }
        None => {
          operation.val = Some(ctx.register_async_fd(fd, events))
          Pending
        }
      }
    },
    () => {
      if !done.val {
        done.val = true
        cleanup()
        cancel()
      }
    },
  )
}

///|
fn preview3_tcp_connect_future(
  host : WasiComponentHost,
  state : TcpSocketState,
  address : ComponentSocketAddress,
) -> @runtime_impl.HostFuture raise @runtime_impl.ComponentRuntimeError {
  if state.phase.val != Unbound && state.phase.val != Bound {
    return preview3_ready_future([preview3_socket_error_code(5)])
  }
  if address.native.family != state.family {
    return preview3_ready_future([preview3_socket_error_code(2)])
  }
  if !preview3_socket_address_allowed(host, address) {
    return preview3_ready_future([preview3_socket_error_code(0)])
  }
  let started = Ref(false)
  preview3_socket_fd_future(
    host.ctx,
    state.fd,
    0x04,
    () => {
      if !started.val {
        started.val = true
        let result = @wasi.native_socket_connect(state.fd, address.native)
        if result == 0 {
          state.phase.val = Connected
          return Some(preview3_socket_ok_void())
        }
        if result != 1 {
          state.phase.val = Closed
          state.closed.val = true
          @wasi.native_close(state.fd) |> ignore
          return Some(preview3_socket_error())
        }
        state.phase.val = ConnectStarted
        return None
      }
      match @wasi.native_socket_error(state.fd) {
        Some(0) => {
          state.phase.val = Connected
          Some(preview3_socket_ok_void())
        }
        Some(error) => {
          state.phase.val = Closed
          state.closed.val = true
          @wasi.native_close(state.fd) |> ignore
          Some(preview3_socket_native_error(error))
        }
        None => Some(preview3_socket_error())
      }
    },
    () => {
      if !state.closed.val {
        state.closed.val = true
        state.phase.val = Closed
        @wasi.native_close(state.fd) |> ignore
      }
    },
  )
}

///|
fn preview3_tcp_listen_stream(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  state : TcpSocketState,
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  if state.phase.val == Unbound {
    let address : @wasi.NativeSocketAddress = {
      family: state.family,
      address: FixedArray::make(if state.family == 4 { 4 } else { 16 }, b'\x00'),
      port: 0,
      scope_id: 0,
    }
    if !@wasi.native_socket_bind(state.fd, address) {
      return preview3_socket_error()
    }
    state.phase.val = Bound
  }
  if state.phase.val != Bound {
    return preview3_socket_error_code(5)
  }
  if !@wasi.native_socket_listen(state.fd, state.backlog.val) {
    return preview3_socket_error()
  }
  state.phase.val = Listening
  let types = wasi_preview3_type_space(name => host.resolve_resource_type(name))
  guard preview3_func(preview3_sockets_interface, "[method]tcp-socket.listen").result
    is Some(TypeIdx(result_index)) &&
    types.get(result_index)
    is Some(Some(Result(Some(TypeIdx(stream_index)), Some(_)))) &&
    types.get(stream_index) is Some(Some(Stream(Some(element_type)))) else {
    raise HostCallError("generated Preview 3 TCP listen contract is malformed")
  }
  let operation : Ref[Int?] = Ref(None)
  let stream = host.runtime.new_host_value_stream_source(
    table,
    element_type,
    types,
    maximum => {
      if maximum <= 0 {
        return Values([])
      }
      match operation.val {
        Some(id) =>
          if host.ctx.async_fd_ready(id) {
            operation.val = None
          } else {
            return Pending
          }
        None => ()
      }
      let fd = @wasi.native_accept(state.fd)
      if fd >= 0 {
        Values([
          U32(preview3_new_tcp_socket(host, table, fd, state.family, Connected)),
        ])
      } else if @wasi.native_last_errno_to_wasi() == 6 {
        operation.val = Some(host.ctx.register_async_fd(state.fd, 0x01))
        Pending
      } else {
        Closed
      }
    },
    () => {
      match operation.val {
        Some(id) => host.ctx.cancel_async_fd(id)
        None => ()
      }
      operation.val = None
    },
  )
  preview3_socket_ok(U32(stream))
}

///|
fn preview3_tcp_send_future(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  state : TcpSocketState,
  readable : Int,
) -> @runtime_impl.HostFuture {
  if state.phase.val != Connected {
    host.runtime.drop_host_readable_stream(table, readable) catch {
      _ => ()
    }
    return preview3_ready_future([preview3_socket_error_code(5)])
  }
  let pending : Ref[(Bytes, Int)?] = Ref(None)
  let operation : Ref[Int?] = Ref(None)
  let done = Ref(false)
  fn cleanup() -> Unit raise @runtime_impl.ComponentRuntimeError {
    match operation.val {
      Some(id) => host.ctx.cancel_async_fd(id)
      None => ()
    }
    operation.val = None
    if !done.val {
      done.val = true
      host.runtime.drop_host_readable_stream(table, readable)
    }
  }
  fn write(bytes : Bytes, offset : Int) -> Int {
    let remaining = bytes.length() - offset
    let buffer = FixedArray::makei(remaining, i => bytes[offset + i])
    match @wasi.native_write(state.fd, buffer, remaining) {
      Some(count) => count
      None => if @wasi.native_last_errno_to_wasi() == 6 { 0 } else { -1 }
    }
  }
  HostFuture(
    () => {
      if done.val {
        return Ready([preview3_socket_ok_void()])
      }
      match operation.val {
        Some(id) =>
          if host.ctx.async_fd_ready(id) {
            operation.val = None
          } else {
            return Pending
          }
        None => ()
      }
      while true {
        match pending.val {
          Some((bytes, offset)) => {
            let count = write(bytes, offset)
            if count < 0 {
              cleanup()
              return Ready([preview3_socket_error()])
            }
            if offset + count < bytes.length() {
              pending.val = Some((bytes, offset + count))
              operation.val = Some(host.ctx.register_async_fd(state.fd, 0x04))
              return Pending
            }
            pending.val = None
          }
          None => ()
        }
        match host.runtime.read_host_byte_stream(table, readable) {
          Closed => {
            cleanup()
            return Ready([preview3_socket_ok_void()])
          }
          Pending => return Pending
          Data(bytes) => {
            let count = write(bytes, 0)
            if count < 0 {
              cleanup()
              return Ready([preview3_socket_error()])
            }
            if count < bytes.length() {
              pending.val = Some((bytes, count))
              operation.val = Some(host.ctx.register_async_fd(state.fd, 0x04))
              return Pending
            }
          }
        }
      }
      Pending
    },
    () => cleanup(),
  )
}

///|
fn preview3_tcp_receive(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  state : TcpSocketState,
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  let (stream_element, future_element, types) = preview3_stream_future_types(
    host, preview3_sockets_interface, "[method]tcp-socket.receive",
  )
  let buffered : Array[Byte] = []
  let next = Ref(0)
  let operation : Ref[Int?] = Ref(None)
  let completion : Ref[@runtime_impl.ComponentValue?] = Ref(
    if state.phase.val == Connected {
      None
    } else {
      Some(preview3_socket_error_code(5))
    },
  )
  let users = Ref(2)
  fn release() {
    if users.val > 0 {
      users.val = users.val - 1
    }
    if users.val == 0 {
      match operation.val {
        Some(id) => host.ctx.cancel_async_fd(id)
        None => ()
      }
      operation.val = None
    }
  }
  fn pump(capacity : Int) -> Unit {
    if completion.val is Some(_) {
      return
    }
    match operation.val {
      Some(id) =>
        if host.ctx.async_fd_ready(id) {
          operation.val = None
        } else {
          return
        }
      None => ()
    }
    let count = if capacity <= 0 { 65536 } else { capacity }
    let buffer = FixedArray::make(count, b'\x00')
    match @wasi.native_read(state.fd, buffer, count) {
      Some(0) => completion.val = Some(preview3_socket_ok_void())
      Some(read) => {
        for i in 0..<read {
          buffered.push(buffer[i])
        }
        operation.val = Some(host.ctx.register_async_fd(state.fd, 0x01))
      }
      None =>
        if @wasi.native_last_errno_to_wasi() == 6 {
          operation.val = Some(host.ctx.register_async_fd(state.fd, 0x01))
        } else {
          completion.val = Some(preview3_socket_error())
        }
    }
  }
  let stream = host.runtime.new_host_value_stream_source(
    table,
    stream_element,
    types,
    maximum => {
      if maximum <= 0 {
        return Values([])
      }
      if next.val >= buffered.length() {
        buffered.clear()
        next.val = 0
        pump(maximum)
      }
      let available = buffered.length() - next.val
      if available > 0 {
        let count = if maximum < available { maximum } else { available }
        let values : Array[@runtime_impl.ComponentValue] = []
        for i in 0..<count {
          values.push(U8(buffered[next.val + i].to_int()))
        }
        next.val = next.val + count
        Values(values)
      } else if completion.val is Some(_) {
        Closed
      } else {
        Pending
      }
    },
    () => release(),
  )
  let future = host.runtime.new_host_value_future_source(
    table,
    future_element,
    types,
    () => {
      pump(65536)
      match completion.val {
        Some(value) => Ready(value)
        None => Pending
      }
    },
    () => release(),
  )
  Tuple([U32(stream), U32(future)])
}

///|
fn preview3_socket_option(
  fd : Int,
  family : Int,
  option : Int,
  convert : (Int) -> @runtime_impl.ComponentValue,
) -> @runtime_impl.ComponentValue {
  match @wasi.native_socket_option_get(fd, family, option) {
    Some(value) => preview3_socket_ok(convert(value))
    None => preview3_socket_error()
  }
}

///|
fn preview3_set_socket_option(
  fd : Int,
  family : Int,
  option : Int,
  value : Int,
) -> @runtime_impl.ComponentValue {
  if @wasi.native_socket_option_set(fd, family, option, value) {
    preview3_socket_ok_void()
  } else {
    preview3_socket_error()
  }
}

///|
fn add_preview3_tcp_options(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  fn state(
    args : Array[@runtime_impl.ComponentValue],
    table : @runtime_impl.ResourceTable,
  ) -> TcpSocketState raise @runtime_impl.ComponentRuntimeError {
    preview3_tcp_socket_state(host, table, args, 0)
  }
  fn add_bool(
    getter : String,
    setter : String,
    option : Int,
  ) -> Unit raise @runtime_impl.ComponentRuntimeError {
    builder.add_func(
      getter,
      preview3_func(preview3_sockets_interface, getter),
      (args, table) => {
        let socket = state(args, table)
        [
          preview3_socket_option(socket.fd, socket.family, option, n => {
            Bool(n != 0)
          }),
        ]
      },
    )
    builder.add_func(
      setter,
      preview3_func(preview3_sockets_interface, setter),
      (args, table) => {
        guard args[1] is Bool(value) else {
          raise HostCallError("expected socket boolean option")
        }
        let socket = state(args, table)
        [
          preview3_set_socket_option(
            socket.fd,
            socket.family,
            option,
            if value {
              1
            } else {
              0
            },
          ),
        ]
      },
    )
  }
  fn add_u64(
    getter : String,
    setter : String,
    option : Int,
  ) -> Unit raise @runtime_impl.ComponentRuntimeError {
    builder.add_func(
      getter,
      preview3_func(preview3_sockets_interface, getter),
      (args, table) => {
        let socket = state(args, table)
        [
          preview3_socket_option(socket.fd, socket.family, option, n => {
            U64(n.to_int64())
          }),
        ]
      },
    )
    builder.add_func(
      setter,
      preview3_func(preview3_sockets_interface, setter),
      (args, table) => {
        let value = socket_u64_arg(args, 1)
        let socket = state(args, table)
        [
          if value <= 0L || value > 0x7fffffffL {
            preview3_socket_error_code(2)
          } else {
            preview3_set_socket_option(
              socket.fd,
              socket.family,
              option,
              value.to_int(),
            )
          },
        ]
      },
    )
  }
  add_bool(
    "[method]tcp-socket.get-keep-alive-enabled", "[method]tcp-socket.set-keep-alive-enabled",
    0,
  )
  for
    entry in [
      (
        "[method]tcp-socket.get-keep-alive-idle-time", "[method]tcp-socket.set-keep-alive-idle-time",
        1,
      ),
      (
        "[method]tcp-socket.get-keep-alive-interval", "[method]tcp-socket.set-keep-alive-interval",
        2,
      ),
    ] {
    let (getter, setter, option) = entry
    builder.add_func(
      getter,
      preview3_func(preview3_sockets_interface, getter),
      (args, table) => {
        let socket = state(args, table)
        [
          preview3_socket_option(socket.fd, socket.family, option, n => {
            U64(n.to_int64() * 1_000_000_000L)
          }),
        ]
      },
    )
    builder.add_func(
      setter,
      preview3_func(preview3_sockets_interface, setter),
      (args, table) => {
        let socket = state(args, table)
        match duration_seconds(socket_u64_arg(args, 1)) {
          Some(value) =>
            [
              preview3_set_socket_option(
                socket.fd,
                socket.family,
                option,
                value,
              ),
            ]
          None => [preview3_socket_error_code(2)]
        }
      },
    )
  }
  for
    entry in [
      (
        "[method]tcp-socket.get-keep-alive-count", "[method]tcp-socket.set-keep-alive-count",
        3,
      ),
    ] {
    let (getter, setter, option) = entry
    builder.add_func(
      getter,
      preview3_func(preview3_sockets_interface, getter),
      (args, table) => {
        let socket = state(args, table)
        [preview3_socket_option(socket.fd, socket.family, option, n => U32(n))]
      },
    )
    builder.add_func(
      setter,
      preview3_func(preview3_sockets_interface, setter),
      (args, table) => {
        let value = socket_u32_arg(args, 1)
        let socket = state(args, table)
        [
          if value <= 0 {
            preview3_socket_error_code(2)
          } else {
            preview3_set_socket_option(socket.fd, socket.family, option, value)
          },
        ]
      },
    )
  }
  builder.add_func(
    "[method]tcp-socket.get-hop-limit",
    preview3_func(
      preview3_sockets_interface, "[method]tcp-socket.get-hop-limit",
    ),
    (args, table) => {
      let socket = state(args, table)
      [preview3_socket_option(socket.fd, socket.family, 4, n => U8(n))]
    },
  )
  builder.add_func(
    "[method]tcp-socket.set-hop-limit",
    preview3_func(
      preview3_sockets_interface, "[method]tcp-socket.set-hop-limit",
    ),
    (args, table) => {
      guard args[1] is U8(value) else {
        raise HostCallError("expected socket hop limit")
      }
      let socket = state(args, table)
      [
        if value <= 0 {
          preview3_socket_error_code(2)
        } else {
          preview3_set_socket_option(socket.fd, socket.family, 4, value)
        },
      ]
    },
  )
  add_u64(
    "[method]tcp-socket.get-receive-buffer-size", "[method]tcp-socket.set-receive-buffer-size",
    5,
  )
  add_u64(
    "[method]tcp-socket.get-send-buffer-size", "[method]tcp-socket.set-send-buffer-size",
    6,
  )
}

///|
fn add_preview3_tcp(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  builder.add_func(
    "[static]tcp-socket.create",
    preview3_func(preview3_sockets_interface, "[static]tcp-socket.create"),
    (args, table) => {
      guard args is [family_value] else {
        raise HostCallError("expected TCP address family")
      }
      let family = preview3_socket_family(family_value)
      match @wasi.native_socket_create(family, 1) {
        Some(fd) =>
          [
            preview3_socket_ok(
              U32(preview3_new_tcp_socket(host, table, fd, family, Unbound)),
            ),
          ]
        None => [preview3_socket_error()]
      }
    },
  )
  builder.add_func(
    "[method]tcp-socket.bind",
    preview3_func(preview3_sockets_interface, "[method]tcp-socket.bind"),
    (args, table) => {
      let state = preview3_tcp_socket_state(host, table, args, 0)
      guard decode_socket_address(args[1]) is Some(address) else {
        return [preview3_socket_error_code(2)]
      }
      if state.phase.val != Unbound {
        return [preview3_socket_error_code(5)]
      }
      if address.native.family != state.family {
        return [preview3_socket_error_code(2)]
      }
      if !preview3_socket_address_allowed(host, address) {
        return [preview3_socket_error_code(0)]
      }
      if @wasi.native_socket_bind(state.fd, address.native) {
        state.phase.val = Bound
        [preview3_socket_ok_void()]
      } else {
        [preview3_socket_error()]
      }
    },
  )
  builder.add_async_func(
    "[method]tcp-socket.connect",
    preview3_func(preview3_sockets_interface, "[method]tcp-socket.connect"),
    (args, table) => {
      let state = preview3_tcp_socket_state(host, table, args, 0)
      guard decode_socket_address(args[1]) is Some(address) else {
        return preview3_ready_future([preview3_socket_error_code(2)])
      }
      preview3_tcp_connect_future(host, state, address)
    },
  )
  builder.add_func(
    "[method]tcp-socket.listen",
    preview3_func(preview3_sockets_interface, "[method]tcp-socket.listen"),
    (args, table) => {
      [
        preview3_tcp_listen_stream(
          host,
          table,
          preview3_tcp_socket_state(host, table, args, 0),
        ),
      ]
    },
  )
  builder.add_func(
    "[method]tcp-socket.send",
    preview3_func(preview3_sockets_interface, "[method]tcp-socket.send"),
    (args, table) => {
      guard args is [_, U32(readable)] else {
        raise HostCallError("expected Preview 3 TCP byte stream")
      }
      [
        preview3_call_future_value(
          host,
          table,
          preview3_sockets_interface,
          "[method]tcp-socket.send",
          preview3_tcp_send_future(
            host,
            table,
            preview3_tcp_socket_state(host, table, args, 0),
            readable,
          ),
        ),
      ]
    },
  )
  builder.add_func(
    "[method]tcp-socket.receive",
    preview3_func(preview3_sockets_interface, "[method]tcp-socket.receive"),
    (args, table) => {
      let state = preview3_tcp_socket_state(host, table, args, 0)
      [preview3_tcp_receive(host, table, state)]
    },
  )
  fn add_address(
    name : String,
    peer : Bool,
  ) -> Unit raise @runtime_impl.ComponentRuntimeError {
    builder.add_func(name, preview3_func(preview3_sockets_interface, name), (
      args,
      table,
    ) => {
      let state = preview3_tcp_socket_state(host, table, args, 0)
      [
        match @wasi.native_socket_address(state.fd, peer) {
          Some(address) => preview3_socket_ok(encode_socket_address(address))
          None => preview3_socket_error()
        },
      ]
    })
  }
  add_address("[method]tcp-socket.get-local-address", false)
  add_address("[method]tcp-socket.get-remote-address", true)
  builder.add_func(
    "[method]tcp-socket.get-is-listening",
    preview3_func(
      preview3_sockets_interface, "[method]tcp-socket.get-is-listening",
    ),
    (args, table) => {
      [
        Bool(
          preview3_tcp_socket_state(host, table, args, 0).phase.val == Listening,
        ),
      ]
    },
  )
  builder.add_func(
    "[method]tcp-socket.get-address-family",
    preview3_func(
      preview3_sockets_interface, "[method]tcp-socket.get-address-family",
    ),
    (args, table) => {
      [
        U32(
          if preview3_tcp_socket_state(host, table, args, 0).family == 4 {
            0
          } else {
            1
          },
        ),
      ]
    },
  )
  builder.add_func(
    "[method]tcp-socket.set-listen-backlog-size",
    preview3_func(
      preview3_sockets_interface, "[method]tcp-socket.set-listen-backlog-size",
    ),
    (args, table) => {
      let state = preview3_tcp_socket_state(host, table, args, 0)
      let value = socket_u64_arg(args, 1)
      if value <= 0L || value > 0x7fffffffL {
        [preview3_socket_error_code(2)]
      } else if state.phase.val == Listening ||
        state.phase.val == Connected ||
        state.phase.val == ConnectStarted {
        [preview3_socket_error_code(5)]
      } else {
        state.backlog.val = value.to_int()
        [preview3_socket_ok_void()]
      }
    },
  )
  add_preview3_tcp_options(host, builder)
}

///|
fn preview3_udp_async_future(
  host : WasiComponentHost,
  state : UdpSocketState,
  events : Int,
  step : () -> @runtime_impl.ComponentValue? raise @runtime_impl.ComponentRuntimeError,
) -> @runtime_impl.HostFuture {
  preview3_socket_fd_future(host.ctx, state.fd, events, step, () => ())
}

///|
fn add_preview3_udp_options(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  fn add_u64(
    getter : String,
    setter : String,
    option : Int,
  ) -> Unit raise @runtime_impl.ComponentRuntimeError {
    builder.add_func(
      getter,
      preview3_func(preview3_sockets_interface, getter),
      (args, table) => {
        let socket = preview3_udp_socket_state(host, table, args, 0)
        [
          preview3_socket_option(socket.fd, socket.family, option, n => {
            U64(n.to_int64())
          }),
        ]
      },
    )
    builder.add_func(
      setter,
      preview3_func(preview3_sockets_interface, setter),
      (args, table) => {
        let socket = preview3_udp_socket_state(host, table, args, 0)
        let value = socket_u64_arg(args, 1)
        [
          if value <= 0L || value > 0x7fffffffL {
            preview3_socket_error_code(2)
          } else {
            preview3_set_socket_option(
              socket.fd,
              socket.family,
              option,
              value.to_int(),
            )
          },
        ]
      },
    )
  }
  builder.add_func(
    "[method]udp-socket.get-unicast-hop-limit",
    preview3_func(
      preview3_sockets_interface, "[method]udp-socket.get-unicast-hop-limit",
    ),
    (args, table) => {
      let socket = preview3_udp_socket_state(host, table, args, 0)
      [preview3_socket_option(socket.fd, socket.family, 4, n => U8(n))]
    },
  )
  builder.add_func(
    "[method]udp-socket.set-unicast-hop-limit",
    preview3_func(
      preview3_sockets_interface, "[method]udp-socket.set-unicast-hop-limit",
    ),
    (args, table) => {
      guard args[1] is U8(value) else {
        raise HostCallError("expected UDP hop limit")
      }
      let socket = preview3_udp_socket_state(host, table, args, 0)
      [
        if value <= 0 {
          preview3_socket_error_code(2)
        } else {
          preview3_set_socket_option(socket.fd, socket.family, 4, value)
        },
      ]
    },
  )
  add_u64(
    "[method]udp-socket.get-receive-buffer-size", "[method]udp-socket.set-receive-buffer-size",
    5,
  )
  add_u64(
    "[method]udp-socket.get-send-buffer-size", "[method]udp-socket.set-send-buffer-size",
    6,
  )
}

///|
fn add_preview3_udp(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  builder.add_func(
    "[static]udp-socket.create",
    preview3_func(preview3_sockets_interface, "[static]udp-socket.create"),
    (args, table) => {
      guard args is [family_value] else {
        raise HostCallError("expected UDP address family")
      }
      let family = preview3_socket_family(family_value)
      match @wasi.native_socket_create(family, 2) {
        Some(fd) =>
          [
            preview3_socket_ok(
              U32(preview3_new_udp_socket(host, table, fd, family)),
            ),
          ]
        None => [preview3_socket_error()]
      }
    },
  )
  builder.add_func(
    "[method]udp-socket.bind",
    preview3_func(preview3_sockets_interface, "[method]udp-socket.bind"),
    (args, table) => {
      let state = preview3_udp_socket_state(host, table, args, 0)
      guard decode_socket_address(args[1]) is Some(address) else {
        return [preview3_socket_error_code(2)]
      }
      if state.phase.val != UdpUnbound {
        return [preview3_socket_error_code(5)]
      }
      if address.native.family != state.family {
        return [preview3_socket_error_code(2)]
      }
      if !preview3_socket_address_allowed(host, address) {
        return [preview3_socket_error_code(0)]
      }
      if @wasi.native_socket_bind(state.fd, address.native) {
        state.phase.val = UdpBound
        [preview3_socket_ok_void()]
      } else {
        [preview3_socket_error()]
      }
    },
  )
  builder.add_func(
    "[method]udp-socket.connect",
    preview3_func(preview3_sockets_interface, "[method]udp-socket.connect"),
    (args, table) => {
      let state = preview3_udp_socket_state(host, table, args, 0)
      guard decode_socket_address(args[1]) is Some(address) else {
        return [preview3_socket_error_code(2)]
      }
      if address.native.family != state.family ||
        !preview3_socket_address_allowed(host, address) {
        return [preview3_socket_error_code(0)]
      }
      if @wasi.native_socket_connect(state.fd, address.native) == 0 {
        state.remote.val = Some(address.native)
        [preview3_socket_ok_void()]
      } else {
        [preview3_socket_error()]
      }
    },
  )
  builder.add_func(
    "[method]udp-socket.disconnect",
    preview3_func(preview3_sockets_interface, "[method]udp-socket.disconnect"),
    (args, table) => {
      let state = preview3_udp_socket_state(host, table, args, 0)
      if @wasi.native_socket_disconnect(state.fd) {
        state.remote.val = None
        [preview3_socket_ok_void()]
      } else {
        [preview3_socket_error()]
      }
    },
  )
  builder.add_async_func(
    "[method]udp-socket.send",
    preview3_func(preview3_sockets_interface, "[method]udp-socket.send"),
    (args, table) => {
      let state = preview3_udp_socket_state(host, table, args, 0)
      guard component_bytes(args[1]) is Some(data) &&
        decode_optional_socket_address(args[2]) is Some(remote) else {
        return preview3_ready_future([preview3_socket_error_code(2)])
      }
      let destination = match (state.remote.val, remote) {
        (Some(_), None) => None
        (Some(expected), Some(actual)) =>
          if native_socket_address_equal(expected, actual.native) {
            None
          } else {
            return preview3_ready_future([preview3_socket_error_code(2)])
          }
        (None, Some(address)) =>
          if address.native.family == state.family &&
            network_allows(preview3_network_policy(host), address) {
            Some(address.native)
          } else {
            return preview3_ready_future([preview3_socket_error_code(0)])
          }
        (None, None) =>
          return preview3_ready_future([preview3_socket_error_code(5)])
      }
      preview3_udp_async_future(host, state, 0x04, () => {
        let sent = @wasi.native_socket_send_to(state.fd, data, destination)
        if sent == data.length().to_int64() {
          Some(preview3_socket_ok_void())
        } else if sent < 0L && @wasi.native_last_errno_to_wasi() == 6 {
          None
        } else {
          Some(preview3_socket_error())
        }
      })
    },
  )
  builder.add_async_func(
    "[method]udp-socket.receive",
    preview3_func(preview3_sockets_interface, "[method]udp-socket.receive"),
    (args, table) => {
      let state = preview3_udp_socket_state(host, table, args, 0)
      preview3_udp_async_future(host, state, 0x01, () => {
        match @wasi.native_socket_recv_from(state.fd, 65535) {
          Some(datagram) =>
            Some(
              preview3_socket_ok(
                Tuple([
                  encode_component_bytes(datagram.data),
                  encode_socket_address(datagram.address),
                ]),
              ),
            )
          None =>
            if @wasi.native_last_errno_to_wasi() == 6 {
              None
            } else {
              Some(preview3_socket_error())
            }
        }
      })
    },
  )
  fn add_address(
    name : String,
    peer : Bool,
  ) -> Unit raise @runtime_impl.ComponentRuntimeError {
    builder.add_func(name, preview3_func(preview3_sockets_interface, name), (
      args,
      table,
    ) => {
      let state = preview3_udp_socket_state(host, table, args, 0)
      [
        match @wasi.native_socket_address(state.fd, peer) {
          Some(address) => preview3_socket_ok(encode_socket_address(address))
          None => preview3_socket_error()
        },
      ]
    })
  }
  add_address("[method]udp-socket.get-local-address", false)
  add_address("[method]udp-socket.get-remote-address", true)
  builder.add_func(
    "[method]udp-socket.get-address-family",
    preview3_func(
      preview3_sockets_interface, "[method]udp-socket.get-address-family",
    ),
    (args, table) => {
      [
        U32(
          if preview3_udp_socket_state(host, table, args, 0).family == 4 {
            0
          } else {
            1
          },
        ),
      ]
    },
  )
  add_preview3_udp_options(host, builder)
}

///|
fn preview3_lookup_error(index : Int) -> @runtime_impl.ComponentValue {
  Variant(
    1,
    Some(
      if index == 5 {
        Variant(5, Some(Variant(0, None)))
      } else {
        Variant(index, None)
      },
    ),
  )
}

///|
fn preview3_resolve_addresses_future(
  host : WasiComponentHost,
  name : String,
) -> @runtime_impl.HostFuture raise @runtime_impl.ComponentRuntimeError {
  let policy = preview3_network_policy(host)
  if name.length() == 0 || name.length() > 253 {
    return preview3_ready_future([preview3_lookup_error(1)])
  }
  if policy == DenyAll ||
    (policy == LoopbackOnly && !loopback_name_allowed(name)) {
    return preview3_ready_future([preview3_lookup_error(0)])
  }
  guard @wasi.native_resolver_start(name) is Some(resolver) else {
    return preview3_ready_future([preview3_lookup_error(5)])
  }
  let operation : Ref[Int?] = Ref(None)
  let addresses : Array[@runtime_impl.ComponentValue] = []
  let done = Ref(false)
  fn cleanup() {
    match operation.val {
      Some(id) => host.ctx.cancel_async_fd(id)
      None => ()
    }
    operation.val = None
    if !done.val {
      done.val = true
      @wasi.native_resolver_drop(resolver.handle)
    }
  }
  HostFuture(
    () => {
      match operation.val {
        Some(id) =>
          if host.ctx.async_fd_ready(id) {
            operation.val = None
          } else {
            return Pending
          }
        None => ()
      }
      while true {
        match @wasi.native_resolver_next(resolver.handle) {
          Address(address) =>
            if policy != LoopbackOnly || native_address_is_loopback(address) {
              addresses.push(encode_ip_address(address))
            }
          Pending => {
            operation.val = Some(
              host.ctx.register_async_fd(resolver.poll_fd, 0x01),
            )
            return Pending
          }
          Finished => {
            cleanup()
            return Ready([preview3_socket_ok(List(addresses.copy()))])
          }
          NameUnresolvable => {
            cleanup()
            return Ready([preview3_lookup_error(2)])
          }
          TemporaryFailure => {
            cleanup()
            return Ready([preview3_lookup_error(3)])
          }
          PermanentFailure => {
            cleanup()
            return Ready([preview3_lookup_error(4)])
          }
        }
      }
      Ready([preview3_lookup_error(5)])
    },
    () => cleanup(),
  )
}

///|
fn add_preview3_ip_name_lookup(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.3.0/ip-name-lookup"
  let builder = host.linker.host_instance_builder(
    "wasi:sockets/ip-name-lookup@\{preview3_version}",
    host.runtime,
  )
  host.prepare_preview3_interface(builder, interface)
  builder.add_async_func(
    "resolve-addresses",
    preview3_func(interface, "resolve-addresses"),
    (args, _table) => {
      guard args is [String(name)] else {
        raise HostCallError("expected resolver name")
      }
      preview3_resolve_addresses_future(host, name)
    },
  )
  host.linker.add_instance(
    "wasi:sockets/ip-name-lookup@\{preview3_version}",
    builder.finish(),
  )
}

///|
pub fn WasiComponentHost::add_preview3_sockets(
  self : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = self.linker.host_instance_builder(
    "wasi:sockets/types@\{preview3_version}",
    self.runtime,
  )
  self.prepare_preview3_interface(builder, preview3_sockets_interface)
  add_preview3_tcp(self, builder)
  add_preview3_udp(self, builder)
  self.linker.add_instance(
    "wasi:sockets/types@\{preview3_version}",
    builder.finish(),
  )
  add_preview3_ip_name_lookup(self)
}
