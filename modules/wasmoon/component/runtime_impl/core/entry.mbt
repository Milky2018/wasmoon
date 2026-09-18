///|
/// Entry state for one component instance.
///
/// Defined adapters can run during core module instantiation. Publication of
/// the component graph is guarded separately by the linker's staging transaction.
/// Synchronous calls may nest. The active depth gates new async tasks and is
/// released while stackful execution is suspended. Shared poison rejects new
/// host calls without preventing admitted tasks from resuming.
struct ComponentInstanceEntryState {
  active_depth : Ref[Int]
  poisoned : Ref[Bool]
} derive(Debug)

///|
pub fn ComponentInstanceEntryState::new(
  poisoned? : Ref[Bool] = Ref(false),
) -> ComponentInstanceEntryState {
  { active_depth: Ref(0), poisoned, }
}

///|
pub fn ComponentInstanceEntryState::may_start_async(
  self : ComponentInstanceEntryState,
) -> Bool {
  self.active_depth.val == 0
}

///|
pub fn ComponentInstanceEntryState::enter(
  self : ComponentInstanceEntryState,
) -> Unit {
  self.active_depth.val += 1
}

///|
pub fn ComponentInstanceEntryState::leave(
  self : ComponentInstanceEntryState,
) -> Unit {
  self.active_depth.val -= 1
}

///|
pub fn ComponentInstanceEntryState::poison(
  self : ComponentInstanceEntryState,
) -> Unit {
  self.poisoned.val = true
}
