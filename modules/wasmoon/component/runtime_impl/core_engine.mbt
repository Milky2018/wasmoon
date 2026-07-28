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
/// suspension point. `cancel` releases that state without resuming it.
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
/// or JIT adapter according to the typed execution request.
struct CoreExecutionEngine {
  prepare_store_fn : (@runtime.Store) -> Unit
  close_fn : () -> Unit
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
  close? : () -> Unit = fn() { () },
) -> CoreExecutionEngine {
  {
    prepare_store_fn: prepare_store,
    close_fn: close,
    register_instance_fn: register_instance,
    invoke_fn: invoke,
  }
}

///|
/// Release execution-engine resources after all calls and continuations end.
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
      Some(CoreSuspension::Yield)
    }
    Some(Wait(waitable_set)) => {
      canon_suspend[0] = None
      Some(CoreSuspension::Wait(waitable_set))
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
