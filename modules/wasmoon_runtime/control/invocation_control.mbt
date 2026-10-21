///|
/// Invocation-local cooperative cancellation and elapsed-time deadline.
/// Uses a monotonic clock; time spent suspended or in host code counts.
pub struct InvocationControl {
  deadline : (@perf.Instant, Double)?
  cancel : (() -> Bool)?
  mut cancelled : Bool
  mut timed_out : Bool
  priv mut remaining : Int64?
  exhausted : Ref[Bool]
}

///|
/// A negative timeout is invalid; zero expires before guest execution.
pub fn InvocationControl::new(
  timeout_ms : Int32?,
  cancel : (() -> Bool)?,
  safepoints~ : Int64? = None,
) -> InvocationControl? {
  if (timeout_ms is Some(ms) && ms < 0) ||
    (safepoints is Some(count) && count < 0L) {
    return None
  }
  Some({
    deadline: timeout_ms.map(ms => {
      (@perf.instant_now(), ms.to_double() / 1000.0)
    }),
    cancel,
    cancelled: false,
    timed_out: false,
    remaining: safepoints,
    exhausted: Ref(false),
  })
}

///|
/// Check the deadline without invoking the user's cancellation callback.
pub fn InvocationControl::expired(self : InvocationControl) -> Bool {
  if !self.cancelled &&
    !self.exhausted.val &&
    self.deadline is Some((start, seconds)) {
    if @perf.instant_elapsed_as_secs_f64(start) >= seconds {
      self.timed_out = true
    }
  }
  self.timed_out
}

///|
/// Observe interruption without attempting to consume another safepoint.
pub fn InvocationControl::interrupted(self : InvocationControl) -> Bool {
  if self.cancelled || self.exhausted.val || self.expired() {
    return true
  }
  if self.cancel is Some(callback) && callback() {
    self.cancelled = true
    return true
  }
  if self.expired() {
    return true
  }
  false
}

///|
/// Latch stop reasons before entering work that requires a safepoint.
pub fn InvocationControl::preflight(self : InvocationControl) -> Bool {
  if self.interrupted() {
    return true
  }
  if self.remaining == Some(0L) {
    self.exhausted.val = true
    return true
  }
  false
}

///|
pub fn InvocationControl::poll(self : InvocationControl) -> Bool {
  if self.preflight() {
    return true
  }
  if self.remaining is Some(count) {
    if count == 0L {
      self.exhausted.val = true
      return true
    }
    self.remaining = Some(count - 1L)
  }
  false
}
