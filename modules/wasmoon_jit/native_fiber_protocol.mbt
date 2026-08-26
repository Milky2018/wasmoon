///|
priv enum NativeFiberProtocolFailure {
  FiberWrongThread
  FiberInvalidTransition(NativeFiberPhase)
  FiberInvalidState(Int)
  FiberUnexpectedYield(Int64)
  FiberNativeFailure(Int)
}

///|
// Debug is consumed only by the white-box protocol snapshot.
#warnings("-unused_value")
priv enum NativeFiberAdvanceCode {
  FiberDidSuspend
  FiberDidReturn
  FiberAdvanceWrongThread
  FiberAdvanceInvalidTransition
  FiberAdvanceInvalidState
  FiberAdvanceNativeFailure(Int)
} derive(Debug)

///|
priv enum NativeFiberAdvanceResult {
  FiberSuspended(Int64)
  FiberReturned(Int64)
  FiberAdvanceFailed(NativeFiberProtocolFailure)
}

///|
#warnings("-unused_value")
priv enum NativeFiberCancelCode {
  FiberDidCancel
  FiberCancelWrongThread
  FiberCancelInvalidTransition
  FiberCancelNativeFailure(Int)
} derive(Debug)

///|
priv enum NativeJITAdvanceResult {
  JITHostcallSuspended
  JITCompleted
  JITTrapped(Int)
  JITAdvanceFailed(NativeFiberProtocolFailure)
}

///|
fn decode_native_fiber_state_code(code : Int) -> Result[NativeFiberPhase, Int] {
  match code {
    0 => Ok(Ready)
    1 => Ok(Running)
    2 => Ok(Suspended)
    3 => Ok(Returned)
    4 => Ok(Cancelled)
    code => Err(code)
  }
}

///|
fn decode_native_fiber_advance_code(
  status_code : Int,
) -> NativeFiberAdvanceCode {
  match status_code {
    0 => FiberDidSuspend
    1 => FiberDidReturn
    -2 => FiberAdvanceWrongThread
    -3 => FiberAdvanceInvalidTransition
    -4 => FiberAdvanceInvalidState
    code => FiberAdvanceNativeFailure(code)
  }
}

///|
fn decode_native_fiber_cancel_code(status_code : Int) -> NativeFiberCancelCode {
  match status_code {
    0 => FiberDidCancel
    -2 => FiberCancelWrongThread
    -3 => FiberCancelInvalidTransition
    code => FiberCancelNativeFailure(code)
  }
}

///|
fn native_fiber_invalid_transition(
  raw : NativeFiberObject,
) -> NativeFiberProtocolFailure {
  match native_fiber_state(raw) {
    Ok(phase) => FiberInvalidTransition(phase)
    Err(code) => FiberInvalidState(code)
  }
}

///|
fn native_fiber_state(raw : NativeFiberObject) -> Result[NativeFiberPhase, Int] {
  decode_native_fiber_state_code(c_native_fiber_state_code(raw))
}

///|
fn native_fiber_is_allocated(raw : NativeFiberObject) -> Bool {
  native_fiber_state(raw) is Ok(_)
}

///|
fn native_fiber_phase(raw : NativeFiberObject) -> NativeFiberPhase {
  match native_fiber_state(raw) {
    Ok(phase) => phase
    Err(code) => abort("invalid native fiber state code: \{code}")
  }
}

///|
fn native_fiber_advance(
  raw : NativeFiberObject,
  resume_value : Int64,
) -> NativeFiberAdvanceResult {
  let status_code = c_native_fiber_continue_code(raw, resume_value)
  match decode_native_fiber_advance_code(status_code) {
    FiberDidSuspend => FiberSuspended(c_native_fiber_yielded_value(raw))
    FiberDidReturn => FiberReturned(c_native_fiber_return_value(raw))
    FiberAdvanceWrongThread => FiberAdvanceFailed(FiberWrongThread)
    FiberAdvanceInvalidTransition =>
      FiberAdvanceFailed(native_fiber_invalid_transition(raw))
    FiberAdvanceInvalidState =>
      FiberAdvanceFailed(FiberInvalidState(c_native_fiber_state_code(raw)))
    FiberAdvanceNativeFailure(code) =>
      FiberAdvanceFailed(FiberNativeFailure(code))
  }
}

///|
fn native_jit_continuation_advance(
  raw : NativeFiberObject,
  resume_value : Int64,
) -> NativeJITAdvanceResult {
  match native_fiber_advance(raw, resume_value) {
    FiberSuspended(event) =>
      if event == c_native_hostcall_suspend_event() {
        JITHostcallSuspended
      } else {
        JITAdvanceFailed(FiberUnexpectedYield(event))
      }
    FiberReturned(value) =>
      if value == 0L {
        JITCompleted
      } else if value > 0L {
        JITTrapped(value.to_int())
      } else {
        JITAdvanceFailed(FiberNativeFailure(value.to_int()))
      }
    FiberAdvanceFailed(failure) => JITAdvanceFailed(failure)
  }
}

///|
fn native_fiber_cancel(raw : NativeFiberObject) -> NativeFiberProtocolFailure? {
  let status_code = c_native_fiber_cancel_code(raw)
  match decode_native_fiber_cancel_code(status_code) {
    FiberDidCancel => None
    FiberCancelWrongThread => Some(FiberWrongThread)
    FiberCancelInvalidTransition => Some(native_fiber_invalid_transition(raw))
    FiberCancelNativeFailure(code) => Some(FiberNativeFailure(code))
  }
}

///|
fn NativeFiberProtocolFailure::to_error(
  self : NativeFiberProtocolFailure,
) -> NativeFiberError {
  match self {
    FiberWrongThread => WrongThread
    FiberInvalidTransition(phase) => InvalidTransition(phase)
    FiberInvalidState(code) => InvalidState(code)
    FiberUnexpectedYield(event) => UnexpectedYield(event)
    FiberNativeFailure(code) => NativeFailure(code)
  }
}
