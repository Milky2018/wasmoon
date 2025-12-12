// Register Allocation
// Maps virtual registers to physical registers using linear scan algorithm
//
// This module provides:
// 1. Liveness analysis (live intervals, use-def chains)
// 2. Linear scan register allocation
// 3. Spilling to memory when registers are exhausted
// 4. Register coalescing for move elimination

// ============ Live Interval ============

///|
/// A program point - identifies a position in the VCode
pub(all) struct ProgPoint {
  block : Int // Block index
  inst : Int // Instruction index within block (-1 for block params)
  pos : ProgPos // Before or after the instruction
}

///|
/// Position relative to an instruction
pub enum ProgPos {
  Before // Before the instruction executes (uses happen here)
  After // After the instruction executes (defs happen here)
}

///|
/// Compare two program points using a block order map
/// This is used by the register allocator to correctly order points in non-linear CFGs
fn ProgPoint::compare_with_order(
  self : ProgPoint,
  other : ProgPoint,
  block_order : Map[Int, Int],
) -> Int {
  if self.block != other.block {
    let self_order = block_order.get(self.block).unwrap_or(self.block)
    let other_order = block_order.get(other.block).unwrap_or(other.block)
    return self_order - other_order
  }
  if self.inst != other.inst {
    return self.inst - other.inst
  }
  // Before < After
  match (self.pos, other.pos) {
    (Before, After) => -1
    (After, Before) => 1
    _ => 0
  }
}

///|
fn ProgPoint::to_string(self : ProgPoint) -> String {
  let pos_str = match self.pos {
    Before => "b"
    After => "a"
  }
  "(\{self.block}:\{self.inst}\{pos_str})"
}

///|
pub impl Show for ProgPoint with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// A live interval - the range where a virtual register is live
pub(all) struct LiveInterval {
  vreg : VReg
  start : ProgPoint // First use or definition
  mut end : ProgPoint // Last use
  // Use positions within the interval (for spill cost calculation)
  uses : Array[ProgPoint]
  // Register hint (e.g., from a move instruction)
  hint : PReg?
  // Assigned physical register (filled by allocator)
  mut assigned : PReg?
  // Spill slot if spilled (filled by allocator)
  mut spill_slot : Int?
  // Whether this interval crosses a function call (cannot use caller-saved registers)
  mut crosses_call : Bool
}

///|
fn LiveInterval::new(vreg : VReg, start : ProgPoint) -> LiveInterval {
  {
    vreg,
    start,
    end: start,
    uses: [start],
    hint: None,
    assigned: None,
    spill_slot: None,
    crosses_call: false,
  }
}

///|
/// Extend interval using block execution order for comparison
fn LiveInterval::extend_with_order(
  self : LiveInterval,
  point : ProgPoint,
  block_order : Map[Int, Int],
) -> Unit {
  if point.compare_with_order(self.end, block_order) > 0 {
    self.end = point
  }
  self.uses.push(point)
}

///|
fn LiveInterval::to_string(self : LiveInterval) -> String {
  let mut result = "\{self.vreg}: \{self.start} - \{self.end}"
  match self.assigned {
    Some(preg) => result = result + " -> \{preg}"
    None =>
      match self.spill_slot {
        Some(slot) => result = result + " -> [sp+\{slot}]"
        None => ()
      }
  }
  result
}

///|
pub impl Show for LiveInterval with output(self, logger) {
  logger.write_string(self.to_string())
}

// ============ Use-Def Chain ============

///|
/// Use-def information for a single vreg
pub(all) struct UseDefInfo {
  vreg : VReg
  mut def_point : ProgPoint? // Where this vreg is defined
  use_points : Array[ProgPoint] // Where this vreg is used
}

///|
fn UseDefInfo::new(vreg : VReg) -> UseDefInfo {
  { vreg, def_point: None, use_points: [] }
}

// ============ Liveness Analysis ============

///|
/// Debug: print liveness info
pub fn debug_liveness(liveness : LivenessResult) -> String {
  let mut result = "=== Liveness Debug ===\n"

  // Print use-def chains
  result = result + "Use-Def Chains:\n"
  for entry in liveness.use_def {
    let (vreg_id, info) = entry
    result = result + "  v\{vreg_id}: def=\{info.def_point}, uses=["
    for i, use_point in info.use_points {
      if i > 0 {
        result = result + ", "
      }
      result = result + "\{use_point}"
    }
    result = result + "]\n"
  }

  // Print live-in/out
  result = result + "\nLive-in/out:\n"
  for i, live_in_set in liveness.live_in {
    let in_list : Array[Int] = []
    for v in live_in_set {
      in_list.push(v)
    }
    let out_list : Array[Int] = []
    for v in liveness.live_out[i] {
      out_list.push(v)
    }
    result = result + "  block\{i}: in=\{in_list}, out=\{out_list}\n"
  }

  // Print intervals
  result = result + "\nIntervals:\n"
  for entry in liveness.intervals {
    let (_, interval) = entry
    result = result + "  \{interval}\n"
  }
  result
}

///|
/// Liveness analysis result
pub(all) struct LivenessResult {
  // Live intervals for each vreg
  intervals : Map[Int, LiveInterval]
  // Use-def chains
  use_def : Map[Int, UseDefInfo]
  // Block live-in sets (vregs live at block entry)
  live_in : Array[Set[Int]]
  // Block live-out sets (vregs live at block exit)
  live_out : Array[Set[Int]]
  // Block order: maps block ID -> linear position (for correct interval comparison)
  block_order : Map[Int, Int]
  // Call points (block_idx, inst_idx) - instructions that clobber caller-saved registers
  call_points : Array[ProgPoint]
}

///|
fn LivenessResult::new(num_blocks : Int) -> LivenessResult {
  let live_in : Array[Set[Int]] = []
  let live_out : Array[Set[Int]] = []
  for _ in 0..<num_blocks {
    live_in.push(Set::new())
    live_out.push(Set::new())
  }
  {
    intervals: {},
    use_def: {},
    live_in,
    live_out,
    block_order: {},
    call_points: [],
  }
}

///|
/// Compute reverse postorder of blocks (for linearizing the CFG)
fn compute_reverse_postorder(func : VCodeFunction) -> Map[Int, Int] {
  let visited : Set[Int] = Set::new()
  let postorder : Array[Int] = []

  // DFS to compute postorder
  fn dfs(
    func : VCodeFunction,
    block_id : Int,
    visited : Set[Int],
    postorder : Array[Int],
  ) {
    if visited.contains(block_id) {
      return
    }
    visited.add(block_id)

    // Visit successors first
    // Since block ID equals array index, we can use direct indexing
    if block_id >= 0 && block_id < func.blocks.length() {
      let block = func.blocks[block_id]
      match block.terminator {
        Some(term) =>
          match term {
            Jump(target) => dfs(func, target, visited, postorder)
            Branch(_, then_b, else_b) => {
              dfs(func, then_b, visited, postorder)
              dfs(func, else_b, visited, postorder)
            }
            BrTable(_, targets, default) => {
              for t in targets {
                dfs(func, t, visited, postorder)
              }
              dfs(func, default, visited, postorder)
            }
            Return(_) | Trap(_) => ()
          }
        None => ()
      }
    }

    // Add to postorder after visiting all successors
    postorder.push(block_id)
  }

  // Start DFS from block 0 (entry)
  if func.blocks.length() > 0 {
    dfs(func, func.blocks[0].id, visited, postorder)
  }

  // Also visit any unreachable blocks (shouldn't happen in valid code)
  for block in func.blocks {
    if !visited.contains(block.id) {
      dfs(func, block.id, visited, postorder)
    }
  }

  // Reverse postorder: reverse the postorder array
  // Map block ID -> position in reverse postorder
  let order : Map[Int, Int] = {}
  let n = postorder.length()
  for i, block_id in postorder {
    order.set(block_id, n - 1 - i)
  }
  order
}

///|
/// Compute liveness information for a VCode function
pub fn compute_liveness(func : VCodeFunction) -> LivenessResult {
  let result = LivenessResult::new(func.blocks.length())

  // Compute block order for correct interval comparison
  let block_order = compute_reverse_postorder(func)
  for entry in block_order {
    let (block_id, order) = entry
    result.block_order.set(block_id, order)
  }

  // Phase 1: Collect definitions and uses
  collect_defs_uses(func, result)

  // Phase 2: Compute live-in and live-out sets using dataflow analysis
  compute_live_sets(func, result)

  // Phase 3: Build live intervals from the live sets
  build_intervals(func, result)
  result
}

///|
/// Phase 1: Collect all definitions and uses
fn collect_defs_uses(func : VCodeFunction, result : LivenessResult) -> Unit {
  // Record function parameters as definitions at the start
  for param in func.params {
    let info = UseDefInfo::new(param)
    info.def_point = Some({ block: 0, inst: -1, pos: After })
    result.use_def.set(param.id, info)
  }

  // Process each block
  for block_idx, block in func.blocks {
    // Block parameters receive values from predecessor block moves (SSA deconstruction).
    // Add a use point at block entry to keep them live through the block.
    for param in block.params {
      let info = match result.use_def.get(param.id) {
        Some(existing) => existing
        None => {
          let new_info = UseDefInfo::new(param)
          result.use_def.set(param.id, new_info)
          new_info
        }
      }
      // Add use point at block entry (before first instruction)
      info.use_points.push({ block: block_idx, inst: 0, pos: Before })
    }

    // Process instructions
    for inst_idx, inst in block.insts {
      // Record call points for caller-saved register handling
      if inst.opcode is CallIndirect(_, _) {
        result.call_points.push({ block: block_idx, inst: inst_idx, pos: After })
      }

      // Record uses (before the instruction)
      for use_reg in inst.uses {
        match use_reg {
          Virtual(vreg) => {
            let info = match result.use_def.get(vreg.id) {
              Some(existing) => existing
              None => {
                let new_info = UseDefInfo::new(vreg)
                result.use_def.set(vreg.id, new_info)
                new_info
              }
            }
            info.use_points.push({
              block: block_idx,
              inst: inst_idx,
              pos: Before,
            })
          }
          Physical(_) => () // Physical regs don't need liveness tracking
        }
      }

      // Record definitions (after the instruction)
      for def in inst.defs {
        match def.reg {
          Virtual(vreg) => {
            let info = match result.use_def.get(vreg.id) {
              Some(existing) => existing
              None => {
                let new_info = UseDefInfo::new(vreg)
                result.use_def.set(vreg.id, new_info)
                new_info
              }
            }
            // For SSA deconstruction, the same vreg may be defined in multiple
            // blocks on different paths. Keep the earliest definition in
            // execution order (using block_order for comparison).
            let new_def : ProgPoint = {
              block: block_idx,
              inst: inst_idx,
              pos: After,
            }
            match info.def_point {
              None => info.def_point = Some(new_def)
              Some(existing_def) =>
                // Keep the earlier definition (lower order = earlier in execution)
                if new_def.compare_with_order(existing_def, result.block_order) <
                  0 {
                  info.def_point = Some(new_def)
                }
            }
          }
          Physical(_) => ()
        }
      }
    }

    // Record uses in terminator
    if block.terminator is Some(term) {
      match term {
        Branch(cond, _, _) =>
          match cond {
            Virtual(vreg) => {
              let info = match result.use_def.get(vreg.id) {
                Some(existing) => existing
                None => {
                  let new_info = UseDefInfo::new(vreg)
                  result.use_def.set(vreg.id, new_info)
                  new_info
                }
              }
              let inst_idx = block.insts.length()
              info.use_points.push({
                block: block_idx,
                inst: inst_idx,
                pos: Before,
              })
            }
            Physical(_) => ()
          }
        Return(values) =>
          for value in values {
            match value {
              Virtual(vreg) => {
                let info = match result.use_def.get(vreg.id) {
                  Some(existing) => existing
                  None => {
                    let new_info = UseDefInfo::new(vreg)
                    result.use_def.set(vreg.id, new_info)
                    new_info
                  }
                }
                let inst_idx = block.insts.length()
                info.use_points.push({
                  block: block_idx,
                  inst: inst_idx,
                  pos: Before,
                })
              }
              Physical(_) => ()
            }
          }
        _ => ()
      }
    }
  }
}

///|
/// Phase 2: Compute live-in and live-out sets
fn compute_live_sets(func : VCodeFunction, result : LivenessResult) -> Unit {
  // Fixed-point iteration for dataflow analysis
  // live_in[B] = use[B] ∪ (live_out[B] - def[B])
  // live_out[B] = ∪{S ∈ succ[B]} live_in[S]

  // First, compute use and def sets for each block
  let block_use : Array[Set[Int]] = []
  let block_def : Array[Set[Int]] = []
  for block in func.blocks {
    let use_set : Set[Int] = Set::new()
    let def_set : Set[Int] = Set::new()

    // Block parameters are NOT defs in SSA deconstruction
    // They represent values passed from predecessors, so they're live-in
    // (Do not add block params to def_set)

    // Process instructions
    for inst in block.insts {
      // Uses that are not already defined locally
      for use_reg in inst.uses {
        match use_reg {
          Virtual(vreg) =>
            if !def_set.contains(vreg.id) {
              use_set.add(vreg.id)
            }
          Physical(_) => ()
        }
      }
      // Definitions
      for def in inst.defs {
        match def.reg {
          Virtual(vreg) => def_set.add(vreg.id)
          Physical(_) => ()
        }
      }
    }

    // Terminator uses
    if block.terminator is Some(term) {
      match term {
        Branch(cond, _, _) =>
          match cond {
            Virtual(vreg) =>
              if !def_set.contains(vreg.id) {
                use_set.add(vreg.id)
              }
            Physical(_) => ()
          }
        Return(values) =>
          for value in values {
            match value {
              Virtual(vreg) =>
                if !def_set.contains(vreg.id) {
                  use_set.add(vreg.id)
                }
              Physical(_) => ()
            }
          }
        _ => ()
      }
    }
    block_use.push(use_set)
    block_def.push(def_set)
  }

  // Get successors for each block
  fn get_successors(func : VCodeFunction, block_idx : Int) -> Array[Int] {
    let succs : Array[Int] = []
    match func.blocks[block_idx].terminator {
      Some(term) =>
        match term {
          Jump(target) => succs.push(target)
          Branch(_, then_b, else_b) => {
            succs.push(then_b)
            succs.push(else_b)
          }
          BrTable(_, targets, default) => {
            for t in targets {
              succs.push(t)
            }
            succs.push(default)
          }
          Return(_) | Trap(_) => ()
        }
      None => ()
    }
    succs
  }

  // Fixed-point iteration
  let mut changed = true
  while changed {
    changed = false
    // Process blocks in reverse order for faster convergence
    for block_idx = func.blocks.length() - 1
        block_idx >= 0
        block_idx = block_idx - 1 {
      // live_out[B] = ∪{S ∈ succ[B]} live_in[S]
      let succs = get_successors(func, block_idx)
      for succ in succs {
        for vreg_id in result.live_in[succ] {
          if !result.live_out[block_idx].contains(vreg_id) {
            result.live_out[block_idx].add(vreg_id)
            changed = true
          }
        }
      }

      // live_in[B] = use[B] ∪ (live_out[B] - def[B])
      // First add all uses
      for vreg_id in block_use[block_idx] {
        if !result.live_in[block_idx].contains(vreg_id) {
          result.live_in[block_idx].add(vreg_id)
          changed = true
        }
      }
      // Then add live-out minus defs
      for vreg_id in result.live_out[block_idx] {
        if !block_def[block_idx].contains(vreg_id) &&
          !result.live_in[block_idx].contains(vreg_id) {
          result.live_in[block_idx].add(vreg_id)
          changed = true
        }
      }
    }
  }
}

///|
/// Phase 3: Build live intervals from use-def info
fn build_intervals(func : VCodeFunction, result : LivenessResult) -> Unit {
  // Get block order for correct interval comparison
  let block_order = result.block_order

  // For each vreg, create an interval spanning from def to last use
  for entry in result.use_def {
    let (vreg_id, info) = entry
    let start = match info.def_point {
      Some(def) => def
      None =>
        // If no def point, use the first use (shouldn't happen in valid code)
        if info.use_points.length() > 0 {
          info.use_points[0]
        } else {
          continue // No uses or defs, skip
        }
    }
    let interval = LiveInterval::new(info.vreg, start)

    // Extend to cover all uses (using block order for correct comparison)
    for use_point in info.use_points {
      interval.extend_with_order(use_point, block_order)
    }

    // Extend to cover live-in blocks - the interval needs to span from
    // block entry through all uses in that block
    for block_idx, live_in_set in result.live_in {
      if live_in_set.contains(vreg_id) {
        // The vreg is live at the start of this block
        // Extend from block entry
        let entry_point = { block: block_idx, inst: -1, pos: Before }
        interval.extend_with_order(entry_point, block_order)
        // Also extend to end of block if live-out (already handled below)
      }
    }

    // Extend to cover live-out of blocks where this vreg is live
    for block_idx, live_out_set in result.live_out {
      if live_out_set.contains(vreg_id) {
        // The vreg is live at the end of this block
        let block = func.blocks[block_idx]
        let end_point = {
          block: block_idx,
          inst: block.insts.length(),
          pos: After,
        }
        interval.extend_with_order(end_point, block_order)
      }
    }

    // Check if this interval crosses any call point
    // If so, it cannot be assigned to a caller-saved register
    for call_point in result.call_points {
      // An interval crosses a call if:
      // - The call is after the interval's start AND before the interval's end
      let start_cmp = interval.start.compare_with_order(call_point, block_order)
      let end_cmp = interval.end.compare_with_order(call_point, block_order)
      // start <= call_point < end (interval is live across the call)
      if start_cmp <= 0 && end_cmp > 0 {
        interval.crosses_call = true
        break
      }
    }
    result.intervals.set(vreg_id, interval)
  }
}

// ============ Linear Scan Register Allocator ============

///|
/// Register allocation result
pub(all) struct RegAllocResult {
  // Map from vreg id to assigned physical register
  assignments : Map[Int, PReg]
  // Map from vreg id to spill slot (if spilled)
  spill_slots : Map[Int, Int]
  // Total number of spill slots used
  mut num_spill_slots : Int
  // Instructions to insert (for spills/reloads)
  spills : Array[SpillInfo]
  reloads : Array[ReloadInfo]
}

///|
/// Information about a spill
pub(all) struct SpillInfo {
  vreg : VReg
  slot : Int
  point : ProgPoint
}

///|
/// Information about a reload
pub(all) struct ReloadInfo {
  vreg : VReg
  slot : Int
  preg : PReg
  point : ProgPoint
}

///|
/// Linear scan register allocator
pub(all) struct LinearScanAllocator {
  // Available physical registers by class
  int_regs : Array[PReg]
  float_regs : Array[PReg]
  // Callee-saved registers for cross-call allocation (may exclude X23)
  callee_saved_int_regs : Array[PReg]
  // Callee-saved float registers for cross-call allocation (D8-D15)
  callee_saved_float_regs : Array[PReg]
  // Current state
  mut active : Array[LiveInterval] // Intervals currently occupying registers
  mut next_spill_slot : Int
  // Block order for correct interval comparison in non-linear CFGs
  block_order : Map[Int, Int]
}

///|
pub fn LinearScanAllocator::new(
  int_regs : Array[PReg],
  float_regs : Array[PReg],
  callee_saved_int_regs : Array[PReg],
  callee_saved_float_regs? : Array[PReg] = [],
) -> LinearScanAllocator {
  {
    int_regs,
    float_regs,
    callee_saved_int_regs,
    callee_saved_float_regs,
    active: [],
    next_spill_slot: 0,
    block_order: {},
  }
}

///|
/// Allocate registers for a function
pub fn LinearScanAllocator::allocate(
  self : LinearScanAllocator,
  func : VCodeFunction,
  liveness : LivenessResult,
) -> RegAllocResult {
  // Copy block order from liveness result
  for entry in liveness.block_order {
    let (block_id, order) = entry
    self.block_order.set(block_id, order)
  }
  let result : RegAllocResult = {
    assignments: {},
    spill_slots: {},
    num_spill_slots: 0,
    spills: [],
    reloads: [],
  }

  // Pre-assign function parameters to ABI registers
  // JIT ABI: X0 = func_table, X1 = memory_base, X2 = memory_size, args in X3-X10
  // So WASM parameters start at X3
  // NOTE: Only pre-assign if the parameter doesn't cross a call, otherwise
  // it will be handled by the normal allocation process (which will use callee-saved)
  // NOTE: Only the first 8 params (0-7) are in registers. Params 8+ are on stack.
  let max_reg_params = 8
  for i, param in func.params {
    // Skip stack parameters - they're not in registers
    if i >= max_reg_params {
      continue
    }
    match liveness.intervals.get(param.id) {
      Some(interval) =>
        if interval.crosses_call {
          // Parameter crosses a call, don't pre-assign to caller-saved register
          // The allocation loop below will handle it and assign to callee-saved
          continue
        } else {
          // Safe to pre-assign to ABI register
          let preg = match param.class {
            Int => { index: i + 3, class: Int } // X3, X4, X5, ... X10
            Float32 | Float64 => { index: i, class: param.class } // D0, D1, D2, ... D7
          }
          result.assignments.set(param.id, preg)
          interval.assigned = Some(preg)
          self.active.push(interval)
        }
      None => ()
    }
  }

  // Sort intervals by start point using block order
  let intervals : Array[LiveInterval] = []
  for entry in liveness.intervals {
    let (_, interval) = entry
    // Skip already-assigned parameters
    if interval.assigned is Some(_) {
      continue
    }
    intervals.push(interval)
  }
  let block_order = self.block_order
  intervals.sort_by(fn(a, b) {
    a.start.compare_with_order(b.start, block_order)
  })

  // Process intervals in order of start point
  for interval in intervals {
    // Expire old intervals that end before this one starts
    self.expire_old_intervals(interval)

    // Get available registers for this class
    // If interval crosses a call, only use callee-saved registers
    let avail_regs = if interval.crosses_call {
      match interval.vreg.class {
        Int => self.callee_saved_int_regs
        Float32 | Float64 =>
          // Use callee-saved FPRs (D8-D15) for floats that must survive across calls
          self.callee_saved_float_regs
      }
    } else {
      match interval.vreg.class {
        Int => self.int_regs
        Float32 | Float64 => self.float_regs
      }
    }

    // Try to allocate a register
    let assigned = self.try_allocate_reg(interval, avail_regs)
    match assigned {
      Some(preg) => {
        // Preserve the original vreg's class when storing the assignment
        // This is important for Bitcast to distinguish f32 vs f64 operations
        let assigned_preg : PReg = {
          index: preg.index,
          class: interval.vreg.class,
        }
        interval.assigned = Some(assigned_preg)
        self.active.push(interval)
        result.assignments.set(interval.vreg.id, assigned_preg)
      }
      None =>
        // Need to spill
        self.spill_interval(func, interval, result)
    }
  }
  result.num_spill_slots = self.next_spill_slot
  result
}

///|
/// Remove intervals that have ended
fn LinearScanAllocator::expire_old_intervals(
  self : LinearScanAllocator,
  current : LiveInterval,
) -> Unit {
  // Sort active by end point using block order, and remove those that end before current starts
  let block_order = self.block_order
  self.active.sort_by(fn(a, b) { a.end.compare_with_order(b.end, block_order) })
  let new_active : Array[LiveInterval] = []
  for interval in self.active {
    // Check if interval ends before current starts
    // CRITICAL FIX: In the same basic block, be conservative about register reuse.
    // We require at least 2 instructions gap before expiring an interval.
    // This prevents two issues:
    // 1. Same instruction use-def: v25 = add x21, v22 cannot become x23 = add x21, x23
    // 2. Adjacent definitions: dead values should not immediately share registers
    //    with the next definition (e.g., d0 = ldf 1; d0 = ldf 2 is wrong)
    let overlaps = if interval.end.block == current.start.block {
      // Same block: require at least 2 instruction gap
      // interval.end.inst >= current.start.inst - 1 means they're adjacent or same
      interval.end.inst >= current.start.inst - 1
    } else {
      // Different blocks: use normal comparison
      let cmp = interval.end.compare_with_order(current.start, block_order)
      cmp >= 0
    }
    if overlaps {
      new_active.push(interval)
    }
  }
  self.active = new_active
}

///|
/// Check if two register classes are compatible (can use same physical registers)
fn reg_class_eq(a : RegClass, b : RegClass) -> Bool {
  match (a, b) {
    (Int, Int) => true
    (Float32, Float32)
    | (Float32, Float64)
    | (Float64, Float32)
    | (Float64, Float64) => true
    _ => false
  }
}

///|
/// Try to allocate a physical register for an interval
fn LinearScanAllocator::try_allocate_reg(
  self : LinearScanAllocator,
  interval : LiveInterval,
  avail_regs : Array[PReg],
) -> PReg? {
  // Build set of registers currently in use
  let used : Set[Int] = Set::new()
  for active in self.active {
    match active.assigned {
      Some(preg) =>
        if reg_class_eq(preg.class, interval.vreg.class) {
          used.add(preg.index)
        }
      None => ()
    }
  }

  // Try hint first if available
  match interval.hint {
    Some(hint) => if !used.contains(hint.index) { return Some(hint) }
    None => ()
  }

  // Find a free register
  for preg in avail_regs {
    if !used.contains(preg.index) {
      return Some(preg)
    }
  }
  None
}

///|
/// Spill an interval to memory
fn LinearScanAllocator::spill_interval(
  self : LinearScanAllocator,
  func : VCodeFunction,
  interval : LiveInterval,
  result : RegAllocResult,
) -> Unit {
  ignore(func)
  // Allocate a spill slot
  let slot = self.next_spill_slot
  self.next_spill_slot = slot + 1
  interval.spill_slot = Some(slot)
  result.spill_slots.set(interval.vreg.id, slot)

  // Record spill at definition point
  match interval.start.pos {
    After =>
      result.spills.push({ vreg: interval.vreg, slot, point: interval.start })
    Before => ()
  }

  // For each use, we need to reload into a temporary
  // This is a simplified approach - a real allocator would be smarter
  for use_point in interval.uses {
    // Get a register for this reload (use first available)
    let avail_regs = match interval.vreg.class {
      Int => self.int_regs
      Float32 | Float64 => self.float_regs
    }
    if avail_regs.length() > 0 {
      result.reloads.push({
        vreg: interval.vreg,
        slot,
        preg: avail_regs[0],
        point: use_point,
      })
    }
  }
}

// ============ Apply Allocation ============

// Scratch registers for spill/reload (not allocatable)
// X16 is used for integer spills, we can use X17 if needed

///|
/// Apply register allocation results to a VCode function
/// Handles spilled registers by inserting StackLoad/StackStore instructions
pub fn apply_allocation(
  func : VCodeFunction,
  alloc : RegAllocResult,
) -> VCodeFunction {
  let new_func = VCodeFunction::new(func.name)
  new_func.next_vreg_id = func.next_vreg_id
  new_func.num_spill_slots = alloc.num_spill_slots

  // Convert function parameters
  let max_reg_params = 8 // Params 0-7 are passed in registers, 8+ on stack
  for i, param in func.params {
    match alloc.assignments.get(param.id) {
      Some(preg) => {
        // Parameter is assigned to physical register
        // We still track it as vreg but note the assignment
        let new_vreg = { id: param.id, class: param.class }
        new_func.params.push(new_vreg)
        // Store the physical register assignment for emit_prologue
        // For register params (0-7): only need move if not in default ABI register
        // For stack params (8+): ALWAYS need to store the assigned register
        //   because emit_prologue must load them from the stack
        if i >= max_reg_params {
          // Stack param - always store the assigned register
          new_func.param_pregs.push(Some(preg))
        } else {
          // Register param - check if it needs a move from default location
          let default_preg : PReg = match param.class {
            Int => { index: i + 3, class: Int } // X3-X10
            Float32 | Float64 => { index: i, class: param.class } // D0-D7
          }
          if preg.index != default_preg.index {
            new_func.param_pregs.push(Some(preg))
          } else {
            new_func.param_pregs.push(None) // No move needed
          }
        }
      }
      None => {
        new_func.params.push(param)
        new_func.param_pregs.push(None)
      }
    }
  }

  // Copy results
  for r in func.results {
    new_func.results.push(r)
  }

  // Copy result types for multi-value return support
  for ty in func.result_types {
    new_func.result_types.push(ty)
  }

  // Process each block
  for block in func.blocks {
    let new_block = new_func.new_block()

    // Copy block params
    for param in block.params {
      new_block.params.push(param)
    }

    // Block-level scratch register counter to avoid aliasing across instructions
    let mut block_scratch_idx = 0

    // Process instructions
    for inst in block.insts {
      // First, insert reload instructions for any spilled uses
      // Track which scratch registers are used for each spilled vreg
      let spill_regs : Map[Int, PReg] = {}

      // Check if this is a CallIndirect instruction - needs special handling
      let is_call_indirect = inst.opcode is CallIndirect(_, _)

      // For CallIndirect with many spilled args, we use a special strategy:
      // - func_ptr (uses[0]): reload to X18
      // - register args (uses[1-8]): if spilled, reload to X16/X17 (max 2)
      // - stack args (uses[9+]): if spilled, use spilled register encoding (emit handles them)
      //
      // X16, X17 are the only truly safe scratch registers because:
      // - X3-X10: may hold function parameters
      // - X11-X15: used by CallIndirect marshalling
      // - X18: used by CallIndirect for func_ptr
      // - X19+: allocatable callee-saved registers

      let mut inst_spill_idx = 0
      for i, use_reg in inst.uses {
        match use_reg {
          Virtual(vreg) =>
            if alloc.assignments.get(vreg.id) is None {
              // This vreg is spilled, need to reload
              match alloc.spill_slots.get(vreg.id) {
                Some(slot) => {
                  let scratch_class = match vreg.class {
                    Float32 | Float64 => Float64
                    _ => vreg.class
                  }

                  // Determine how to handle this spilled use
                  if is_call_indirect && i == 0 {
                    // CallIndirect's func_ptr (first use): reload directly to X18
                    let scratch_preg : PReg = {
                      index: 18,
                      class: scratch_class,
                    }
                    spill_regs.set(vreg.id, scratch_preg)
                    let reload_inst = VCodeInst::new(StackLoad(slot * 8))
                    reload_inst.add_def({ reg: Physical(scratch_preg) })
                    new_block.add_inst(reload_inst)
                  } else if is_call_indirect && i >= 1 {
                    // CallIndirect's args (all args, including register args 0-7 and stack args 8+)
                    // Use spilled register encoding - emit code will handle the load directly
                    // This avoids X16/X17 aliasing when many args are spilled
                    let spilled_preg = PReg::spilled(slot, scratch_class)
                    spill_regs.set(vreg.id, spilled_preg)
                    // Don't insert reload - emit code will load directly from spill slot
                  } else {
                    // Regular spilled uses (non-CallIndirect instructions)
                    // Use X16, X17 as scratch registers
                    let scratch_indices = [16, 17]
                    let scratch_preg : PReg = {
                      index: scratch_indices[inst_spill_idx % 2],
                      class: scratch_class,
                    }
                    inst_spill_idx = inst_spill_idx + 1
                    block_scratch_idx = block_scratch_idx + 1
                    spill_regs.set(vreg.id, scratch_preg)
                    let reload_inst = VCodeInst::new(StackLoad(slot * 8))
                    reload_inst.add_def({ reg: Physical(scratch_preg) })
                    new_block.add_inst(reload_inst)
                  }
                }
                None => ()
              }
            }
          Physical(_) => ()
        }
      }

      // Check if any definitions are spilled - collect ALL spilled defs
      let spilled_defs : Array[(VReg, Int)] = []
      for def in inst.defs {
        match def.reg {
          Virtual(vreg) =>
            if alloc.assignments.get(vreg.id) is None {
              match alloc.spill_slots.get(vreg.id) {
                Some(slot) => spilled_defs.push((vreg, slot))
                None => ()
              }
            }
          Physical(_) => ()
        }
      }

      // Create new instruction with rewritten registers
      let new_inst = VCodeInst::new(inst.opcode)

      // Rewrite definitions - use X16, X17 as scratch for spilled defs
      let spill_scratch_map : Map[Int, PReg] = {} // vreg.id -> scratch preg
      for def in inst.defs {
        match def.reg {
          Virtual(vreg) =>
            match alloc.assignments.get(vreg.id) {
              Some(preg) => new_inst.add_def({ reg: Physical(preg) })
              None => {
                // Spilled: use X16, X17 as scratch registers
                let scratch_class = match vreg.class {
                  Float32 | Float64 => Float64
                  _ => vreg.class
                }
                let scratch_indices = [16, 17]
                let scratch_preg : PReg = {
                  index: scratch_indices[block_scratch_idx % 2],
                  class: scratch_class,
                }
                block_scratch_idx = block_scratch_idx + 1
                spill_scratch_map.set(vreg.id, scratch_preg)
                new_inst.add_def({ reg: Physical(scratch_preg) })
              }
            }
          Physical(_) => new_inst.add_def(def)
        }
      }

      // Rewrite uses
      for use_reg in inst.uses {
        match use_reg {
          Virtual(vreg) =>
            match alloc.assignments.get(vreg.id) {
              Some(preg) => new_inst.add_use(Physical(preg))
              None =>
                // Spilled: use the scratch register we reloaded into
                match spill_regs.get(vreg.id) {
                  Some(scratch_preg) => new_inst.add_use(Physical(scratch_preg))
                  None => {
                    // Fallback: use X16 if somehow not in spill_regs
                    let scratch_preg : PReg = { index: 16, class: vreg.class }
                    new_inst.add_use(Physical(scratch_preg))
                  }
                }
            }
          Physical(_) => new_inst.add_use(use_reg)
        }
      }
      new_block.add_inst(new_inst)

      // Insert spill instructions after the defining instruction for ALL spilled defs
      for entry in spilled_defs {
        let (vreg, slot) = entry
        let spill_inst = VCodeInst::new(StackStore(slot * 8))
        let scratch_preg = spill_scratch_map.get(vreg.id).unwrap()
        spill_inst.add_use(Physical(scratch_preg))
        new_block.add_inst(spill_inst)
      }
    }

    // Rewrite terminator
    match block.terminator {
      Some(term) => {
        let new_term = match term {
          Jump(target) => Jump(target)
          Branch(cond, then_b, else_b) => {
            // Handle spilled condition register
            let new_cond = rewrite_reg_with_spill(cond, alloc, new_block)
            Branch(new_cond, then_b, else_b)
          }
          BrTable(index, targets, default) => {
            // Handle spilled index register
            let new_index = rewrite_reg_with_spill(index, alloc, new_block)
            BrTable(new_index, targets, default)
          }
          Return(values) => {
            // Handle Return specially to use block-level scratch counter
            // This ensures each spilled value uses a different scratch register
            let new_values : Array[Reg] = []
            for v in values {
              match v {
                Virtual(vreg) =>
                  match alloc.assignments.get(vreg.id) {
                    Some(preg) => new_values.push(Physical(preg))
                    None =>
                      // Spilled: insert reload and use scratch register from block pool
                      match alloc.spill_slots.get(vreg.id) {
                        Some(slot) => {
                          // Use X16, X17 as scratch registers
                          // These are the only safe scratch registers
                          let scratch_class = match vreg.class {
                            Float32 | Float64 => Float64
                            _ => vreg.class
                          }
                          let scratch_indices = [16, 17]
                          let scratch_preg : PReg = {
                            index: scratch_indices[block_scratch_idx % 2],
                            class: scratch_class,
                          }
                          block_scratch_idx = block_scratch_idx + 1
                          let reload_inst = VCodeInst::new(StackLoad(slot * 8))
                          reload_inst.add_def({ reg: Physical(scratch_preg) })
                          new_block.add_inst(reload_inst)
                          new_values.push(Physical(scratch_preg))
                        }
                        None => new_values.push(v) // Should not happen
                      }
                  }
                Physical(_) => new_values.push(v)
              }
            }
            Return(new_values)
          }
          Trap(msg) => Trap(msg)
        }
        new_block.set_terminator(new_term)
      }
      None => ()
    }
  }
  new_func
}

///|
/// Rewrite a register, inserting reload if spilled
fn rewrite_reg_with_spill(
  reg : Reg,
  alloc : RegAllocResult,
  block : VCodeBlock,
) -> Reg {
  match reg {
    Virtual(vreg) =>
      match alloc.assignments.get(vreg.id) {
        Some(preg) => Physical(preg)
        None =>
          // Spilled: insert reload and use scratch register
          match alloc.spill_slots.get(vreg.id) {
            Some(slot) => {
              let scratch_preg : PReg = { index: 16, class: vreg.class }
              let reload_inst = VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: Physical(scratch_preg) })
              block.add_inst(reload_inst)
              Physical(scratch_preg)
            }
            None => reg // Should not happen
          }
      }
    Physical(_) => reg
  }
}

///|
#warnings("-unused_value")
fn rewrite_reg(reg : Reg, alloc : RegAllocResult) -> Reg {
  match reg {
    Virtual(vreg) =>
      match alloc.assignments.get(vreg.id) {
        Some(preg) => Physical(preg)
        None => reg // Keep as virtual if not allocated (spilled)
      }
    Physical(_) => reg
  }
}

// ============ Dead Code Elimination ============

///|
/// Check if an opcode has side effects (cannot be eliminated even if dead)
fn has_side_effects(opcode : VCodeOpcode) -> Bool {
  match opcode {
    // Memory stores have side effects
    Store(_, _) | StackStore(_) => true
    // Bounds check can trap
    BoundsCheck(_, _) => true
    // Function calls have side effects
    CallIndirect(_, _) => true
    // Everything else is pure computation
    _ => false
  }
}

///|
/// Eliminate dead code from a VCode function
/// Removes instructions that define vregs which are never used
pub fn eliminate_dead_code(func : VCodeFunction) -> VCodeFunction {
  // Step 1: Collect all used vregs
  let used_vregs : Set[Int] = Set::new()

  // Add function parameters (they're implicitly used)
  for param in func.params {
    used_vregs.add(param.id)
  }

  // Scan all instructions and terminators for uses
  for block in func.blocks {
    // Block parameters are used (they receive values from jumps)
    for param in block.params {
      used_vregs.add(param.id)
    }

    // Instruction uses
    for inst in block.insts {
      for use_reg in inst.uses {
        match use_reg {
          Virtual(vreg) => used_vregs.add(vreg.id)
          Physical(_) => ()
        }
      }
    }

    // Terminator uses
    match block.terminator {
      Some(term) =>
        match term {
          Branch(cond, _, _) =>
            match cond {
              Virtual(vreg) => used_vregs.add(vreg.id)
              Physical(_) => ()
            }
          BrTable(index, _, _) =>
            match index {
              Virtual(vreg) => used_vregs.add(vreg.id)
              Physical(_) => ()
            }
          Return(values) =>
            for v in values {
              match v {
                Virtual(vreg) => used_vregs.add(vreg.id)
                Physical(_) => ()
              }
            }
          Jump(_) | Trap(_) => ()
        }
      None => ()
    }
  }

  // Step 2: Build new function without dead instructions
  let new_func = VCodeFunction::new(func.name)
  new_func.next_vreg_id = func.next_vreg_id

  // Copy params and results
  for param in func.params {
    new_func.params.push(param)
  }
  for result in func.results {
    new_func.results.push(result)
  }
  // Copy result types for multi-value return support
  for ty in func.result_types {
    new_func.result_types.push(ty)
  }

  // Copy blocks, filtering out dead instructions
  for block in func.blocks {
    let new_block = new_func.new_block()

    // Copy block params
    for param in block.params {
      new_block.params.push(param)
    }

    // Filter instructions: keep if has side effects OR defines a used vreg
    for inst in block.insts {
      let should_keep = if has_side_effects(inst.opcode) {
        true
      } else {
        // Keep if any defined vreg is used
        let mut any_def_used = false
        for def in inst.defs {
          match def.reg {
            Virtual(vreg) =>
              if used_vregs.contains(vreg.id) {
                any_def_used = true
              }
            Physical(_) => any_def_used = true // Always keep physical reg defs
          }
        }
        // Also keep instructions with no defs (shouldn't happen for pure ops, but be safe)
        any_def_used || inst.defs.is_empty()
      }
      if should_keep {
        new_block.add_inst(inst)
      }
    }

    // Copy terminator
    match block.terminator {
      Some(term) => new_block.set_terminator(term)
      None => ()
    }
  }
  new_func
}

// ============ Convenience API ============

///|
/// Allocate registers for a function using default AArch64 register set
pub fn allocate_registers_aarch64(func : VCodeFunction) -> VCodeFunction {
  // Step 0: Eliminate dead code first
  let func = eliminate_dead_code(func)

  // Check if function needs extra results buffer (uses X23)
  // This is true if:
  // 1. Function returns more than 2 values (needs_extra_results_ptr)
  // 2. Function calls other functions that return more than 2 values (calls_multi_value_function)
  let calls_multi = func.calls_multi_value_function()
  let needs_extra = func.needs_extra_results_ptr()
  let needs_x23_reserved = needs_extra || calls_multi

  // Build allocatable register pool:
  // 1. Scratch regs (caller-saved, no save needed) - use first
  // 2. Callee-saved regs (must save/restore) - use when scratch exhausted
  let int_regs : Array[PReg] = []
  let callee_saved_int_regs : Array[PReg] = []
  for r in allocatable_scratch_regs() {
    int_regs.push(r)
  }
  for r in allocatable_callee_saved_regs() {
    // X23 (index 23) is reserved for extra_results_buffer when needed
    if needs_x23_reserved && r.index == 23 {
      continue
    }
    int_regs.push(r)
    callee_saved_int_regs.push(r)
  }
  // Float regs pool: D0-D7 (caller-saved) + D8-D15 (callee-saved)
  // This mirrors the int_regs structure which includes both scratch and callee-saved
  let float_regs : Array[PReg] = []
  for r in aapcs64_arg_fprs() {
    float_regs.push(r)
  }
  for r in callee_saved_fprs() {
    float_regs.push(r)
  }
  let callee_saved_float_regs = callee_saved_fprs()

  // Compute liveness
  let liveness = compute_liveness(func)

  // Allocate
  let allocator = LinearScanAllocator::new(
    int_regs,
    float_regs,
    callee_saved_int_regs,
    callee_saved_float_regs~,
  )
  let alloc_result = allocator.allocate(func, liveness)

  // Apply allocation
  let allocated_func = apply_allocation(func, alloc_result)
  allocated_func
}
