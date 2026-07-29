///|
pub suberror NativeReactorError {
  UnsupportedPlatform
  AllocationFailed
  RegistrationFailed(Int)
  WaitFailed(Int)
  WakeFailed(Int)
} derive(Debug, Eq)

///|
pub impl Show for NativeReactorError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
priv type NativeReactorObject

///|
extern "c" fn c_reactor_supported() -> Int = "wasmoon_async_reactor_supported"

///|
extern "c" fn c_reactor_alloc() -> NativeReactorObject = "wasmoon_async_reactor_alloc"

///|
#borrow(reactor)
extern "c" fn c_reactor_state(reactor : NativeReactorObject) -> Int = "wasmoon_async_reactor_state"

///|
#borrow(reactor)
extern "c" fn c_reactor_errno(reactor : NativeReactorObject) -> Int = "wasmoon_async_reactor_errno"

///|
#borrow(reactor)
extern "c" fn c_reactor_register_fd(
  reactor : NativeReactorObject,
  fd : Int,
  writable : Int,
  token : Int64,
) -> Int = "wasmoon_async_reactor_register_fd"

///|
#borrow(reactor)
extern "c" fn c_reactor_register_timer(
  reactor : NativeReactorObject,
  delay_ns : Int64,
  token : Int64,
) -> Int = "wasmoon_async_reactor_register_timer"

///|
#borrow(reactor)
extern "c" fn c_reactor_cancel(
  reactor : NativeReactorObject,
  token : Int64,
) -> Int = "wasmoon_async_reactor_cancel"

///|
#borrow(reactor, tokens)
extern "c" fn c_reactor_wait(
  reactor : NativeReactorObject,
  timeout_ns : Int64,
  tokens : FixedArray[Int64],
  capacity : Int,
) -> Int = "wasmoon_async_reactor_wait"

///|
#borrow(reactor)
extern "c" fn c_reactor_wake(reactor : NativeReactorObject) -> Int = "wasmoon_async_reactor_wake"

///|
priv enum RegistrationState {
  Pending
  Ready
  Cancelled
}

///|
priv struct RegistrationRecord {
  state : Ref[RegistrationState]
}

///|
/// Native descriptor-readiness adapter.
///
/// Platform descriptors, event filters, and kernel user-data tokens are
/// confined to this package. Callers retain only an opaque registration.
struct NativeReactor {
  raw : NativeReactorObject
  mut next_token : Int64
  registrations : Map[Int64, RegistrationRecord]
}

///|
pub fn NativeReactor::supported() -> Bool {
  c_reactor_supported() == 1
}

///|
pub fn NativeReactor::try_new() -> NativeReactor raise NativeReactorError {
  if !NativeReactor::supported() {
    raise UnsupportedPlatform
  }
  let raw = c_reactor_alloc()
  if c_reactor_state(raw) != 0 {
    raise AllocationFailed
  }
  { raw, next_token: 1L, registrations: Map([]) }
}

///|
fn NativeReactor::allocate_token(self : NativeReactor) -> Int64 {
  let token = self.next_token
  self.next_token = token + 1L
  token
}

///|
fn NativeReactor::register(
  self : NativeReactor,
  install : (Int64) -> Int,
) -> NativeRegistration raise NativeReactorError {
  let token = self.allocate_token()
  let status = install(token)
  if status != 0 {
    raise RegistrationFailed(status)
  }
  let record : RegistrationRecord = { state: Ref(Pending) }
  self.registrations.set(token, record)
  NativeRegistration(self, token, record)
}

///|
/// Register one one-shot readable event.
///
/// Each registration owns an independent duplicate of `fd`, so multiple
/// concurrent registrations for the same descriptor remain isolated.
pub fn NativeReactor::register_read(
  self : NativeReactor,
  fd : Int,
) -> NativeRegistration raise NativeReactorError {
  self.register(fn(token) { c_reactor_register_fd(self.raw, fd, 0, token) })
}

///|
/// Register one one-shot writable event.
pub fn NativeReactor::register_write(
  self : NativeReactor,
  fd : Int,
) -> NativeRegistration raise NativeReactorError {
  self.register(fn(token) { c_reactor_register_fd(self.raw, fd, 1, token) })
}

///|
/// Register one one-shot relative timer.
pub fn NativeReactor::register_timer(
  self : NativeReactor,
  delay_ns : Int64,
) -> NativeRegistration raise NativeReactorError {
  let token = self.allocate_token()
  let status = c_reactor_register_timer(self.raw, delay_ns.max(1L), token)
  if status != 0 {
    raise RegistrationFailed(status)
  }
  let record : RegistrationRecord = { state: Ref(Pending) }
  self.registrations.set(token, record)
  NativeRegistration(self, token, record)
}

///|
fn NativeReactor::complete_token(self : NativeReactor, token : Int64) -> Bool {
  guard self.registrations.get(token) is Some(record) else { return false }
  self.registrations.remove(token)
  match record.state.val {
    Pending => {
      record.state.val = Ready
      true
    }
    Ready | Cancelled => false
  }
}

///|
/// Whether this reactor still owns kernel registrations that can complete.
pub fn NativeReactor::has_pending(self : NativeReactor) -> Bool {
  !self.registrations.is_empty()
}

///|
/// Wait for readiness and deliver it to the shared async runtime.
///
/// `None` blocks until an event. `Some(0)` performs a nonblocking drain.
pub fn NativeReactor::wait(
  self : NativeReactor,
  timeout_ns : Int64?,
) -> Int raise NativeReactorError {
  let capacity = (self.registrations.length() + 1).max(1)
  let tokens = FixedArray::make(capacity, 0L)
  let count = c_reactor_wait(
    self.raw,
    timeout_ns.unwrap_or(-1L),
    tokens,
    capacity,
  )
  if count < 0 {
    raise WaitFailed(c_reactor_errno(self.raw))
  }
  let mut completed = 0
  for i in 0..<count {
    let token = tokens[i]
    if token != 0L && self.complete_token(token) {
      completed = completed + 1
    }
  }
  completed
}

///|
/// Trigger the reactor's explicit wakeup source.
pub fn NativeReactor::wake(
  self : NativeReactor,
) -> Unit raise NativeReactorError {
  let status = c_reactor_wake(self.raw)
  if status != 0 {
    raise WakeFailed(status)
  }
}

///|
pub impl Debug for NativeReactor with fn to_repr(self) {
  Repr::ctor("NativeReactor", [
    (Some("registrations"), to_repr(self.registrations.length())),
  ])
}

///|
/// One native one-shot registration.
struct NativeRegistration(NativeReactor, Int64, RegistrationRecord)

///|
/// Whether this registration is still waiting for a kernel event.
pub fn NativeRegistration::is_active(self : NativeRegistration) -> Bool {
  self.2.state.val is Pending
}

///|
/// Whether the registered kernel event has completed.
pub fn NativeRegistration::is_ready(self : NativeRegistration) -> Bool {
  self.2.state.val is Ready
}

///|
/// Cancel this native registration.
///
/// Cancellation is idempotent. A kernel event already queued for this token is
/// ignored because the token is removed before the registration is cancelled.
pub fn NativeRegistration::cancel(self : NativeRegistration) -> Unit {
  match self.2.state.val {
    Pending => {
      self.2.state.val = Cancelled
      self.0.registrations.remove(self.1)
      c_reactor_cancel(self.0.raw, self.1) |> ignore
    }
    Ready => self.2.state.val = Cancelled
    Cancelled => ()
  }
}
