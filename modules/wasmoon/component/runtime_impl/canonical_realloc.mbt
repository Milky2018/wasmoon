///|
struct CanonicalRealloc {
  func : CoreFuncRef
  async_state : AsyncState
  owner_component_id : Int
}

///|
impl Debug for CanonicalRealloc with fn to_repr(self) {
  Repr::literal("CanonicalRealloc(component=\{self.owner_component_id})")
}

///|
fn CanonicalRealloc::call(
  self : CanonicalRealloc,
  store : @runtime.Store,
  args : Array[@types.Value],
) -> Array[@types.Value] raise ComponentRuntimeError {
  let state = self.async_state
  let task_id = alloc_task_id(state)
  init_task_meta(
    state,
    task_id,
    self.owner_component_id,
    current_task_id(state),
  )
  push_task(state, task_id, false)
  let previous_may_leave = canon_may_leave[0]
  canon_may_leave[0] = false
  defer {
    canon_may_leave[0] = previous_may_leave
    pop_task(state)
    state.task_contexts.remove(task_id)
    drop_task_thread(state, task_id)
    remove_task_meta(state, task_id)
  }
  call_core_func(store, self.func, args)
}
