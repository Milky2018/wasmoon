///|
test "component JIT routes typed core execution requests" {
  guard component_core_route(
      @runtime_impl.CoreExecutionRequest(RunToCompletion, PreferNative),
    )
    is NativeCore else {
    fail("run-to-completion call did not select native execution")
  }
  guard component_core_route(
      @runtime_impl.CoreExecutionRequest(CallbackStep, PreferNative),
    )
    is NativeCore else {
    fail("callback step did not select native execution")
  }
  guard component_core_route(
      @runtime_impl.CoreExecutionRequest(Stackful, PreferNative),
    )
    is InterpreterCore else {
    fail("stackful call did not select interpreter execution")
  }
  guard component_core_route(
      @runtime_impl.CoreExecutionRequest(RunToCompletion, InterpreterOnly),
    )
    is InterpreterCore else {
    fail("interpreter-only call selected native execution")
  }
}
