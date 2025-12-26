// JIT Engine - Bridges compilation strategy with actual code compilation
//
// This module provides:
// 1. JIT Engine that coordinates compilation and execution
// 2. Function compilation pipeline
// 3. Compiled function cache integration

// ============ Compilation Status ============

///|
/// Status of a function's compilation
pub enum CompilationStatus {
  // Never compiled, use interpreter
  NotCompiled
  // Compiled and ready for execution
  Compiled
  // Compilation failed, fall back to interpreter
  Failed(String)
}

///|
fn CompilationStatus::to_string(self : CompilationStatus) -> String {
  match self {
    NotCompiled => "not_compiled"
    Compiled => "compiled"
    Failed(msg) => "failed: \{msg}"
  }
}

///|
pub impl Show for CompilationStatus with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Function Entry ============

///|
/// Entry for a function in the JIT engine
pub(all) struct FunctionEntry {
  // Function index
  func_idx : Int
  // Current compilation status
  mut status : CompilationStatus
  // Compiled code (if status == Compiled)
  mut compiled_code : @vcode.CompiledFunction?
  // Call count (for statistics)
  mut call_count : Int
}

///|
pub fn FunctionEntry::new(func_idx : Int) -> FunctionEntry {
  { func_idx, status: NotCompiled, compiled_code: None, call_count: 0 }
}

///|
pub fn FunctionEntry::is_compiled(self : FunctionEntry) -> Bool {
  self.status is Compiled
}

// ============ JIT Engine ============

///|
/// The main JIT engine
pub(all) struct JITEngine {
  // Compilation strategy
  strategy : CompilationStrategy
  // JIT runtime for code caching
  runtime : @vcode.JITRuntime
  // Function entries
  functions : Map[Int, FunctionEntry]
  // Statistics
  mut total_calls : Int
  mut jit_calls : Int
  mut interpreter_calls : Int
  mut compilation_failures : Int
}

///|
pub fn JITEngine::new(config : TieredConfig) -> JITEngine {
  {
    strategy: CompilationStrategy::new(config),
    runtime: @vcode.JITRuntime::new(0, 65536), // 64KB regions
    functions: {},
    total_calls: 0,
    jit_calls: 0,
    interpreter_calls: 0,
    compilation_failures: 0,
  }
}

///|
pub fn JITEngine::default() -> JITEngine {
  JITEngine::new(TieredConfig::default())
}

///|
/// Called before executing a function
/// Returns whether to use JIT code
pub fn JITEngine::on_call(self : JITEngine, func_idx : Int) -> Bool {
  self.total_calls = self.total_calls + 1

  // Get or create function entry
  let entry = match self.functions.get(func_idx) {
    Some(e) => e
    None => {
      let e = FunctionEntry::new(func_idx)
      self.functions.set(func_idx, e)
      e
    }
  }
  entry.call_count = entry.call_count + 1

  // Check if already compiled
  if entry.is_compiled() {
    self.jit_calls = self.jit_calls + 1
    return true
  }

  // Ask strategy for decision
  let decision = self.strategy.decide(func_idx)
  match decision {
    ExecuteCompiled => {
      self.jit_calls = self.jit_calls + 1
      true
    }
    CompileAndExecute(_) => {
      // In synchronous mode, we would compile here
      // For now, just record the decision and use interpreter
      // Actual compilation will be done when we have the function body
      self.interpreter_calls = self.interpreter_calls + 1
      false
    }
    Interpret => {
      self.interpreter_calls = self.interpreter_calls + 1
      false
    }
  }
}

///|
/// Mark a function as compiled
pub fn JITEngine::mark_compiled(
  self : JITEngine,
  func_idx : Int,
  code : @vcode.CompiledFunction,
) -> Unit {
  // Register with runtime
  match self.runtime.register(func_idx, code) {
    Ok(_) => {
      // Update function entry
      let entry = match self.functions.get(func_idx) {
        Some(e) => e
        None => {
          let e = FunctionEntry::new(func_idx)
          self.functions.set(func_idx, e)
          e
        }
      }
      entry.status = Compiled
      entry.compiled_code = Some(code)

      // Mark in strategy
      self.strategy.mark_compiled(func_idx)
    }
    Err(_) => self.compilation_failures = self.compilation_failures + 1
  }
}

///|
/// Mark a function compilation as failed
pub fn JITEngine::mark_failed(
  self : JITEngine,
  func_idx : Int,
  reason : String,
) -> Unit {
  let entry = match self.functions.get(func_idx) {
    Some(e) => e
    None => {
      let e = FunctionEntry::new(func_idx)
      self.functions.set(func_idx, e)
      e
    }
  }
  entry.status = Failed(reason)
  self.compilation_failures = self.compilation_failures + 1
}

///|
/// Get compiled code for a function
pub fn JITEngine::get_compiled(
  self : JITEngine,
  func_idx : Int,
) -> @vcode.CompiledFunction? {
  self.runtime.lookup(func_idx)
}

///|
/// Check if a function is compiled
pub fn JITEngine::is_compiled(self : JITEngine, func_idx : Int) -> Bool {
  self.strategy.is_compiled(func_idx)
}

///|
/// Invalidate a compiled function
pub fn JITEngine::invalidate(self : JITEngine, func_idx : Int) -> Unit {
  self.runtime.invalidate(func_idx)
  if self.functions.get(func_idx) is Some(entry) {
    entry.status = NotCompiled
  }
}

///|
/// Get engine statistics
pub fn JITEngine::stats(self : JITEngine) -> (Int, Int, Int, Int, Int) {
  // (total_calls, jit_calls, interpreter_calls, compiled_count, failures)
  let mut compiled_count = 0
  for entry in self.functions.values() {
    if entry.is_compiled() {
      compiled_count = compiled_count + 1
    }
  }
  (
    self.total_calls,
    self.jit_calls,
    self.interpreter_calls,
    compiled_count,
    self.compilation_failures,
  )
}

///|
fn JITEngine::to_string(self : JITEngine) -> String {
  let (total, jit, interp, compiled, failures) = self.stats()
  "JITEngine(calls=\{total}, jit=\{jit}, interp=\{interp}, compiled=\{compiled}, failures=\{failures})"
}

///|
pub impl Show for JITEngine with output(self, logger) {
  logger.write_string(self.to_string())
}
