///|
/// Interpreter budgets per invocation. Values count operand and local slots,
/// not bytes; control frames include function and structured-control entries.
/// Host calls and guest-continuation callbacks share a native nesting budget
/// across interpreter contexts in the same Store.
/// These limits do not configure JIT stacks or guest linear-memory stacks.
pub struct InterpreterLimits {
  max_frames : Int
  max_values : Int
  max_controls : Int
  max_reentry_depth : Int
} derive(Debug)

///|
pub fn InterpreterLimits::new(
  max_frames? : Int = 16384,
  max_values? : Int = 1048576,
  max_controls? : Int = 65536,
  max_reentry_depth? : Int = 64,
) -> InterpreterLimits raise RuntimeError {
  if max_frames <= 0 ||
    max_values <= 0 ||
    max_controls <= 0 ||
    max_reentry_depth <= 0 {
    raise TypeMismatch
  }
  { max_frames, max_values, max_controls, max_reentry_depth, }
}

///|
pub fn InterpreterLimits::default() -> InterpreterLimits {
  {
    max_frames: 16384,
    max_values: 1048576,
    max_controls: 65536,
    max_reentry_depth: 64,
  }
}

///|
/// Reserve a native callback boundary before entering host or continuation code.
pub fn Store::enter_interpreter_boundary(
  self : Store,
) -> Unit raise RuntimeError {
  if self.interpreter_reentry_depth >= self.interpreter_limits.max_reentry_depth {
    raise CallStackExhausted
  }
  self.interpreter_reentry_depth += 1
}

///|
pub fn Store::leave_interpreter_boundary(self : Store) -> Unit {
  self.interpreter_reentry_depth -= 1
}

///|
pub extend InterpreterLimits with @debug.Debug::{to_repr}
