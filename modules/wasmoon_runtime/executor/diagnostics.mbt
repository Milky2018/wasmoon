///|
/// Owned guest frame, innermost first. Positions are zero-based indices through
/// nested instruction sequences, not byte offsets or native return addresses.
pub(all) struct InterpreterFrame {
  module_index : Int32
  function_index : Int32
  function_name : String?
  instruction_path : ReadOnlyArray[Int32]
} derive(Debug, Eq)

///|
pub(all) enum InterpreterFailureKind {
  GuestTrap
  HostFailure
  ExecutionFailure
} derive(Debug, Eq)

///|
/// Contains no Store, guest values, root leases or executable state.
pub(all) struct InterpreterFailure {
  kind : InterpreterFailureKind
  error : @runtime.RuntimeError
  frames : ReadOnlyArray[InterpreterFrame]
} derive(Debug)

///|
pub(all) suberror InterpreterDiagnosticError {
  InterpreterFailed(InterpreterFailure)
} derive(Debug)

///|
fn ExecContext::capture_failure(self : ExecContext, error : Error) -> Error {
  guard self.capture_diagnostics && self.diagnostic_frames is None else {
    return error
  }
  match error {
    BranchWith(_, _) | Return | TailCall(_, _, _, _) | ExecutionSuspended =>
      return error
    _ => ()
  }
  let frames : Array[InterpreterFrame] = []
  let path : Array[Int32] = []
  let mut owner = self.instance
  for i = self.execution.length() - 1; i >= 0; i = i - 1 {
    let frame = self.execution[i]
    path.push(if frame.ip > 0 { frame.ip - 1 } else { 0 })
    if frame.kind is FunctionControl(caller, _, address) {
      let mut index = -1
      for position, candidate in owner.func_addrs {
        if candidate == address {
          index = position
          break
        }
      }
      path.rev_in_place()
      frames.push({
        module_index: owner.store_index(),
        function_index: index,
        function_name: owner.function_name(index),
        instruction_path: ReadOnlyArray::from_array(path),
      })
      path.clear()
      owner = caller
    }
  }
  self.diagnostic_frames = Some(ReadOnlyArray::from_array(frames))
  error
}

///|
fn diagnostic_error(
  error : Error,
  frames : ReadOnlyArray[InterpreterFrame],
) -> InterpreterDiagnosticError {
  let cause = normalize_runtime_error(error)
  let kind = match error {
    InvocationSignal::HostInvocation(_) => HostFailure
    InvocationSignal::Cancelled => ExecutionFailure
    _ if frames.is_empty() => ExecutionFailure
    _ =>
      match cause {
        ExecutionCancelled
        | ExecutionTimedOut
        | ExecutionBudgetExceeded
        | ContinuationAlreadyConsumed
        | StoreClosed => ExecutionFailure
        _ => GuestTrap
      }
  }
  InterpreterFailed({ kind, error: cause, frames, })
}

///|
/// Opt into owned failure frames; the ordinary resumable API avoids capture.
pub fn call_func_by_index_resumable_with_diagnostics(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int32,
  args : Array[@types.Value],
  classify_suspension : (@runtime.RuntimeError) -> Int64?,
  cooperative~ : Bool = false,
  cooperative_quantum~ : Int32 = 1024,
) -> ResumableCallOutcome raise InterpreterDiagnosticError {
  let context = ExecContext(
    store,
    instance,
    classify_suspension~,
    cooperative~,
    cooperative_quantum~,
    capture_diagnostics=true,
  ) catch {
    error => raise diagnostic_error(error, [])
  }
  start_resumable_unchecked(context, func_idx, args) catch {
    error =>
      raise diagnostic_error(error, context.diagnostic_frames.unwrap_or([]))
  }
}

///|
/// Enable capture for this resume, including continuations created by the
/// ordinary API. The consumed continuation is not retained by the diagnostic.
pub fn ExecutionContinuation::continue_execution_with_diagnostics(
  self : ExecutionContinuation,
) -> ResumableCallOutcome raise InterpreterDiagnosticError {
  let context = self.captured.map(captured => captured.context)
  if context is Some(context) {
    context.capture_diagnostics = true
  }
  self.continue_unchecked() catch {
    error => {
      let frames = match context {
        Some(context) => context.diagnostic_frames.unwrap_or([])
        None => []
      }
      raise diagnostic_error(error, frames)
    }
  }
}

///|
/// Instantiate and execute a synchronous start function with owned diagnostics.
/// Preserve existing Core publication and enclosing transaction semantics.
pub fn instantiate_module_with_diagnostics(
  store : @runtime.Store,
  module_ : @types.Module,
  imports : @runtime.Imports,
) -> @runtime.ModuleInstance raise InterpreterDiagnosticError {
  store.with_instantiation(fn() raise {
    imports.check_store(store)
    let admission = store.reserve_instance(module_~)
    errdefer admission.cancel()
    let validated = validate_execution_module(module_)
    let instance = instantiate_validated_module_with_imports_unstarted(
      store,
      validated,
      imports,
      admission~,
    )
    if validated.start() is Some(index) {
      match
        call_func_by_index_resumable_with_diagnostics(
          store,
          instance,
          index,
          [],
          _ => None,
        ) {
        Returned(_) => ()
        Suspended(_, continuation) => {
          continuation.cancel()
          raise diagnostic_error(@runtime.RuntimeError::UnhandledSuspension, [])
        }
      }
    }
    instance
  }) catch {
    InterpreterFailed(_) as error => raise error
    error => raise diagnostic_error(error, [])
  }
}

///|
pub extend InterpreterFrame with Debug::{to_repr}

///|
pub extend InterpreterFrame with Eq::{equal, not_equal}

///|
pub extend InterpreterFailureKind with Debug::{to_repr}

///|
pub extend InterpreterFailureKind with Eq::{equal, not_equal}

///|
pub extend InterpreterFailure with Debug::{to_repr}

///|
pub extend InterpreterDiagnosticError with Debug::{to_repr}
