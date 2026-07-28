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
  ident : Int64,
  filter : Int,
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
priv struct RegistrationRecord {
  operation : @wasmoon_async.OperationHandle
  ident : Int64
  filter : Int
  active : Array[Bool]
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
  waker : @wasmoon_async.Waker,
  ident : Int64,
  filter : Int,
  install : (Int64) -> Int,
) -> NativeRegistration raise NativeReactorError {
  guard waker.register() is Some(operation) else { raise RegistrationFailed(0) }
  let token = self.allocate_token()
  let status = install(token)
  if status != 0 {
    operation.cancel()
    raise RegistrationFailed(status)
  }
  let record : RegistrationRecord = { operation, ident, filter, active: [true] }
  self.registrations.set(token, record)
  NativeRegistration(self, token, record)
}

///|
/// Register one one-shot readable event.
pub fn NativeReactor::register_read(
  self : NativeReactor,
  fd : Int,
  waker : @wasmoon_async.Waker,
) -> NativeRegistration raise NativeReactorError {
  self.register(waker, fd.to_int64(), -1, fn(token) {
    c_reactor_register_fd(self.raw, fd, 0, token)
  })
}

///|
/// Register one one-shot writable event.
pub fn NativeReactor::register_write(
  self : NativeReactor,
  fd : Int,
  waker : @wasmoon_async.Waker,
) -> NativeRegistration raise NativeReactorError {
  self.register(waker, fd.to_int64(), -2, fn(token) {
    c_reactor_register_fd(self.raw, fd, 1, token)
  })
}

///|
/// Register one one-shot relative timer.
pub fn NativeReactor::register_timer(
  self : NativeReactor,
  delay_ns : Int64,
  waker : @wasmoon_async.Waker,
) -> NativeRegistration raise NativeReactorError {
  let token = self.allocate_token()
  guard waker.register() is Some(operation) else { raise RegistrationFailed(0) }
  let status = c_reactor_register_timer(self.raw, delay_ns.max(1L), token)
  if status != 0 {
    operation.cancel()
    raise RegistrationFailed(status)
  }
  let record : RegistrationRecord = {
    operation,
    ident: token,
    filter: -7,
    active: [true],
  }
  self.registrations.set(token, record)
  NativeRegistration(self, token, record)
}

///|
fn NativeReactor::complete_token(self : NativeReactor, token : Int64) -> Bool {
  guard self.registrations.get(token) is Some(record) else { return false }
  self.registrations.remove(token)
  if !record.active[0] {
    return false
  }
  record.active[0] = false
  record.operation.complete()
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
pub fn NativeRegistration::operation_id(
  self : NativeRegistration,
) -> @wasmoon_async.OperationId {
  self.2.operation.id()
}

///|
pub fn NativeRegistration::is_active(self : NativeRegistration) -> Bool {
  self.2.active[0]
}

///|
/// Cancel this native registration and its runtime operation.
///
/// Cancellation is idempotent. A kernel event already queued for this token is
/// ignored because the token is removed before the operation is cancelled.
pub fn NativeRegistration::cancel(self : NativeRegistration) -> Unit {
  if !self.2.active[0] {
    return
  }
  self.2.active[0] = false
  self.0.registrations.remove(self.1)
  c_reactor_cancel(self.0.raw, self.1, self.2.ident, self.2.filter) |> ignore
  self.2.operation.cancel()
}
