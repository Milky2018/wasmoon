///|
/// One asynchronous host function registered with a Store.
pub type AsyncHostFunction = async (Caller, Array[@types.Value]) -> Result[
  Array[@types.Value],
  Error,
]

///|
/// Result of polling the host operation at the current Wasm call site.
pub(all) enum AsyncHostPoll {
  AsyncHostPending
  AsyncHostReady(Array[@types.Value])
} derive(Debug)

///|
priv enum AsyncHostCallState {
  Idle
  Waiting(Int, @async.Task[AsyncHostCompletion], Ref[Bool])
  Result(Int, AsyncHostCompletion)
  Delivered(GcRootLease)
}

///|
/// A completed host task owns any GC references in its result until the Wasm
/// executor has incorporated them into its own root set.
priv enum AsyncHostCompletion {
  Completed(Array[@types.Value], GcRootLease)
  Failed(Error)
}

///|
/// Invocation-local owner of one pending asynchronous host operation.
///
/// The driver is intentionally opaque. Executors poll it only at an imported
/// hostcall and wait on it only after the Wasm continuation has been parked.
pub struct AsyncHostCallDriver {
  priv spawn : (async () -> AsyncHostCompletion) -> @async.Task[
    AsyncHostCompletion,
  ]
  priv state : Ref[AsyncHostCallState]
}

///|
pub impl Debug for AsyncHostCallDriver with fn to_repr(_self) {
  Repr::literal("<async-host-call-driver>")
}

///|
/// Run one asynchronous Wasm invocation with structured ownership of every
/// host task it starts.
pub async fn[X] with_async_host_call_driver(
  body : async (AsyncHostCallDriver) -> X raise Error,
) -> X {
  @async.with_task_group(group => {
    let driver : AsyncHostCallDriver = {
      spawn: fn(task) { group.spawn(task) },
      state: Ref(Idle),
    }
    defer driver.cancel()
    body(driver)
  })
}

///|
/// Poll the operation associated with the current imported call.
///
/// The first poll starts the host task. A later poll consumes its result after
/// `wait_pending` has returned.
pub fn AsyncHostCallDriver::poll(
  self : AsyncHostCallDriver,
  func_addr : Int,
  func : AsyncHostFunction,
  caller : Caller,
  args : Array[@types.Value],
) -> AsyncHostPoll raise RuntimeError {
  match self.state.val {
    Idle => {
      let owned = Ref(true)
      let task = (self.spawn)(async fn() {
        match func(caller, args) {
          Ok(values) => {
            let root_lease = caller.store().pin_gc_roots(values)
            if !owned.val {
              root_lease.release()
            }
            Completed(values, root_lease)
          }
          Err(error) => Failed(error)
        }
      })
      self.state.val = Waiting(func_addr, task, owned)
      AsyncHostPending
    }
    Waiting(pending_addr, _, _) => {
      if pending_addr != func_addr {
        raise AsyncHostCallInProgress
      }
      AsyncHostPending
    }
    Result(result_addr, completion) => {
      if result_addr != func_addr {
        raise AsyncHostCallInProgress
      }
      match completion {
        Completed(values, root_lease) => {
          self.state.val = Delivered(root_lease)
          AsyncHostReady(values)
        }
        Failed(error) => {
          self.state.val = Idle
          raise normalize_async_host_error(error)
        }
      }
    }
    Delivered(root_lease) => {
      root_lease.release()
      self.state.val = Idle
      self.poll(func_addr, func, caller, args)
    }
  }
}

///|
pub fn normalize_async_host_error(error : Error) -> RuntimeError {
  match RuntimeError::from_error(error) {
    Some(runtime_error) => runtime_error
    None if @async.is_cancellation_error(error) => AsyncHostCallCancelled
    None => AsyncHostError(error.to_string())
  }
}

///|
/// Wait without blocking the host thread until the parked host operation can
/// be consumed by a retry of the same Wasm call site.
pub async fn AsyncHostCallDriver::wait_pending(
  self : AsyncHostCallDriver,
) -> Unit raise RuntimeError {
  guard self.state.val is Waiting(func_addr, task, _) else { raise Unreachable }
  let result = task.wait() catch {
    _ => {
      self.cancel()
      raise AsyncHostCallCancelled
    }
  }
  self.state.val = Result(func_addr, result)
}

///|
/// Cancel the pending host operation, if any.
pub fn AsyncHostCallDriver::cancel(self : AsyncHostCallDriver) -> Unit {
  match self.state.val {
    Waiting(_, task, owned) => {
      owned.val = false
      let completion = task.try_wait() catch { _ => None }
      match completion {
        Some(Completed(_, root_lease)) => root_lease.release()
        Some(Failed(_)) | None => ()
      }
      task.cancel()
    }
    Result(_, Completed(_, root_lease)) | Delivered(root_lease) =>
      root_lease.release()
    Idle | Result(_, Failed(_)) => ()
  }
  self.state.val = Idle
}
