///|
pub(all) enum NativeComponentExecutionEvent {
  RunToReturn
  Resumable
  ExplicitInterpreter
} derive(Debug, Eq)

///|
priv enum ComponentCoreRoute {
  Native
  Interpreter
}

///|
fn component_core_route(
  request : @runtime_impl.CoreExecutionRequest,
) -> ComponentCoreRoute {
  if request.backend is InterpreterOnly {
    Interpreter
  } else {
    Native
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
    Cancelled => Cancelled
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
fn native_component_session(
  opt_level : Int,
  on_execution : (NativeComponentExecutionEvent) -> Unit,
) -> @runtime_impl.CoreExecutionEngine {
  let contexts : Map[Int, ComponentJITContext] = Map([])
  let interpreter = @runtime_impl.interpreter_core_execution_engine()
  let target = try @wasmoon_jit.host_native_target() catch {
    _ => None
  } noraise {
    value => Some(value)
  }
  CoreExecutionEngine(
    fn(store, module_, instance) raise @runtime_impl.ComponentRuntimeError {
      guard target is Some(target) else {
        raise NativeEngineUnavailable(
          "the host architecture has no Wasmoon native component target",
        )
      }
      let pending_suspension : Array[@runtime_impl.CoreSuspension?] = [None]
      let suspension_enabled = [false]
      let core = load_component_jit_context(
        module_,
        instance,
        store,
        target,
        opt_level,
        fn(_error) {
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
        },
      )
      contexts[instance.store_idx] = {
        core,
        pending_suspension,
        suspension_enabled,
      }
    },
    fn(
      store,
      instance,
      function_index,
      arguments,
      request,
    ) raise @runtime_impl.ComponentRuntimeError {
      if component_core_route(request) is Interpreter {
        let outcome = interpreter.invoke(
          store, instance, function_index, arguments, request,
        )
        on_execution(ExplicitInterpreter)
        return outcome
      }
      guard contexts.get(instance.store_idx) is Some(context) else {
        raise NativeCompilationFailed(
          "native context is missing for core instance \{instance.store_idx}",
        )
      }
      context.pending_suspension[0] = None
      context.suspension_enabled[0] = request.suspension is Resumable
      defer {
        context.suspension_enabled[0] = false
      }
      let outcome = context.core.call_core_func_resumable(
        store, instance, function_index, arguments,
      ) catch {
        error => raise component_jit_error(error)
      }
      if request.suspension is Resumable {
        on_execution(Resumable)
        component_native_outcome(context, outcome)
      } else {
        on_execution(RunToReturn)
        match outcome {
          NativeCoreReturned(results) => Returned(results)
          NativeCoreSuspended(continuation) => {
            continuation.cancel()
            raise CanonCallError(
              "native run-to-return core execution unexpectedly suspended",
            )
          }
        }
      }
    },
    prepare_store=fn(store) { try! store.enable_c_heap() },
    close=fn() {
      for _, context in contexts {
        context.core.close()
      }
      contexts.clear()
    },
  )
}

///|
pub fn native_component_engine(
  opt_level? : Int = 2,
  on_execution? : (NativeComponentExecutionEvent) -> Unit = fn(_event) { () },
) -> @component_engine.ComponentEngine {
  let normalized_level = if opt_level < 0 {
    0
  } else if opt_level > 3 {
    3
  } else {
    opt_level
  }
  @component_engine.ComponentEngine::from_session_factory(fn() {
    native_component_session(normalized_level, on_execution)
  })
}
