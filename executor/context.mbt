// Execution Context - manages stack, store, and call frames

///|
/// Execution context for running WASM code
struct ExecContext {
  stack : @runtime.Stack
  store : @runtime.Store
  frames : Array[@runtime.Frame]
  mut current_frame : Int
} derive(Show)

///|
fn ExecContext::new(store : @runtime.Store) -> ExecContext {
  { stack: @runtime.Stack::new(), store, frames: [], current_frame: 0 }
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
  let _ = self.frames.pop()
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
