///|
/// Semantic shape of one core function call.
///
/// `CallbackStep` returns a callback code before the component scheduler
/// decides whether to invoke it again. `Stackful` may suspend without returning
/// from the core function and therefore requires a resumable execution stack.
pub(all) enum CoreCallStyle {
  RunToCompletion
  CallbackStep
  Stackful
} derive(Debug, Eq)

///|
/// Whether an execution adapter may select its native backend for this call.
///
/// This is deliberately separate from `CoreCallStyle`: execution semantics do
/// not change merely because an instance cannot use the native backend.
pub(all) enum CoreBackendPolicy {
  PreferNative
  InterpreterOnly
} derive(Debug, Eq)

///|
/// Whether this particular core entry must preserve its activation when a
/// canonical host intrinsic suspends.
///
/// This is independent of `CoreCallStyle`: a callback step normally returns a
/// callback code, but may still call a sync-lowered async import before it
/// returns.
pub(all) enum CoreSuspensionPolicy {
  RunToReturn
  Resumable
} derive(Debug, Eq)

///|
/// Typed contract passed from component execution to a core backend adapter.
pub struct CoreExecutionRequest {
  style : CoreCallStyle
  backend : CoreBackendPolicy
  suspension : CoreSuspensionPolicy
} derive(Debug, Eq)

///|
pub fn CoreExecutionRequest::CoreExecutionRequest(
  style : CoreCallStyle,
  backend : CoreBackendPolicy,
  suspension : CoreSuspensionPolicy,
) -> CoreExecutionRequest {
  { style, backend, suspension }
}

///|
/// Why a core execution continuation stopped.
pub(all) enum CoreSuspension {
  Yield
  Wait(Int64)
} derive(Debug, Eq)

///|
/// A suspended core computation.
///
/// The continuation owns the execution state needed to resume after the
/// suspension point. It is linear: continue it until the next suspension or
/// terminal return, or cancel it. `cancel` releases that state without
/// resuming it.
struct CoreContinuation {
  resume_fn : () -> CoreExecutionOutcome raise ComponentRuntimeError
  cancel_fn : () -> Unit
}

///|
pub fn CoreContinuation::CoreContinuation(
  continue_with : () -> CoreExecutionOutcome raise ComponentRuntimeError,
  cancel : () -> Unit,
) -> CoreContinuation {
  { resume_fn: continue_with, cancel_fn: cancel }
}

///|
pub fn CoreContinuation::continue_execution(
  self : CoreContinuation,
) -> CoreExecutionOutcome raise ComponentRuntimeError {
  (self.resume_fn)()
}

///|
pub fn CoreContinuation::cancel(self : CoreContinuation) -> Unit {
  (self.cancel_fn)()
}

///|
pub impl Debug for CoreContinuation with fn to_repr(_self) {
  Repr::literal("<core-continuation>")
}

///|
/// Result of entering or resuming a core function.
pub(all) enum CoreExecutionOutcome {
  Returned(Array[@types.Value])
  Suspended(CoreSuspension, CoreContinuation)
} derive(Debug)

///|
/// Component-owned seam for core Wasm execution.
///
/// `register_instance` is called once after interpreter instantiation has
/// allocated the shared store objects. `invoke` may then select an interpreter
/// or JIT adapter according to the typed execution request. Implementations
/// are thread-confined to the Store supplied by the component linker.
struct CoreExecutionEngine {
  prepare_store_fn : (@runtime.Store) -> Unit
  close_fn : () -> Unit
  register_rollback_fn : (@runtime.InstantiationTransaction) -> Unit
  register_instance_fn : (
    @runtime.Store,
    @types.Module,
    @runtime.ModuleInstance,
  ) -> Unit raise ComponentRuntimeError
  invoke_fn : (
    @runtime.Store,
    @runtime.ModuleInstance,
    Int,
    Array[@types.Value],
    CoreExecutionRequest,
  ) -> CoreExecutionOutcome raise ComponentRuntimeError
}

///|
/// An engine that accepts no further work.
///
/// Reported by a linker whose engine has already been released at terminal
/// close, so a late caller gets the same structured `Cancelled` it would get
/// from a closing lifecycle rather than reaching a closed engine.
fn closed_core_execution_engine() -> CoreExecutionEngine {
  CoreExecutionEngine(
    fn(_store, _module, _instance) raise ComponentRuntimeError {
      raise Cancelled
    },
    fn(
      _store,
      _instance,
      _func_idx,
      _args,
      _request,
    ) raise ComponentRuntimeError {
      raise Cancelled
    },
    prepare_store=fn(_store) { () },
    close=fn() { () },
  )
}

///|
priv struct CoreExecutionLifecycle {
  active_leases : Ref[Int]
  closing : Ref[Bool]
  close_when_idle : Ref[(() -> Unit)?]
}

///|
fn CoreExecutionLifecycle::new() -> CoreExecutionLifecycle {
  { active_leases: Ref(0), closing: Ref(false), close_when_idle: Ref(None) }
}

///|
fn CoreExecutionLifecycle::ensure_open(
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
fn CoreExecutionLifecycle::begin_close(self : CoreExecutionLifecycle) -> Unit {
  self.closing.val = true
}

///|
fn CoreExecutionLifecycle::request_close(
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
fn[T] CoreExecutionLifecycle::with_lease(
  self : CoreExecutionLifecycle,
  operation : () -> T raise ComponentRuntimeError,
  rollback? : () -> Unit = fn() {  },
) -> T raise ComponentRuntimeError {
  self.enter()
  let result = operation() catch {
    error => {
      rollback()
      let closing = self.closing.val
      self.leave()
      if closing {
        raise Cancelled
      }
      raise error
    }
  }
  if self.closing.val {
    rollback()
    self.leave()
    raise Cancelled
  }
  self.leave()
  result
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
      let outcome = self.continue_execution() catch {
        error => {
          let closing = lifecycle.closing.val
          lifecycle.leave()
          if closing {
            raise Cancelled
          }
          raise error
        }
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
pub fn CoreExecutionEngine::CoreExecutionEngine(
  register_instance : (@runtime.Store, @types.Module, @runtime.ModuleInstance) -> Unit raise ComponentRuntimeError,
  invoke : (
    @runtime.Store,
    @runtime.ModuleInstance,
    Int,
    Array[@types.Value],
    CoreExecutionRequest,
  ) -> CoreExecutionOutcome raise ComponentRuntimeError,
  prepare_store? : (@runtime.Store) -> Unit = fn(_store) { () },
  register_rollback? : (@runtime.InstantiationTransaction) -> Unit = fn(
    _transaction,
  ) {
    ()
  },
  close? : () -> Unit = fn() { () },
) -> CoreExecutionEngine {
  {
    prepare_store_fn: prepare_store,
    close_fn: close,
    register_rollback_fn: register_rollback,
    register_instance_fn: register_instance,
    invoke_fn: invoke,
  }
}

///|
fn CoreExecutionEngine::with_lifecycle(
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
      let outcome = self.invoke(store, instance, func_idx, args, request) catch {
        error => {
          let closing = lifecycle.closing.val
          lifecycle.leave()
          if closing {
            raise Cancelled
          }
          raise error
        }
      }
      lifecycle.finish_outcome(outcome)
    },
    prepare_store=fn(store) { self.prepare_store(store) },
    register_rollback=fn(transaction) { self.register_rollback(transaction) },
    close=fn() { self.close() },
  )
}

///|
/// Release execution-engine resources after all calls and continuations end.
///
/// This operation is terminal. The owning linker makes repeated close calls
/// idempotent.
pub fn CoreExecutionEngine::close(self : CoreExecutionEngine) -> Unit {
  (self.close_fn)()
}

///|
pub fn CoreExecutionEngine::prepare_store(
  self : CoreExecutionEngine,
  store : @runtime.Store,
) -> Unit {
  (self.prepare_store_fn)(store)
}

///|
pub fn CoreExecutionEngine::register_rollback(
  self : CoreExecutionEngine,
  transaction : @runtime.InstantiationTransaction,
) -> Unit {
  (self.register_rollback_fn)(transaction)
}

///|
pub fn CoreExecutionEngine::register_instance(
  self : CoreExecutionEngine,
  store : @runtime.Store,
  module_ : @types.Module,
  instance : @runtime.ModuleInstance,
) -> Unit raise ComponentRuntimeError {
  (self.register_instance_fn)(store, module_, instance)
}

///|
pub fn CoreExecutionEngine::invoke(
  self : CoreExecutionEngine,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int,
  args : Array[@types.Value],
  request : CoreExecutionRequest,
) -> CoreExecutionOutcome raise ComponentRuntimeError {
  (self.invoke_fn)(store, instance, func_idx, args, request)
}

///|
pub impl Debug for CoreExecutionEngine with fn to_repr(_self) {
  Repr::literal("<core-execution-engine>")
}

///|
fn core_suspension_from_token(token : Int64) -> CoreSuspension {
  if token == -1L {
    Yield
  } else {
    Wait(token)
  }
}

///|
/// Consume the canonical suspension requested by the current host intrinsic.
///
/// Native execution adapters call this only while advancing a stackful core
/// invocation. Synchronous callers leave the marker for the ordinary canonical
/// trap path.
pub fn take_core_suspension() -> CoreSuspension? {
  match canon_suspend[0] {
    Some(Yield) => {
      canon_suspend[0] = None
      Some(Yield)
    }
    Some(Wait(waitable_set)) => {
      canon_suspend[0] = None
      Some(Wait(waitable_set))
    }
    None => None
  }
}

///|
fn resume_interpreter_continuation(
  continuation : @executor.ExecutionContinuation,
) -> CoreExecutionOutcome raise ComponentRuntimeError {
  let outcome = continuation.continue_execution() catch {
    error => {
      let message = match canon_trap_message[0] {
        Some(message) => message
        None => error.to_string()
      }
      let debug = match canon_debug_message[0] {
        Some(marker) => " [last=\{marker}]"
        None => ""
      }
      raise CanonCallError("\{message}\{debug}")
    }
  }
  interpreter_outcome(outcome)
}

///|
fn interpreter_outcome(
  outcome : @executor.ResumableCallOutcome,
) -> CoreExecutionOutcome {
  match outcome {
    Returned(results) => Returned(results)
    Suspended(token, continuation) => {
      // The typed outcome now owns the suspension reason. Do not let the
      // process-local canonical marker classify a later, unrelated trap.
      canon_suspend[0] = None
      Suspended(
        core_suspension_from_token(token),
        CoreContinuation(
          fn() raise ComponentRuntimeError {
            resume_interpreter_continuation(continuation)
          },
          fn() { continuation.cancel() },
        ),
      )
    }
  }
}

///|
/// Default core execution adapter.
pub fn interpreter_core_execution_engine() -> CoreExecutionEngine {
  CoreExecutionEngine(fn(_store, _module, _instance) { () }, fn(
    store,
    instance,
    func_idx,
    args,
    request,
  ) raise ComponentRuntimeError {
    match request.suspension {
      RunToReturn => {
        let results = @executor.call_func_by_index(
          store, instance, func_idx, args,
        ) catch {
          error => raise CanonCallError(error.to_string())
        }
        Returned(results)
      }
      Resumable => {
        let outcome = @executor.call_func_by_index_resumable(
          store,
          instance,
          func_idx,
          args,
          fn(_error) {
            match canon_suspend[0] {
              Some(Yield) => Some(-1L)
              Some(Wait(waitable_set)) => Some(waitable_set)
              None => None
            }
          },
        ) catch {
          error => raise CanonCallError(error.to_string())
        }
        interpreter_outcome(outcome)
      }
    }
  })
}
