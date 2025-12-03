// Execution Context - manages stack, store, and call frames

///|
/// Execution context for running WASM code
struct ExecContext {
  stack : @runtime.Stack
  store : @runtime.Store
  mut instance : @runtime.ModuleInstance // mutable for cross-module call context switching
  frames : Array[@runtime.Frame]
  mut current_frame : Int
} derive(Show)

///|
fn ExecContext::new(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
) -> ExecContext {
  {
    stack: @runtime.Stack::new(),
    store,
    instance,
    frames: [],
    current_frame: 0,
  }
}

///|
fn ExecContext::push_frame(self : ExecContext, frame : @runtime.Frame) -> Unit {
  self.frames.push(frame)
  self.current_frame = self.frames.length() - 1
}

///|
fn ExecContext::pop_frame(
  self : ExecContext,
) -> Unit raise @runtime.RuntimeError {
  if self.frames.length() == 0 {
    raise @runtime.CallStackExhausted
  }
  self.frames.pop() |> ignore
  self.current_frame = self.frames.length() - 1
}

///|
fn ExecContext::get_frame(
  self : ExecContext,
) -> @runtime.Frame raise @runtime.RuntimeError {
  if self.current_frame < 0 || self.current_frame >= self.frames.length() {
    raise @runtime.CallStackExhausted
  }
  self.frames[self.current_frame]
}

///|
/// Capture the current call stack for error reporting
fn ExecContext::capture_call_stack(
  self : ExecContext,
) -> Array[@runtime.CallStackEntry] {
  let stack : Array[@runtime.CallStackEntry] = []
  for frame in self.frames {
    stack.push({ func_idx: frame.get_func_idx(), func_name: None })
  }
  stack
}

///|
/// Create a RuntimeErrorContext with the current call stack
fn ExecContext::make_error_context(
  self : ExecContext,
  error : @runtime.RuntimeError,
) -> @runtime.RuntimeErrorContext {
  @runtime.RuntimeErrorContext::new(error).with_call_stack(
    self.capture_call_stack(),
  )
}
