// JIT Debug Support
//
// This module provides:
// 1. Source mapping (WASM instruction offset to source location)
// 2. Breakpoint management
// 3. Stack trace generation

// ============ Source Location ============

///|
/// A location in source code
pub(all) struct SourceLocation {
  // Function index
  func_idx : Int
  // Instruction offset within function
  offset : Int
  // Optional source file name
  file : String?
  // Optional line number (1-indexed)
  line : Int?
  // Optional column number (1-indexed)
  column : Int?
}

///|
pub fn SourceLocation::new(func_idx : Int, offset : Int) -> SourceLocation {
  { func_idx, offset, file: None, line: None, column: None }
}

///|
pub fn SourceLocation::with_source(
  func_idx : Int,
  offset : Int,
  file : String,
  line : Int,
  column : Int,
) -> SourceLocation {
  { func_idx, offset, file: Some(file), line: Some(line), column: Some(column) }
}

///|
fn SourceLocation::to_string(self : SourceLocation) -> String {
  match (self.file, self.line, self.column) {
    (Some(f), Some(l), Some(c)) =>
      "\{f}:\{l}:\{c} (func \{self.func_idx} @ \{self.offset})"
    (Some(f), Some(l), None) =>
      "\{f}:\{l} (func \{self.func_idx} @ \{self.offset})"
    (Some(f), None, None) => "\{f} (func \{self.func_idx} @ \{self.offset})"
    _ => "func \{self.func_idx} @ \{self.offset}"
  }
}

///|
pub impl Show for SourceLocation with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Source Map ============

///|
/// Maps WASM offsets to source locations
pub(all) struct SourceMap {
  // Function index -> (offset -> location)
  mappings : Map[Int, Map[Int, SourceLocation]]
  // Function names (for display)
  func_names : Map[Int, String]
}

///|
pub fn SourceMap::new() -> SourceMap {
  { mappings: {}, func_names: {} }
}

///|
/// Add a mapping from WASM offset to source location
pub fn SourceMap::add_mapping(
  self : SourceMap,
  func_idx : Int,
  offset : Int,
  location : SourceLocation,
) -> Unit {
  match self.mappings.get(func_idx) {
    Some(func_map) => func_map.set(offset, location)
    None => {
      let func_map : Map[Int, SourceLocation] = {}
      func_map.set(offset, location)
      self.mappings.set(func_idx, func_map)
    }
  }
}

///|
/// Add a function name
pub fn SourceMap::add_func_name(
  self : SourceMap,
  func_idx : Int,
  name : String,
) -> Unit {
  self.func_names.set(func_idx, name)
}

///|
/// Get source location for a WASM offset
pub fn SourceMap::get_location(
  self : SourceMap,
  func_idx : Int,
  offset : Int,
) -> SourceLocation? {
  match self.mappings.get(func_idx) {
    Some(func_map) => func_map.get(offset)
    None => None
  }
}

///|
/// Get function name
pub fn SourceMap::get_func_name(self : SourceMap, func_idx : Int) -> String {
  match self.func_names.get(func_idx) {
    Some(name) => name
    None => "func_\{func_idx}"
  }
}

///|
/// Find nearest source location at or before given offset
pub fn SourceMap::find_nearest(
  self : SourceMap,
  func_idx : Int,
  offset : Int,
) -> SourceLocation? {
  match self.mappings.get(func_idx) {
    Some(func_map) => {
      let mut best : SourceLocation? = None
      let mut best_offset = -1
      for entry in func_map.iter() {
        let (off, loc) = entry
        if off <= offset && off > best_offset {
          best = Some(loc)
          best_offset = off
        }
      }
      best
    }
    None => None
  }
}

///|
/// Get total number of mappings
pub fn SourceMap::mapping_count(self : SourceMap) -> Int {
  let mut count = 0
  for func_map in self.mappings.values() {
    count = count + func_map.length()
  }
  count
}

// ============ Breakpoint ============

///|
/// A breakpoint at a specific location
pub(all) struct Breakpoint {
  // Unique breakpoint ID
  id : Int
  // Function index
  func_idx : Int
  // Instruction offset
  offset : Int
  // Is the breakpoint enabled?
  mut enabled : Bool
  // Hit count
  mut hit_count : Int
  // Optional condition (for conditional breakpoints)
  condition : String?
}

///|
pub fn Breakpoint::new(id : Int, func_idx : Int, offset : Int) -> Breakpoint {
  { id, func_idx, offset, enabled: true, hit_count: 0, condition: None }
}

///|
pub fn Breakpoint::with_condition(
  id : Int,
  func_idx : Int,
  offset : Int,
  condition : String,
) -> Breakpoint {
  {
    id,
    func_idx,
    offset,
    enabled: true,
    hit_count: 0,
    condition: Some(condition),
  }
}

///|
pub fn Breakpoint::enable(self : Breakpoint) -> Unit {
  self.enabled = true
}

///|
pub fn Breakpoint::disable(self : Breakpoint) -> Unit {
  self.enabled = false
}

///|
pub fn Breakpoint::hit(self : Breakpoint) -> Unit {
  self.hit_count = self.hit_count + 1
}

///|
fn Breakpoint::to_string(self : Breakpoint) -> String {
  let status = if self.enabled { "enabled" } else { "disabled" }
  let cond = match self.condition {
    Some(c) => " if \{c}"
    None => ""
  }
  "Breakpoint #\{self.id} at func \{self.func_idx}:\{self.offset} (\{status}, hits=\{self.hit_count})\{cond}"
}

///|
pub impl Show for Breakpoint with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Breakpoint Manager ============

///|
/// Manages all breakpoints
pub(all) struct BreakpointManager {
  // All breakpoints by ID
  breakpoints : Map[Int, Breakpoint]
  // Index: func_idx -> offset -> breakpoint_id
  by_location : Map[Int, Map[Int, Int]]
  // Next breakpoint ID
  mut next_id : Int
}

///|
pub fn BreakpointManager::new() -> BreakpointManager {
  { breakpoints: {}, by_location: {}, next_id: 1 }
}

///|
/// Add a new breakpoint
pub fn BreakpointManager::add(
  self : BreakpointManager,
  func_idx : Int,
  offset : Int,
) -> Breakpoint {
  let id = self.next_id
  self.next_id = self.next_id + 1
  let bp = Breakpoint::new(id, func_idx, offset)
  self.breakpoints.set(id, bp)

  // Add to location index
  match self.by_location.get(func_idx) {
    Some(func_map) => func_map.set(offset, id)
    None => {
      let func_map : Map[Int, Int] = {}
      func_map.set(offset, id)
      self.by_location.set(func_idx, func_map)
    }
  }
  bp
}

///|
/// Add a conditional breakpoint
pub fn BreakpointManager::add_conditional(
  self : BreakpointManager,
  func_idx : Int,
  offset : Int,
  condition : String,
) -> Breakpoint {
  let id = self.next_id
  self.next_id = self.next_id + 1
  let bp = Breakpoint::with_condition(id, func_idx, offset, condition)
  self.breakpoints.set(id, bp)

  // Add to location index
  match self.by_location.get(func_idx) {
    Some(func_map) => func_map.set(offset, id)
    None => {
      let func_map : Map[Int, Int] = {}
      func_map.set(offset, id)
      self.by_location.set(func_idx, func_map)
    }
  }
  bp
}

///|
/// Remove a breakpoint by ID
pub fn BreakpointManager::remove(self : BreakpointManager, id : Int) -> Bool {
  match self.breakpoints.get(id) {
    Some(bp) => {
      // Remove from location index
      match self.by_location.get(bp.func_idx) {
        Some(func_map) => {
          let _ = func_map.remove(bp.offset)

        }
        None => ()
      }
      let _ = self.breakpoints.remove(id)
      true
    }
    None => false
  }
}

///|
/// Get breakpoint by ID
pub fn BreakpointManager::get(
  self : BreakpointManager,
  id : Int,
) -> Breakpoint? {
  self.breakpoints.get(id)
}

///|
/// Check if there's a breakpoint at the given location
pub fn BreakpointManager::at_location(
  self : BreakpointManager,
  func_idx : Int,
  offset : Int,
) -> Breakpoint? {
  match self.by_location.get(func_idx) {
    Some(func_map) =>
      match func_map.get(offset) {
        Some(id) => self.breakpoints.get(id)
        None => None
      }
    None => None
  }
}

///|
/// Check if there's an enabled breakpoint at the location
pub fn BreakpointManager::should_break(
  self : BreakpointManager,
  func_idx : Int,
  offset : Int,
) -> Bool {
  match self.at_location(func_idx, offset) {
    Some(bp) => bp.enabled
    None => false
  }
}

///|
/// Get all breakpoints
pub fn BreakpointManager::all(self : BreakpointManager) -> Array[Breakpoint] {
  let result : Array[Breakpoint] = []
  for bp in self.breakpoints.values() {
    result.push(bp)
  }
  result
}

///|
/// Get breakpoint count
pub fn BreakpointManager::count(self : BreakpointManager) -> Int {
  self.breakpoints.length()
}

///|
/// Clear all breakpoints
pub fn BreakpointManager::clear(self : BreakpointManager) -> Unit {
  self.breakpoints.clear()
  self.by_location.clear()
  self.next_id = 1
}

// ============ Stack Frame ============

///|
/// A frame in the call stack
pub(all) struct StackFrame {
  // Frame index (0 = top of stack)
  index : Int
  // Function index
  func_idx : Int
  // Instruction pointer (offset)
  ip : Int
  // Function name (if known)
  func_name : String
  // Source location (if available)
  location : SourceLocation?
  // Local variable count
  local_count : Int
}

///|
pub fn StackFrame::new(
  index : Int,
  func_idx : Int,
  ip : Int,
  func_name : String,
) -> StackFrame {
  { index, func_idx, ip, func_name, location: None, local_count: 0 }
}

///|
pub fn StackFrame::with_location(
  index : Int,
  func_idx : Int,
  ip : Int,
  func_name : String,
  location : SourceLocation,
) -> StackFrame {
  { index, func_idx, ip, func_name, location: Some(location), local_count: 0 }
}

///|
fn StackFrame::to_string(self : StackFrame) -> String {
  let loc = match self.location {
    Some(l) => " at \{l}"
    None => ""
  }
  "#\{self.index} \{self.func_name} (ip=\{self.ip})\{loc}"
}

///|
pub impl Show for StackFrame with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Stack Trace ============

///|
/// A full stack trace
pub(all) struct StackTrace {
  // Frames from top (most recent) to bottom
  frames : Array[StackFrame]
  // Optional error message
  error : String?
}

///|
pub fn StackTrace::new() -> StackTrace {
  { frames: [], error: None }
}

///|
pub fn StackTrace::with_error(error : String) -> StackTrace {
  { frames: [], error: Some(error) }
}

///|
pub fn StackTrace::push_frame(self : StackTrace, frame : StackFrame) -> Unit {
  self.frames.push(frame)
}

///|
pub fn StackTrace::depth(self : StackTrace) -> Int {
  self.frames.length()
}

///|
fn StackTrace::to_string(self : StackTrace) -> String {
  let mut result = ""
  match self.error {
    Some(e) => result = "Error: \{e}\n"
    None => ()
  }
  result = result + "Stack trace:\n"
  for frame in self.frames {
    result = result + "  \{frame}\n"
  }
  result
}

///|
pub impl Show for StackTrace with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Debug Context ============

///|
/// Main debug context that combines all debug features
pub(all) struct DebugContext {
  // Source mapping
  source_map : SourceMap
  // Breakpoint manager
  breakpoints : BreakpointManager
  // Is debugging enabled?
  mut enabled : Bool
  // Step mode (for single-stepping)
  mut step_mode : StepMode
  // Current stack trace (updated on break)
  mut current_trace : StackTrace?
}

///|
/// Step modes for debugging
pub enum StepMode {
  // Normal execution
  Continue
  // Step to next instruction
  StepInto
  // Step over function calls
  StepOver
  // Step out of current function
  StepOut
}

///|
fn StepMode::to_string(self : StepMode) -> String {
  match self {
    Continue => "continue"
    StepInto => "step_into"
    StepOver => "step_over"
    StepOut => "step_out"
  }
}

///|
pub impl Show for StepMode with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn DebugContext::new() -> DebugContext {
  {
    source_map: SourceMap::new(),
    breakpoints: BreakpointManager::new(),
    enabled: false,
    step_mode: Continue,
    current_trace: None,
  }
}

///|
pub fn DebugContext::enable(self : DebugContext) -> Unit {
  self.enabled = true
}

///|
pub fn DebugContext::disable(self : DebugContext) -> Unit {
  self.enabled = false
}

///|
/// Check if execution should pause at the given location
pub fn DebugContext::should_pause(
  self : DebugContext,
  func_idx : Int,
  offset : Int,
) -> Bool {
  if not(self.enabled) {
    return false
  }
  // Check step mode
  match self.step_mode {
    StepInto => true
    StepOver | StepOut =>
      // These would need call stack tracking to implement properly
      // For now, just check breakpoints
      self.breakpoints.should_break(func_idx, offset)
    Continue => self.breakpoints.should_break(func_idx, offset)
  }
}

///|
/// Called when execution pauses
pub fn DebugContext::on_pause(
  self : DebugContext,
  func_idx : Int,
  offset : Int,
) -> Unit {
  // Record hit if it's a breakpoint
  match self.breakpoints.at_location(func_idx, offset) {
    Some(bp) => bp.hit()
    None => ()
  }
  // Reset step mode to continue
  self.step_mode = Continue
}

///|
/// Set step mode
pub fn DebugContext::set_step_mode(
  self : DebugContext,
  mode : StepMode,
) -> Unit {
  self.step_mode = mode
}

///|
/// Get source location for display
pub fn DebugContext::location_string(
  self : DebugContext,
  func_idx : Int,
  offset : Int,
) -> String {
  let func_name = self.source_map.get_func_name(func_idx)
  match self.source_map.find_nearest(func_idx, offset) {
    Some(loc) => "\{func_name}: \{loc}"
    None => "\{func_name} @ offset \{offset}"
  }
}

///|
fn DebugContext::to_string(self : DebugContext) -> String {
  let status = if self.enabled { "enabled" } else { "disabled" }
  "DebugContext(\{status}, breakpoints=\{self.breakpoints.count()}, mappings=\{self.source_map.mapping_count()})"
}

///|
pub impl Show for DebugContext with output(self, logger) {
  logger.write_string(self.to_string())
}
