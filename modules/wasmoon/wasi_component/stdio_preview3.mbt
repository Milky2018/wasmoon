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
priv struct Preview3StdinSource {
  ctx : WasiComponentCtx
  state : InputStreamState
  fd : Int
  buffered : Array[Byte]
  next : Ref[Int]
  always_ready : Bool
  operation : Ref[WasiAsyncOperation?]
  completion : Ref[@runtime_impl.ComponentValue?]
}

///|
fn Preview3StdinSource::new(
  ctx : WasiComponentCtx,
  state : InputStreamState,
  fd : Int,
) -> Preview3StdinSource raise @runtime_impl.ComponentRuntimeError {
  let stat = @wasi.native_fstat(fd)
  let invalid = stat is None
  let always_ready = match stat {
    Some(stat) => stat.filetype == 4
    None => false
  }
  if invalid {
    state.closed.val = true
  }
  {
    ctx,
    state,
    fd,
    buffered: [],
    next: Ref(0),
    always_ready,
    operation: Ref(
      if state.closed.val || always_ready || invalid {
        None
      } else {
        Some(ctx.register_async_fd(fd, 0x01))
      },
    ),
    completion: Ref(
      if invalid {
        Some(Variant(1, Some(U32(0))))
      } else if state.closed.val {
        Some(Variant(0, None))
      } else {
        None
      },
    ),
  }
}

///|
fn Preview3StdinSource::cancel_operation(self : Preview3StdinSource) -> Unit {
  match self.operation.val {
    Some(operation) => self.ctx.cancel_async_operation(operation)
    None => ()
  }
  self.operation.val = None
}

///|
fn Preview3StdinSource::complete(
  self : Preview3StdinSource,
  value : @runtime_impl.ComponentValue,
  close_input : Bool,
) -> Unit {
  if self.completion.val is None {
    self.completion.val = Some(value)
  }
  if close_input {
    self.state.closed.val = true
  }
  self.cancel_operation()
}

///|
fn Preview3StdinSource::pump(
  self : Preview3StdinSource,
  capacity : Int,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  if self.completion.val is Some(_) || self.next.val < self.buffered.length() {
    return
  }
  match self.operation.val {
    Some(operation) =>
      if self.ctx.async_operation_ready(operation) {
        self.operation.val = None
      } else {
        return
      }
    None => if !self.always_ready { return }
  }
  let count = if capacity <= 0 {
    1
  } else if capacity > 65536 {
    65536
  } else {
    capacity
  }
  let buffer = FixedArray::make(count, b'\x00')
  match @wasi.native_read(self.fd, buffer, count) {
    Some(0) => self.complete(Variant(0, None), true)
    Some(read) => {
      self.buffered.clear()
      self.next.val = 0
      for i in 0..<read {
        self.buffered.push(buffer[i])
      }
      let reached_regular_file_end = self.always_ready &&
        @wasi.native_fstat(self.fd) is Some(stat) &&
        @wasi.native_tell(self.fd) is Some(position) &&
        position >= 0L &&
        stat.size <= position.reinterpret_as_uint64()
      if reached_regular_file_end {
        self.complete(Variant(0, None), true)
      } else if !self.always_ready {
        self.operation.val = Some(self.ctx.register_async_fd(self.fd, 0x01))
      }
    }
    None =>
      if @wasi.native_last_errno_to_wasi() == 6 {
        self.operation.val = Some(self.ctx.register_async_fd(self.fd, 0x01))
      } else {
        self.complete(Variant(1, Some(U32(0))), true)
      }
  }
}

///|
fn Preview3StdinSource::pull(
  self : Preview3StdinSource,
  maximum : Int,
) -> @runtime_impl.HostValueStreamPoll raise @runtime_impl.ComponentRuntimeError {
  if maximum <= 0 {
    return Values([])
  }
  if self.next.val >= self.buffered.length() {
    self.buffered.clear()
    self.next.val = 0
    self.pump(maximum)
  }
  let available = self.buffered.length() - self.next.val
  if available > 0 {
    let count = if maximum < available { maximum } else { available }
    let values : Array[@runtime_impl.ComponentValue] = []
    for i in 0..<count {
      values.push(U8(self.buffered[self.next.val + i].to_int()))
    }
    self.next.val = self.next.val + count
    Values(values)
  } else if self.completion.val is Some(_) {
    Closed
  } else {
    Pending
  }
}

///|
fn preview3_native_stdin(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  state : InputStreamState,
  fd : Int,
  stream_element : @component.ValType,
  future_element : @component.ValType,
  types : Array[@component.TypeDef?],
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  let source = Preview3StdinSource::new(host.ctx, state, fd)
  let users = Ref(2)
  fn release() {
    if users.val > 0 {
      users.val = users.val - 1
    }
    if users.val == 0 {
      source.cancel_operation()
    }
  }
  let stream = host.runtime.new_host_value_stream_source(
    table,
    stream_element,
    types,
    maximum => source.pull(maximum),
    () => {
      source.complete(Variant(0, None), false)
      release()
    },
  )
  let future = host.runtime.new_host_value_future_source(
    table,
    future_element,
    types,
    () => {
      source.pump(65536)
      match source.completion.val {
        Some(value) => Ready(value)
        None => Pending
      }
    },
    () => release(),
  )
  Tuple([U32(stream), U32(future)])
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
  let fd_operation : Ref[WasiAsyncOperation?] = Ref(None)
  let done = Ref(false)
  fn register_fd() raise @runtime_impl.ComponentRuntimeError {
    match (output.native_fd, fd_operation.val) {
      (Some(fd), None) =>
        fd_operation.val = Some(host.ctx.register_async_fd(fd, 0x04))
      _ => ()
    }
  }

  fn cleanup() -> Unit raise @runtime_impl.ComponentRuntimeError {
    match fd_operation.val {
      Some(operation) => host.ctx.cancel_async_operation(operation)
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
          if host.ctx.async_operation_ready(operation) {
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
      let (stream_element, future_element, types) = preview3_stream_future_types(
        host, interface, "read-via-stream",
      )
      match host.ctx.get_resource(host.ctx.stdin_rep) {
        Some(InputStream(state)) =>
          match state.native_fd {
            Some(fd) =>
              [
                preview3_native_stdin(
                  host, table, state, fd, stream_element, future_element, types,
                ),
              ]
            None => {
              let (bytes, error_case) = preview3_stdin_snapshot(host.ctx)
              let readable = host.runtime.new_host_byte_stream(table, bytes)
              let future = match error_case {
                Some(error_case) =>
                  host.runtime.new_host_unit_result_future(
                    table,
                    future_element,
                    types,
                    error_case~,
                  )
                None =>
                  host.runtime.new_host_unit_result_future(
                    table, future_element, types,
                  )
              }
              [Tuple([U32(readable), U32(future)])]
            }
          }
        _ => {
          let readable = host.runtime.new_host_byte_stream(table, b"")
          let future = host.runtime.new_host_unit_result_future(
            table,
            future_element,
            types,
            error_case=0,
          )
          [Tuple([U32(readable), U32(future)])]
        }
      }
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
  builder.add_func(
    "write-via-stream",
    preview3_func(interface, "write-via-stream"),
    (args, table) => {
      guard args is [U32(readable)] else {
        raise HostCallError("expected Preview 3 byte stream")
      }
      [
        preview3_call_future_value(
          host,
          table,
          interface,
          "write-via-stream",
          preview3_output_future(host, table, readable, output_rep),
        ),
      ]
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
