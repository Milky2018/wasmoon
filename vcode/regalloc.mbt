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
fn ProgPoint::compare(self : ProgPoint, other : ProgPoint) -> Int {
  if self.block != other.block {
    return self.block - other.block
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
  }
}

///|
fn LiveInterval::extend(self : LiveInterval, point : ProgPoint) -> Unit {
  if point.compare(self.end) > 0 {
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
}

///|
fn LivenessResult::new(num_blocks : Int) -> LivenessResult {
  let live_in : Array[Set[Int]] = []
  let live_out : Array[Set[Int]] = []
  for _ in 0..<num_blocks {
    live_in.push(Set::new())
    live_out.push(Set::new())
  }
  { intervals: {}, use_def: {}, live_in, live_out }
}

///|
/// Compute liveness information for a VCode function
pub fn compute_liveness(func : VCodeFunction) -> LivenessResult {
  let result = LivenessResult::new(func.blocks.length())

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
    // Block parameters are definitions at block entry
    for param in block.params {
      let info = match result.use_def.get(param.id) {
        Some(existing) => existing
        None => {
          let new_info = UseDefInfo::new(param)
          result.use_def.set(param.id, new_info)
          new_info
        }
      }
      info.def_point = Some({ block: block_idx, inst: -1, pos: After })
    }

    // Process instructions
    for inst_idx, inst in block.insts {
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
            // Only set def_point if not already set (keep earliest definition)
            // This is important for block parameters that may be redefined
            // in parallel copy moves
            if info.def_point is None {
              info.def_point = Some({
                block: block_idx,
                inst: inst_idx,
                pos: After,
              })
            }
          }
          Physical(_) => ()
        }
      }
    }

    // Record uses in terminator
    match block.terminator {
      Some(term) =>
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
      None => ()
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

    // Block params are defs
    for param in block.params {
      def_set.add(param.id)
    }

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
    match block.terminator {
      Some(term) =>
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
      None => ()
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
        if !block_def[block_idx].contains(vreg_id) {
          if !result.live_in[block_idx].contains(vreg_id) {
            result.live_in[block_idx].add(vreg_id)
            changed = true
          }
        }
      }
    }
  }
}

///|
/// Phase 3: Build live intervals from use-def info
fn build_intervals(func : VCodeFunction, result : LivenessResult) -> Unit {
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

    // Extend to cover all uses
    for use_point in info.use_points {
      interval.extend(use_point)
    }

    // Extend to cover live-in blocks - the interval needs to span from
    // block entry through all uses in that block
    for block_idx, live_in_set in result.live_in {
      if live_in_set.contains(vreg_id) {
        // The vreg is live at the start of this block
        // Extend from block entry
        let entry_point = { block: block_idx, inst: -1, pos: Before }
        interval.extend(entry_point)
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
        interval.extend(end_point)
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
  // Current state
  mut active : Array[LiveInterval] // Intervals currently occupying registers
  mut next_spill_slot : Int
}

///|
pub fn LinearScanAllocator::new(
  int_regs : Array[PReg],
  float_regs : Array[PReg],
) -> LinearScanAllocator {
  { int_regs, float_regs, active: [], next_spill_slot: 0 }
}

///|
/// Allocate registers for a function
pub fn LinearScanAllocator::allocate(
  self : LinearScanAllocator,
  func : VCodeFunction,
  liveness : LivenessResult,
) -> RegAllocResult {
  let result : RegAllocResult = {
    assignments: {},
    spill_slots: {},
    num_spill_slots: 0,
    spills: [],
    reloads: [],
  }

  // Sort intervals by start point
  let intervals : Array[LiveInterval] = []
  for entry in liveness.intervals {
    let (_, interval) = entry
    intervals.push(interval)
  }
  intervals.sort_by(fn(a, b) { a.start.compare(b.start) })

  // Process intervals in order of start point
  for interval in intervals {
    // Expire old intervals that end before this one starts
    self.expire_old_intervals(interval)

    // Get available registers for this class
    let avail_regs = match interval.vreg.class {
      Int => self.int_regs
      Float => self.float_regs
    }

    // Try to allocate a register
    let assigned = self.try_allocate_reg(interval, avail_regs)
    match assigned {
      Some(preg) => {
        interval.assigned = Some(preg)
        self.active.push(interval)
        result.assignments.set(interval.vreg.id, preg)
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
  // Sort active by end point and remove those that end before current starts
  self.active.sort_by(fn(a, b) { a.end.compare(b.end) })
  let new_active : Array[LiveInterval] = []
  for interval in self.active {
    if interval.end.compare(current.start) >= 0 {
      new_active.push(interval)
    }
  }
  self.active = new_active
}

///|
/// Check if two register classes are equal
fn reg_class_eq(a : RegClass, b : RegClass) -> Bool {
  match (a, b) {
    (Int, Int) => true
    (Float, Float) => true
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
      Float => self.float_regs
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

///|
/// Apply register allocation results to a VCode function
pub fn apply_allocation(
  func : VCodeFunction,
  alloc : RegAllocResult,
) -> VCodeFunction {
  let new_func = VCodeFunction::new(func.name)
  new_func.next_vreg_id = func.next_vreg_id

  // Convert function parameters
  for param in func.params {
    match alloc.assignments.get(param.id) {
      Some(_) => {
        // Parameter is assigned to physical register
        // We still track it as vreg but note the assignment
        let new_vreg = { id: param.id, class: param.class }
        new_func.params.push(new_vreg)
      }
      None => new_func.params.push(param)
    }
  }

  // Copy results
  for r in func.results {
    new_func.results.push(r)
  }

  // Process each block
  for block in func.blocks {
    let new_block = new_func.new_block()

    // Copy block params
    for param in block.params {
      new_block.params.push(param)
    }

    // Process instructions
    for inst in block.insts {
      let new_inst = VCodeInst::new(inst.opcode)

      // Rewrite definitions
      for def in inst.defs {
        let new_reg = rewrite_reg(def.reg, alloc)
        new_inst.add_def({ reg: new_reg })
      }

      // Rewrite uses
      for use_reg in inst.uses {
        let new_reg = rewrite_reg(use_reg, alloc)
        new_inst.add_use(new_reg)
      }
      new_block.add_inst(new_inst)
    }

    // Rewrite terminator
    match block.terminator {
      Some(term) => {
        let new_term = match term {
          Jump(target) => Jump(target)
          Branch(cond, then_b, else_b) => {
            let new_cond = rewrite_reg(cond, alloc)
            Branch(new_cond, then_b, else_b)
          }
          Return(values) => {
            let new_values : Array[Reg] = []
            for v in values {
              new_values.push(rewrite_reg(v, alloc))
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

// ============ Convenience API ============

///|
/// Allocate registers for a function using default AArch64 register set
pub fn allocate_registers_aarch64(func : VCodeFunction) -> VCodeFunction {
  // Get AArch64 allocatable registers
  // Use caller-saved registers for general allocation
  let int_regs = aapcs64_caller_saved()
  let float_regs = aapcs64_arg_fprs()

  // Compute liveness
  let liveness = compute_liveness(func)

  // Allocate
  let allocator = LinearScanAllocator::new(int_regs, float_regs)
  let alloc_result = allocator.allocate(func, liveness)

  // Apply allocation
  apply_allocation(func, alloc_result)
}
