///|
test "component JIT routes typed core execution requests" {
  guard component_core_route(
      CoreExecutionRequest(RunToCompletion, PreferNative, RunToReturn),
    )
    is NativeCore else {
    fail("run-to-completion call did not select native execution")
  }
  guard component_core_route(
      CoreExecutionRequest(CallbackStep, PreferNative, Resumable),
    )
    is NativeCore else {
    fail("callback step did not select native execution")
  }
  guard component_core_route(
      CoreExecutionRequest(Stackful, PreferNative, Resumable),
    )
    is NativeCore else {
    fail("stackful call did not select native execution")
  }
  guard component_core_route(
      CoreExecutionRequest(RunToCompletion, InterpreterOnly, RunToReturn),
    )
    is InterpreterCore else {
    fail("interpreter-only call selected native execution")
  }
}

///|
test "component JIT records typed execution evidence" {
  let evidence = ComponentJITExecutionEvidence::new()
  evidence.record(NativeRunToReturn)
  evidence.record(NativeResumable)
  evidence.record(ExplicitInterpreter)
  debug_inspect(
    (
      evidence.native_run_to_return.val,
      evidence.native_resumable.val,
      evidence.explicit_interpreter.val,
    ),
    content="(1, 1, 1)",
  )
}

///|
test "component JIT reports unavailable native code without fallback" {
  inspect(
    component_jit_error(FunctionUnavailable(7)),
    content="CanonCallError(\"component JIT invocation failed: FunctionUnavailable(7)\")",
  )
}
