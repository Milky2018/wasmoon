///|
test "native fiber starts, yields repeatedly, and returns" {
  let events : Array[Int64] = []
  let fiber = @wasmoon_jit.NativeFiber::new(fn() {
    events.push(1L)
    let first = @wasmoon_jit.NativeFiber::suspend(10L)
    events.push(first)
    let second = @wasmoon_jit.NativeFiber::suspend(20L)
    events.push(second)
    30L
  })
  debug_inspect(
    (fiber.phase(), fiber.continue_with(), fiber.phase(), events.copy()),
    content="(Ready, Yielded(10), Suspended, [1])",
  )
  debug_inspect(
    (fiber.continue_with(value=11L), fiber.phase(), events.copy()),
    content="(Yielded(20), Suspended, [1, 11])",
  )
  debug_inspect(
    (fiber.continue_with(value=21L), fiber.phase(), events),
    content="(Finished(30), Returned, [1, 11, 21])",
  )
  try fiber.continue_with() catch {
    InvalidTransition(phase) => debug_inspect(phase, content="Returned")
    error => fail("unexpected fiber error: \{error}")
  } noraise {
    _ => fail("returned fiber resumed twice")
  }
}

///|
test "two native fibers interleave without sharing state" {
  let first = @wasmoon_jit.NativeFiber::new(fn() {
    let value = @wasmoon_jit.NativeFiber::suspend(101L)
    value + 1L
  })
  let second = @wasmoon_jit.NativeFiber::new(fn() {
    let value = @wasmoon_jit.NativeFiber::suspend(201L)
    value + 2L
  })
  debug_inspect(
    (first.continue_with(), second.continue_with()),
    content="(Yielded(101), Yielded(201))",
  )
  debug_inspect(
    (second.continue_with(value=300L), first.continue_with(value=400L)),
    content="(Finished(302), Finished(401))",
  )
}

///|
test "native fiber cancellation is terminal and exact" {
  let fiber = @wasmoon_jit.NativeFiber::new(fn() {
    @wasmoon_jit.NativeFiber::suspend(1L) |> ignore
    2L
  })
  debug_inspect(fiber.continue_with(), content="Yielded(1)")
  fiber.cancel()
  debug_inspect(fiber.phase(), content="Cancelled")
  try fiber.cancel() catch {
    InvalidTransition(phase) => debug_inspect(phase, content="Cancelled")
    error => fail("unexpected fiber error: \{error}")
  } noraise {
    _ => fail("cancelled fiber cancelled twice")
  }
}

///|
test "native fiber allocates a guarded stack" {
  for size in [64L * 1024L, 128L * 1024L, 1024L * 1024L, 2L * 1024L * 1024L] {
    let fiber = @wasmoon_jit.NativeFiber::new(fn() { 0L }, stack_size=size)
    assert_eq(fiber.stack_size(), size)
    assert_true(fiber.guard_size() > 0L)
    assert_true(@native_test_support.fiber_guard_rejects_access(size))
    fiber.cancel()
  }
}

///|
test "native fiber preserves ABI callee-saved registers" {
  debug_inspect(
    @native_test_support.fiber_preserves_registers(),
    content="true",
  )
}
