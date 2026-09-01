// Execution Context - manages stack, store, and call frames

///|
/// Maximum call stack depth to prevent stack overflow
// The interpreter executes WASM calls via host recursion (not an explicit
// instruction-pointer loop). Keep this limit conservative so runaway recursion
// traps with `CallStackExhausted` instead of crashing the process with a native
// stack overflow on typical 8MiB thread stacks (e.g. macOS).
const MAX_CALL_STACK_DEPTH : Int = 256

///|
/// Enable forced GC after GC allocations in interpreter mode
const GC_STRESS_ENV : String = "WASMOON_GC_STRESS"

///|
/// Collect every N GC allocations when stress mode is enabled (default 1)
const GC_STRESS_EVERY_ENV : String = "WASMOON_GC_STRESS_EVERY"

///|
fn is_truthy_env_flag(value : String) -> Bool {
  value == "1" ||
  value == "true" ||
  value == "TRUE" ||
  value == "yes" ||
  value == "YES" ||
  value == "on" ||
  value == "ON"
}

///|
fn gc_stress_enabled() -> Bool {
  match @env.get_env_var(GC_STRESS_ENV) {
    Some(v) => is_truthy_env_flag(v)
    None => false
  }
}

///|
fn parse_decimal_int(value : String) -> Int? {
  if value.length() == 0 {
    return None
  }
  let mut parsed = 0
  for codepoint in value {
    let digit = codepoint.to_int() - b'0'.to_int()
    if digit < 0 || digit > 9 {
      return None
    }
    parsed = parsed * 10 + digit
  }
  Some(parsed)
}

///|
fn gc_stress_every() -> Int {
  match @env.get_env_var(GC_STRESS_EVERY_ENV) {
    Some(raw_value) =>
      match parse_decimal_int(raw_value) {
        Some(parsed) if parsed > 0 => parsed
        _ => 1
      }
    None => 1
  }
}

///|
/// Label info for tracking block arity during branching
/// is_loop: true for loops (branch goes to start, uses param arity)
/// arity: number of values to carry when branching
/// stack_height: stack depth when the block was entered (for stack unwinding)
priv struct LabelInfo {
  is_loop : Bool
  arity : Int
  stack_height : Int
} derive(Debug)

///|
priv struct CancellationPoller {
  callback : () -> Bool
}

///|
impl Debug for CancellationPoller with fn to_repr(_self) {
  Repr::literal("<callback>")
}

///|
priv struct SuspensionClassifier {
  classify : (@runtime.RuntimeError) -> Int64?
}

///|
impl Debug for SuspensionClassifier with fn to_repr(_self) {
  Repr::literal("<suspension-classifier>")
}

///|
priv struct ResumeAction {
  run : () -> Unit raise
}

///|
impl Debug for ResumeAction with fn to_repr(_self) {
  Repr::literal("<resume-action>")
}

///|
/// Execution context for running WASM code
struct ExecContext {
  stack : @runtime.Stack
  store : @runtime.Store
  mut instance : @runtime.ModuleInstance // mutable for cross-module call context switching
  frames : Array[@runtime.Frame]
  mut current_frame : Int
  labels : Array[LabelInfo] // Stack of labels for tracking branch arities
  gc_stress : Bool
  gc_stress_every : Int
  mut gc_stress_alloc_count : Int
  cancel : CancellationPoller?
  suspension_classifier : SuspensionClassifier?
  async_host_driver : @runtime.AsyncHostCallDriver?
  mut resume_action : ResumeAction?
  mut suspension_token : Int64?
} derive(Debug)

///|
fn ExecContext::ExecContext(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  cancel? : (() -> Bool)? = None,
  classify_suspension? : (@runtime.RuntimeError) -> Int64? = fn(_) { None },
  async_host_driver? : @runtime.AsyncHostCallDriver? = None,
) -> ExecContext {
  {
    stack: Stack(),
    store,
    instance,
    frames: [],
    current_frame: 0,
    labels: [],
    gc_stress: gc_stress_enabled(),
    gc_stress_every: gc_stress_every(),
    gc_stress_alloc_count: 0,
    cancel: cancel.map(fn(callback) { { callback, } }),
    suspension_classifier: Some({ classify: classify_suspension, }),
    async_host_driver,
    resume_action: None,
    suspension_token: None,
  }
}

///|
/// Poll the invocation-local cancellation callback at a Wasm safepoint.
fn ExecContext::check_cancellation(self : ExecContext) -> Unit raise {
  if self.cancel is Some(poller) && (poller.callback)() {
    raise InvocationSignal::Cancelled
  }
}

///|
/// Push a label for a block/loop/if
fn ExecContext::push_label(
  self : ExecContext,
  is_loop : Bool,
  arity : Int,
) -> Unit {
  self.labels.push({ is_loop, arity, stack_height: self.stack.size(), })
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
    raise CallStackExhausted
  }
  self.frames.push(frame)
  self.current_frame = self.frames.length() - 1
}

///|
fn ExecContext::pop_frame(
  self : ExecContext,
) -> Unit raise @runtime.RuntimeError {
  if self.frames.length() == 0 {
    raise CallStackExhausted
  }
  self.frames.pop() |> ignore
  self.current_frame = self.frames.length() - 1
}

///|
fn ExecContext::get_frame(
  self : ExecContext,
) -> @runtime.Frame raise @runtime.RuntimeError {
  if self.current_frame < 0 || self.current_frame >= self.frames.length() {
    raise CallStackExhausted
  }
  self.frames[self.current_frame]
}

///|
/// Collect transient GC roots from interpreter stack and frame locals
fn ExecContext::collect_gc_additional_roots(
  self : ExecContext,
) -> Array[@types.Value] {
  let roots = self.stack.active_values()
  for frame in self.frames {
    for local_value in frame.locals_values() {
      roots.push(local_value)
    }
  }
  roots
}

///|
/// In stress mode, force a GC cycle after allocation sites
fn ExecContext::maybe_collect_gc_stress(self : ExecContext) -> Unit {
  if !self.gc_stress {
    return
  }
  self.gc_stress_alloc_count = self.gc_stress_alloc_count + 1
  if self.gc_stress_alloc_count % self.gc_stress_every != 0 {
    return
  }
  let roots = self.collect_gc_additional_roots()
  self.store.collect_garbage(additional_roots=roots) |> ignore
}
