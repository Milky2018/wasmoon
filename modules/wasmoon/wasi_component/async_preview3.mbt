///|
fn preview3_deadline_after(now : Int64, duration : Int64) -> Int64 {
  if duration < 0L || duration > 0x7fffffffffffffffL - now {
    0x7fffffffffffffffL
  } else {
    now + duration
  }
}

///|
fn preview3_clock_future(
  ctx : WasiComponentCtx,
  deadline : Int64,
) -> @runtime_impl.HostFuture {
  let operation = ctx.register_deadline(deadline)
  let done = Ref(false)
  HostFuture(
    fn() {
      if done.val || ctx.deadline_ready(operation) {
        done.val = true
        Ready([])
      } else {
        Pending
      }
    },
    fn() {
      if !done.val {
        ctx.cancel_deadline(operation)
        done.val = true
      }
    },
  )
}

///|
fn preview3_clock_arg(
  args : Array[@runtime_impl.ComponentValue],
) -> Int64 raise @runtime_impl.ComponentRuntimeError {
  match args {
    [U64(value)] => value
    _ => raise HostCallError("expected one u64 clock value")
  }
}

///|
fn add_preview3_monotonic_clock(
  host : WasiComponentHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let builder = host.linker.host_instance_builder(
    "wasi:clocks/monotonic-clock@\{preview3_version}",
    host.runtime,
  )
  let interface = "wasi:clocks@0.3.0/monotonic-clock"
  host.prepare_preview3_interface(builder, interface)
  builder.add_func("now", preview3_func(interface, "now"), (args, _table) => {
    empty_args(args)
    let now = @wasi.native_clock_gettime_monotonic()
    if now < 0L {
      raise HostCallError("monotonic clock is unavailable")
    }
    [U64(now)]
  })
  builder.add_func(
    "get-resolution",
    preview3_func(interface, "get-resolution"),
    (args, _table) => {
      empty_args(args)
      guard @wasi.native_clock_getres_monotonic() is Some(resolution) else {
        raise HostCallError("monotonic clock resolution is unavailable")
      }
      [U64(resolution)]
    },
  )
  builder.add_async_func("wait-until", preview3_func(interface, "wait-until"), (
    args,
    _table,
  ) => {
    let deadline = preview3_clock_arg(args)
    preview3_clock_future(
      host.ctx,
      if deadline < 0L {
        0x7fffffffffffffffL
      } else {
        deadline
      },
    )
  })
  builder.add_async_func("wait-for", preview3_func(interface, "wait-for"), (
    args,
    _table,
  ) => {
    let duration = preview3_clock_arg(args)
    let now = @wasi.native_clock_gettime_monotonic()
    if now < 0L {
      raise HostCallError("monotonic clock is unavailable")
    }
    preview3_clock_future(host.ctx, preview3_deadline_after(now, duration))
  })
  host.linker.add_instance(
    "wasi:clocks/monotonic-clock@\{preview3_version}",
    builder.finish(),
  )
}
