///|
/// Structured failure while invoking a prepared JIT module context.
pub(all) suberror JITCoreCallError {
  FunctionUnavailable(Int)
  ArgumentTypeMismatch(Int)
  ResultTypeMismatch(Int)
  Trap(String)
  NativeFiberFailure(String)
  Cancelled
  Exit(Int)
  HostInvocation(@runtime.RuntimeError)
  GcSetupFailed(String)
  ExecutionStateFailure(@wasmoon_jit.NativeExecutionStateError)
} derive(Debug, Eq)

///|
pub impl Show for JITCoreCallError with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
fn encode_jit_entry_args(
  args : Array[@types.Value],
  param_types : Array[@types.ValueType],
  store : @runtime.Store,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> Array[Int64] raise JITCoreCallError {
  if args.length() != param_types.length() {
    raise ArgumentTypeMismatch(args.length())
  }
  let slots : Array[Int64] = []
  for i, ty in param_types {
    match encode_value(ty, args[i], store, jit_module, instance) {
      Some(encoded) =>
        for raw in encoded {
          slots.push(raw)
        }
      None => raise ArgumentTypeMismatch(i)
    }
  }
  slots
}

///|
fn decode_jit_entry_results(
  results : Array[Int64],
  result_types : Array[@types.ValueType],
  store : @runtime.Store,
  jit_module : @jit.JITModule,
  instance : @runtime.ModuleInstance,
) -> Array[@types.Value] raise JITCoreCallError {
  let values : Array[@types.Value] = []
  let mut slot = 0
  for i, ty in result_types {
    let needed = if ty is V128 { 2 } else { 1 }
    if slot + needed > results.length() {
      raise ResultTypeMismatch(i)
    }
    let value : @types.Value = match ty {
      I32 => I32(@types.FromInt64::from_int64_bits(results[slot]))
      I64 => I64(@types.FromInt64::from_int64_bits(results[slot]))
      F32 => F32(@types.FromInt64::from_int64_bits(results[slot]))
      F64 => F64(@types.FromInt64::from_int64_bits(results[slot]))
      V128 =>
        V128(@types.int64_pair_to_v128_le(results[slot], results[slot + 1]))
      _ => decode_ref_value(ty, results[slot], store, jit_module, instance)
    }
    values.push(value)
    slot = slot + needed
  }
  if slot != results.length() {
    raise ResultTypeMismatch(result_types.length())
  }
  values
}

///|
fn prepare_jit_core_environment(
  context : JITModuleContext,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
) -> Bool raise JITCoreCallError {
  sync_store_globals_to_jit(context, store)
  sync_tables_to_jit(
    instance,
    store,
    context.jit_module,
    use_subtype_indirect_check=context.use_subtype_indirect_check,
  )
  match store.c_heap {
    Some(heap) => {
      context.jit_module.setup_gc(
        heap,
        context.module_types,
        context.canonical_type_indices,
        context.func_type_indices,
      ) catch {
        error => raise GcSetupFailed(error.to_string())
      }
      context.jit_module.set_gc_heap(heap.get_ptr())
      true
    }
    None => false
  }
}

///|
fn finish_jit_core_environment(
  context : JITModuleContext,
  store : @runtime.Store,
  gc_active : Bool,
) -> Unit {
  if gc_active {
    context.jit_module.teardown_gc()
  }
  sync_jit_globals_to_store(context, store)
  sync_jit_tables_to_store(context, store)
}

///|
fn JITModuleContext::map_jit_call_error(
  self : JITModuleContext,
  error : @jit.JITTrap,
  invocation_id : Int64,
) -> JITCoreCallError {
  match error {
    JITTrap(message) =>
      match self.async_host_errors.get(invocation_id) {
        Some(host_error) => {
          self.async_host_errors.remove(invocation_id)
          HostInvocation(host_error)
        }
        None => Trap(message)
      }
    JITNativeFiberFailure(message) => NativeFiberFailure(message)
    JITCancelled => Cancelled
    JITExit(code) => Exit(code)
  }
}

///|
fn JITModuleContext::clear_async_host_state(
  self : JITModuleContext,
  invocation_id : Int64,
) -> Unit {
  self.async_host_drivers.remove(invocation_id)
  self.async_host_errors.remove(invocation_id)
}

///|
/// Result of entering or resuming a stackful native core call.
pub(all) enum JITCoreCallOutcome {
  NativeCoreReturned(Array[@types.Value])
  NativeCoreSuspended(JITCoreContinuation)
}

///|
/// Product-owned native core continuation retained by Component Async.
struct JITCoreContinuation {
  context : JITModuleContext
  store : @runtime.Store
  instance : @runtime.ModuleInstance
  result_types : Array[@types.ValueType]
  call : @jit.JITCallContinuation
  invocation : @wasmoon_jit.NativeInvocationHandle
  active : Array[Bool]
}

///|
fn JITCoreContinuation::finish(
  self : JITCoreContinuation,
  outcome : @jit.JITContinuationOutcome,
) -> JITCoreCallOutcome raise JITCoreCallError {
  match outcome {
    JITSuspended(_) => {
      self.invocation.park() catch {
        error => {
          self.context.clear_async_host_state(self.invocation.id())
          self.invocation.release_if_live()
          self.active[0] = false
          raise ExecutionStateFailure(error)
        }
      }
      NativeCoreSuspended(self)
    }
    JITReturned(raw_results) => {
      self.active[0] = false
      self.context.clear_async_host_state(self.invocation.id())
      self.invocation.complete() catch {
        error => {
          self.invocation.release_if_live()
          raise ExecutionStateFailure(error)
        }
      }
      NativeCoreReturned(
        decode_jit_entry_results(
          raw_results,
          self.result_types,
          self.store,
          self.context.jit_module,
          self.instance,
        ),
      )
    }
  }
}

///|
pub fn JITCoreContinuation::continue_execution(
  self : JITCoreContinuation,
) -> JITCoreCallOutcome raise JITCoreCallError {
  if !self.active[0] {
    raise Trap("native core continuation is no longer active")
  }
  self.invocation.reactivate() catch {
    error => raise ExecutionStateFailure(error)
  }
  let gc_active = {
    errdefer {
      self.context.clear_async_host_state(self.invocation.id())
      self.invocation.release_if_live()
      self.active[0] = false
    }
    prepare_jit_core_environment(self.context, self.store, self.instance)
  }
  let outcome = self.call.continue_execution() catch {
    error => {
      finish_jit_core_environment(self.context, self.store, gc_active)
      self.invocation.release_if_live()
      self.active[0] = false
      let mapped = self.context.map_jit_call_error(error, self.invocation.id())
      self.context.clear_async_host_state(self.invocation.id())
      raise mapped
    }
  }
  finish_jit_core_environment(self.context, self.store, gc_active)
  self.finish(outcome)
}

///|
pub fn JITCoreContinuation::cancel(self : JITCoreContinuation) -> Unit {
  if !self.active[0] {
    return
  }
  self.call.cancel() catch {
    _ => ()
  }
  self.context.clear_async_host_state(self.invocation.id())
  self.invocation.release_if_live()
  self.active[0] = false
}

///|
/// Enter one function on a native fiber and retain its machine stack if an
/// imported canonical hostcall suspends.
fn JITModuleContext::start_core_func_resumable(
  self : JITModuleContext,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int,
  args : Array[@types.Value],
  async_host_driver? : @runtime.AsyncHostCallDriver? = None,
) -> JITCoreCallOutcome raise JITCoreCallError {
  guard self.jit_module.get_func(func_idx) is Some(func) else {
    raise FunctionUnavailable(func_idx)
  }
  let encoded_args = encode_jit_entry_args(
    args,
    func.param_types,
    store,
    self.jit_module,
    instance,
  )
  let invocation = store.native_execution_state().begin() catch {
      error => raise ExecutionStateFailure(error)
    }
  let invocation_id = invocation.id()
  if async_host_driver is Some(driver) {
    self.async_host_drivers.set(invocation_id, driver)
  }
  let gc_active = {
    errdefer {
      self.clear_async_host_state(invocation_id)
      invocation.release_if_live()
    }
    prepare_jit_core_environment(self, store, instance)
  }
  let outcome = self.jit_module.start_continuation_call(func, encoded_args) catch {
    error => {
      finish_jit_core_environment(self, store, gc_active)
      invocation.release_if_live()
      let mapped = self.map_jit_call_error(error, invocation_id)
      self.clear_async_host_state(invocation_id)
      raise mapped
    }
  }
  finish_jit_core_environment(self, store, gc_active)
  match outcome {
    JITSuspended(call) => {
      let continuation : JITCoreContinuation = {
        context: self,
        store,
        instance,
        result_types: func.result_types,
        call,
        invocation,
        active: [true],
      }
      continuation.finish(outcome)
    }
    JITReturned(raw_results) => {
      self.clear_async_host_state(invocation_id)
      invocation.complete() catch {
        error => {
          invocation.release_if_live()
          raise ExecutionStateFailure(error)
        }
      }
      NativeCoreReturned(
        decode_jit_entry_results(
          raw_results,
          func.result_types,
          store,
          self.jit_module,
          instance,
        ),
      )
    }
  }
}

///|
pub fn JITModuleContext::call_core_func_resumable(
  self : JITModuleContext,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int,
  args : Array[@types.Value],
) -> JITCoreCallOutcome raise JITCoreCallError {
  self.start_core_func_resumable(store, instance, func_idx, args)
}

///|
/// Invoke one function through a prepared JIT module context.
///
/// This is the shared entry-call seam used by WAST and component adapters. It
/// keeps globals and tables coherent with interpreter-visible store state and
/// scopes the C-heap registration to the native invocation.
pub fn JITModuleContext::call_core_func(
  self : JITModuleContext,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int,
  args : Array[@types.Value],
) -> Array[@types.Value] raise JITCoreCallError {
  guard self.jit_module.get_func(func_idx) is Some(func) else {
    raise FunctionUnavailable(func_idx)
  }
  let encoded_args = encode_jit_entry_args(
    args,
    func.param_types,
    store,
    self.jit_module,
    instance,
  )
  let gc_active = prepare_jit_core_environment(self, store, instance)
  defer finish_jit_core_environment(self, store, gc_active)
  let invocation = store.native_execution_state().begin() catch {
      error => raise ExecutionStateFailure(error)
    }
  let invocation_id = invocation.id()
  defer self.clear_async_host_state(invocation_id)
  defer invocation.release_if_live()
  let raw_results = self.jit_module.call_with_context(func, encoded_args) catch {
    error => raise self.map_jit_call_error(error, invocation_id)
  }
  invocation.complete() catch {
    error => raise ExecutionStateFailure(error)
  }
  decode_jit_entry_results(
    raw_results,
    func.result_types,
    store,
    self.jit_module,
    instance,
  )
}

///|
fn normalize_async_jit_call_error(error : Error) -> JITCoreCallError {
  match error {
    FunctionUnavailable(_) as call_error => call_error
    ArgumentTypeMismatch(_) as call_error => call_error
    ResultTypeMismatch(_) as call_error => call_error
    Trap(_) as call_error => call_error
    NativeFiberFailure(_) as call_error => call_error
    Cancelled => Cancelled
    Exit(_) as call_error => call_error
    HostInvocation(_) as call_error => call_error
    GcSetupFailed(_) as call_error => call_error
    ExecutionStateFailure(_) as call_error => call_error
    @runtime.AsyncHostCallCancelled => Cancelled
    _ if @async.is_cancellation_error(error) => Cancelled
    _ => HostInvocation(@runtime.normalize_async_host_error(error))
  }
}

///|
/// Call JIT-compiled Wasm while allowing asynchronous host imports to park its
/// native fiber until their futures are ready.
pub async fn JITModuleContext::call_core_func_async(
  self : JITModuleContext,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int,
  args : Array[@types.Value],
) -> Array[@types.Value] raise JITCoreCallError {
  @runtime.with_async_host_call_driver(async fn(driver) raise Error {
    let mut outcome = self.start_core_func_resumable(
      store,
      instance,
      func_idx,
      args,
      async_host_driver=Some(driver),
    )
    for ;; {
      match outcome {
        NativeCoreReturned(values) => return values
        NativeCoreSuspended(continuation) => {
          errdefer continuation.cancel()
          driver.wait_pending()
          outcome = continuation.continue_execution()
        }
      }
    }
  }) catch {
    error => raise normalize_async_jit_call_error(error)
  }
}
