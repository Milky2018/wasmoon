///|
struct CoreExecutionLifecycle {
  active_leases : Ref[Int]
  closing : Ref[Bool]
  close_when_idle : Ref[(() -> Unit)?]
}

///|
pub fn CoreExecutionLifecycle::new() -> CoreExecutionLifecycle {
  { active_leases: Ref(0), closing: Ref(false), close_when_idle: Ref(None), }
}

///|
pub fn CoreExecutionLifecycle::ensure_open(
  self : CoreExecutionLifecycle,
) -> Unit raise ComponentRuntimeError {
  if self.closing.val {
    raise Cancelled
  }
}

///|
fn CoreExecutionLifecycle::enter(
  self : CoreExecutionLifecycle,
) -> Unit raise ComponentRuntimeError {
  self.ensure_open()
  self.active_leases.val = self.active_leases.val + 1
}

///|
fn CoreExecutionLifecycle::leave(self : CoreExecutionLifecycle) -> Unit {
  self.active_leases.val = self.active_leases.val - 1
  if self.active_leases.val == 0 && self.closing.val {
    match self.close_when_idle.val {
      Some(close) => {
        self.close_when_idle.val = None
        close()
      }
      None => ()
    }
  }
}

///|
pub fn CoreExecutionLifecycle::begin_close(
  self : CoreExecutionLifecycle,
) -> Unit {
  self.closing.val = true
}

///|
pub fn CoreExecutionLifecycle::request_close(
  self : CoreExecutionLifecycle,
  close : () -> Unit,
) -> Unit {
  if self.active_leases.val == 0 {
    close()
  } else {
    self.close_when_idle.val = Some(close)
  }
}

///|
fn CoreExecutionLifecycle::finish_outcome(
  self : CoreExecutionLifecycle,
  outcome : CoreExecutionOutcome,
) -> CoreExecutionOutcome raise ComponentRuntimeError {
  if self.closing.val {
    match outcome {
      Suspended(_, continuation) => continuation.cancel()
      Returned(_) => ()
    }
    self.leave()
    raise Cancelled
  }
  match outcome {
    Returned(results) => {
      self.leave()
      Returned(results)
    }
    Suspended(reason, continuation) =>
      Suspended(reason, continuation.with_lifecycle(self))
  }
}

///|
/// Run one synchronous operation under a lifecycle lease.
///
/// This is the single implementation of the enter/catch/leave/closing
/// protocol for operations that complete within the call (engine
/// registration, whole instantiations). A close that begins while the
/// operation runs defers teardown until the lease is released here, and the
/// operation's result is discarded in favour of `Cancelled` — with
/// `rollback` running first so staged state never outlives the refusal.
/// `invoke` keeps its own flow: a suspension transfers the lease to the
/// continuation instead of releasing it.
pub fn[T] CoreExecutionLifecycle::with_lease(
  self : CoreExecutionLifecycle,
  operation : () -> T raise ComponentRuntimeError,
  rollback? : () -> Unit = fn() {  },
) -> T raise ComponentRuntimeError {
  self.enter()
  let cancellation_cleanup_armed = [true]
  errdefer (if cancellation_cleanup_armed[0] {
    rollback()
    self.leave()
  })
  let operation_result : Result[T, ComponentRuntimeError] = try
    operation()
  catch {
    error => Err(error)
  } noraise {
    result => Ok(result)
  }
  cancellation_cleanup_armed[0] = false
  match operation_result {
    Err(error) => {
      rollback()
      let closing = self.closing.val
      self.leave()
      if closing {
        raise Cancelled
      }
      raise error
    }
    Ok(result) => {
      if self.closing.val {
        rollback()
        self.leave()
        raise Cancelled
      }
      self.leave()
      result
    }
  }
}

///|
fn CoreContinuation::with_lifecycle(
  self : CoreContinuation,
  lifecycle : CoreExecutionLifecycle,
) -> CoreContinuation {
  let consumed = Ref(false)
  CoreContinuation(
    fn() raise ComponentRuntimeError {
      if consumed.val {
        raise CanonCallError("core continuation has already been consumed")
      }
      consumed.val = true
      if lifecycle.closing.val {
        self.cancel()
        lifecycle.leave()
        raise Cancelled
      }
      let cancellation_cleanup_armed = [true]
      errdefer (if cancellation_cleanup_armed[0] { lifecycle.leave() })
      let continuation_result : Result[
        CoreExecutionOutcome,
        ComponentRuntimeError,
      ] = try self.continue_execution() catch {
        error => Err(error)
      } noraise {
        outcome => Ok(outcome)
      }
      cancellation_cleanup_armed[0] = false
      let outcome = match continuation_result {
        Err(error) => {
          let closing = lifecycle.closing.val
          lifecycle.leave()
          if closing {
            raise Cancelled
          }
          raise error
        }
        Ok(outcome) => outcome
      }
      lifecycle.finish_outcome(outcome)
    },
    fn() {
      if !consumed.val {
        consumed.val = true
        self.cancel()
        lifecycle.leave()
      }
    },
  )
}

///|
pub fn CoreExecutionEngine::with_lifecycle(
  self : CoreExecutionEngine,
  lifecycle : CoreExecutionLifecycle,
) -> CoreExecutionEngine {
  CoreExecutionEngine(
    fn(store, module_, instance) raise ComponentRuntimeError {
      // Registration runs embedder code and must hold a lease like invoke:
      // a callback that closes the linker would otherwise tear the engine
      // down mid-instantiation, and the registration would still commit.
      lifecycle.with_lease(fn() raise ComponentRuntimeError {
        self.register_instance(store, module_, instance)
      })
    },
    fn(store, instance, func_idx, args, request) raise ComponentRuntimeError {
      lifecycle.enter()
      let cancellation_cleanup_armed = [true]
      errdefer (if cancellation_cleanup_armed[0] { lifecycle.leave() })
      let invocation_result : Result[
        CoreExecutionOutcome,
        ComponentRuntimeError,
      ] = try self.invoke(store, instance, func_idx, args, request) catch {
        error => Err(error)
      } noraise {
        outcome => Ok(outcome)
      }
      cancellation_cleanup_armed[0] = false
      let outcome = match invocation_result {
        Err(error) => {
          let closing = lifecycle.closing.val
          lifecycle.leave()
          if closing {
            raise Cancelled
          }
          raise error
        }
        Ok(outcome) => outcome
      }
      lifecycle.finish_outcome(outcome)
    },
    prepare_store=fn(store) { self.prepare_store(store) },
    register_rollback=fn(registrar) { self.register_rollback(registrar) },
    close=fn() { self.close() },
  )
}
