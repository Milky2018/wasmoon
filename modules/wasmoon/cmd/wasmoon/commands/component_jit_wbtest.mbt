///|
test "component JIT routes typed core execution requests" {
  guard component_core_route(
      @runtime_impl.CoreExecutionRequest(RunToCompletion, PreferNative),
    )
    is NativeCore else {
    fail("run-to-completion call did not select native execution")
  }
  for style in [@runtime_impl.CallbackStep, @runtime_impl.Stackful] {
    guard component_core_route(
        @runtime_impl.CoreExecutionRequest(style, PreferNative),
      )
      is InterpreterCore else {
      fail("continuation-sensitive call did not select interpreter execution")
    }
  }
  guard component_core_route(
      @runtime_impl.CoreExecutionRequest(RunToCompletion, InterpreterOnly),
    )
    is InterpreterCore else {
    fail("interpreter-only call selected native execution")
  }
}
