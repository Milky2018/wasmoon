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
  driving : Array[Bool]
  cancel_requested : Array[Bool]
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
  retire_task(self.async_state, self.task_id)
}

///|
fn ComponentInvocation::finish(
  self : ComponentInvocation,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  let (func_type, types, callee_instance_id) = component_invocation_contract(
    self.task.func,
  )
  let values = take_task_result(self.async_state, self.task_id).unwrap_or([])
  let owner = self.async_state.tasks
    .read_task_result_owner(self.task_id)
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
  abort_task_children(self.async_state, self.task_id)
  cancel_callback_task(self.task)
  self.cleanup_task()
  self.phase[0] = Failed(error)
}

///|
fn ComponentInvocation::finish_cancel(
  self : ComponentInvocation,
) -> Unit raise ComponentRuntimeError {
  self.cancel_requested[0] = false
  let cancellation_error : ComponentRuntimeError? = match
    self.task.host_future[0] {
    Some(future) => {
      self.task.host_future[0] = None
      try (future.cancel)() catch {
        error => Some(error)
      } noraise {
        _ => None
      }
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
  abort_task_children(self.async_state, self.task_id)
  self.cleanup_task()
  self.phase[0] = WasCancelled
  match cancellation_error {
    Some(error) => raise error
    None => ()
  }
}

///|
fn ComponentInvocation::finish_cancel_during_unwind(
  self : ComponentInvocation,
) -> Unit {
  try self.finish_cancel() catch {
    _ => ()
  } noraise {
    _ => ()
  }
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
  if self.async_state.tasks.closed.val {
    self.finish_cancel_during_unwind()
    raise Cancelled
  }
  if self.driving[0] {
    raise InvocationAlreadyDriving
  }
  self.driving[0] = true
  defer {
    self.driving[0] = false
  }
  push_task(self.async_state, self.task_id, self.can_block)
  let step_cleanup_armed = [true]
  errdefer (if step_cleanup_armed[0] {
    pop_task(self.async_state)
    self.finish_cancel_during_unwind()
  })
  let step_result : Result[TaskStep, ComponentRuntimeError] = try {
    if !self.task.started[0] &&
      self.task.continuation[0] is None &&
      self.task.func is Lifted(_, ty, _, _, table, _, _, _) &&
      ty.is_async &&
      backpressure_value_for_instance(self.async_state, table.id) > 0 {
      Blocked
    } else {
      step_task_once(self.task, self.store, self.caller_table, self.async_state)
    }
  } catch {
    error => Err(error)
  } noraise {
    step => Ok(step)
  }
  step_cleanup_armed[0] = false
  pop_task(self.async_state)
  let step = match step_result {
    Ok(step) => step
    Err(error) => {
      if self.cancel_requested[0] {
        self.finish_cancel()
        raise Cancelled
      }
      self.fail(error)
      raise error
    }
  }
  if self.cancel_requested[0] || self.async_state.tasks.closed.val {
    self.finish_cancel()
    raise Cancelled
  }
  let result = match step {
    Done => {
      let finish_cleanup_armed = [true]
      errdefer (if finish_cleanup_armed[0] {
        self.finish_cancel_during_unwind()
      })
      let finish_result : Result[Array[ComponentValue], ComponentRuntimeError] = try
        self.finish()
      catch {
        error => Err(error)
      } noraise {
        values => Ok(values)
      }
      finish_cleanup_armed[0] = false
      match finish_result {
        Ok(values) => DriveReady(values)
        Err(error) => {
          self.fail(error)
          raise error
        }
      }
    }
    Progressed | Blocked => {
      let progress_cleanup_armed = [true]
      errdefer (if progress_cleanup_armed[0] {
        self.finish_cancel_during_unwind()
      })
      let progress_result : Result[
        ComponentInvocationStep,
        ComponentRuntimeError,
      ] = try {
        let subtask_progressed = progress_one_subtask_nonblocking(
          self.async_state,
          self.store,
        )
        if self.cancel_requested[0] {
          DriveBlocked
        } else {
          let host_progressed = poll_host_event(self.async_state, self.store)
          if self.cancel_requested[0] {
            DriveBlocked
          } else if step == Progressed || subtask_progressed || host_progressed {
            DriveProgressed
          } else {
            DriveBlocked
          }
        }
      } catch {
        error => Err(error)
      } noraise {
        result => Ok(result)
      }
      progress_cleanup_armed[0] = false
      match progress_result {
        Ok(result) => result
        Err(error) => {
          if self.cancel_requested[0] {
            self.finish_cancel()
            raise Cancelled
          }
          self.fail(error)
          raise error
        }
      }
    }
  }
  if self.cancel_requested[0] {
    self.finish_cancel()
    raise Cancelled
  }
  result
}

///|
pub fn ComponentInvocation::poll(
  self : ComponentInvocation,
) -> ComponentInvocationPoll raise ComponentRuntimeError {
  match self.drive_once() {
    DriveReady(values) =>
      InvocationReady(values.map(ComponentValue::to_host_value))
    DriveProgressed | DriveBlocked => InvocationPending
  }
}

///|
fn ComponentInvocation::wait_transport(
  self : ComponentInvocation,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  while true {
    match self.drive_once() {
      DriveReady(values) => return values
      DriveProgressed => continue
      DriveBlocked => {
        let wait_cleanup_armed = [true]
        errdefer (if wait_cleanup_armed[0] {
          self.finish_cancel_during_unwind()
        })
        let wait_result : Result[Unit, ComponentRuntimeError] = try {
          if !wait_for_host_event(self.async_state, self.store) {
            let error = CanonCallError(
              "wasm trap: deadlock detected: event loop cannot make further progress",
            )
            raise error
          }
        } catch {
          error => Err(error)
        } noraise {
          _ => Ok(())
        }
        wait_cleanup_armed[0] = false
        match wait_result {
          Ok(_) => ()
          Err(error) => {
            self.fail(error)
            raise error
          }
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
  if self.driving[0] {
    self.cancel_requested[0] = true
    return
  }
  self.finish_cancel()
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
  let (func_type, _, _) = component_invocation_contract(func)
  start_component_invocation(
    func,
    args,
    self.store,
    self.resource_table,
    self.async_state,
    0L,
    func_type.is_async,
  )
}

///|
fn start_component_invocation(
  func : ComponentFunc,
  args : Array[ComponentValue],
  store : @runtime.Store,
  caller_table : ResourceTable,
  async_state : AsyncState,
  caller_task_id : Int64,
  can_block : Bool,
) -> ComponentInvocation raise ComponentRuntimeError {
  let (_, _, callee_instance_id) = component_invocation_contract(func)
  let task_id = alloc_task_id(async_state)
  init_task_meta(async_state, task_id, callee_instance_id, caller_task_id)
  take_task_result(async_state, task_id) |> ignore
  let invocation : ComponentInvocation = {
    task_id,
    task: {
      func,
      args: args.copy(),
      args_owner_component_id: [caller_table.id],
      started: [false],
      main_finished: [false],
      code: [0],
      waiting_set: [None],
      host_future: [None],
      cancelled: [false],
      continuation: [None],
    },
    store,
    caller_table,
    async_state,
    can_block,
    phase: [Running],
    driving: [false],
    cancel_requested: [false],
  }
  async_state.tasks.records.get(task_id).unwrap().root_task = Some(
    invocation.task,
  )
  invocation
}

///|
pub fn ComponentInvocation::wait(
  self : ComponentInvocation,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  self.wait_transport().map(ComponentValue::to_host_value)
}
