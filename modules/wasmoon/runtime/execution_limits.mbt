///|
/// A captured execution scope survives suspension. Nested scopes also charge
/// their parent, so a nested call cannot reset its caller's budget.
pub struct ExecutionScope {
  priv controls : FixedArray[@wasmoon_jit.InvocationControl]
}

///|
pub fn ExecutionScope::failure(self : ExecutionScope) -> RuntimeError? {
  for i in 0..<self.controls.length() {
    let control = self.controls[i]
    if control.cancelled {
      return Some(ExecutionCancelled)
    }
    if control.timed_out {
      return Some(ExecutionTimedOut)
    }
    if control.exhausted.val {
      return Some(ExecutionBudgetExceeded)
    }
  }
  None
}

///|
pub fn ExecutionScope::poll(self : ExecutionScope) -> Bool {
  for i in 0..<self.controls.length() {
    if self.controls[i].poll() {
      return true
    }
  }
  false
}

///|
pub fn ExecutionScope::check(self : ExecutionScope) -> Unit raise RuntimeError {
  if self.poll() && self.failure() is Some(error) {
    raise error
  }
}

///|
pub fn Store::execution_scope(self : Store) -> ExecutionScope? {
  self.execution_scope
}

///|
/// Bound a group of calls and any continuations they publish. Safepoint units
/// count cooperative polls, not Wasm instructions or equivalent engine fuel.
/// Blocking synchronous host callbacks are checked after returning, not interrupted.
pub fn[T] Store::with_execution_limits(
  self : Store,
  run : () -> T raise,
  timeout_ms~ : Int32? = None,
  safepoints~ : Int64? = None,
  cancel~ : (() -> Bool)? = None,
) -> T raise {
  self.ensure_open()
  guard @wasmoon_jit.InvocationControl::new(timeout_ms, cancel, safepoints~)
    is Some(control) else {
    raise InvalidExecutionLimit
  }
  let previous = self.execution_scope
  let controls = match previous {
    Some(scope) => scope.controls[:].to_owned()
    None => []
  }
  controls.push(control)
  let scope = ExecutionScope::{
    controls: FixedArray::makei(controls.length(), i => controls[i]),
  }
  self.execution_scope = Some(scope)
  defer {
    self.execution_scope = previous
  }
  for i in 0..<scope.controls.length() {
    if scope.controls[i].preflight() && scope.failure() is Some(error) {
      raise error
    }
  }
  let result = run()
  if control.expired() {
    raise ExecutionTimedOut
  }
  result
}

///|
pub extend ExecutionScope with Debug::{to_repr}

///|
pub impl Debug for ExecutionScope with fn to_repr(_self) {
  Repr::literal("ExecutionScope")
}

///|
/// Drive captured work without resetting its limits. Any currently active
/// parent policy is also applied, with each shared controller charged once.
pub fn[T, E : Error] Store::in_execution_scope(
  self : Store,
  captured : ExecutionScope?,
  run : () -> T raise E,
) -> T raise E {
  let previous = self.execution_scope
  let controls = match previous {
    Some(scope) => scope.controls[:].to_owned()
    None => []
  }
  if captured is Some(scope) {
    for control in scope.controls {
      if !controls.any(existing => physical_equal(existing, control)) {
        controls.push(control)
      }
    }
  }
  self.execution_scope = if controls.is_empty() {
    None
  } else {
    Some({ controls: FixedArray::makei(controls.length(), i => controls[i]), })
  }
  defer {
    self.execution_scope = previous
  }
  run()
}
