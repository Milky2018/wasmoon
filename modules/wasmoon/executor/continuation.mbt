///|
/// Result of entering or resuming a suspendable interpreter invocation.
pub(all) enum ResumableCallOutcome {
  Returned(Array[@types.Value])
  Suspended(Int64, ExecutionContinuation)
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
/// labels, current module instance, and a composed closure for the remaining
/// structured control flow.
struct ExecutionContinuation {
  context : ExecContext
  return_arity : Int
  active : Array[Bool]
  root_lease : @runtime.GcRootLease
}

///|
pub impl Debug for ExecutionContinuation with fn to_repr(_self) {
  Repr::literal("<execution-continuation>")
}

///|
fn ExecContext::set_base_resume_action(
  self : ExecContext,
  token : Int64,
  action : () -> Unit raise,
) -> Unit {
  self.suspension_token = Some(token)
  self.resume_action = Some({ run: action, })
}

///|
/// Compose work that must run after the currently captured continuation
/// completes normally. If the inner continuation suspends again, the same
/// suffix is reattached to the newly captured base action.
fn ExecContext::append_resume_suffix(
  self : ExecContext,
  suffix : () -> Unit raise,
) -> Unit {
  guard self.resume_action is Some(previous) else {
    abort("missing interpreter resume action")
  }
  self.resume_action = Some({
    run: fn() raise {
      (previous.run)() catch {
        ExecutionSuspended => {
          self.append_resume_suffix(suffix)
          raise ExecutionSuspended
        }
        error => raise error
      }
      suffix()
    },
  })
}

///|
/// Compose a structured-control handler around the captured continuation.
/// Unlike a plain suffix, the handler observes branch/return/exception signals
/// produced after resumption.
fn ExecContext::append_resume_handler(
  self : ExecContext,
  handler : (ExecBlockResult) -> Unit raise,
) -> Unit {
  guard self.resume_action is Some(previous) else {
    abort("missing interpreter resume action")
  }
  self.resume_action = Some({
    run: fn() raise {
      let result = try (previous.run)() catch {
        ExecutionSuspended => {
          self.append_resume_handler(handler)
          raise ExecutionSuspended
        }
        error => ExecBlockRaised(error)
      } noraise {
        _ => ExecBlockCompleted
      }
      handler(result)
    },
  })
}

///|
fn ExecContext::suspend_host_call(
  self : ExecContext,
  error : @runtime.RuntimeError,
  retry : () -> Unit raise,
  roots? : Array[@types.Value] = [],
) -> Unit raise {
  match self.suspension_classifier {
    Some(classifier) =>
      match (classifier.classify)(error) {
        Some(token) => {
          self.suspension_roots = roots.copy()
          self.set_base_resume_action(token, retry)
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
  active : Array[Bool],
) -> ResumableCallOutcome {
  guard context.suspension_token is Some(token) else {
    abort("missing interpreter suspension token")
  }
  context.suspension_token = None
  let roots = context.collect_gc_additional_roots()
  for value in context.suspension_roots {
    roots.push(value)
  }
  context.suspension_roots.clear()
  let root_lease = context.store.pin_gc_roots(roots)
  Suspended(token, { context, return_arity, active, root_lease, })
}

///|
/// Resume this continuation without choosing an embedding error policy.
fn ExecutionContinuation::continue_unchecked(
  self : ExecutionContinuation,
) -> ResumableCallOutcome raise {
  if !self.active[0] {
    raise @runtime.Unreachable
  }
  guard self.context.resume_action is Some(action) else {
    self.active[0] = false
    self.root_lease.release()
    raise @runtime.Unreachable
  }
  self.root_lease.release()
  self.context.resume_action = None
  (action.run)() catch {
    ExecutionSuspended =>
      return suspended_outcome(self.context, self.return_arity, self.active)
    error => {
      self.active[0] = false
      raise error
    }
  }
  self.active[0] = false
  Returned(self.context.collect_call_results(self.return_arity))
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
    Suspended(_, continuation) => ResumableSuspended(continuation)
  }
}

///|
/// Drop the captured interpreter state without resuming it.
pub fn ExecutionContinuation::cancel(self : ExecutionContinuation) -> Unit {
  if self.active[0] {
    self.active[0] = false
    self.root_lease.release()
    self.context.resume_action = None
    self.context.frames.clear()
    self.context.labels.clear()
    self.context.stack.clear()
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
) -> ResumableCallOutcome raise @runtime.RuntimeError {
  let context = ExecContext(store, instance, classify_suspension~)
  let store_addr = instance.func_addrs[func_idx]
  let func_inst = store.get_func_inst(store_addr)
  let type_idx = instance.func_type_indices[func_idx]
  let func_type = instance.validated_func_type_at(type_idx)
  let return_arity = func_type.results.length()
  context.call_func_inst_with_context(store_addr, func_inst, args, return_arity) catch {
    ExecutionSuspended =>
      return suspended_outcome(context, return_arity, [true])
    error => raise normalize_runtime_error(error)
  }
  Returned(context.collect_call_results(return_arity))
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
    ExecutionSuspended =>
      return suspended_outcome(context, return_arity, [true])
    error => raise error
  }
  Returned(context.collect_call_results(return_arity))
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
