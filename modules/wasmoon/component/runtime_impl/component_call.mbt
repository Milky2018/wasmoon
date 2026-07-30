///|
pub(all) enum ComponentInvocationPoll {
  InvocationPending
  InvocationReady(Array[ComponentValue])
} derive(Debug)

///|
priv enum ComponentInvocationPhase {
  Running
  Completed(Array[ComponentValue])
  Failed(ComponentRuntimeError)
  WasCancelled
}

///|
priv enum ComponentInvocationStep {
  DriveProgressed
  DriveBlocked
  DriveReady(Array[ComponentValue])
}

///|
struct ComponentInvocation {
  task_id : Int64
  task : CallbackTask
  store : @runtime.Store
  caller_table : ResourceTable
  async_state : AsyncState
  can_block : Bool
  phase : Array[ComponentInvocationPhase]
}

///|
fn component_invocation_contract(
  func : ComponentFunc,
) -> (FuncType, Array[TypeDef?], Int) {
  match func {
    Host(func_type, types, _) | HostAsync(func_type, types, _) =>
      (func_type, types, -1)
    Lifted(_, func_type, _, types, callee_table, _, _, _) =>
      (func_type, types, callee_table.id)
  }
}

///|
fn ComponentInvocation::cleanup_task(self : ComponentInvocation) -> Unit {
  match self.task.waiting_set[0] {
    Some(waitable_set) =>
      if self.async_state.waitable_sets.get(waitable_set) is Some(set) &&
        set.waiters[0] > 0 {
        set.waiters[0] = set.waiters[0] - 1
      }
    None => ()
  }
  self.task.waiting_set[0] = None
  self.async_state.task_results.remove(self.task_id)
  self.async_state.task_result_owner.remove(self.task_id)
  self.async_state.task_returned.remove(self.task_id)
  self.async_state.task_self_cancelled.remove(self.task_id)
  self.async_state.task_cancelled.remove(self.task_id)
  self.async_state.task_contexts.remove(self.task_id)
  self.async_state.yield_suspended.remove(self.task_id)
  self.async_state.waiting_ws.remove(self.task_id)
  self.async_state.sync_lower_states.remove(self.task_id)
  drop_task_thread(self.async_state, self.task_id)
  remove_task_meta(self.async_state, self.task_id)
}

///|
fn ComponentInvocation::finish(
  self : ComponentInvocation,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  let (func_type, types, callee_instance_id) = component_invocation_contract(
    self.task.func,
  )
  let values = take_task_result(self.async_state, self.task_id).unwrap_or([])
  let owner = self.async_state.task_result_owner
    .get(self.task_id)
    .unwrap_or(
      if callee_instance_id >= 0 {
        callee_instance_id
      } else {
        self.caller_table.id
      },
    )
  let transferred = transfer_results_if_needed(
    values,
    func_type.result,
    types,
    self.async_state,
    owner,
    self.caller_table.id,
  )
  self.cleanup_task()
  self.phase[0] = Completed(transferred)
  transferred
}

///|
fn ComponentInvocation::fail(
  self : ComponentInvocation,
  error : ComponentRuntimeError,
) -> Unit {
  match self.task.continuation[0] {
    Some(continuation) => {
      self.task.continuation[0] = None
      continuation.cancel()
    }
    None => ()
  }
  self.cleanup_task()
  self.phase[0] = Failed(error)
}

///|
fn ComponentInvocation::drive_once(
  self : ComponentInvocation,
) -> ComponentInvocationStep raise ComponentRuntimeError {
  match self.phase[0] {
    Completed(values) => return DriveReady(values)
    Failed(error) => raise error
    WasCancelled => raise Cancelled
    Running => ()
  }
  push_task(self.async_state, self.task_id, self.can_block)
  let step = step_task_once(
    self.task,
    self.store,
    self.caller_table,
    self.async_state,
  ) catch {
    error => {
      pop_task(self.async_state)
      self.fail(error)
      raise error
    }
  }
  pop_task(self.async_state)
  match step {
    Done =>
      DriveReady(self.finish()) catch {
        error => {
          self.fail(error)
          raise error
        }
      }
    Progressed => DriveProgressed
    Blocked =>
      try {
        if progress_one_subtask_nonblocking(self.async_state, self.store) ||
          poll_host_event(self.async_state, self.store) {
          DriveProgressed
        } else {
          DriveBlocked
        }
      } catch {
        error => {
          self.fail(error)
          raise error
        }
      }
  }
}

///|
pub fn ComponentInvocation::poll(
  self : ComponentInvocation,
) -> ComponentInvocationPoll raise ComponentRuntimeError {
  match self.drive_once() {
    DriveReady(values) => InvocationReady(values)
    DriveProgressed | DriveBlocked => InvocationPending
  }
}

///|
pub fn ComponentInvocation::wait(
  self : ComponentInvocation,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  while true {
    match self.drive_once() {
      DriveReady(values) => return values
      DriveProgressed => continue
      DriveBlocked =>
        try {
          if !wait_for_host_event(self.async_state, self.store) {
            let error = CanonCallError(
              "wasm trap: deadlock detected: event loop cannot make further progress",
            )
            raise error
          }
        } catch {
          error => {
            self.fail(error)
            raise error
          }
        }
    }
  }
  raise CanonCallError("unreachable")
}

///|
pub async fn ComponentInvocation::join(
  self : ComponentInvocation,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  while true {
    match self.poll() {
      InvocationReady(values) => return values
      InvocationPending =>
        @async.pause() catch {
          _ => {
            self.cancel()
            raise Cancelled
          }
        }
    }
  }
  raise CanonCallError("unreachable")
}

///|
pub fn ComponentInvocation::cancel(
  self : ComponentInvocation,
) -> Unit raise ComponentRuntimeError {
  match self.phase[0] {
    Running => ()
    Completed(_) | Failed(_) | WasCancelled => return
  }
  self.task.cancelled[0] = true
  let cancellation_error : ComponentRuntimeError? = match
    self.task.host_future[0] {
    Some(future) =>
      try (future.cancel)() catch {
        error => Some(error)
      } noraise {
        _ => None
      }
    None => None
  }
  match self.task.continuation[0] {
    Some(continuation) => {
      self.task.continuation[0] = None
      continuation.cancel()
    }
    None => ()
  }
  self.cleanup_task()
  self.phase[0] = WasCancelled
  match cancellation_error {
    Some(error) => raise error
    None => ()
  }
}

///|
pub fn ComponentInstance::start_exported_func(
  self : ComponentInstance,
  name : String,
  args : Array[ComponentValue],
) -> ComponentInvocation raise ComponentRuntimeError {
  let func = match self.exports.get(name) {
    Some(Func(func)) => func
    Some(_) | None => raise UnknownExport(name)
  }
  let (func_type, _types, callee_instance_id) = component_invocation_contract(
    func,
  )
  let task_id = alloc_task_id(self.async_state)
  init_task_meta(self.async_state, task_id, callee_instance_id, 0L)
  take_task_result(self.async_state, task_id) |> ignore
  {
    task_id,
    task: {
      func,
      args: args.copy(),
      args_owner_component_id: [self.resource_table.id],
      started: [false],
      code: [0],
      waiting_set: [None],
      host_future: [None],
      cancelled: [false],
      continuation: [None],
    },
    store: self.store,
    caller_table: self.resource_table,
    async_state: self.async_state,
    can_block: func_type.is_async,
    phase: [Running],
  }
}
