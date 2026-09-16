///|
/// Invocation-local cooperative cancellation and elapsed-time deadline.
/// Uses a monotonic clock; time spent suspended or in host code counts.
pub struct InvocationControl {
  deadline : (@perf.Instant, Double)?
  cancel : (() -> Bool)?
  mut cancelled : Bool
  mut timed_out : Bool
}

///|
/// A negative timeout is invalid; zero expires before guest execution.
pub fn InvocationControl::new(
  timeout_ms : Int?,
  cancel : (() -> Bool)?,
) -> InvocationControl? {
  if timeout_ms is Some(ms) && ms < 0 {
    return None
  }
  Some({
    deadline: timeout_ms.map(ms => {
      (@perf.instant_now(), ms.to_double() / 1000.0)
    }),
    cancel,
    cancelled: false,
    timed_out: false,
  })
}

///|
/// Check the deadline without invoking the user's cancellation callback.
pub fn InvocationControl::expired(self : InvocationControl) -> Bool {
  if !self.cancelled && self.deadline is Some((start, seconds)) {
    if @perf.instant_elapsed_as_secs_f64(start) >= seconds {
      self.timed_out = true
    }
  }
  self.timed_out
}

///|
/// Latch the first observed stop reason for stable result classification.
pub fn InvocationControl::poll(self : InvocationControl) -> Bool {
  if self.cancelled || self.expired() {
    return true
  }
  if self.cancel is Some(callback) && callback() {
    self.cancelled = true
    return true
  }
  self.expired()
}
