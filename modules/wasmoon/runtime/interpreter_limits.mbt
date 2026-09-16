///|
/// Interpreter budgets per invocation. Values count operand and local slots,
/// not bytes; control frames include function and structured-control entries.
/// Host-call nesting is counted across interpreter contexts sharing a Store.
/// These limits do not configure JIT stacks or guest linear-memory stacks.
pub struct InterpreterLimits {
  max_frames : Int
  max_values : Int
  max_controls : Int
  max_host_calls : Int
} derive(Debug)

///|
pub fn InterpreterLimits::new(
  max_frames? : Int = 16384,
  max_values? : Int = 1048576,
  max_controls? : Int = 65536,
  max_host_calls? : Int = 64,
) -> InterpreterLimits raise RuntimeError {
  if max_frames <= 0 ||
    max_values <= 0 ||
    max_controls <= 0 ||
    max_host_calls <= 0 {
    raise TypeMismatch
  }
  { max_frames, max_values, max_controls, max_host_calls, }
}

///|
pub fn InterpreterLimits::default() -> InterpreterLimits {
  {
    max_frames: 16384,
    max_values: 1048576,
    max_controls: 65536,
    max_host_calls: 64,
  }
}

///|
/// Reserve one nested interpreter-to-host call before entering host code.
pub fn Store::enter_interpreter_host_call(
  self : Store,
) -> Unit raise RuntimeError {
  if self.interpreter_host_calls >= self.interpreter_limits.max_host_calls {
    raise CallStackExhausted
  }
  self.interpreter_host_calls += 1
}

///|
pub fn Store::leave_interpreter_host_call(self : Store) -> Unit {
  self.interpreter_host_calls -= 1
}

///|
pub extend InterpreterLimits with @debug.Debug::{to_repr}
