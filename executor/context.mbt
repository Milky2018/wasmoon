// Execution Context - manages stack, store, and call frames

///|
/// Maximum call stack depth to prevent stack overflow
const MAX_CALL_STACK_DEPTH : Int = 1000

///|
/// Label info for tracking block arity during branching
/// is_loop: true for loops (branch goes to start, uses param arity)
/// arity: number of values to carry when branching
/// stack_height: stack depth when the block was entered (for stack unwinding)
priv struct LabelInfo {
  is_loop : Bool
  arity : Int
  stack_height : Int
} derive(Show)

///|
/// Execution context for running WASM code
struct ExecContext {
  stack : @runtime.Stack
  store : @runtime.Store
  mut instance : @runtime.ModuleInstance // mutable for cross-module call context switching
  frames : Array[@runtime.Frame]
  mut current_frame : Int
  labels : Array[LabelInfo] // Stack of labels for tracking branch arities
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
    labels: [],
  }
}

///|
/// Push a label for a block/loop/if
fn ExecContext::push_label(
  self : ExecContext,
  is_loop : Bool,
  arity : Int,
) -> Unit {
  self.labels.push(LabelInfo::{
    is_loop,
    arity,
    stack_height: self.stack.size(),
  })
}

///|
/// Pop a label when exiting a block/loop/if
fn ExecContext::pop_label(self : ExecContext) -> Unit {
  if self.labels.length() > 0 {
    self.labels.pop() |> ignore
  }
}

///|
/// Get the arity for a branch to the given depth
fn ExecContext::get_branch_arity(self : ExecContext, depth : Int) -> Int {
  let label_idx = self.labels.length() - 1 - depth
  if label_idx >= 0 && label_idx < self.labels.length() {
    self.labels[label_idx].arity
  } else {
    0
  }
}

///|
/// Restore stack to the given height (discard values above it)
fn ExecContext::restore_stack_to(self : ExecContext, height : Int) -> Unit {
  while self.stack.size() > height {
    try self.stack.pop() |> ignore catch {
      _ => break
    }
  }
}

///|
fn ExecContext::push_frame(
  self : ExecContext,
  frame : @runtime.Frame,
) -> Unit raise @runtime.RuntimeError {
  if self.frames.length() >= MAX_CALL_STACK_DEPTH {
    raise @runtime.CallStackExhausted
  }
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
#warnings("-unused_value")
fn ExecContext::make_error_context(
  self : ExecContext,
  error : @runtime.RuntimeError,
) -> @runtime.RuntimeErrorContext {
  @runtime.RuntimeErrorContext::new(error).with_call_stack(
    self.capture_call_stack(),
  )
}
