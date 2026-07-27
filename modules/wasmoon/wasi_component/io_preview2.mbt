///|
fn resource_type_id(
  ty : @component.TypeDef?,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  match ty {
    Some(ResourceType(id, _, _, HostDefined)) => id
    _ => raise HostCallError("invalid host resource type")
  }
}

///|
fn allocate_resource_handle(
  ctx : WasiComponentCtx,
  table : @runtime_impl.ResourceTable,
  ty : @component.TypeDef?,
  rep : Int,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  let type_id = resource_type_id(ty)
  table.alloc({
    type_id,
    rep,
    dtor: None,
    host_dtor: Some(HostResourceDestructor(fn(rep) { ctx.drop_resource(rep) })),
    kind: HostDefined,
    impl_component_id: table.id,
    own: true,
    borrow_scope: None,
    num_lends: [0],
  })
}

///|
fn resource_rep(
  table : @runtime_impl.ResourceTable,
  handle : Int,
  ty : @component.TypeDef?,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  let type_id = resource_type_id(ty)
  match table.get(handle) {
    Some(resource) =>
      if resource.type_id == type_id {
        resource.rep
      } else {
        raise HostCallError("resource handle has the wrong type")
      }
    None => raise HostCallError("resource handle is not live")
  }
}

///|
fn resource_handle_arg(
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  if index < 0 || index >= args.length() {
    raise HostCallError("missing resource argument")
  }
  match args[index] {
    U32(handle) => handle
    _ => raise HostCallError("expected resource handle")
  }
}

///|
fn ok_void() -> @runtime_impl.ComponentValue {
  Variant(0, None)
}

///|
fn closed_stream_error() -> @runtime_impl.ComponentValue {
  Variant(1, None)
}

///|
fn err_closed() -> @runtime_impl.ComponentValue {
  Variant(1, Some(closed_stream_error()))
}

///|
fn err_last_operation_failed(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  message : String,
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  let rep = host.ctx.insert_resource(IoError(message, None))
  let handle = allocate_resource_handle(
    host.ctx,
    table,
    host.resource_types.error,
    rep,
  )
  Variant(1, Some(Variant(0, Some(U32(handle)))))
}

///|
fn ok_value(
  value : @runtime_impl.ComponentValue,
) -> @runtime_impl.ComponentValue {
  Variant(0, Some(value))
}

///|
fn component_list_to_bytes(
  value : @runtime_impl.ComponentValue,
) -> Bytes raise @runtime_impl.ComponentRuntimeError {
  guard value is List(values) else { raise HostCallError("expected byte list") }
  let bytes : Array[Byte] = []
  for value in values {
    match value {
      U8(byte) if byte >= 0 && byte <= 255 => bytes.push(byte.to_byte())
      _ => raise HostCallError("expected byte list")
    }
  }
  Bytes::from_array(bytes)
}

///|
fn bytes_to_list_range(
  bytes : Bytes,
  start : Int,
  end : Int,
) -> @runtime_impl.ComponentValue {
  let values : Array[@runtime_impl.ComponentValue] = []
  for i in start..<end {
    values.push(U8(bytes[i].to_int()))
  }
  List(values)
}

///|
fn stream_length_arg(
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  if index < 0 || index >= args.length() {
    raise HostCallError("missing stream length")
  }
  match args[index] {
    U64(len) =>
      if len < 0L || len > 0x7fffffffL {
        raise HostCallError("stream length is not representable")
      } else {
        len.to_int()
      }
    _ => raise HostCallError("expected u64 stream length")
  }
}

///|
fn read_input_stream(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  rep : Int,
  len : Int,
  blocking : Bool,
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  guard host.ctx.get_resource(rep) is Some(InputStream(state)) else {
    raise HostCallError("input stream resource is not live")
  }
  if state.closed.val {
    return err_closed()
  }
  if len == 0 {
    return ok_value(List([]))
  }
  let bytes = state.bytes.val
  if state.offset.val < bytes.length() {
    let end = if bytes.length() - state.offset.val < len {
      bytes.length()
    } else {
      state.offset.val + len
    }
    let result = bytes_to_list_range(bytes, state.offset.val, end)
    state.offset.val = end
    return ok_value(result)
  }
  match state.native_fd {
    None => {
      state.closed.val = true
      err_closed()
    }
    Some(fd) => {
      let timeout = if blocking { -1 } else { 0 }
      guard @wasi.native_poll([fd], [0x01], timeout) is Some(poll_result) else {
        state.closed.val = true
        return err_last_operation_failed(
          host, table, "input readiness poll failed",
        )
      }
      if poll_result.ready_count == 0 {
        return ok_value(List([]))
      }
      let count = if len < 4096 { len } else { 4096 }
      let buffer = FixedArray::make(count, b'\x00')
      let read_result = match state.file_position {
        Some(position) =>
          match @wasi.native_pread(fd, buffer, count, position.val) {
            Some(read) => {
              position.val = position.val + read.to_int64()
              Some(read)
            }
            None => None
          }
        None => @wasi.native_read(fd, buffer, count)
      }
      match read_result {
        Some(read) if read > 0 => {
          let values : Array[@runtime_impl.ComponentValue] = []
          for i in 0..<read {
            values.push(U8(buffer[i].to_int()))
          }
          ok_value(List(values))
        }
        Some(_) => {
          state.closed.val = true
          err_closed()
        }
        None => {
          state.closed.val = true
          err_last_operation_failed(host, table, "input stream read failed")
        }
      }
    }
  }
}

///|
fn skip_input_stream(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  rep : Int,
  len : Int,
  blocking : Bool,
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  match read_input_stream(host, table, rep, len, blocking) {
    Variant(0, Some(List(values))) => ok_value(U64(values.length().to_int64()))
    Variant(1, payload) => Variant(1, payload)
    _ => raise HostCallError("invalid input stream result")
  }
}

///|
fn output_stream_state(
  ctx : WasiComponentCtx,
  rep : Int,
) -> OutputStreamState raise @runtime_impl.ComponentRuntimeError {
  match ctx.get_resource(rep) {
    Some(OutputStream(state)) => state
    _ => raise HostCallError("output stream resource is not live")
  }
}

///|
fn write_output_stream(
  host : WasiComponentHost,
  table : @runtime_impl.ResourceTable,
  state : OutputStreamState,
  bytes : Bytes,
  require_permit : Bool,
  blocking : Bool,
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  if state.closed.val {
    return err_closed()
  }
  if require_permit && bytes.length().to_int64() > state.permit.val {
    raise HostCallError("write exceeds check-write permit")
  }
  state.permit.val = 0L
  let success = match state.native_fd {
    None => (state.write)(bytes)
    Some(fd) => {
      let mut offset = 0
      while offset < bytes.length() {
        if blocking && @wasi.native_poll([fd], [0x04], -1) is None {
          break
        }
        let remaining = bytes.length() - offset
        let buffer = FixedArray::makei(remaining, fn(i) { bytes[offset + i] })
        let write_result = if state.append {
          match @wasi.native_fstat(fd) {
            Some(stat) =>
              if stat.size > 0x7fffffffffffffffUL {
                None
              } else {
                @wasi.native_pwrite(
                  fd,
                  buffer,
                  remaining,
                  stat.size.reinterpret_as_int64(),
                )
              }
            None => None
          }
        } else {
          match state.file_position {
            Some(position) =>
              match @wasi.native_pwrite(fd, buffer, remaining, position.val) {
                Some(written) => {
                  position.val = position.val + written.to_int64()
                  Some(written)
                }
                None => None
              }
            None => @wasi.native_write(fd, buffer, remaining)
          }
        }
        match write_result {
          Some(written) if written > 0 => offset = offset + written
          _ => break
        }
        if !blocking {
          break
        }
      }
      offset == bytes.length()
    }
  }
  if success {
    ok_void()
  } else {
    state.closed.val = true
    err_last_operation_failed(host, table, "output stream write failed")
  }
}

///|
fn poll_source_ready(ctx : WasiComponentCtx, source : PollSource) -> Bool {
  match source {
    Deadline(deadline) => {
      let now = @wasi.native_clock_gettime_monotonic()
      now >= 0L && now >= deadline
    }
    Input(rep) =>
      match ctx.get_resource(rep) {
        Some(InputStream(state)) =>
          if state.closed.val || state.offset.val < state.bytes.val.length() {
            true
          } else {
            match state.native_fd {
              Some(fd) =>
                match @wasi.native_poll([fd], [0x01], 0) {
                  Some(result) => result.ready_count > 0
                  None => true
                }
              None => true
            }
          }
        _ => true
      }
    Output(rep) =>
      match ctx.get_resource(rep) {
        Some(OutputStream(state)) =>
          if state.closed.val {
            true
          } else {
            match state.native_fd {
              Some(fd) =>
                match @wasi.native_poll([fd], [0x04], 0) {
                  Some(result) => result.ready_count > 0
                  None => true
                }
              None => true
            }
          }
        _ => true
      }
    Socket(fd, events) | OwnedSocket(fd, events) =>
      match @wasi.native_poll([fd], [events], 0) {
        Some(result) => result.ready_count > 0
        None => true
      }
  }
}

///|
fn block_poll_source(
  ctx : WasiComponentCtx,
  source : PollSource,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  if poll_source_ready(ctx, source) {
    return
  }
  match source {
    Deadline(deadline) => {
      let now = @wasi.native_clock_gettime_monotonic()
      if now < 0L {
        raise HostCallError("monotonic clock is unavailable")
      }
      if deadline > now {
        @wasi.native_nanosleep(deadline - now) |> ignore
      }
    }
    Input(rep) =>
      match ctx.get_resource(rep) {
        Some(InputStream(state)) =>
          match state.native_fd {
            Some(fd) =>
              if @wasi.native_poll([fd], [0x01], -1) is None {
                raise HostCallError("input readiness poll failed")
              }
            None => ()
          }
        _ => ()
      }
    Output(rep) =>
      match ctx.get_resource(rep) {
        Some(OutputStream(state)) =>
          if state.native_fd is Some(fd) &&
            @wasi.native_poll([fd], [0x04], -1) is None {
            raise HostCallError("output readiness poll failed")
          }
        _ => ()
      }
    Socket(fd, events) | OwnedSocket(fd, events) =>
      if @wasi.native_poll([fd], [events], -1) is None {
        raise HostCallError("socket readiness poll failed")
      }
  }
}

///|
fn poll_timeout_ms(deadline : Int64?, now : Int64) -> Int {
  match deadline {
    None => -1
    Some(deadline) =>
      if deadline <= now {
        0
      } else {
        let remaining = deadline - now
        let milliseconds = (remaining - 1L) / 1000000L + 1L
        if milliseconds > 0x7fffffffL {
          0x7fffffff
        } else {
          milliseconds.to_int()
        }
      }
  }
}

///|
fn block_poll_sources(
  ctx : WasiComponentCtx,
  sources : Array[PollSource],
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let fds : Array[Int] = []
  let events : Array[Int] = []
  let mut nearest_deadline : Int64? = None
  for source in sources {
    match source {
      Deadline(deadline) =>
        match nearest_deadline {
          Some(current) if current <= deadline => ()
          _ => nearest_deadline = Some(deadline)
        }
      Input(rep) =>
        match ctx.get_resource(rep) {
          Some(InputStream(state)) =>
            if !state.closed.val &&
              state.offset.val >= state.bytes.val.length() &&
              state.native_fd is Some(fd) {
              fds.push(fd)
              events.push(0x01)
            }
          _ => ()
        }
      Output(rep) =>
        match ctx.get_resource(rep) {
          Some(OutputStream(state)) =>
            if !state.closed.val && state.native_fd is Some(fd) {
              fds.push(fd)
              events.push(0x04)
            }
          _ => ()
        }
      Socket(fd, socket_events) | OwnedSocket(fd, socket_events) => {
        fds.push(fd)
        events.push(socket_events)
      }
    }
  }
  let now = @wasi.native_clock_gettime_monotonic()
  if now < 0L {
    raise HostCallError("monotonic clock is unavailable")
  }
  let timeout = poll_timeout_ms(nearest_deadline, now)
  if fds.length() > 0 {
    @wasi.native_poll(fds, events, timeout) |> ignore
  } else {
    match nearest_deadline {
      Some(deadline) if deadline > now =>
        @wasi.native_nanosleep(deadline - now) |> ignore
      _ => ()
    }
  }
}

///|
fn pollable_source(
  ctx : WasiComponentCtx,
  table : @runtime_impl.ResourceTable,
  handle : Int,
  pollable_type : @component.TypeDef?,
) -> PollSource raise @runtime_impl.ComponentRuntimeError {
  let rep = resource_rep(table, handle, pollable_type)
  match ctx.get_resource(rep) {
    Some(Pollable(source)) => source
    _ => raise HostCallError("pollable resource is not live")
  }
}

///|
fn monotonic_instant_arg(
  args : Array[@runtime_impl.ComponentValue],
  index : Int,
) -> Int64 raise @runtime_impl.ComponentRuntimeError {
  if index < 0 || index >= args.length() {
    raise HostCallError("missing monotonic clock value")
  }
  match args[index] {
    U64(value) => value
    _ => raise HostCallError("expected monotonic clock u64")
  }
}

///|
fn add_preview2_monotonic_clock(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:clocks/monotonic-clock@\{preview2_version}",
    host.runtime,
  )
  let interface = "wasi:clocks@0.2.11/monotonic-clock"
  host.prepare_preview2_interface(builder, interface)
  builder.add_func("now", preview2_func(interface, "now"), (args, _table) => {
    empty_args(args)
    let now = @wasi.native_clock_gettime_monotonic()
    if now < 0L {
      raise HostCallError("monotonic clock is unavailable")
    }
    [U64(now)]
  })
  builder.add_func("resolution", preview2_func(interface, "resolution"), (
    args,
    _table,
  ) => {
    empty_args(args)
    guard @wasi.native_clock_getres_monotonic() is Some(resolution) else {
      raise HostCallError("monotonic clock resolution is unavailable")
    }
    [U64(resolution)]
  })
  builder.add_func(
    "subscribe-instant",
    preview2_func(interface, "subscribe-instant"),
    (args, table) => {
      let requested = monotonic_instant_arg(args, 0)
      let deadline = if requested < 0L {
        0x7fffffffffffffffL
      } else {
        requested
      }
      let rep = host.ctx.insert_resource(Pollable(Deadline(deadline)))
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
    "subscribe-duration",
    preview2_func(interface, "subscribe-duration"),
    (args, table) => {
      let duration = monotonic_instant_arg(args, 0)
      let now = @wasi.native_clock_gettime_monotonic()
      if now < 0L {
        raise HostCallError("monotonic clock is unavailable")
      }
      let deadline = if duration < 0L || duration > 0x7fffffffffffffffL - now {
        0x7fffffffffffffffL
      } else {
        now + duration
      }
      let rep = host.ctx.insert_resource(Pollable(Deadline(deadline)))
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
    "wasi:clocks/monotonic-clock@\{preview2_version}",
    builder.finish(),
  )
}

///|
fn add_error_interface(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:io/error@\{preview2_version}",
    host.runtime,
  )
  let interface = "wasi:io@0.2.11/error"
  host.prepare_preview2_interface(builder, interface)
  let error_type = host.resource_types.error
  builder.add_func(
    "[method]error.to-debug-string",
    preview2_func(interface, "[method]error.to-debug-string"),
    (args, table) => {
      let handle = resource_handle_arg(args, 0)
      let rep = resource_rep(table, handle, error_type)
      match host.ctx.get_resource(rep) {
        Some(IoError(message, _)) => [String(message)]
        _ => raise HostCallError("I/O error resource is not live")
      }
    },
  )
  host.linker.add_instance(
    "wasi:io/error@\{preview2_version}",
    builder.finish(),
  )
}

///|
fn add_poll_interface(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:io/poll@\{preview2_version}",
    host.runtime,
  )
  let interface = "wasi:io@0.2.11/poll"
  host.prepare_preview2_interface(builder, interface)
  let pollable_type = host.resource_types.pollable
  builder.add_func(
    "[method]pollable.ready",
    preview2_func(interface, "[method]pollable.ready"),
    (args, table) => {
      let source = pollable_source(
        host.ctx,
        table,
        resource_handle_arg(args, 0),
        pollable_type,
      )
      [Bool(poll_source_ready(host.ctx, source))]
    },
  )
  builder.add_func(
    "[method]pollable.block",
    preview2_func(interface, "[method]pollable.block"),
    (args, table) => {
      let source = pollable_source(
        host.ctx,
        table,
        resource_handle_arg(args, 0),
        pollable_type,
      )
      block_poll_source(host.ctx, source)
      []
    },
  )
  builder.add_func("poll", preview2_func(interface, "poll"), (args, table) => {
    guard args is [List(handles)] else {
      raise HostCallError("expected a non-empty pollable list")
    }
    if handles.length() == 0 {
      raise HostCallError("pollable list must not be empty")
    }
    let sources : Array[PollSource] = []
    for handle in handles {
      guard handle is U32(index) else {
        raise HostCallError("expected pollable handle")
      }
      sources.push(pollable_source(host.ctx, table, index, pollable_type))
    }
    let ready : Array[@runtime_impl.ComponentValue] = []
    for i, source in sources {
      if poll_source_ready(host.ctx, source) {
        ready.push(U32(i))
      }
    }
    if ready.length() == 0 {
      block_poll_sources(host.ctx, sources)
      for i, source in sources {
        if poll_source_ready(host.ctx, source) {
          ready.push(U32(i))
        }
      }
    }
    [List(ready)]
  })
  host.linker.add_instance("wasi:io/poll@\{preview2_version}", builder.finish())
}

///|
fn add_input_stream_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:io@0.2.11/streams"
  let input_type = host.resource_types.input_stream
  builder.add_func(
    "[method]input-stream.read",
    preview2_func(interface, "[method]input-stream.read"),
    (args, table) => {
      let rep = resource_rep(table, resource_handle_arg(args, 0), input_type)
      [read_input_stream(host, table, rep, stream_length_arg(args, 1), false)]
    },
  )
  builder.add_func(
    "[method]input-stream.blocking-read",
    preview2_func(interface, "[method]input-stream.blocking-read"),
    (args, table) => {
      let rep = resource_rep(table, resource_handle_arg(args, 0), input_type)
      [read_input_stream(host, table, rep, stream_length_arg(args, 1), true)]
    },
  )
  builder.add_func(
    "[method]input-stream.skip",
    preview2_func(interface, "[method]input-stream.skip"),
    (args, table) => {
      let rep = resource_rep(table, resource_handle_arg(args, 0), input_type)
      [skip_input_stream(host, table, rep, stream_length_arg(args, 1), false)]
    },
  )
  builder.add_func(
    "[method]input-stream.blocking-skip",
    preview2_func(interface, "[method]input-stream.blocking-skip"),
    (args, table) => {
      let rep = resource_rep(table, resource_handle_arg(args, 0), input_type)
      [skip_input_stream(host, table, rep, stream_length_arg(args, 1), true)]
    },
  )
  builder.add_func(
    "[method]input-stream.subscribe",
    preview2_func(interface, "[method]input-stream.subscribe"),
    (args, table) => {
      let input_rep = resource_rep(
        table,
        resource_handle_arg(args, 0),
        input_type,
      )
      let poll_rep = host.ctx.insert_resource(Pollable(Input(input_rep)))
      [
        U32(
          allocate_resource_handle(
            host.ctx,
            table,
            host.resource_types.pollable,
            poll_rep,
          ),
        ),
      ]
    },
  )
}

///|
fn add_output_stream_methods(
  host : WasiComponentHost,
  builder : @runtime_impl.HostInstanceBuilder,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:io@0.2.11/streams"
  let output_type = host.resource_types.output_stream
  builder.add_func(
    "[method]output-stream.check-write",
    preview2_func(interface, "[method]output-stream.check-write"),
    (args, table) => {
      let rep = resource_rep(table, resource_handle_arg(args, 0), output_type)
      let state = output_stream_state(host.ctx, rep)
      if state.closed.val {
        [err_closed()]
      } else {
        match state.native_fd {
          Some(fd) =>
            match @wasi.native_poll([fd], [0x04], 0) {
              Some(result) => {
                let permit = if result.ready_count > 0 { 65536L } else { 0L }
                state.permit.val = permit
                [ok_value(U64(permit))]
              }
              None => {
                state.closed.val = true
                [
                  err_last_operation_failed(
                    host, table, "output readiness poll failed",
                  ),
                ]
              }
            }
          None => {
            state.permit.val = 65536L
            [ok_value(U64(65536L))]
          }
        }
      }
    },
  )
  builder.add_func(
    "[method]output-stream.write",
    preview2_func(interface, "[method]output-stream.write"),
    (args, table) => {
      let rep = resource_rep(table, resource_handle_arg(args, 0), output_type)
      if args.length() != 2 {
        raise HostCallError("expected output stream and byte list")
      }
      [
        write_output_stream(
          host,
          table,
          output_stream_state(host.ctx, rep),
          component_list_to_bytes(args[1]),
          true,
          false,
        ),
      ]
    },
  )
  builder.add_func(
    "[method]output-stream.blocking-write-and-flush",
    preview2_func(interface, "[method]output-stream.blocking-write-and-flush"),
    (args, table) => {
      let rep = resource_rep(table, resource_handle_arg(args, 0), output_type)
      if args.length() != 2 {
        raise HostCallError("expected output stream and byte list")
      }
      let bytes = component_list_to_bytes(args[1])
      if bytes.length() > 4096 {
        raise HostCallError("blocking write exceeds 4096 bytes")
      }
      [
        write_output_stream(
          host,
          table,
          output_stream_state(host.ctx, rep),
          bytes,
          false,
          true,
        ),
      ]
    },
  )
  builder.add_func(
    "[method]output-stream.flush",
    preview2_func(interface, "[method]output-stream.flush"),
    (args, table) => {
      let rep = resource_rep(table, resource_handle_arg(args, 0), output_type)
      if output_stream_state(host.ctx, rep).closed.val {
        [err_closed()]
      } else {
        [ok_void()]
      }
    },
  )
  builder.add_func(
    "[method]output-stream.blocking-flush",
    preview2_func(interface, "[method]output-stream.blocking-flush"),
    (args, table) => {
      let rep = resource_rep(table, resource_handle_arg(args, 0), output_type)
      if output_stream_state(host.ctx, rep).closed.val {
        [err_closed()]
      } else {
        [ok_void()]
      }
    },
  )
  builder.add_func(
    "[method]output-stream.subscribe",
    preview2_func(interface, "[method]output-stream.subscribe"),
    (args, table) => {
      let output_rep = resource_rep(
        table,
        resource_handle_arg(args, 0),
        output_type,
      )
      let poll_rep = host.ctx.insert_resource(Pollable(Output(output_rep)))
      [
        U32(
          allocate_resource_handle(
            host.ctx,
            table,
            host.resource_types.pollable,
            poll_rep,
          ),
        ),
      ]
    },
  )
  builder.add_func(
    "[method]output-stream.write-zeroes",
    preview2_func(interface, "[method]output-stream.write-zeroes"),
    (args, table) => {
      let rep = resource_rep(table, resource_handle_arg(args, 0), output_type)
      let len = stream_length_arg(args, 1)
      let bytes = Bytes::from_array(Array::make(len, b'\x00'))
      [
        write_output_stream(
          host,
          table,
          output_stream_state(host.ctx, rep),
          bytes,
          true,
          false,
        ),
      ]
    },
  )
  builder.add_func(
    "[method]output-stream.blocking-write-zeroes-and-flush",
    preview2_func(
      interface, "[method]output-stream.blocking-write-zeroes-and-flush",
    ),
    (args, table) => {
      let rep = resource_rep(table, resource_handle_arg(args, 0), output_type)
      let len = stream_length_arg(args, 1)
      if len > 4096 {
        raise HostCallError("blocking zero write exceeds 4096 bytes")
      }
      let bytes = Bytes::from_array(Array::make(len, b'\x00'))
      [
        write_output_stream(
          host,
          table,
          output_stream_state(host.ctx, rep),
          bytes,
          false,
          true,
        ),
      ]
    },
  )
  fn splice(
    args : Array[@runtime_impl.ComponentValue],
    table : @runtime_impl.ResourceTable,
    blocking : Bool,
  ) -> Array[@runtime_impl.ComponentValue] raise @runtime_impl.ComponentRuntimeError {
    let output_rep = resource_rep(
      table,
      resource_handle_arg(args, 0),
      output_type,
    )
    let input_rep = resource_rep(
      table,
      resource_handle_arg(args, 1),
      host.resource_types.input_stream,
    )
    let len = stream_length_arg(args, 2)
    let output_state = output_stream_state(host.ctx, output_rep)
    if output_state.closed.val {
      return [err_closed()]
    }
    let permit = match output_state.native_fd {
      Some(fd) => {
        let timeout = if blocking { -1 } else { 0 }
        match @wasi.native_poll([fd], [0x04], timeout) {
          Some(result) =>
            if result.ready_count > 0 {
              if blocking {
                4096
              } else {
                65536
              }
            } else {
              0
            }
          None => {
            output_state.closed.val = true
            return [
              err_last_operation_failed(
                host, table, "output readiness poll failed",
              ),
            ]
          }
        }
      }
      None => if blocking { 4096 } else { 65536 }
    }
    output_state.permit.val = permit.to_int64()
    let transfer_len = if len < permit { len } else { permit }
    if transfer_len == 0 {
      return [ok_value(U64(0L))]
    }
    match read_input_stream(host, table, input_rep, transfer_len, blocking) {
      Variant(0, Some(List(values))) => {
        let bytes = component_list_to_bytes(List(values))
        match
          write_output_stream(host, table, output_state, bytes, true, blocking) {
          Variant(0, _) => [ok_value(U64(values.length().to_int64()))]
          Variant(1, payload) => [Variant(1, payload)]
          _ => raise HostCallError("invalid output stream result")
        }
      }
      Variant(1, payload) => [Variant(1, payload)]
      _ => raise HostCallError("invalid input stream result")
    }
  }

  builder.add_func(
    "[method]output-stream.splice",
    preview2_func(interface, "[method]output-stream.splice"),
    (args, table) => splice(args, table, false),
  )
  builder.add_func(
    "[method]output-stream.blocking-splice",
    preview2_func(interface, "[method]output-stream.blocking-splice"),
    (args, table) => splice(args, table, true),
  )
}

///|
fn add_streams_interface(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:io/streams@\{preview2_version}",
    host.runtime,
  )
  host.prepare_preview2_interface(builder, "wasi:io@0.2.11/streams")
  add_input_stream_methods(host, builder)
  add_output_stream_methods(host, builder)
  host.linker.add_instance(
    "wasi:io/streams@\{preview2_version}",
    builder.finish(),
  )
}

///|
fn add_stdio_interface(
  host : WasiComponentHost,
  interface_name : String,
  export_name : String,
  resource_type : @component.TypeDef?,
  rep : Int,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:cli/\{interface_name}@\{preview2_version}",
    host.runtime,
  )
  let interface = "wasi:cli@0.2.11/\{interface_name}"
  host.prepare_preview2_interface(builder, interface)
  builder.add_func(export_name, preview2_func(interface, export_name), (
    _args,
    table,
  ) => {
    let owned_rep = host.ctx.clone_resource(rep)
    [U32(allocate_resource_handle(host.ctx, table, resource_type, owned_rep))]
  })
  host.linker.add_instance(
    "wasi:cli/\{interface_name}@\{preview2_version}",
    builder.finish(),
  )
}

///|
fn add_terminal_marker_interface(
  host : WasiComponentHost,
  interface_name : String,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:cli/\{interface_name}@\{preview2_version}",
    host.runtime,
  )
  host.prepare_preview2_interface(builder, "wasi:cli@0.2.11/\{interface_name}")
  host.linker.add_instance(
    "wasi:cli/\{interface_name}@\{preview2_version}",
    builder.finish(),
  )
}

///|
fn add_terminal_getter_interface(
  host : WasiComponentHost,
  interface_name : String,
  export_name : String,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:cli/\{interface_name}@\{preview2_version}",
    host.runtime,
  )
  let interface = "wasi:cli@0.2.11/\{interface_name}"
  host.prepare_preview2_interface(builder, interface)
  builder.add_func(export_name, preview2_func(interface, export_name), (
    _args,
    _table,
  ) => [Variant(0, None)])
  host.linker.add_instance(
    "wasi:cli/\{interface_name}@\{preview2_version}",
    builder.finish(),
  )
}

///|
pub fn WasiComponentHost::add_preview2_io(
  self : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  add_error_interface(self)
  add_poll_interface(self)
  add_streams_interface(self)
  add_stdio_interface(
    self,
    "stdin",
    "get-stdin",
    self.resource_types.input_stream,
    self.ctx.stdin_rep,
  )
  add_stdio_interface(
    self,
    "stdout",
    "get-stdout",
    self.resource_types.output_stream,
    self.ctx.stdout_rep,
  )
  add_stdio_interface(
    self,
    "stderr",
    "get-stderr",
    self.resource_types.output_stream,
    self.ctx.stderr_rep,
  )
  add_terminal_marker_interface(self, "terminal-input")
  add_terminal_marker_interface(self, "terminal-output")
  add_terminal_getter_interface(self, "terminal-stdin", "get-terminal-stdin")
  add_terminal_getter_interface(self, "terminal-stdout", "get-terminal-stdout")
  add_terminal_getter_interface(self, "terminal-stderr", "get-terminal-stderr")
}
