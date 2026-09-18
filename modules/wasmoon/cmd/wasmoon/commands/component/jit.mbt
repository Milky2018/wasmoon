///|
fn component_execution_engine(
  use_jit : Bool,
  on_execution : ((@component_runtime.NativeComponentExecutionEvent) -> Unit)?,
) -> @component_runtime.ComponentEngine {
  if !use_jit {
    return @component_runtime.interpreter_component_engine()
  }
  match on_execution {
    Some(record) =>
      @component_runtime.native_component_engine(
        opt_level=0,
        on_execution=record,
      )
    None => @component_runtime.native_component_engine(opt_level=0)
  }
}
