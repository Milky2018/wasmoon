///|
/// Whether a core call is allowed to suspend.
///
/// A native JIT adapter must reject or route `Suspendable` calls to a resumable
/// engine before entering native code. Native stacks are not continuations.
pub(all) enum CoreExecutionMode {
  Synchronous
  Interpreted
  Suspendable
} derive(Debug, Eq)

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
/// or JIT adapter according to `mode`.
struct CoreExecutionEngine {
  prepare_store_fn : (@runtime.Store) -> Unit
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
    CoreExecutionMode,
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
    CoreExecutionMode,
  ) -> CoreExecutionOutcome raise ComponentRuntimeError,
  prepare_store? : (@runtime.Store) -> Unit = fn(_store) { () },
) -> CoreExecutionEngine {
  {
    prepare_store_fn: prepare_store,
    register_instance_fn: register_instance,
    invoke_fn: invoke,
  }
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
  mode : CoreExecutionMode,
) -> CoreExecutionOutcome raise ComponentRuntimeError {
  (self.invoke_fn)(store, instance, func_idx, args, mode)
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
    mode,
  ) raise ComponentRuntimeError {
    match mode {
      Synchronous => {
        let results = @executor.call_func_by_index(
          store, instance, func_idx, args,
        ) catch {
          error => raise CanonCallError(error.to_string())
        }
        Returned(results)
      }
      Interpreted => {
        let results = @executor.call_func_by_index(
          store, instance, func_idx, args,
        ) catch {
          error => raise CanonCallError(error.to_string())
        }
        Returned(results)
      }
      Suspendable => {
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
