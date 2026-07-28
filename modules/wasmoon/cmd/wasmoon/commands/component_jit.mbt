///|
/// Build the Wasmoon-owned native adapter for component core execution.
///
/// Suspendable calls are selected before native entry and remain on the
/// resumable interpreter path. A JIT stack is never treated as a continuation.
fn component_jit_execution_engine() -> @runtime_impl.CoreExecutionEngine {
  let contexts : Map[Int, @wast.JITModuleContext] = Map([])
  let interpreter = @runtime_impl.interpreter_core_execution_engine()
  CoreExecutionEngine(
    fn(store, module_, instance) raise @runtime_impl.ComponentRuntimeError {
      match try_compile_jit(module_, instance, store) {
        Ok(context) => contexts.set(instance.store_idx, context)
        Err(message) =>
          raise CanonCallError("component JIT compilation failed: \{message}")
      }
    },
    fn(
      store,
      instance,
      func_idx,
      args,
      mode,
    ) raise @runtime_impl.ComponentRuntimeError {
      if mode != Synchronous {
        return interpreter.invoke(store, instance, func_idx, args, mode)
      }
      guard contexts.get(instance.store_idx) is Some(context) else {
        raise CanonCallError(
          "component JIT context is missing for core instance \{instance.store_idx}",
        )
      }
      let results = context.call_core_func(store, instance, func_idx, args) catch {
        FunctionUnavailable(_) =>
          // Re-exported imports do not have local machine code in this module.
          @executor.call_func_by_index(store, instance, func_idx, args) catch {
            error => raise CanonCallError(error.to_string())
          }
        Exit(code) => raise HostExit(code)
        Trap(message) =>
          if message.contains("unreachable") {
            raise CanonCallError(
              "wasm trap: wasm `unreachable` instruction executed",
            )
          } else {
            raise CanonCallError("wasm trap: \{message}")
          }
        error =>
          raise CanonCallError("component JIT invocation failed: \{error}")
      }
      Returned(results)
    },
    prepare_store=fn(store) { store.enable_c_heap() },
  )
}
