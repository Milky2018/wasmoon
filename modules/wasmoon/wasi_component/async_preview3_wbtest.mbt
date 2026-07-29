///|
test "Preview 3 timers become ready through the native reactor" {
  let ctx = WasiComponentCtxBuilder().build()
  defer ctx.close()
  let now = @wasi.native_clock_gettime_monotonic()
  if now < 0L {
    return fail("monotonic clock is unavailable")
  }
  let operation = ctx.register_deadline(now + 1000000L)
  debug_inspect(
    (
      ctx.async_operation_ready(operation),
      operation.registration.is_active(),
      operation.registration.is_ready(),
    ),
    content="(false, true, false)",
  )
  guard ctx.wait_for_async_event() else {
    return fail("native timer readiness did not arrive")
  }
  debug_inspect(
    (
      ctx.async_operation_ready(operation),
      operation.registration.is_active(),
      operation.registration.is_ready(),
      ctx.native_reactor,
    ),
    content="(true, false, true, Some(NativeReactor(registrations=0)))",
  )
}

///|
test "Preview 3 cancellation releases runtime and native registrations" {
  let ctx = WasiComponentCtxBuilder().build()
  defer ctx.close()
  let now = @wasi.native_clock_gettime_monotonic()
  if now < 0L {
    return fail("monotonic clock is unavailable")
  }
  let operation = ctx.register_deadline(now + 1000000000L)
  ctx.cancel_async_operation(operation)
  ctx.cancel_async_operation(operation)
  debug_inspect(
    (
      operation.registration.is_active(),
      operation.registration.is_ready(),
      ctx.wait_for_async_event(),
      ctx.native_reactor,
    ),
    content="(false, false, false, Some(NativeReactor(registrations=0)))",
  )
}

///|
test "Preview 3 repeated cancellation leaves no host operations" {
  let ctx = WasiComponentCtxBuilder().build()
  defer ctx.close()
  let now = @wasi.native_clock_gettime_monotonic()
  if now < 0L {
    return fail("monotonic clock is unavailable")
  }
  for index in 0..<512 {
    let operation = ctx.register_deadline(now + 1000000000L + index.to_int64())
    ctx.cancel_async_operation(operation)
  }
  debug_inspect(
    (ctx.wait_for_async_event(), ctx.native_reactor),
    content="(false, Some(NativeReactor(registrations=0)))",
  )
}

///|
fn test_descriptor_is_open(fd : Int) -> Bool {
  match @wasi.native_dup(fd) {
    Some(duplicate) => {
      @wasi.native_close(duplicate) |> ignore
      true
    }
    None => false
  }
}

///|
test "WASI component close releases inherited stdio descriptors" {
  let ctx = WasiComponentCtxBuilder().inherit_stdio().build()
  guard ctx.get_resource(ctx.stdin_rep) is Some(InputStream(stdin)) &&
    stdin.native_fd is Some(stdin_fd) &&
    ctx.get_resource(ctx.stdout_rep) is Some(OutputStream(stdout)) &&
    stdout.native_fd is Some(stdout_fd) &&
    ctx.get_resource(ctx.stderr_rep) is Some(OutputStream(stderr)) &&
    stderr.native_fd is Some(stderr_fd) else {
    ctx.close()
    return fail("inherited stdio descriptors are unavailable")
  }
  ctx.close()
  ctx.close()
  debug_inspect(
    (
      stdin.closed.val,
      stdout.closed.val,
      stderr.closed.val,
      [
        test_descriptor_is_open(stdin_fd),
        test_descriptor_is_open(stdout_fd),
        test_descriptor_is_open(stderr_fd),
      ],
    ),
    content="(true, true, true, [false, false, false])",
  )
}

///|
test "dropping one inherited stdio handle preserves its peer" {
  let ctx = WasiComponentCtxBuilder().inherit_stdin().build()
  let clone = ctx.clone_resource(ctx.stdin_rep)
  guard ctx.get_resource(clone) is Some(InputStream(stdin)) &&
    stdin.native_fd is Some(fd) else {
    ctx.close()
    return fail("inherited stdin descriptor is unavailable")
  }
  ctx.drop_resource(ctx.stdin_rep)
  let peer_survived = !stdin.closed.val && test_descriptor_is_open(fd)
  ctx.drop_resource(clone)
  debug_inspect(
    (
      peer_survived,
      stdin.closed.val,
      test_descriptor_is_open(fd),
      ctx.resources.length(),
    ),
    content="(true, true, false, 3)",
  )
  ctx.close()
}

///|
test "WASI component close cancels pending native registrations" {
  let ctx = WasiComponentCtxBuilder().build()
  let now = @wasi.native_clock_gettime_monotonic()
  if now < 0L {
    ctx.close()
    return fail("monotonic clock is unavailable")
  }
  let operation = ctx.register_deadline(now + 1000000000L)
  ctx.close()
  debug_inspect(
    (
      operation.registration.is_active(),
      operation.registration.is_ready(),
      ctx.native_reactor,
    ),
    content="(false, false, Some(NativeReactor(registrations=0)))",
  )
}

///|
test "WASI component close sweeps resources and preopen roots" {
  let ctx = WasiComponentCtxBuilder()
    .preopened_directory("/tmp", "/sandbox", false)
    .build()
  guard @wasi.native_open("/dev/null", [ReadOnly], 0) is Some(fd) else {
    ctx.close()
    return fail("could not open lifecycle test descriptor")
  }
  let descriptor : DescriptorState = {
    fd,
    flags: descriptor_read,
    file_type: 0,
    closed: Ref(false),
  }
  ctx.insert_resource(Descriptor(descriptor)) |> ignore
  let preopen = ctx.preopens[0]
  ctx.close()
  ctx.close()
  debug_inspect(
    (
      descriptor.closed.val,
      preopen.closed.val,
      ctx.resources.length(),
      test_descriptor_is_open(fd),
      test_descriptor_is_open(preopen.fd),
    ),
    content="(true, true, 0, false, false)",
  )
}

///|
test "WASI component close rejects new async registrations" {
  let ctx = WasiComponentCtxBuilder().build()
  ctx.close()
  try ctx.register_deadline(1L) catch {
    error =>
      debug_inspect(
        error,
        content="HostCallError(\"WASI component context is closed\")",
      )
  } noraise {
    _ => fail("closed context accepted a native registration")
  }
}
