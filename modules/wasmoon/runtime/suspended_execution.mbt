///|
priv struct SuspendedExecutionCleanup {
  run : () -> Unit
}

///|
impl Debug for SuspendedExecutionCleanup with fn to_repr(_self) {
  Repr::literal("<suspended-execution-cleanup>")
}

///|
/// Register parked execution for cancellation on terminal Store close.
/// The executor removes this registration before resuming or cancelling it.
pub fn Store::register_suspended_execution(
  self : Store,
  cancel : () -> Unit,
) -> Int64 raise RuntimeError {
  self.ensure_open()
  let id = self.next_suspended_execution_id
  self.next_suspended_execution_id += 1L
  self.suspended_executions.set(id, { run: cancel, })
  id
}

///|
/// Detach parked execution before running any of its cleanup callbacks.
pub fn Store::release_suspended_execution(self : Store, id : Int64) -> Unit {
  self.suspended_executions.remove(id)
}
