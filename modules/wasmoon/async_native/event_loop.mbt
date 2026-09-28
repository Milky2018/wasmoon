///|
priv struct HostEventLoop {
  reactor : @reactor.NativeReactor
  wakeup : FuncRef[() -> Unit]
  ready : @async.CondVar
}

///|
let active_loop : Ref[HostEventLoop?] = Ref(None)

///|
/// Install native WASI readiness as async's external event loop. Call once,
/// before the first asynchronous operation and before creating WASI contexts.
/// The async runtime owns shutdown; callers must not close the loop themselves.
pub fn install_event_loop() -> Unit raise NativeReactorError {
  if active_loop.val is Some(_) {
    return
  }
  let reactor = @reactor.NativeReactor::try_new()
  errdefer reactor.close()
  let wakeup = reactor.attach_external_wakeup()
  let event_loop = { reactor, wakeup, ready: Cond(), }
  @async.set_external_event_loop(event_loop)
  active_loop.val = Some(event_loop)
}

///|
/// Subscribe from a structured host task. The consumer must poll its persistent
/// operation state before waiting; notifications themselves are not state.
pub async fn wait_for_readiness() -> Unit {
  if active_loop.val is Some(event_loop) {
    event_loop.ready.wait()
  } else {
    raise Failure("native external event loop is not installed")
  }
}

///|
pub fn event_loop_installed() -> Bool {
  active_loop.val is Some(_)
}

///|
impl @external_loop_integration.ExternalEventLoop for HostEventLoop with fn poll(
  self,
  timeout?,
) {
  let timeout_ns = timeout.map(ms => ms.to_int64() * 1000000L)
  if self.reactor.wait(timeout_ns) > 0 {
    self.ready.broadcast()
  }
}

///|
impl @external_loop_integration.ExternalEventLoop for HostEventLoop with fn get_wakeup_callback_for_foreign_thread(
  self,
) {
  self.wakeup
}

///|
impl @external_loop_integration.ExternalEventLoop for HostEventLoop with fn terminate(
  self,
) {
  // async joins its foreign-thread waiter before calling terminate.
  @reactor.detach_external_wakeup()
  self.reactor.close()
  active_loop.val = None
}
