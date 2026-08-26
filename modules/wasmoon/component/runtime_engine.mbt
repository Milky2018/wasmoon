///|
/// Reusable component execution policy.
///
/// This stable wrapper intentionally hides the Store-scoped core execution
/// engine owned by the implementation adapter.
struct ComponentEngine {
  open_session : () -> @runtime_impl.CoreExecutionEngine
}

///|
pub(all) enum NativeComponentExecutionEvent {
  RunToReturn
  Resumable
  ExplicitInterpreter
} derive(Debug, Eq)

///|
pub fn interpreter_component_engine() -> ComponentEngine {
  { open_session: fn() { @runtime_impl.interpreter_core_execution_engine() }, }
}

///|
pub fn native_component_engine(
  opt_level? : Int = 2,
  on_execution? : (NativeComponentExecutionEvent) -> Unit = fn(_event) { () },
) -> ComponentEngine {
  {
    open_session: fn() {
      @component_native.open_native_component_session(opt_level~, on_execution=fn(
        event,
      ) {
        on_execution(
          match event {
            RunToReturn => RunToReturn
            Resumable => Resumable
            ExplicitInterpreter => ExplicitInterpreter
          },
        )
      })
    },
  }
}

///|
fn ComponentEngine::open_session(
  self : ComponentEngine,
) -> @runtime_impl.CoreExecutionEngine {
  (self.open_session)()
}
