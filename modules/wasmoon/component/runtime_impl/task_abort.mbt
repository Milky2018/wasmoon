///|
fn callback_releases_backpressure(task : CallbackTask) -> Bool {
  match task.func {
    HostAsync(_, _, _) => true
    Lifted(_, _, _, _, _, _, Some(_), _) => task.started[0]
    _ => false
  }
}

///|
fn abort_waiting_callback(
  async_state : AsyncState,
  task : CallbackTask,
) -> Unit {
  cancel_callback_task(task)
  if task.waiting_set[0] is Some(key) &&
    async_state.waitable_sets.get(key) is Some(set) &&
    set.waiters[0] > 0 {
    set.waiters[0] -= 1
  }
  task.waiting_set[0] = None
}

///|
/// Retire work owned by an aborted invocation before its ancestry is removed.
fn abort_task_children(async_state : AsyncState, root : Int64) -> Unit {
  let root = async_state.tasks.resolve(root)
  let tasks : Array[Int64] = [root]
  let owned : Map[Int64, Bool] = Map([(root, true)])
  let children : Map[Int64, Array[Int64]] = Map([])
  for entry in async_state.tasks.entries_task_caller() {
    let (child, parent) = entry
    match children.get(parent) {
      Some(ids) => ids.push(child)
      None => children.set(parent, [child])
    }
  }
  for i = 0; i < tasks.length(); i = i + 1 {
    if children.get(tasks[i]) is Some(ids) {
      for child in ids {
        if owned.get(child) is None {
          owned.set(child, true)
          tasks.push(child)
        }
      }
    }
  }
  // Cancel callbacks while their task metadata and borrow scopes still exist.
  for id in tasks {
    if id != root && async_state.tasks.read_subtasks(id) is Some(subtask) {
      let CallbackLifted(task) = subtask.driver
      abort_waiting_callback(async_state, task)
    }
    if async_state.tasks.read_sync_lower_states(id) is Some(lower) {
      abort_waiting_callback(async_state, lower.task)
      async_state.tasks.clear_sync_lower_states(id)
    }
  }
  // Pending queues contain guest handles, so capture them before retirement.
  let owned_handles : Map[Int64, Bool] = Map([])
  for id in tasks {
    if async_state.tasks.handles.get(id) is Some(handle) {
      owned_handles.set(handle, true)
    }
  }
  let slots : Map[Int, Bool] = Map([])
  let handles : Array[(Int, Int)] = []
  for i = tasks.length() - 1; i > 0; i = i - 1 {
    let id = tasks[i]
    if async_state.tasks.read_subtasks(id) is Some(subtask) {
      async_state.tasks.clear_subtasks(id)
      if !subtask.detached {
        let owner = subtask.caller_table.id
        remove_waitable_membership(async_state, owner, subtask.id)
        async_state.waitable_events.remove(handle_key(owner, subtask.id))
        handles.push((owner, subtask.id))
        slots.set(subtask.bp_key, true)
      }
    }
    cleanup_thread_task(async_state, id)
  }
  discard_task_children(async_state, root)
  let queue_keys : Array[Int] = []
  for key, _ in async_state.pending_by_instance {
    queue_keys.push(key)
  }
  for key in queue_keys {
    let remaining : Array[Int64] = []
    for id in async_state.pending_by_instance[key] {
      if owned.get(id) is None && owned_handles.get(id) is None {
        remaining.push(id)
      }
    }
    if remaining.is_empty() {
      async_state.pending_by_instance.remove(key)
    } else {
      async_state.pending_by_instance.set(key, remaining)
    }
  }
  // Another invocation may still own the same admission slot.
  for key, _ in slots {
    let mut occupied = false
    for entry in async_state.tasks.entries_subtasks() {
      let (_, subtask) = entry
      if !subtask.detached &&
        subtask.bp_key == key &&
        subtask.phase[0] == Started {
        let CallbackLifted(task) = subtask.driver
        if !callback_releases_backpressure(task) {
          occupied = true
        }
      }
    }
    async_state.inflight_by_instance.set(key, if occupied { 1 } else { 0 })
  }
  for handle in handles {
    let (owner, id) = handle
    free_shared_handle(async_state, owner, id)
  }
}
