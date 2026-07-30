///|
priv enum ComponentCoreRoute {
  NativeCore
  InterpreterCore
} derive(Eq)

///|
priv enum ComponentCoreExecutionEvent {
  NativeRunToReturn
  NativeResumable
  ExplicitInterpreter
}

///|
priv struct ComponentJITExecutionEvidence {
  native_run_to_return : Ref[Int]
  native_resumable : Ref[Int]
  explicit_interpreter : Ref[Int]
}

///|
fn ComponentJITExecutionEvidence::new() -> ComponentJITExecutionEvidence {
  {
    native_run_to_return: Ref(0),
    native_resumable: Ref(0),
    explicit_interpreter: Ref(0),
  }
}

///|
fn ComponentJITExecutionEvidence::record(
  self : ComponentJITExecutionEvidence,
  event : ComponentCoreExecutionEvent,
) -> Unit {
  match event {
    NativeRunToReturn =>
      self.native_run_to_return.val = self.native_run_to_return.val + 1
    NativeResumable => self.native_resumable.val = self.native_resumable.val + 1
    ExplicitInterpreter =>
      self.explicit_interpreter.val = self.explicit_interpreter.val + 1
  }
}

///|
fn component_core_route(
  request : @runtime_impl.CoreExecutionRequest,
) -> ComponentCoreRoute {
  if request.backend == InterpreterOnly {
    return InterpreterCore
  }
  match request.style {
    RunToCompletion | CallbackStep | Stackful => NativeCore
  }
}

///|
priv struct ComponentJITContext {
  core : @wast.JITModuleContext
  pending_suspension : Array[@runtime_impl.CoreSuspension?]
  suspension_enabled : Array[Bool]
}

///|
fn component_jit_error(
  error : @wast.JITCoreCallError,
) -> @runtime_impl.ComponentRuntimeError {
  match error {
    Exit(code) => HostExit(code)
    Trap(message) =>
      if message.contains("unreachable") {
        CanonCallError("wasm trap: wasm `unreachable` instruction executed")
      } else {
        CanonCallError("wasm trap: \{message}")
      }
    error => CanonCallError("component JIT invocation failed: \{error}")
  }
}

///|
fn component_native_outcome(
  context : ComponentJITContext,
  outcome : @wast.JITCoreCallOutcome,
) -> @runtime_impl.CoreExecutionOutcome raise @runtime_impl.ComponentRuntimeError {
  match outcome {
    NativeCoreReturned(results) => {
      context.pending_suspension[0] = None
      Returned(results)
    }
    NativeCoreSuspended(native_continuation) => {
      guard context.pending_suspension[0] is Some(reason) else {
        native_continuation.cancel()
        raise CanonCallError(
          "native core execution suspended without a canonical reason",
        )
      }
      context.pending_suspension[0] = None
      Suspended(
        reason,
        CoreContinuation(
          fn() raise @runtime_impl.ComponentRuntimeError {
            context.pending_suspension[0] = None
            context.suspension_enabled[0] = true
            defer {
              context.suspension_enabled[0] = false
            }
            let resumed = native_continuation.continue_execution() catch {
              error => raise component_jit_error(error)
            }
            component_native_outcome(context, resumed)
          },
          fn() { native_continuation.cancel() },
        ),
      )
    }
  }
}

///|
/// Build the Wasmoon-owned native adapter for component core execution.
///
/// Stackful calls retain their native machine stack across canonical hostcall
/// suspension. Callback steps return normally after each scheduler decision.
fn component_jit_execution_engine(
  evidence? : ComponentJITExecutionEvidence = ComponentJITExecutionEvidence::new(),
) -> @runtime_impl.CoreExecutionEngine {
  let contexts : Map[Int, ComponentJITContext] = Map([])
  let interpreter = @runtime_impl.interpreter_core_execution_engine()
  CoreExecutionEngine(
    fn(store, module_, instance) raise @runtime_impl.ComponentRuntimeError {
      let pending_suspension : Array[@runtime_impl.CoreSuspension?] = [None]
      let suspension_enabled = [false]
      match
        try_compile_jit_with_suspension(module_, instance, store, fn(_error) {
          if !suspension_enabled[0] {
            return false
          }
          match @runtime_impl.take_core_suspension() {
            Some(reason) => {
              pending_suspension[0] = Some(reason)
              true
            }
            None => false
          }
        }) {
        Ok(core) =>
          contexts.set(instance.store_idx, {
            core,
            pending_suspension,
            suspension_enabled,
          })
        Err(message) =>
          raise CanonCallError("component JIT compilation failed: \{message}")
      }
    },
    fn(
      store,
      instance,
      func_idx,
      args,
      request,
    ) raise @runtime_impl.ComponentRuntimeError {
      if component_core_route(request) == InterpreterCore {
        let outcome = interpreter.invoke(
          store, instance, func_idx, args, request,
        )
        evidence.record(ExplicitInterpreter)
        return outcome
      }
      guard contexts.get(instance.store_idx) is Some(context) else {
        raise CanonCallError(
          "component JIT context is missing for core instance \{instance.store_idx}",
        )
      }
      if request.suspension is Resumable {
        context.pending_suspension[0] = None
        context.suspension_enabled[0] = true
        defer {
          context.suspension_enabled[0] = false
        }
        let outcome = context.core.call_core_func_resumable(
          store, instance, func_idx, args,
        ) catch {
          error => raise component_jit_error(error)
        }
        evidence.record(NativeResumable)
        return component_native_outcome(context, outcome)
      }
      let outcome = context.core.call_core_func_resumable(
        store, instance, func_idx, args,
      ) catch {
        error => raise component_jit_error(error)
      }
      evidence.record(NativeRunToReturn)
      match outcome {
        NativeCoreReturned(results) => Returned(results)
        NativeCoreSuspended(continuation) => {
          continuation.cancel()
          raise CanonCallError(
            "native run-to-return core execution unexpectedly suspended",
          )
        }
      }
    },
    prepare_store=fn(store) { try! store.enable_c_heap() },
    close=fn() {
      for entry in contexts {
        entry.1.core.close()
      }
      contexts.clear()
    },
  )
}
