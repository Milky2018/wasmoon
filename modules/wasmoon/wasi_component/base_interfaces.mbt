///|
pub let preview2_version : String = "0.2.11"

///|
pub let preview3_version : String = "0.3.0-rc-2025-09-16"

///|
fn empty_args(
  args : Array[@runtime_impl.ComponentValue],
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  if args.length() != 0 {
    raise HostCallError("expected no arguments")
  }
}

///|
fn random_length(
  args : Array[@runtime_impl.ComponentValue],
) -> Int raise @runtime_impl.ComponentRuntimeError {
  match args {
    [U64(len)] =>
      if len < 0L || len > 0x7fffffffL {
        raise HostCallError("random byte length is not representable")
      } else {
        len.to_int()
      }
    _ => raise HostCallError("expected one u64 length")
  }
}

///|
fn bytes_to_component_list(
  bytes : FixedArray[Byte],
) -> @runtime_impl.ComponentValue {
  let values : Array[@runtime_impl.ComponentValue] = []
  for byte in bytes {
    values.push(U8(byte.to_int()))
  }
  List(values)
}

///|
fn secure_random_bytes(
  len : Int,
) -> FixedArray[Byte] raise @runtime_impl.ComponentRuntimeError {
  let bytes = FixedArray::make(len, b'\x00')
  if !@wasi.native_getrandom(bytes, len) {
    raise HostCallError("operating-system random provider failed")
  }
  bytes
}

///|
fn little_endian_u64(bytes : FixedArray[Byte]) -> Int64 {
  let mut value = 0L
  for i in 0..<8 {
    value = value | (bytes[i].to_int().to_int64() << (i * 8))
  }
  value
}

///|
fn insecure_bytes(ctx : WasiComponentCtx, len : Int) -> FixedArray[Byte] {
  let bytes = FixedArray::make(len, b'\x00')
  let mut offset = 0
  while offset < len {
    let value = ctx.next_insecure_u64()
    let count = if len - offset < 8 { len - offset } else { 8 }
    for i in 0..<count {
      bytes[offset + i] = ((value >> (i * 8)) & 0xffL).to_int().to_byte()
    }
    offset = offset + count
  }
  bytes
}

///|
fn add_environment_interface(
  host : WasiComponentHost,
  version : String,
  cwd_export : String,
  preview3 : Bool,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:cli/environment@\{version}",
    host.runtime,
  )
  let interface = "wasi:cli@\{version}/environment"
  if preview3 {
    host.prepare_preview3_interface(builder, interface)
  } else {
    host.prepare_preview2_interface(builder, interface)
  }
  fn contract(
    name : String,
  ) -> @component.FuncType raise @runtime_impl.ComponentRuntimeError {
    if preview3 {
      preview3_func(interface, name)
    } else {
      preview2_func(interface, name)
    }
  }
  builder.add_func("get-environment", contract("get-environment"), (
    args,
    _table,
  ) => {
    empty_args(args)
    let values : Array[@runtime_impl.ComponentValue] = []
    for entry in host.ctx.environment() {
      let (key, value) = entry
      values.push(Tuple([String(key), String(value)]))
    }
    [List(values)]
  })
  builder.add_func("get-arguments", contract("get-arguments"), (args, _table) => {
    empty_args(args)
    let values : Array[@runtime_impl.ComponentValue] = []
    for arg in host.ctx.arguments() {
      values.push(String(arg))
    }
    [List(values)]
  })
  builder.add_func(cwd_export, contract(cwd_export), (args, _table) => {
    empty_args(args)
    match host.ctx.initial_cwd() {
      Some(path) => [Variant(1, Some(String(path)))]
      None => [Variant(0, None)]
    }
  })
  host.linker.add_instance("wasi:cli/environment@\{version}", builder.finish())
}

///|
fn add_exit_interface(
  host : WasiComponentHost,
  version : String,
  preview3 : Bool,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:cli/exit@\{version}",
    host.runtime,
  )
  let interface = "wasi:cli@\{version}/exit"
  let contract = if preview3 {
    host.prepare_preview3_interface(builder, interface)
    preview3_func(interface, "exit")
  } else {
    host.prepare_preview2_interface(builder, interface)
    preview2_func(interface, "exit")
  }
  builder.add_func("exit", contract, (args, _table) => {
    match args {
      [Variant(0, None)] => {
        host.ctx.request_exit(0)
        []
      }
      [Variant(1, None)] => {
        host.ctx.request_exit(1)
        []
      }
      _ => raise HostCallError("expected result status")
    }
  })
  host.linker.add_instance("wasi:cli/exit@\{version}", builder.finish())
}

///|
fn add_wall_clock_interface(
  host : WasiComponentHost,
  version : String,
  resolution_export : String,
  preview3 : Bool,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:clocks/wall-clock@\{version}",
    host.runtime,
  )
  let interface = "wasi:clocks@\{version}/wall-clock"
  if preview3 {
    host.prepare_preview3_interface(builder, interface)
  } else {
    host.prepare_preview2_interface(builder, interface)
  }
  fn contract(
    name : String,
  ) -> @component.FuncType raise @runtime_impl.ComponentRuntimeError {
    if preview3 {
      preview3_func(interface, name)
    } else {
      preview2_func(interface, name)
    }
  }
  builder.add_func("now", contract("now"), (args, _table) => {
    empty_args(args)
    let now = @wasi.native_clock_gettime_realtime()
    if now < 0L {
      raise HostCallError("wall clock is unavailable")
    }
    [Tuple([U64(now / 1000000000L), U32((now % 1000000000L).to_int())])]
  })
  builder.add_func(resolution_export, contract(resolution_export), (
    args,
    _table,
  ) => {
    empty_args(args)
    guard @wasi.native_clock_getres_realtime() is Some(resolution) else {
      raise HostCallError("wall clock resolution is unavailable")
    }
    [
      Tuple([
        U64(resolution / 1000000000L),
        U32((resolution % 1000000000L).to_int()),
      ]),
    ]
  })
  host.linker.add_instance(
    "wasi:clocks/wall-clock@\{version}",
    builder.finish(),
  )
}

///|
fn add_random_interface(
  host : WasiComponentHost,
  version : String,
  preview3 : Bool,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:random/random@\{version}",
    host.runtime,
  )
  let interface = "wasi:random@\{version}/random"
  if preview3 {
    host.prepare_preview3_interface(builder, interface)
  } else {
    host.prepare_preview2_interface(builder, interface)
  }
  fn contract(
    name : String,
  ) -> @component.FuncType raise @runtime_impl.ComponentRuntimeError {
    if preview3 {
      preview3_func(interface, name)
    } else {
      preview2_func(interface, name)
    }
  }
  builder.add_func("get-random-bytes", contract("get-random-bytes"), (
    args,
    _table,
  ) => {
    let len = random_length(args)
    [bytes_to_component_list(secure_random_bytes(len))]
  })
  builder.add_func("get-random-u64", contract("get-random-u64"), (args, _table) => {
    empty_args(args)
    [U64(little_endian_u64(secure_random_bytes(8)))]
  })
  host.linker.add_instance("wasi:random/random@\{version}", builder.finish())
}

///|
fn add_insecure_random_interface(
  host : WasiComponentHost,
  version : String,
  preview3 : Bool,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:random/insecure@\{version}",
    host.runtime,
  )
  let interface = "wasi:random@\{version}/insecure"
  if preview3 {
    host.prepare_preview3_interface(builder, interface)
  } else {
    host.prepare_preview2_interface(builder, interface)
  }
  fn contract(
    name : String,
  ) -> @component.FuncType raise @runtime_impl.ComponentRuntimeError {
    if preview3 {
      preview3_func(interface, name)
    } else {
      preview2_func(interface, name)
    }
  }
  builder.add_func(
    "get-insecure-random-bytes",
    contract("get-insecure-random-bytes"),
    (args, _table) => {
      let len = random_length(args)
      [bytes_to_component_list(insecure_bytes(host.ctx, len))]
    },
  )
  builder.add_func(
    "get-insecure-random-u64",
    contract("get-insecure-random-u64"),
    (args, _table) => {
      empty_args(args)
      [U64(host.ctx.next_insecure_u64())]
    },
  )
  host.linker.add_instance("wasi:random/insecure@\{version}", builder.finish())
}

///|
fn add_insecure_seed_interface(
  host : WasiComponentHost,
  version : String,
  export_name : String,
  preview3 : Bool,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:random/insecure-seed@\{version}",
    host.runtime,
  )
  let interface = "wasi:random@\{version}/insecure-seed"
  let contract = if preview3 {
    host.prepare_preview3_interface(builder, interface)
    preview3_func(interface, export_name)
  } else {
    host.prepare_preview2_interface(builder, interface)
    preview2_func(interface, export_name)
  }
  builder.add_func(export_name, contract, (args, _table) => {
    empty_args(args)
    let (low, high) = host.ctx.insecure_seed
    [Tuple([U64(low), U64(high)])]
  })
  host.linker.add_instance(
    "wasi:random/insecure-seed@\{version}",
    builder.finish(),
  )
}

///|
/// Register the complete resource-free portion of the stable Preview 2 command
/// world. Stream, poll, filesystem, and socket interfaces are registered by
/// their dedicated host layers.
fn add_preview2_base_interfaces(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  add_environment_interface(host, preview2_version, "initial-cwd", false)
  add_exit_interface(host, preview2_version, false)
  add_wall_clock_interface(host, preview2_version, "resolution", false)
  add_random_interface(host, preview2_version, false)
  add_insecure_random_interface(host, preview2_version, false)
  add_insecure_seed_interface(host, preview2_version, "insecure-seed", false)
}

///|
/// Register the resource-free portion of the pinned Preview 3 async command
/// world. Async waits and stream/future interfaces are registered separately.
fn add_preview3_base_interfaces(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  add_environment_interface(host, preview3_version, "get-initial-cwd", true)
  add_exit_interface(host, preview3_version, true)
  add_wall_clock_interface(host, preview3_version, "get-resolution", true)
  add_random_interface(host, preview3_version, true)
  add_insecure_random_interface(host, preview3_version, true)
  add_insecure_seed_interface(host, preview3_version, "get-insecure-seed", true)
}
