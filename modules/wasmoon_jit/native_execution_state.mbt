///|
/// Lifecycle phase of a Store-owned native invocation.
pub(all) enum NativeInvocationPhase {
  Active
  Parked
} derive(Debug, Eq)

///|
/// Invalid transition in the Store-owned native invocation state machine.
pub suberror NativeExecutionStateError {
  ExecutionStateSealed
  UnknownInvocation(Int64)
  InvocationNotActive(Int64)
  InvocationNotParked(Int64)
  InvocationNotCurrent(Int64)
} derive(Debug, Eq)

///|
pub impl Show for NativeExecutionStateError with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(to_repr(self).to_string()))
}

///|
/// One live native invocation.
///
/// `resource_id` identifies the exclusive stack resource assigned to this
/// invocation. The native continuation layer owns the corresponding fiber.
priv struct NativeInvocation {
  id : Int64
  resource_id : Int64
  mut phase : NativeInvocationPhase
  release_fn : () -> Unit
}

///|
/// Store-scoped owner of native invocation lifetimes.
///
/// The active stack models nested native entry. Parked invocations remain in
/// `invocations` but are absent from `active`, so any number of component tasks
/// can retain distinct native resources without sharing an execution stack.
struct NativeExecutionState {
  mut accepting_new_invocations : Bool
  mut next_invocation_id : Int64
  mut next_resource_id : Int64
  active : Array[Int64]
  invocations : Map[Int64, NativeInvocation]
  reusable_resources : Array[Int64]
}

///|
pub fn NativeExecutionState::NativeExecutionState() -> NativeExecutionState {
  {
    accepting_new_invocations: true,
    next_invocation_id: 0L,
    next_resource_id: 0L,
    active: [],
    invocations: Map([]),
    reusable_resources: [],
  }
}

///|
/// Irreversibly reject new invocations while preserving cleanup operations for
/// existing handles.
pub fn NativeExecutionState::seal(self : NativeExecutionState) -> Unit {
  self.accepting_new_invocations = false
}

///|
fn NativeExecutionState::allocate_resource_id(
  self : NativeExecutionState,
) -> Int64 {
  if self.reusable_resources.length() > 0 {
    self.reusable_resources.remove(self.reusable_resources.length() - 1)
  } else {
    let id = self.next_resource_id
    self.next_resource_id = id + 1L
    id
  }
}

///|
pub fn NativeExecutionState::begin(
  self : NativeExecutionState,
  release? : () -> Unit = fn() { () },
) -> NativeInvocationHandle raise NativeExecutionStateError {
  if !self.accepting_new_invocations {
    raise ExecutionStateSealed
  }
  // Retaining the release closure retains everything it captures. Suspendable
  // callers use it to pin code, instances, and native buffers until the
  // invocation either completes or is cancelled.
  let id = self.next_invocation_id
  self.next_invocation_id = id + 1L
  let invocation = {
    id,
    resource_id: self.allocate_resource_id(),
    phase: Active,
    release_fn: release,
  }
  self.invocations.set(id, invocation)
  self.active.push(id)
  NativeInvocationHandle(self, id)
}

///|
fn NativeExecutionState::invocation(
  self : NativeExecutionState,
  id : Int64,
) -> NativeInvocation raise NativeExecutionStateError {
  match self.invocations.get(id) {
    Some(invocation) => invocation
    None => raise UnknownInvocation(id)
  }
}

///|
fn NativeExecutionState::require_current(
  self : NativeExecutionState,
  id : Int64,
) -> NativeInvocation raise NativeExecutionStateError {
  let invocation = self.invocation(id)
  if invocation.phase != Active {
    raise InvocationNotActive(id)
  }
  if self.active.is_empty() || self.active[self.active.length() - 1] != id {
    raise InvocationNotCurrent(id)
  }
  invocation
}

///|
fn NativeExecutionState::release(
  self : NativeExecutionState,
  invocation : NativeInvocation,
) -> Unit {
  self.invocations.remove(invocation.id)
  self.reusable_resources.push(invocation.resource_id)
  (invocation.release_fn)()
}

///|
fn NativeExecutionState::park(
  self : NativeExecutionState,
  id : Int64,
) -> Unit raise NativeExecutionStateError {
  let invocation = self.require_current(id)
  self.active.remove(self.active.length() - 1) |> ignore
  invocation.phase = Parked
}

///|
fn NativeExecutionState::reactivate(
  self : NativeExecutionState,
  id : Int64,
) -> Unit raise NativeExecutionStateError {
  let invocation = self.invocation(id)
  if invocation.phase != Parked {
    raise InvocationNotParked(id)
  }
  invocation.phase = Active
  self.active.push(id)
}

///|
fn NativeExecutionState::complete(
  self : NativeExecutionState,
  id : Int64,
) -> Unit raise NativeExecutionStateError {
  let invocation = self.require_current(id)
  self.active.remove(self.active.length() - 1) |> ignore
  self.release(invocation)
}

///|
fn NativeExecutionState::cancel(
  self : NativeExecutionState,
  id : Int64,
) -> Unit raise NativeExecutionStateError {
  let invocation = self.invocation(id)
  if invocation.phase != Parked {
    raise InvocationNotParked(id)
  }
  self.release(invocation)
}

///|
/// Best-effort scope cleanup after an error.
///
/// Strict user-visible transitions use `complete` and `cancel`; this method is
/// intentionally idempotent so a `defer` can release an unfinished invocation
/// without masking the original trap.
pub fn NativeExecutionState::release_if_live(
  self : NativeExecutionState,
  id : Int64,
) -> Unit {
  guard self.invocations.get(id) is Some(invocation) else { return }
  match invocation.phase {
    Active =>
      if self.active.length() > 0 && self.active[self.active.length() - 1] == id {
        self.active.remove(self.active.length() - 1) |> ignore
        self.release(invocation)
      }
    Parked => self.release(invocation)
  }
}

///|
pub fn NativeExecutionState::current_invocation(
  self : NativeExecutionState,
) -> Int64? {
  if self.active.is_empty() {
    None
  } else {
    Some(self.active[self.active.length() - 1])
  }
}

///|
pub fn NativeExecutionState::active_depth(self : NativeExecutionState) -> Int {
  self.active.length()
}

///|
pub fn NativeExecutionState::parked_count(self : NativeExecutionState) -> Int {
  let mut count = 0
  for entry in self.invocations.iter() {
    if entry.1.phase == Parked {
      count = count + 1
    }
  }
  count
}

///|
pub fn NativeExecutionState::live_count(self : NativeExecutionState) -> Int {
  self.invocations.length()
}

///|
pub impl Debug for NativeExecutionState with fn to_repr(self) {
  Repr::ctor("NativeExecutionState", [
    (Some("active_depth"), to_repr(self.active_depth())),
    (Some("parked_count"), to_repr(self.parked_count())),
    (Some("live_count"), to_repr(self.live_count())),
  ])
}

///|
/// Stable handle for one Store-owned native invocation.
struct NativeInvocationHandle(NativeExecutionState, Int64)

///|
pub fn NativeInvocationHandle::id(self : NativeInvocationHandle) -> Int64 {
  self.1
}

///|
pub fn NativeInvocationHandle::resource_id(
  self : NativeInvocationHandle,
) -> Int64 raise NativeExecutionStateError {
  self.0.invocation(self.1).resource_id
}

///|
pub fn NativeInvocationHandle::phase(
  self : NativeInvocationHandle,
) -> NativeInvocationPhase raise NativeExecutionStateError {
  self.0.invocation(self.1).phase
}

///|
pub fn NativeInvocationHandle::park(
  self : NativeInvocationHandle,
) -> Unit raise NativeExecutionStateError {
  self.0.park(self.1)
}

///|
pub fn NativeInvocationHandle::reactivate(
  self : NativeInvocationHandle,
) -> Unit raise NativeExecutionStateError {
  self.0.reactivate(self.1)
}

///|
pub fn NativeInvocationHandle::complete(
  self : NativeInvocationHandle,
) -> Unit raise NativeExecutionStateError {
  self.0.complete(self.1)
}

///|
pub fn NativeInvocationHandle::cancel(
  self : NativeInvocationHandle,
) -> Unit raise NativeExecutionStateError {
  self.0.cancel(self.1)
}

///|
pub fn NativeInvocationHandle::release_if_live(
  self : NativeInvocationHandle,
) -> Unit {
  self.0.release_if_live(self.1)
}

///|
pub impl Debug for NativeInvocationHandle with fn to_repr(self) {
  Repr::ctor("NativeInvocationHandle", [(Some("id"), to_repr(self.1))])
}
