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
      operation.task.is_active(),
      operation.registration.is_active(),
      ctx.async_ready.length(),
    ),
    content="(false, true, true, 1)",
  )
  guard ctx.wait_for_async_event() else {
    return fail("native timer readiness did not arrive")
  }
  debug_inspect(
    (
      ctx.async_operation_ready(operation),
      operation.task.is_active(),
      operation.registration.is_active(),
      ctx.async_ready.length(),
      ctx.async_runtime,
    ),
    content=(
      #|(
      #|  true,
      #|  false,
      #|  false,
      #|  0,
      #|  Runtime(now=0, tasks=0, operations=0, ready=0),
      #|)
    ),
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
      operation.task.is_active(),
      operation.registration.is_active(),
      ctx.async_ready.length(),
      ctx.wait_for_async_event(),
      ctx.async_runtime,
    ),
    content=(
      #|(
      #|  false,
      #|  false,
      #|  0,
      #|  false,
      #|  Runtime(now=0, tasks=0, operations=0, ready=0),
      #|)
    ),
  )
}
