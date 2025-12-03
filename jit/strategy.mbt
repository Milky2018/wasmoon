// JIT Compilation Strategy
//
// This module provides:
// 1. Compilation mode selection (interpret, baseline, optimized)
// 2. Lazy compilation (compile on demand)
// 3. Tiered compilation strategy

// ============ Compilation Mode ============

///|
/// The compilation mode for a function
pub(all) enum CompilationMode {
  // Always interpret (never JIT compile)
  Interpret
  // Baseline JIT (fast compilation, less optimization)
  Baseline
  // Optimized JIT (slow compilation, more optimization)
  Optimized
}

///|
fn CompilationMode::to_string(self : CompilationMode) -> String {
  match self {
    Interpret => "interpret"
    Baseline => "baseline"
    Optimized => "optimized"
  }
}

///|
pub impl Show for CompilationMode with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Compilation Request ============

///|
/// A request to compile a function
pub(all) struct CompilationRequest {
  // Function index in the module
  func_idx : Int
  // Requested compilation mode
  mode : CompilationMode
  // Priority (higher = compile sooner)
  priority : Int
}

///|
pub fn CompilationRequest::new(
  func_idx : Int,
  mode : CompilationMode,
) -> CompilationRequest {
  { func_idx, mode, priority: 0 }
}

///|
pub fn CompilationRequest::with_priority(
  func_idx : Int,
  mode : CompilationMode,
  priority : Int,
) -> CompilationRequest {
  { func_idx, mode, priority }
}

// ============ Compilation Queue ============

///|
/// Queue of pending compilation requests
pub(all) struct CompilationQueue {
  // Pending requests
  requests : Array[CompilationRequest]
  // Maximum queue size (0 = unlimited)
  max_size : Int
}

///|
pub fn CompilationQueue::new(max_size : Int) -> CompilationQueue {
  { requests: [], max_size }
}

///|
/// Add a compilation request to the queue
pub fn CompilationQueue::enqueue(
  self : CompilationQueue,
  request : CompilationRequest,
) -> Bool {
  // Check for duplicates
  for req in self.requests {
    if req.func_idx == request.func_idx {
      return false
    }
  }
  // Check size limit
  if self.max_size > 0 && self.requests.length() >= self.max_size {
    return false
  }
  // Insert sorted by priority (highest first)
  let mut inserted = false
  for i in 0..<self.requests.length() {
    if request.priority > self.requests[i].priority {
      // Insert at position i
      let old = self.requests
      let new_arr : Array[CompilationRequest] = []
      for j in 0..<i {
        new_arr.push(old[j])
      }
      new_arr.push(request)
      for j in i..<old.length() {
        new_arr.push(old[j])
      }
      // Copy back
      self.requests.clear()
      for req in new_arr {
        self.requests.push(req)
      }
      inserted = true
      break
    }
  }
  if !inserted {
    self.requests.push(request)
  }
  true
}

///|
/// Get the next request to process
pub fn CompilationQueue::dequeue(
  self : CompilationQueue,
) -> CompilationRequest? {
  if self.requests.length() == 0 {
    return None
  }
  // Pop first (highest priority)
  let first = self.requests[0]
  let new_arr : Array[CompilationRequest] = []
  for i in 1..<self.requests.length() {
    new_arr.push(self.requests[i])
  }
  self.requests.clear()
  for req in new_arr {
    self.requests.push(req)
  }
  Some(first)
}

///|
/// Check if a function is in the queue
pub fn CompilationQueue::contains(
  self : CompilationQueue,
  func_idx : Int,
) -> Bool {
  for req in self.requests {
    if req.func_idx == func_idx {
      return true
    }
  }
  false
}

///|
/// Get queue length
pub fn CompilationQueue::length(self : CompilationQueue) -> Int {
  self.requests.length()
}

///|
/// Check if queue is empty
pub fn CompilationQueue::is_empty(self : CompilationQueue) -> Bool {
  self.requests.length() == 0
}

///|
/// Clear the queue
pub fn CompilationQueue::clear(self : CompilationQueue) -> Unit {
  self.requests.clear()
}

// ============ Tiered Compilation Strategy ============

///|
/// Configuration for tiered compilation
pub(all) struct TieredConfig {
  // Threshold for baseline compilation
  baseline_threshold : Int
  // Threshold for optimized recompilation
  optimize_threshold : Int
  // Whether to compile synchronously (blocking) or asynchronously
  synchronous : Bool
  // Maximum concurrent compilations (for async mode)
  max_concurrent : Int
}

///|
pub fn TieredConfig::default() -> TieredConfig {
  {
    baseline_threshold: 100,
    optimize_threshold: 10000,
    synchronous: true,
    max_concurrent: 1,
  }
}

///|
pub fn TieredConfig::eager() -> TieredConfig {
  // Compile early, optimize early
  {
    baseline_threshold: 10,
    optimize_threshold: 1000,
    synchronous: true,
    max_concurrent: 1,
  }
}

///|
pub fn TieredConfig::deferred() -> TieredConfig {
  // Compile late, less optimization
  {
    baseline_threshold: 1000,
    optimize_threshold: 100000,
    synchronous: true,
    max_concurrent: 1,
  }
}

// ============ Compilation Decision ============

///|
/// Decision about what to do with a function call
pub enum CompilationDecision {
  // Interpret the function
  Interpret
  // Compile and then execute
  CompileAndExecute(CompilationMode)
  // Execute already compiled code
  ExecuteCompiled
}

///|
fn CompilationDecision::to_string(self : CompilationDecision) -> String {
  match self {
    Interpret => "interpret"
    CompileAndExecute(mode) => "compile_and_execute(\{mode})"
    ExecuteCompiled => "execute_compiled"
  }
}

///|
pub impl Show for CompilationDecision with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Compilation Strategy ============

///|
/// The main compilation strategy manager
pub(all) struct CompilationStrategy {
  // Profiler for call counting
  profiler : Profiler
  // Compilation queue
  queue : CompilationQueue
  // Tiered configuration
  config : TieredConfig
  // Statistics
  mut decisions_interpret : Int
  mut decisions_compile : Int
  mut decisions_compiled : Int
}

///|
pub fn CompilationStrategy::new(config : TieredConfig) -> CompilationStrategy {
  let threshold = HotThreshold::{
    warm_threshold: config.baseline_threshold / 2,
    hot_threshold: config.baseline_threshold,
  }
  {
    profiler: Profiler::new(threshold),
    queue: CompilationQueue::new(100), // Max 100 pending compilations
    config,
    decisions_interpret: 0,
    decisions_compile: 0,
    decisions_compiled: 0,
  }
}

///|
/// Make a compilation decision for a function call
pub fn CompilationStrategy::decide(
  self : CompilationStrategy,
  func_idx : Int,
) -> CompilationDecision {
  // Check if already compiled
  if self.profiler.is_compiled(func_idx) {
    self.decisions_compiled = self.decisions_compiled + 1
    return ExecuteCompiled
  }

  // Record the call and check if it should trigger compilation
  let (count, should_compile) = self.profiler.record_call(func_idx)
  if should_compile {
    // Determine compilation mode based on count
    let mode = if count >= self.config.optimize_threshold {
      Optimized
    } else {
      Baseline
    }
    self.decisions_compile = self.decisions_compile + 1
    return CompileAndExecute(mode)
  }
  self.decisions_interpret = self.decisions_interpret + 1
  Interpret
}

///|
/// Mark a function as compiled
pub fn CompilationStrategy::mark_compiled(
  self : CompilationStrategy,
  func_idx : Int,
) -> Unit {
  self.profiler.mark_compiled(func_idx)
}

///|
/// Check if a function is compiled
pub fn CompilationStrategy::is_compiled(
  self : CompilationStrategy,
  func_idx : Int,
) -> Bool {
  self.profiler.is_compiled(func_idx)
}

///|
/// Schedule a function for background compilation
pub fn CompilationStrategy::schedule_compilation(
  self : CompilationStrategy,
  func_idx : Int,
  mode : CompilationMode,
) -> Bool {
  let priority = self.profiler.counter.get_count(func_idx)
  let request = CompilationRequest::with_priority(func_idx, mode, priority)
  self.queue.enqueue(request)
}

///|
/// Get the next function to compile (for background compilation)
pub fn CompilationStrategy::next_to_compile(
  self : CompilationStrategy,
) -> CompilationRequest? {
  self.queue.dequeue()
}

///|
/// Get strategy statistics
pub fn CompilationStrategy::stats(
  self : CompilationStrategy,
) -> (Int, Int, Int, Int, Int, Int) {
  // (total_calls, interpreted, compiled_calls, compilations, queue_len, hot)
  let (total, _, hot, compiled) = self.profiler.stats()
  (
    total,
    self.decisions_interpret,
    self.decisions_compiled,
    compiled,
    self.queue.length(),
    hot,
  )
}

///|
fn CompilationStrategy::to_string(self : CompilationStrategy) -> String {
  let (total, interp, compiled_calls, compilations, queue, hot) = self.stats()
  "CompilationStrategy(calls=\{total}, interp=\{interp}, jit=\{compiled_calls}, compilations=\{compilations}, queue=\{queue}, hot=\{hot})"
}

///|
pub impl Show for CompilationStrategy with output(self, logger) {
  logger.write_string(self.to_string())
}
