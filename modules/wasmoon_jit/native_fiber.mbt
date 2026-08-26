///|
/// Observable lifecycle of a single-threaded native fiber.
pub(all) enum NativeFiberPhase {
  Ready
  Running
  Suspended
  Returned
  Cancelled
} derive(Debug, Eq)

///|
/// Result of entering or continuing a native fiber.
pub(all) enum NativeFiberEvent {
  Yielded(Int64)
  Finished(Int64)
} derive(Debug, Eq)

///|
/// Result of advancing a stackful JIT invocation.
pub(all) enum NativeJITContinuationEvent {
  NativeHostcallSuspended
  NativeJITCompleted
  NativeJITTrapped(Int)
} derive(Debug, Eq)

///|
pub suberror NativeFiberError {
  StackAllocationFailed(Int64)
  WrongThread
  InvalidTransition(NativeFiberPhase)
  InvalidState(Int)
  UnexpectedYield(Int64)
  NativeFailure(Int)
} derive(Debug, Eq)

///|
pub impl Show for NativeFiberError with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
/// Fixed-stack, single-threaded native fiber.
///
/// The external object owns a guarded native stack and the entry closure. A
/// fiber may only be continued or cancelled on the thread that created it.
struct NativeFiber {
  raw : NativeFiberObject
}

///|
/// Stackful JIT invocation whose entry frame is entirely native.
///
/// MoonBit hostcall callbacks always return before this continuation yields.
struct NativeJITContinuation {
  raw : NativeFiberObject
}

///|
pub fn NativeFiber::new(
  entry : () -> Int64,
  stack_size? : Int64 = 1024L * 1024L,
) -> NativeFiber raise NativeFiberError {
  let call_closure : FuncRef[(() -> Int64) -> Int64] = fn(f) { f() }
  let raw = c_native_fiber_alloc(call_closure, entry, stack_size)
  let fiber : NativeFiber = { raw, }
  if !native_fiber_is_allocated(raw) {
    raise StackAllocationFailed(stack_size)
  }
  fiber
}

///|
pub fn NativeJITContext::start_continuation(
  self : NativeJITContext,
  trampoline_ptr : Int64,
  func_ptr : Int64,
  values : FixedArray[Int64],
  values_len : Int,
  stack_size? : Int64 = 1024L * 1024L,
) -> NativeJITContinuation raise NativeFiberError {
  let effective_stack_size = if self.configured_stack_size > 0L {
    self.configured_stack_size
  } else {
    stack_size
  }
  let raw = c_native_jit_continuation_alloc(
    self.handle,
    trampoline_ptr,
    func_ptr,
    values,
    values_len,
    effective_stack_size,
  )
  let continuation = NativeJITContinuation::{ raw, }
  if !native_fiber_is_allocated(raw) {
    raise StackAllocationFailed(effective_stack_size)
  }
  continuation
}

///|
pub fn NativeFiber::phase(self : NativeFiber) -> NativeFiberPhase {
  native_fiber_phase(self.raw)
}

///|
pub fn NativeFiber::continue_with(
  self : NativeFiber,
  value? : Int64 = 0L,
) -> NativeFiberEvent raise NativeFiberError {
  match native_fiber_advance(self.raw, value) {
    FiberSuspended(value) => Yielded(value)
    FiberReturned(value) => Finished(value)
    FiberAdvanceFailed(failure) => raise failure.to_error()
  }
}

///|
pub fn NativeJITContinuation::continue_with(
  self : NativeJITContinuation,
  value? : Int64 = 0L,
) -> NativeJITContinuationEvent raise NativeFiberError {
  match native_jit_continuation_advance(self.raw, value) {
    JITHostcallSuspended => NativeHostcallSuspended
    JITCompleted => NativeJITCompleted
    JITTrapped(code) => NativeJITTrapped(code)
    JITAdvanceFailed(failure) => raise failure.to_error()
  }
}

///|
/// Resume a continuation stopped at an imported hostcall.
///
/// `retry=true` re-enters only the suspended hostcall before continuing the
/// native guest frame. It never restarts the guest function from its entry.
pub fn NativeJITContinuation::continue_after_hostcall(
  self : NativeJITContinuation,
  retry~ : Bool,
) -> NativeJITContinuationEvent raise NativeFiberError {
  self.continue_with(value=if retry { 1L } else { 0L })
}

///|
pub fn NativeJITContinuation::cancel(
  self : NativeJITContinuation,
) -> Unit raise NativeFiberError {
  match native_fiber_cancel(self.raw) {
    None => ()
    Some(failure) => raise failure.to_error()
  }
}

///|
pub fn NativeJITContinuation::phase(
  self : NativeJITContinuation,
) -> NativeFiberPhase {
  native_fiber_phase(self.raw)
}

///|
/// Suspend the currently running native fiber and return the next resume value.
pub fn NativeFiber::suspend(value : Int64) -> Int64 {
  c_native_fiber_yield(value)
}

///|
pub fn NativeFiber::cancel(self : NativeFiber) -> Unit raise NativeFiberError {
  match native_fiber_cancel(self.raw) {
    None => ()
    Some(failure) => raise failure.to_error()
  }
}

///|
pub fn NativeFiber::stack_size(self : NativeFiber) -> Int64 {
  c_native_fiber_stack_size(self.raw)
}

///|
pub fn NativeFiber::guard_size(self : NativeFiber) -> Int64 {
  c_native_fiber_guard_size(self.raw)
}

///|
pub impl Debug for NativeFiber with fn to_repr(self) {
  Repr::ctor("NativeFiber", [
    (Some("phase"), Repr(self.phase())),
    (Some("stack_size"), Repr(self.stack_size())),
    (Some("guard_size"), Repr(self.guard_size())),
  ])
}
