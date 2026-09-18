///|
/// Result of entering or resuming a suspendable interpreter invocation.
pub(all) enum SuspensionReason {
  HostCall(Int64)
  CooperativeYield
  AtomicWait
  GuestEffect(@runtime.GuestContinuationEffect)
} derive(Debug)

///|
pub extend SuspensionReason with @debug.Debug::{to_repr}

///|
pub(all) enum ResumableCallOutcome {
  Returned(Array[@types.Value])
  Suspended(SuspensionReason, ExecutionContinuation)
} derive(Debug)

///|
/// Suspendable interpreter result for a JIT/import bridge that must preserve
/// both Wasm exceptions and host-error provenance.
pub(all) enum ResumableCallWithExceptionOutcome {
  ResumableReturned(Array[@types.Value])
  ResumableSuspended(ExecutionContinuation)
  ResumableThrown(Int, Array[@types.Value])
  ResumableHostFailed(@runtime.RuntimeError)
}

///|
/// Explicit continuation for one interpreter invocation.
///
/// The captured execution context owns the operand stack, Wasm frames, locals,
/// labels, current module instance, and explicit instruction/control positions.
/// Only the suspended host/effect operation is retained as a resume action.
/// The Store cancels parked execution on close. A consumed or cancelled handle
/// releases its captured state and reports ContinuationAlreadyConsumed on reuse.
struct ExecutionContinuation {
  mut captured : CapturedExecution?
}

///|
priv struct CapturedExecution {
  context : ExecContext
  return_arity : Int
  root_lease : @runtime.GcRootLease
  registration : Int64
}

///|
pub impl Debug for ExecutionContinuation with fn to_repr(_self) {
  Repr::literal("<execution-continuation>")
}

///|
fn ExecContext::set_base_resume_action(
  self : ExecContext,
  reason : SuspensionReason,
  action : (ExecContext) -> Unit raise,
  cancel? : () -> Unit = fn() { () },
) -> Unit {
  self.suspension_reason = Some(reason)
  self.resume_action = Some({ run: action, cancel, })
}

///|
fn ExecContext::suspend_host_call(
  self : ExecContext,
  error : @runtime.RuntimeError,
  retry : (ExecContext) -> Unit raise,
  roots? : Array[@types.Value] = [],
) -> Unit raise {
  match self.suspension_classifier {
    Some(classifier) =>
      match (classifier.classify)(error) {
        Some(token) => {
          self.suspension_roots = roots.copy()
          self.set_base_resume_action(HostCall(token), retry)
          raise ExecutionSuspended
        }
        None => raise InvocationSignal::HostInvocation(error)
      }
    None => raise InvocationSignal::HostInvocation(error)
  }
}

///|
fn ExecContext::collect_call_results(
  self : ExecContext,
  return_arity : Int,
) -> Array[@types.Value] raise @runtime.RuntimeError {
  let results : Array[@types.Value] = []
  for _ in 0..<return_arity {
    results.push(self.stack.pop())
  }
  results.rev_in_place()
  results
}

///|
fn suspended_outcome(
  context : ExecContext,
  return_arity : Int,
) -> ResumableCallOutcome raise @runtime.RuntimeError {
  errdefer context.discard_captured_execution()
  guard context.suspension_reason is Some(reason) else {
    abort("missing interpreter suspension token")
  }
  context.suspension_reason = None
  let roots = context.collect_gc_additional_roots()
  for value in context.suspension_roots {
    roots.push(value)
  }
  context.suspension_roots.clear()
  let root_lease = context.store.pin_gc_roots(roots)
  errdefer root_lease.release()
  let continuation : ExecutionContinuation = { captured: None, }
  let registration = context.store.register_suspended_execution(fn() {
    continuation.cancel()
  })
  continuation.captured = Some({
    context,
    return_arity,
    root_lease,
    registration,
  })
  Suspended(reason, continuation)
}

///|
/// Resume this continuation without choosing an embedding error policy.
fn ExecutionContinuation::continue_unchecked(
  self : ExecutionContinuation,
) -> ResumableCallOutcome raise {
  guard self.captured is Some(captured) else {
    raise @runtime.ContinuationAlreadyConsumed
  }
  self.captured = None
  let context = captured.context
  context.store.release_suspended_execution(captured.registration)
  captured.root_lease.release()
  errdefer context.discard_captured_execution()
  guard context.resume_action is Some(action) else {
    raise @runtime.ContinuationAlreadyConsumed
  }
  context.resume_action = None
  context.resume_execution(action) catch {
    ExecutionSuspended =>
      return suspended_outcome(context, captured.return_arity)
    error => raise error
  }
  let results = context.collect_call_results(captured.return_arity)
  context.discard_captured_execution()
  Returned(results)
}

///|
/// Resume this continuation exactly once.
pub fn ExecutionContinuation::continue_execution(
  self : ExecutionContinuation,
) -> ResumableCallOutcome raise @runtime.RuntimeError {
  self.continue_unchecked() catch {
    error => raise normalize_runtime_error(error)
  }
}

///|
/// Resume a continuation owned by an imported-Wasm bridge while preserving an
/// uncaught Wasm exception or asynchronous host failure for the native caller.
pub fn ExecutionContinuation::continue_execution_with_exception(
  self : ExecutionContinuation,
) -> ResumableCallWithExceptionOutcome raise @runtime.RuntimeError {
  let outcome = self.continue_unchecked() catch {
    ThrowException(tag_addr, values) => return ResumableThrown(tag_addr, values)
    InvocationSignal::HostInvocation(error) =>
      return ResumableHostFailed(normalize_runtime_error(error))
    error => raise normalize_runtime_error(error)
  }
  match outcome {
    Returned(values) => ResumableReturned(values)
    Suspended(GuestEffect(_), continuation) => {
      continuation.cancel()
      raise UnhandledSuspension
    }
    Suspended(_, continuation) => ResumableSuspended(continuation)
  }
}

///|
/// Drop the captured interpreter state without resuming it.
pub fn ExecutionContinuation::cancel(self : ExecutionContinuation) -> Unit {
  if self.captured is Some(captured) {
    self.captured = None
    captured.context.store.release_suspended_execution(captured.registration)
    captured.root_lease.release()
    captured.context.discard_captured_execution()
  }
}

///|
/// Enter a function using the explicit continuation interpreter seam.
pub fn call_func_by_index_resumable(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int,
  args : Array[@types.Value],
  classify_suspension : (@runtime.RuntimeError) -> Int64?,
  cooperative? : Bool = false,
) -> ResumableCallOutcome raise @runtime.RuntimeError {
  let context = ExecContext(store, instance, classify_suspension~, cooperative~)
  let store_addr = instance.func_addrs[func_idx]
  let func_inst = store.get_func_inst(store_addr)
  let type_idx = instance.func_type_indices[func_idx]
  let func_type = instance.validated_func_type_at(type_idx)
  let return_arity = func_type.results.length()
  context.call_func_inst_with_context(store_addr, func_inst, args, return_arity) catch {
    ExecutionSuspended => return suspended_outcome(context, return_arity)
    error => {
      context.discard_captured_execution()
      raise normalize_runtime_error(error)
    }
  }
  let values = context.collect_call_results(return_arity)
  context.discard_captured_execution()
  Returned(values)
}

///|
fn start_async_host_call_unchecked(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int,
  args : Array[@types.Value],
  driver : @runtime.AsyncHostCallDriver,
) -> ResumableCallOutcome raise {
  let context = ExecContext(store, instance, async_host_driver=Some(driver))
  let store_addr = instance.func_addrs[func_idx]
  let func_inst = store.get_func_inst(store_addr)
  let type_idx = instance.func_type_indices[func_idx]
  let func_type = instance.validated_func_type_at(type_idx)
  let return_arity = func_type.results.length()
  context.call_func_inst_with_context(store_addr, func_inst, args, return_arity) catch {
    ExecutionSuspended => return suspended_outcome(context, return_arity)
    error => {
      context.discard_captured_execution()
      raise error
    }
  }
  let values = context.collect_call_results(return_arity)
  context.discard_captured_execution()
  Returned(values)
}

///|
fn start_async_host_call(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int,
  args : Array[@types.Value],
  driver : @runtime.AsyncHostCallDriver,
) -> ResumableCallOutcome raise @runtime.RuntimeError {
  start_async_host_call_unchecked(store, instance, func_idx, args, driver) catch {
    error => raise normalize_runtime_error(error)
  }
}

///|
/// Enter an interpreted imported-Wasm function using the native caller's async
/// driver, preserving suspension, Wasm exceptions, and host failures.
pub fn call_func_by_index_resumable_async_with_exception(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int,
  args : Array[@types.Value],
  driver : @runtime.AsyncHostCallDriver,
) -> ResumableCallWithExceptionOutcome raise @runtime.RuntimeError {
  let outcome = start_async_host_call_unchecked(
    store, instance, func_idx, args, driver,
  ) catch {
    ThrowException(tag_addr, values) => return ResumableThrown(tag_addr, values)
    InvocationSignal::HostInvocation(error) =>
      return ResumableHostFailed(normalize_runtime_error(error))
    error => raise normalize_runtime_error(error)
  }
  match outcome {
    Returned(values) => ResumableReturned(values)
    Suspended(GuestEffect(_), continuation) => {
      continuation.cancel()
      raise UnhandledSuspension
    }
    Suspended(_, continuation) => ResumableSuspended(continuation)
  }
}

///|
/// Call a function while allowing asynchronous host imports to suspend Wasm.
///
/// The host future is awaited only after the interpreter continuation has been
/// captured, so waiting never blocks the host thread or consumes a Wasm stack.
pub async fn call_func_by_index_async(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int,
  args : Array[@types.Value],
) -> Array[@types.Value] raise @runtime.RuntimeError {
  @runtime.with_async_host_call_driver(async fn(driver) raise Error {
    let mut outcome = start_async_host_call(
      store, instance, func_idx, args, driver,
    )
    for ;; {
      match outcome {
        Returned(values) => return values
        Suspended(GuestEffect(_), continuation) => {
          continuation.cancel()
          raise @runtime.UnhandledSuspension
        }
        Suspended(_, continuation) => {
          errdefer continuation.cancel()
          driver.wait_pending()
          outcome = continuation.continue_execution()
        }
      }
    }
  }) catch {
    error => raise @runtime.normalize_async_host_error(error)
  }
}

///|
/// Call an exported function while allowing asynchronous host imports to
/// suspend Wasm.
pub async fn call_exported_func_async(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  name : String,
  args : Array[@types.Value],
) -> Array[@types.Value] raise @runtime.RuntimeError {
  match find_export_by_name(instance.exports, name) {
    Some({ desc: Func(func_idx), .. }) =>
      call_func_by_index_async(store, instance, func_idx, args)
    Some(_) | None => raise UndefinedElement
  }
}
