///|
fn encode_ip_address(
  address : @wasi.NativeSocketAddress,
) -> @runtime_impl.ComponentValue {
  if address.family == 4 {
    Variant(
      0,
      Some(
        Tuple([
          U8(address.address[0].to_int()),
          U8(address.address[1].to_int()),
          U8(address.address[2].to_int()),
          U8(address.address[3].to_int()),
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
    Variant(1, Some(Tuple(words)))
  }
}

///|
fn native_address_is_loopback(address : @wasi.NativeSocketAddress) -> Bool {
  if address.family == 4 {
    return address.address[0] == b'\x7f'
  }
  if address.family != 6 || address.address[15] != b'\x01' {
    return false
  }
  for i in 0..<15 {
    if address.address[i] != b'\x00' {
      return false
    }
  }
  true
}

///|
fn loopback_name_allowed(name : String) -> Bool {
  if name == "localhost" ||
    name == "localhost." ||
    name == "::1" ||
    name == "0:0:0:0:0:0:0:1" {
    return true
  }
  name.length() >= 4 &&
  name.code_unit_at(0) == '1' &&
  name.code_unit_at(1) == '2' &&
  name.code_unit_at(2) == '7' &&
  name.code_unit_at(3) == '.'
}

///|
fn resolve_address_stream_state(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> ResolveAddressStreamState raise @runtime_impl.ComponentRuntimeError {
  let resource_type = host.resolve_resource_type(
    "wasi:sockets@0.2.11/ip-name-lookup.resolve-address-stream",
  )
  let rep = resource_rep(table, resource_handle_arg(args, index), resource_type)
  match host.ctx.get_resource(rep) {
    Some(ResolveAddressStream(state)) if !state.closed.val => state
    _ => raise HostCallError("resolve address stream is not live")
  }
}

///|
fn add_preview2_ip_name_lookup(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:sockets@0.2.11/ip-name-lookup"
  let builder = host.linker.host_instance_builder(
    "wasi:sockets/ip-name-lookup@\{preview2_version}",
    host.runtime,
  )
  host.prepare_preview2_interface(builder, interface)
  builder.add_func(
    "resolve-addresses",
    preview2_func(interface, "resolve-addresses"),
    (args, table) => {
      let policy = network_policy_for(host, table, args, 0)
      guard args[1] is String(name) else {
        raise HostCallError("expected resolver name")
      }
      if name.length() == 0 || name.length() > 253 {
        return [socket_error_code(3)]
      }
      if policy == DenyAll ||
        (policy == LoopbackOnly && !loopback_name_allowed(name)) {
        return [socket_error_code(1)]
      }
      match @wasi.native_resolver_start(name) {
        Some(resolver) => {
          let rep = host.ctx.insert_resource(
            ResolveAddressStream({
              resolver: resolver.handle,
              poll_fd: resolver.poll_fd,
              policy,
              closed: Ref(false),
            }),
          )
          [
            socket_ok(
              U32(
                allocate_resource_handle(
                  host.ctx,
                  table,
                  host.resolve_resource_type(
                    "wasi:sockets@0.2.11/ip-name-lookup.resolve-address-stream",
                  ),
                  rep,
                ),
              ),
            ),
          ]
        }
        None => [socket_error_code(4)]
      }
    },
  )
  builder.add_func(
    "[method]resolve-address-stream.resolve-next-address",
    preview2_func(
      interface, "[method]resolve-address-stream.resolve-next-address",
    ),
    (args, table) => {
      let state = resolve_address_stream_state(host, table, args, 0)
      while true {
        match @wasi.native_resolver_next(state.resolver) {
          Address(address) =>
            if state.policy == LoopbackOnly &&
              !native_address_is_loopback(address) {
              continue
            } else {
              return [socket_ok(Variant(1, Some(encode_ip_address(address))))]
            }
          Pending => return [socket_error_code(8)]
          Finished => return [socket_ok(Variant(0, None))]
          NameUnresolvable => return [socket_error_code(18)]
          TemporaryFailure => return [socket_error_code(19)]
          PermanentFailure => return [socket_error_code(20)]
        }
      }
      [socket_error_code(0)]
    },
  )
  builder.add_func(
    "[method]resolve-address-stream.subscribe",
    preview2_func(interface, "[method]resolve-address-stream.subscribe"),
    (args, table) => {
      let state = resolve_address_stream_state(host, table, args, 0)
      guard @wasi.native_dup(state.poll_fd) is Some(poll_fd) else {
        raise HostCallError("resolver pollable allocation failed")
      }
      let rep = host.ctx.insert_resource(Pollable(OwnedSocket(poll_fd, 0x01)))
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
  host.linker.add_instance(
    "wasi:sockets/ip-name-lookup@\{preview2_version}",
    builder.finish(),
  )
}
