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
  NativeJITReturned(Int)
} derive(Debug, Eq)

///|
pub suberror NativeFiberError {
  StackAllocationFailed(Int64)
  WrongThread
  InvalidTransition(NativeFiberPhase)
  NativeFailure(Int)
} derive(Debug, Eq)

///|
pub impl Show for NativeFiberError with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(to_repr(self).to_string()))
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
  if c_native_fiber_state(raw) < 0 {
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
  let raw = c_native_jit_continuation_alloc(
    self.0,
    trampoline_ptr,
    func_ptr,
    values,
    values_len,
    stack_size,
  )
  let continuation = NativeJITContinuation::{ raw, }
  if c_native_fiber_state(raw) < 0 {
    raise StackAllocationFailed(stack_size)
  }
  continuation
}

///|
fn native_fiber_phase(code : Int) -> NativeFiberPhase {
  match code {
    0 => Ready
    1 => Running
    2 => Suspended
    3 => Returned
    4 => Cancelled
    _ => Cancelled
  }
}

///|
pub fn NativeFiber::phase(self : NativeFiber) -> NativeFiberPhase {
  native_fiber_phase(c_native_fiber_state(self.raw))
}

///|
pub fn NativeFiber::continue_with(
  self : NativeFiber,
  value? : Int64 = 0L,
) -> NativeFiberEvent raise NativeFiberError {
  let status = c_native_fiber_continue(self.raw, value)
  match status {
    0 => Yielded(c_native_fiber_yielded_value(self.raw))
    1 => Finished(c_native_fiber_return_value(self.raw))
    -2 => raise WrongThread
    -3 => raise InvalidTransition(self.phase())
    code => raise NativeFailure(code)
  }
}

///|
pub fn NativeJITContinuation::continue_with(
  self : NativeJITContinuation,
  value? : Int64 = 0L,
) -> NativeJITContinuationEvent raise NativeFiberError {
  let status = c_native_fiber_continue(self.raw, value)
  match status {
    0 =>
      if c_native_fiber_yielded_value(self.raw) ==
        c_native_hostcall_suspend_event() {
        NativeHostcallSuspended
      } else {
        raise NativeFailure(-5)
      }
    1 => NativeJITReturned(c_native_fiber_return_value(self.raw).to_int())
    -2 => raise WrongThread
    -3 =>
      raise InvalidTransition(
        native_fiber_phase(c_native_fiber_state(self.raw)),
      )
    code => raise NativeFailure(code)
  }
}

///|
pub fn NativeJITContinuation::cancel(
  self : NativeJITContinuation,
) -> Unit raise NativeFiberError {
  let status = c_native_fiber_cancel(self.raw)
  match status {
    0 => ()
    -2 => raise WrongThread
    -3 =>
      raise InvalidTransition(
        native_fiber_phase(c_native_fiber_state(self.raw)),
      )
    code => raise NativeFailure(code)
  }
}

///|
pub fn NativeJITContinuation::phase(
  self : NativeJITContinuation,
) -> NativeFiberPhase {
  native_fiber_phase(c_native_fiber_state(self.raw))
}

///|
/// Suspend the currently running native fiber and return the next resume value.
pub fn NativeFiber::suspend(value : Int64) -> Int64 {
  c_native_fiber_yield(value)
}

///|
pub fn NativeFiber::cancel(self : NativeFiber) -> Unit raise NativeFiberError {
  let status = c_native_fiber_cancel(self.raw)
  match status {
    0 => ()
    -2 => raise WrongThread
    -3 => raise InvalidTransition(self.phase())
    code => raise NativeFailure(code)
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
    (Some("phase"), to_repr(self.phase())),
    (Some("stack_size"), to_repr(self.stack_size())),
    (Some("guard_size"), to_repr(self.guard_size())),
  ])
}

///|
/// Native ABI self-test for callee-preserved registers across a suspension.
pub fn native_fiber_preserves_registers() -> Bool {
  c_native_fiber_register_test() == 1
}

///|
/// Native subprocess self-test that confirms the fiber guard page is
/// inaccessible. Converting such a fault into a structured JIT trap belongs to
/// the trap activation seam.
pub fn native_fiber_guard_rejects_access() -> Bool {
  c_native_fiber_guard_test() == 1
}
