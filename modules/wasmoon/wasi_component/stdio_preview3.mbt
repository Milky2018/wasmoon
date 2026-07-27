///|
fn preview3_future_element(
  host : WasiComponentHost,
  interface : String,
  function : String,
) -> (@component.ValType, Array[@component.TypeDef?]) raise @runtime_impl.ComponentRuntimeError {
  let types = wasi_preview3_type_space(name => host.resolve_resource_type(name))
  guard preview3_func(interface, function).result is Some(TypeIdx(tuple_index)) &&
    types.get(tuple_index) is Some(Some(Tuple([_, TypeIdx(future_index)]))) &&
    types.get(future_index) is Some(Some(Future(Some(element)))) else {
    raise HostCallError("generated Preview 3 future contract is malformed")
  }
  (element, types)
}

///|
fn preview3_stdin_snapshot(ctx : WasiComponentCtx) -> (Bytes, Int?) {
  match ctx.get_resource(ctx.stdin_rep) {
    Some(InputStream(state)) if !state.closed.val && state.native_fd is None => {
      let bytes : Array[Byte] = []
      for i in state.offset.val..<state.bytes.val.length() {
        bytes.push(state.bytes.val[i])
      }
      state.offset.val = state.bytes.val.length()
      (Bytes::from_array(bytes), None)
    }
    _ => (b"", Some(0))
  }
}

///|
fn preview3_output_write_once(
  state : OutputStreamState,
  bytes : Bytes,
  offset : Int,
) -> Int {
  if state.closed.val || offset < 0 || offset > bytes.length() {
    return -1
  }
  let remaining = bytes.length() - offset
  if remaining == 0 {
    return 0
  }
  match state.native_fd {
    None => if (state.write)(bytes) { remaining } else { -1 }
    Some(fd) => {
      let buffer = FixedArray::makei(remaining, fn(i) { bytes[offset + i] })
      match @wasi.native_write(fd, buffer, remaining) {
        Some(written) => written
        None => if @wasi.native_last_errno_to_wasi() == 6 { 0 } else { -1 }
      }
    }
  }
}

///|
fn preview3_output_future(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  readable : Int,
  output_rep : Int,
) -> @runtime_impl.HostFuture raise @runtime_impl.ComponentRuntimeError {
  guard host.ctx.get_resource(output_rep) is Some(OutputStream(output)) else {
    raise HostCallError("Preview 3 output stream is unavailable")
  }
  let pending : Ref[(Bytes, Int)?] = Ref(None)
  let fd_operation : Ref[Int?] = Ref(None)
  let done = Ref(false)
  fn register_fd() {
    match (output.native_fd, fd_operation.val) {
      (Some(fd), None) =>
        fd_operation.val = Some(host.ctx.register_async_fd(fd, 0x04))
      _ => ()
    }
  }

  fn cleanup() -> Unit raise @runtime_impl.ComponentRuntimeError {
    match fd_operation.val {
      Some(operation) => host.ctx.cancel_async_fd(operation)
      None => ()
    }
    fd_operation.val = None
    if !done.val {
      host.runtime.drop_host_readable_stream(table, readable)
      done.val = true
    }
  }

  HostFuture(
    () => {
      if done.val {
        return Ready([Variant(0, None)])
      }
      match fd_operation.val {
        Some(operation) =>
          if host.ctx.async_fd_ready(operation) {
            fd_operation.val = None
          } else {
            return Pending
          }
        None => ()
      }
      match pending.val {
        Some((bytes, offset)) => {
          let written = preview3_output_write_once(output, bytes, offset)
          if written < 0 {
            cleanup()
            return Ready([Variant(1, Some(Variant(0, None)))])
          }
          let next = offset + written
          if next < bytes.length() {
            pending.val = Some((bytes, next))
            register_fd()
            return Pending
          }
          pending.val = None
        }
        None => ()
      }
      match host.runtime.read_host_byte_stream(table, readable) {
        Data(bytes) => {
          let written = preview3_output_write_once(output, bytes, 0)
          if written < 0 {
            cleanup()
            Ready([Variant(1, Some(Variant(0, None)))])
          } else if written < bytes.length() {
            pending.val = Some((bytes, written))
            register_fd()
            Pending
          } else {
            match host.runtime.read_host_byte_stream(table, readable) {
              Closed => {
                cleanup()
                Ready([Variant(0, None)])
              }
              Data(next) => {
                pending.val = Some((next, 0))
                register_fd()
                Pending
              }
              Pending => Pending
            }
          }
        }
        Pending => Pending
        Closed => {
          cleanup()
          Ready([Variant(0, None)])
        }
      }
    },
    () => cleanup(),
  )
}

///|
fn add_preview3_stdio_types(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  for name in ["types", "terminal-input", "terminal-output"] {
    let interface = "wasi:cli@\{preview3_version}/\{name}"
    let builder = host.linker.host_instance_builder(
      "wasi:cli/\{name}@\{preview3_version}",
      host.runtime,
    )
    host.prepare_preview3_interface(builder, interface)
    host.linker.add_instance(
      "wasi:cli/\{name}@\{preview3_version}",
      builder.finish(),
    )
  }
}

///|
fn add_preview3_stdin(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:cli@\{preview3_version}/stdin"
  let builder = host.linker.host_instance_builder(
    "wasi:cli/stdin@\{preview3_version}",
    host.runtime,
  )
  host.prepare_preview3_interface(builder, interface)
  builder.add_func(
    "read-via-stream",
    preview3_func(interface, "read-via-stream"),
    (args, table) => {
      empty_args(args)
      let (bytes, error_case) = preview3_stdin_snapshot(host.ctx)
      let readable = host.runtime.new_host_byte_stream(table, bytes)
      let (future_element, types) = preview3_future_element(
        host, interface, "read-via-stream",
      )
      let future = match error_case {
        Some(error_case) =>
          host.runtime.new_host_unit_result_future(
            table,
            future_element,
            types,
            error_case~,
          )
        None =>
          host.runtime.new_host_unit_result_future(table, future_element, types)
      }
      [Tuple([U32(readable), U32(future)])]
    },
  )
  host.linker.add_instance(
    "wasi:cli/stdin@\{preview3_version}",
    builder.finish(),
  )
}

///|
fn add_preview3_output(
  host : WasiComponentHost,
  name : String,
  output_rep : Int,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:cli@\{preview3_version}/\{name}"
  let builder = host.linker.host_instance_builder(
    "wasi:cli/\{name}@\{preview3_version}",
    host.runtime,
  )
  host.prepare_preview3_interface(builder, interface)
  builder.add_async_func(
    "write-via-stream",
    preview3_func(interface, "write-via-stream"),
    (args, table) => {
      guard args is [U32(readable)] else {
        raise HostCallError("expected Preview 3 byte stream")
      }
      preview3_output_future(host, table, readable, output_rep)
    },
  )
  host.linker.add_instance(
    "wasi:cli/\{name}@\{preview3_version}",
    builder.finish(),
  )
}

///|
fn add_preview3_terminal_getter(
  host : WasiComponentHost,
  name : String,
  function : String,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:cli@\{preview3_version}/\{name}"
  let builder = host.linker.host_instance_builder(
    "wasi:cli/\{name}@\{preview3_version}",
    host.runtime,
  )
  host.prepare_preview3_interface(builder, interface)
  builder.add_func(function, preview3_func(interface, function), (args, _table) => {
    empty_args(args)
    [Variant(0, None)]
  })
  host.linker.add_instance(
    "wasi:cli/\{name}@\{preview3_version}",
    builder.finish(),
  )
}

///|
fn add_preview3_stdio(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  add_preview3_stdio_types(host)
  add_preview3_stdin(host)
  add_preview3_output(host, "stdout", host.ctx.stdout_rep)
  add_preview3_output(host, "stderr", host.ctx.stderr_rep)
  add_preview3_terminal_getter(host, "terminal-stdin", "get-terminal-stdin")
  add_preview3_terminal_getter(host, "terminal-stdout", "get-terminal-stdout")
  add_preview3_terminal_getter(host, "terminal-stderr", "get-terminal-stderr")
}
