///|
pub using @reactor {type NativeReactorError, type NativeRegistration}

///|
/// A context owns its registrations, even when the host shares a kernel reactor.
struct NativeReactor {
  reactor : @reactor.NativeReactor
  shared : Bool
  registrations : Array[NativeRegistration]
  closed : Ref[Bool]
}

///|
pub fn NativeReactor::supported() -> Bool {
  @reactor.NativeReactor::supported()
}

///|
pub fn NativeReactor::try_new() -> NativeReactor raise NativeReactorError {
  let (reactor, shared) = match active_loop.val {
    Some(event_loop) => (event_loop.reactor, true)
    None => (@reactor.NativeReactor::try_new(), false)
  }
  { reactor, shared, registrations: [], closed: Ref(false), }
}

///|
fn NativeReactor::retain(
  self : NativeReactor,
  registration : NativeRegistration,
) -> NativeRegistration {
  let pending = self.registrations.filter(r => r.is_active())
  self.registrations.clear()
  self.registrations.append(pending)
  self.registrations.push(registration)
  registration
}

///|
fn NativeReactor::check_open(
  self : NativeReactor,
) -> Unit raise NativeReactorError {
  if self.closed.val {
    raise Closed
  }
}

///|
pub fn NativeReactor::register_read(
  self : NativeReactor,
  fd : Int,
) -> NativeRegistration raise NativeReactorError {
  self.check_open()
  self.retain(self.reactor.register_read(fd))
}

///|
pub fn NativeReactor::register_write(
  self : NativeReactor,
  fd : Int,
) -> NativeRegistration raise NativeReactorError {
  self.check_open()
  self.retain(self.reactor.register_write(fd))
}

///|
pub fn NativeReactor::register_timer(
  self : NativeReactor,
  delay_ns : Int64,
) -> NativeRegistration raise NativeReactorError {
  self.check_open()
  self.retain(self.reactor.register_timer(delay_ns))
}

///|
pub fn NativeReactor::has_pending(self : NativeReactor) -> Bool {
  self.registrations.any(r => r.is_active())
}

///|
pub fn NativeReactor::wait(
  self : NativeReactor,
  timeout_ns : Int64?,
) -> Int raise NativeReactorError {
  self.check_open()
  let completed = self.reactor.wait(timeout_ns)
  if self.shared && completed > 0 {
    notify_readiness()
  }
  completed
}

///|
pub fn NativeReactor::wake(
  self : NativeReactor,
) -> Unit raise NativeReactorError {
  self.check_open()
  self.reactor.wake()
}

///|
pub fn NativeReactor::close(self : NativeReactor) -> Unit {
  if self.closed.val {
    return
  }
  self.closed.val = true
  for registration in self.registrations {
    registration.cancel()
  }
  self.registrations.clear()
  if !self.shared {
    self.reactor.close()
  }
}

///|
pub impl Debug for NativeReactor with fn to_repr(self) {
  Repr::ctor("NativeReactor", [
    (
      Some("registrations"),
      Repr(self.registrations.filter(r => r.is_active()).length()),
    ),
  ])
}

///|
pub extend NativeReactor with Debug::{to_repr}
