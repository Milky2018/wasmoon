///|
fn component_execution_engine(
  use_jit : Bool,
  on_execution : ((@component.NativeComponentExecutionEvent) -> Unit)?,
) -> @component.ComponentEngine {
  if !use_jit {
    return @component.interpreter_component_engine()
  }
  match on_execution {
    Some(record) =>
      @component.native_component_engine(opt_level=0, on_execution=record)
    None => @component.native_component_engine(opt_level=0)
  }
}
