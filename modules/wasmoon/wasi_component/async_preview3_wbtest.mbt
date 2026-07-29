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
