///|
/// Reusable component execution policy.
///
/// An engine is immutable configuration. Opening a runtime always invokes the
/// factory and therefore creates a fresh Store-scoped execution session.
struct ComponentEngine {
  open_session : () -> @runtime_impl.CoreExecutionEngine
}

///|
/// Construct an execution engine from a Store-scoped session factory.
///
/// This is the adapter seam used by interpreter and native implementations.
/// Ordinary callers should use a concrete engine factory instead.
pub fn ComponentEngine::from_session_factory(
  open_session : () -> @runtime_impl.CoreExecutionEngine,
) -> ComponentEngine {
  { open_session, }
}

///|
/// Open a fresh low-level execution session.
///
/// Component runtime implementations call this once per runtime. Callers must
/// not share the returned session between Stores.
pub fn ComponentEngine::open_session(
  self : ComponentEngine,
) -> @runtime_impl.CoreExecutionEngine {
  (self.open_session)()
}

///|
/// Construct the portable interpreter engine.
pub fn interpreter_component_engine() -> ComponentEngine {
  ComponentEngine::from_session_factory(fn() {
    @runtime_impl.interpreter_core_execution_engine()
  })
}
