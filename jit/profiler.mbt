// JIT Profiler - Call counting and hot function detection
//
// This module provides:
// 1. Call counter for tracking function invocations
// 2. Hot function detection based on call threshold
// 3. Profiling statistics

// ============ Call Counter ============

///|
/// Stores call counts for each function
pub(all) struct CallCounter {
  // Function index -> call count
  counts : Map[Int, Int]
  // Total calls tracked
  mut total_calls : Int
}

///|
pub fn CallCounter::new() -> CallCounter {
  { counts: {}, total_calls: 0 }
}

///|
/// Increment the call count for a function
pub fn CallCounter::increment(self : CallCounter, func_idx : Int) -> Int {
  self.total_calls = self.total_calls + 1
  let current = match self.counts.get(func_idx) {
    Some(n) => n
    None => 0
  }
  let new_count = current + 1
  self.counts.set(func_idx, new_count)
  new_count
}

///|
/// Get the call count for a function
pub fn CallCounter::get_count(self : CallCounter, func_idx : Int) -> Int {
  match self.counts.get(func_idx) {
    Some(n) => n
    None => 0
  }
}

///|
/// Reset counter for a specific function
pub fn CallCounter::reset(self : CallCounter, func_idx : Int) -> Unit {
  self.counts.remove(func_idx)
}

///|
/// Clear all counters
pub fn CallCounter::clear(self : CallCounter) -> Unit {
  self.counts.clear()
  self.total_calls = 0
}

///|
/// Get total number of calls tracked
pub fn CallCounter::total(self : CallCounter) -> Int {
  self.total_calls
}

///|
/// Get the number of unique functions called
pub fn CallCounter::unique_functions(self : CallCounter) -> Int {
  let mut count = 0
  for _ in self.counts {
    count = count + 1
  }
  count
}

// ============ Hot Function Detector ============

///|
/// Configuration for hot function detection
pub(all) struct HotThreshold {
  // Number of calls before a function is considered "warm"
  warm_threshold : Int
  // Number of calls before a function is considered "hot"
  hot_threshold : Int
}

///|
pub fn HotThreshold::default() -> HotThreshold {
  { warm_threshold: 10, hot_threshold: 100 }
}

///|
pub fn HotThreshold::aggressive() -> HotThreshold {
  // Compile sooner
  { warm_threshold: 5, hot_threshold: 50 }
}

///|
pub fn HotThreshold::conservative() -> HotThreshold {
  // Wait longer before compiling
  { warm_threshold: 50, hot_threshold: 500 }
}

///|
/// Temperature of a function based on call frequency
pub enum FunctionTemperature {
  Cold // Not called or rarely called
  Warm // Called frequently, candidate for compilation
  Hot // Very frequently called, priority compilation target
}

///|
fn FunctionTemperature::to_string(self : FunctionTemperature) -> String {
  match self {
    Cold => "cold"
    Warm => "warm"
    Hot => "hot"
  }
}

///|
pub impl Show for FunctionTemperature with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Determines the temperature of a function based on its call count
pub fn get_temperature(
  count : Int,
  threshold : HotThreshold,
) -> FunctionTemperature {
  if count >= threshold.hot_threshold {
    Hot
  } else if count >= threshold.warm_threshold {
    Warm
  } else {
    Cold
  }
}

// ============ Profiler ============

///|
/// Complete profiler combining call counting and hot detection
pub(all) struct Profiler {
  // Call counter
  counter : CallCounter
  // Hot threshold configuration
  threshold : HotThreshold
  // Functions that have been identified as hot
  hot_functions : @hashset.HashSet[Int]
  // Functions that have been marked for compilation
  pending_compilation : @hashset.HashSet[Int]
  // Functions that have been compiled
  compiled_functions : @hashset.HashSet[Int]
}

///|
pub fn Profiler::new(threshold : HotThreshold) -> Profiler {
  {
    counter: CallCounter::new(),
    threshold,
    hot_functions: @hashset.new(),
    pending_compilation: @hashset.new(),
    compiled_functions: @hashset.new(),
  }
}

///|
/// Record a function call and return whether it should be compiled
/// Returns: (new_count, should_compile)
pub fn Profiler::record_call(self : Profiler, func_idx : Int) -> (Int, Bool) {
  let count = self.counter.increment(func_idx)

  // Check if we've reached the hot threshold
  if count == self.threshold.hot_threshold {
    self.hot_functions.add(func_idx)
    // Check if not already compiled or pending
    if !self.compiled_functions.contains(func_idx) &&
      !self.pending_compilation.contains(func_idx) {
      self.pending_compilation.add(func_idx)
      return (count, true)
    }
  }
  (count, false)
}

///|
/// Mark a function as compiled
pub fn Profiler::mark_compiled(self : Profiler, func_idx : Int) -> Unit {
  self.pending_compilation.remove(func_idx)
  self.compiled_functions.add(func_idx)
}

///|
/// Check if a function is compiled
pub fn Profiler::is_compiled(self : Profiler, func_idx : Int) -> Bool {
  self.compiled_functions.contains(func_idx)
}

///|
/// Check if a function should use JIT code
pub fn Profiler::should_use_jit(self : Profiler, func_idx : Int) -> Bool {
  self.compiled_functions.contains(func_idx)
}

///|
/// Get list of functions pending compilation
pub fn Profiler::get_pending(self : Profiler) -> Array[Int] {
  let result : Array[Int] = []
  for func_idx in self.pending_compilation {
    result.push(func_idx)
  }
  result
}

///|
/// Get temperature for a specific function
pub fn Profiler::get_function_temperature(
  self : Profiler,
  func_idx : Int,
) -> FunctionTemperature {
  let count = self.counter.get_count(func_idx)
  get_temperature(count, self.threshold)
}

///|
/// Get profiling statistics
pub fn Profiler::stats(self : Profiler) -> (Int, Int, Int, Int) {
  // (total_calls, unique_functions, hot_count, compiled_count)
  let mut hot_count = 0
  for _ in self.hot_functions {
    hot_count = hot_count + 1
  }
  let mut compiled_count = 0
  for _ in self.compiled_functions {
    compiled_count = compiled_count + 1
  }
  (
    self.counter.total(),
    self.counter.unique_functions(),
    hot_count,
    compiled_count,
  )
}

///|
fn Profiler::to_string(self : Profiler) -> String {
  let (total, unique, hot, compiled) = self.stats()
  "Profiler(calls=\{total}, functions=\{unique}, hot=\{hot}, compiled=\{compiled})"
}

///|
pub impl Show for Profiler with output(self, logger) {
  logger.write_string(self.to_string())
}
