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
/// Compare two program points using a block order array
/// This is used by the register allocator to correctly order points in non-linear CFGs
/// Note: block_order[block_id] = execution order (O(1) lookup vs O(log n) for Map)
fn ProgPoint::compare_with_order(
  self : ProgPoint,
  other : ProgPoint,
  block_order : Array[Int],
) -> Int {
  if self.block != other.block {
    let self_order = block_order[self.block]
    let other_order = block_order[other.block]
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
  vreg : @abi.VReg
  start : ProgPoint // First use or definition
  mut end : ProgPoint // Last use
  // Use positions within the interval (for spill cost calculation)
  uses : Array[ProgPoint]
  // Register hint (e.g., from a move instruction)
  mut hint : @abi.PReg?
  // Hint vreg: prefer to use the same register as this vreg (for copy coalescing)
  mut hint_vreg : Int?
  // Assigned physical register (filled by allocator)
  mut assigned : @abi.PReg?
  // Spill slot if spilled (filled by allocator)
  mut spill_slot : Int?
  // Whether this interval crosses a function call (cannot use caller-saved registers)
  mut crosses_call : Bool
}

///|
fn LiveInterval::new(vreg : @abi.VReg, start : ProgPoint) -> LiveInterval {
  {
    vreg,
    start,
    end: start,
    uses: [start],
    hint: None,
    hint_vreg: None,
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
  block_order : Array[Int],
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
  vreg : @abi.VReg
  mut def_point : ProgPoint? // Where this vreg is defined
  use_points : Array[ProgPoint] // Where this vreg is used
}

///|
fn UseDefInfo::new(vreg : @abi.VReg) -> UseDefInfo {
  { vreg, def_point: None, use_points: [] }
}

// ============ Liveness Analysis ============

// ============ CFG Edges ============

///|
/// CFG edges for liveness analysis
priv struct CFGEdges {
  preds : Array[Array[Int]] // preds[block_id] = predecessor block IDs
  succs : Array[Array[Int]] // succs[block_id] = successor block IDs
}

///|
/// Build CFG edges once (O(B + E))
fn build_cfg_edges(func : VCodeFunction) -> CFGEdges {
  let n = func.blocks.length()
  let preds : Array[Array[Int]] = []
  let succs : Array[Array[Int]] = []

  // Initialize arrays
  for _ in 0..<n {
    preds.push([])
    succs.push([])
  }

  // Build edges from terminators
  for block_idx, block in func.blocks {
    if block.terminator is Some(term) {
      let block_succs = get_terminator_succs(term)
      succs[block_idx] = block_succs
      for succ in block_succs {
        preds[succ].push(block_idx)
      }
    }
  }
  { preds, succs }
}

///|
/// Extract successor block IDs from terminator
fn get_terminator_succs(term : @instr.VCodeTerminator) -> Array[Int] {
  match term {
    Jump(target) => [target]
    Branch(_, then_b, else_b) => [then_b, else_b]
    BranchCmp(_, _, _, _, then_b, else_b) => [then_b, else_b]
    BranchCmpImm(_, _, _, _, then_b, else_b) => [then_b, else_b]
    BranchZero(_, _, _, then_b, else_b) => [then_b, else_b]
    BrTable(_, targets, default) => {
      let result : Array[Int] = []
      for t in targets {
        result.push(t)
      }
      result.push(default)
      result
    }
    Return(_) | Trap(_) => []
  }
}

// ============ Worklist ============

///|
/// Worklist with O(1) membership check
priv struct LivenessWorklist {
  queue : Array[Int]
  in_worklist : Array[Bool]
}

///|
fn LivenessWorklist::new(size : Int) -> LivenessWorklist {
  { queue: [], in_worklist: Array::make(size, false) }
}

///|
fn LivenessWorklist::push(self : LivenessWorklist, block_id : Int) -> Unit {
  if not(self.in_worklist[block_id]) {
    self.queue.push(block_id)
    self.in_worklist[block_id] = true
  }
}

///|
fn LivenessWorklist::pop(self : LivenessWorklist) -> Int? {
  match self.queue.pop() {
    Some(id) => {
      self.in_worklist[id] = false
      Some(id)
    }
    None => None
  }
}

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
  // Block order: block_order[block_id] = linear position (O(1) lookup)
  block_order : Array[Int]
  // Call points (block_idx, inst_idx) - instructions that clobber caller-saved registers
  call_points : Array[ProgPoint]
}

///|
fn LivenessResult::new(num_blocks : Int) -> LivenessResult {
  let live_in : Array[Set[Int]] = []
  let live_out : Array[Set[Int]] = []
  let block_order : Array[Int] = Array::make(num_blocks, 0)
  for _ in 0..<num_blocks {
    live_in.push(Set::new())
    live_out.push(Set::new())
  }
  {
    intervals: {},
    use_def: {},
    live_in,
    live_out,
    block_order,
    call_points: [],
  }
}

///|
/// Compute reverse postorder of blocks (for linearizing the CFG)
/// Returns an Array where order[block_id] = position in reverse postorder
fn compute_reverse_postorder(func : VCodeFunction) -> Array[Int] {
  let n = func.blocks.length()
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
      if block.terminator is Some(term) {
        match term {
          Jump(target) => dfs(func, target, visited, postorder)
          Branch(_, then_b, else_b) => {
            dfs(func, then_b, visited, postorder)
            dfs(func, else_b, visited, postorder)
          }
          BranchCmp(_, _, _, _, then_b, else_b) => {
            dfs(func, then_b, visited, postorder)
            dfs(func, else_b, visited, postorder)
          }
          BranchCmpImm(_, _, _, _, then_b, else_b) => {
            dfs(func, then_b, visited, postorder)
            dfs(func, else_b, visited, postorder)
          }
          BranchZero(_, _, _, then_b, else_b) => {
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
      }
    }

    // Add to postorder after visiting all successors
    postorder.push(block_id)
  }

  // Start DFS from block 0 (entry)
  if n > 0 {
    dfs(func, func.blocks[0].id, visited, postorder)
  }

  // Also visit any unreachable blocks (shouldn't happen in valid code)
  for block in func.blocks {
    if !visited.contains(block.id) {
      dfs(func, block.id, visited, postorder)
    }
  }

  // Reverse postorder: order[block_id] = position in reverse postorder
  let order : Array[Int] = Array::make(n, 0)
  let len = postorder.length()
  for i, block_id in postorder {
    order[block_id] = len - 1 - i
  }
  order
}

///|
/// Compute liveness information for a VCode function
pub fn compute_liveness(func : VCodeFunction) -> LivenessResult {
  let result = LivenessResult::new(func.blocks.length())

  // Compute block order for correct interval comparison
  let block_order = compute_reverse_postorder(func)
  for block_id in 0..<func.blocks.length() {
    result.block_order[block_id] = block_order[block_id]
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
      let info = if result.use_def.get(param.id) is Some(existing) {
        existing
      } else {
        let new_info = UseDefInfo::new(param)
        result.use_def.set(param.id, new_info)
        new_info
      }
      // Add use point at block entry (before first instruction)
      info.use_points.push({ block: block_idx, inst: 0, pos: Before })
    }

    // Process instructions
    for inst_idx, inst in block.insts {
      // Record call points for caller-saved register handling
      // Design: use call_type() to determine if an instruction
      // behaves like a call (clobbers caller-saved registers)
      if inst.opcode.call_type() is @instr.Regular {
        result.call_points.push({ block: block_idx, inst: inst_idx, pos: After })
      }

      // Record uses (before the instruction)
      for use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) {
          let info = if result.use_def.get(vreg.id) is Some(existing) {
            existing
          } else {
            let new_info = UseDefInfo::new(vreg)
            result.use_def.set(vreg.id, new_info)
            new_info
          }
          info.use_points.push({ block: block_idx, inst: inst_idx, pos: Before })
        }
      }

      // Record definitions (after the instruction)
      for def in inst.defs {
        if def.reg is @abi.Virtual(vreg) {
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
          if info.def_point is Some(existing_def) &&
            new_def.compare_with_order(existing_def, result.block_order) < 0 {
            // Keep the earlier definition (lower order = earlier in execution)
            info.def_point = Some(new_def)
          } else if info.def_point is None {
            info.def_point = Some(new_def)
          }
        }
      }
    }

    // Record uses in terminator
    if block.terminator is Some(term) {
      // Helper to record a use point for a virtual register
      fn record_term_use(
        reg : @abi.Reg,
        result : LivenessResult,
        block_idx : Int,
        inst_idx : Int,
      ) -> Unit {
        if reg is @abi.Virtual(vreg) {
          let info = if result.use_def.get(vreg.id) is Some(existing) {
            existing
          } else {
            let new_info = UseDefInfo::new(vreg)
            result.use_def.set(vreg.id, new_info)
            new_info
          }
          info.use_points.push({ block: block_idx, inst: inst_idx, pos: Before })
        }
      }

      let inst_idx = block.insts.length()
      match term {
        Branch(cond, _, _) => record_term_use(cond, result, block_idx, inst_idx)
        BranchCmp(lhs, rhs, _, _, _, _) => {
          record_term_use(lhs, result, block_idx, inst_idx)
          record_term_use(rhs, result, block_idx, inst_idx)
        }
        BranchCmpImm(lhs, _, _, _, _, _) =>
          record_term_use(lhs, result, block_idx, inst_idx)
        BranchZero(reg, _, _, _, _) =>
          record_term_use(reg, result, block_idx, inst_idx)
        Return(values) =>
          for value in values {
            record_term_use(value, result, block_idx, inst_idx)
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
        if use_reg is @abi.Virtual(vreg) && !def_set.contains(vreg.id) {
          use_set.add(vreg.id)
        }
      }
      // Definitions
      for def in inst.defs {
        if def.reg is @abi.Virtual(vreg) {
          def_set.add(vreg.id)
        }
      }
    }

    // Terminator uses
    if block.terminator is Some(term) {
      match term {
        Branch(cond, _, _) =>
          if cond is @abi.Virtual(vreg) && !def_set.contains(vreg.id) {
            use_set.add(vreg.id)
          }
        BranchCmp(lhs, rhs, _, _, _, _) => {
          if lhs is @abi.Virtual(vreg) && !def_set.contains(vreg.id) {
            use_set.add(vreg.id)
          }
          if rhs is @abi.Virtual(vreg) && !def_set.contains(vreg.id) {
            use_set.add(vreg.id)
          }
        }
        BranchCmpImm(lhs, _, _, _, _, _) =>
          if lhs is @abi.Virtual(vreg) && !def_set.contains(vreg.id) {
            use_set.add(vreg.id)
          }
        BranchZero(reg, _, _, _, _) =>
          if reg is @abi.Virtual(vreg) && !def_set.contains(vreg.id) {
            use_set.add(vreg.id)
          }
        Return(values) =>
          for value in values {
            if value is @abi.Virtual(vreg) && !def_set.contains(vreg.id) {
              use_set.add(vreg.id)
            }
          }
        _ => ()
      }
    }
    block_use.push(use_set)
    block_def.push(def_set)
  }

  // Pre-compute CFG edges (O(B + E), only once)
  let cfg = build_cfg_edges(func)

  // Initialize live_in with use sets
  for block_idx in 0..<func.blocks.length() {
    for vreg_id in block_use[block_idx] {
      result.live_in[block_idx].add(vreg_id)
    }
  }

  // Worklist-based dataflow with incremental update
  let worklist = LivenessWorklist::new(func.blocks.length())

  // Initialize worklist - push in forward order so pop() gives reverse order
  // (pop removes from end, so queue [0,1,..,n-1] pops n-1, n-2, .., 0)
  // For backward dataflow, we want to process successors before predecessors
  for i in 0..<func.blocks.length() {
    worklist.push(i)
  }
  while worklist.pop() is Some(block_idx) {
    let old_live_in_size = result.live_in[block_idx].length()

    // live_out[B] = ∪ live_in[S] for S in succs[B]
    // Monotone: only adds, never removes
    for succ in cfg.succs[block_idx] {
      for vreg_id in result.live_in[succ] {
        result.live_out[block_idx].add(vreg_id)
      }
    }

    // live_in[B] = use[B] ∪ (live_out[B] - def[B])
    // Incrementally add from live_out (use already added in init)
    for vreg_id in result.live_out[block_idx] {
      if !block_def[block_idx].contains(vreg_id) {
        result.live_in[block_idx].add(vreg_id)
      }
    }

    // If live_in grew, propagate to predecessors
    if result.live_in[block_idx].length() > old_live_in_size {
      for pred in cfg.preds[block_idx] {
        worklist.push(pred)
      }
    }
  }
}

///|
/// Phase 3: Build live intervals from use-def info
fn build_intervals(func : VCodeFunction, result : LivenessResult) -> Unit {
  // Get block order for correct interval comparison
  let block_order = result.block_order

  // Pre-compute vreg -> blocks mappings to avoid O(vregs × blocks) containment checks
  // This changes from O(V × B × contains) to O(total_live_in_entries + total_live_out_entries)
  let vreg_live_in_blocks : Map[Int, Array[Int]] = {}
  let vreg_live_out_blocks : Map[Int, Array[Int]] = {}
  for block_idx, live_in_set in result.live_in {
    for vreg_id in live_in_set {
      match vreg_live_in_blocks.get(vreg_id) {
        Some(blocks) => blocks.push(block_idx)
        None => vreg_live_in_blocks.set(vreg_id, [block_idx])
      }
    }
  }
  for block_idx, live_out_set in result.live_out {
    for vreg_id in live_out_set {
      match vreg_live_out_blocks.get(vreg_id) {
        Some(blocks) => blocks.push(block_idx)
        None => vreg_live_out_blocks.set(vreg_id, [block_idx])
      }
    }
  }

  // For each vreg, create an interval spanning from def to last use
  for entry in result.use_def {
    let (vreg_id, info) = entry
    let start = if info.def_point is Some(def) {
      def
      // If no def point, use the first use (shouldn't happen in valid code)
    } else if info.use_points.length() > 0 {
      info.use_points[0]
    } else {
      continue // No uses or defs, skip
    }
    let interval = LiveInterval::new(info.vreg, start)

    // Extend to cover all uses (using block order for correct comparison)
    for use_point in info.use_points {
      interval.extend_with_order(use_point, block_order)
    }

    // Extend to cover live-in blocks - use pre-computed mapping
    if vreg_live_in_blocks.get(vreg_id) is Some(blocks) {
      for block_idx in blocks {
        let entry_point = { block: block_idx, inst: -1, pos: Before }
        interval.extend_with_order(entry_point, block_order)
      }
    }

    // Extend to cover live-out blocks - use pre-computed mapping
    if vreg_live_out_blocks.get(vreg_id) is Some(blocks) {
      for block_idx in blocks {
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
      // - The call is strictly after the interval's start AND before the interval's end
      //   (Values defined by the call itself start at the same progpoint and do not
      //    need to survive across the call.)
      let start_cmp = interval.start.compare_with_order(call_point, block_order)
      let end_cmp = interval.end.compare_with_order(call_point, block_order)
      // start < call_point < end (interval is live across the call)
      if start_cmp < 0 && end_cmp > 0 {
        interval.crosses_call = true
        break
      }
    }
    result.intervals.set(vreg_id, interval)
  }
}

// ============ Copy Coalescing ============

///|
/// Coalescing pairs: maps vreg id -> list of vregs it wants to coalesce with
/// Used for bidirectional hint propagation
pub(all) struct CoalescingInfo {
  // Forward hints: dst wants to use src's register (dst = mov src)
  forward_hints : Map[Int, Int]
  // Reverse hints: src wants to use dst's register (for cases where dst is allocated first)
  reverse_hints : Map[Int, Int]
}

///|
fn CoalescingInfo::new() -> CoalescingInfo {
  { forward_hints: {}, reverse_hints: {} }
}

///|
/// Collect coalescing hints from Move instructions
/// For each `dst = mov src`, we want dst to use the same register as src
/// Also tracks reverse hints for cases where dst is processed first
fn collect_coalescing_hints(
  func : VCodeFunction,
  liveness : LivenessResult,
) -> CoalescingInfo {
  let info = CoalescingInfo::new()
  for block in func.blocks {
    for inst in block.insts {
      // Check if this is a Move instruction with virtual registers
      if inst.opcode is @instr.Move &&
        inst.defs.length() == 1 &&
        inst.uses.length() == 1 {
        // Get source and destination vregs
        let src_vreg_opt = match inst.uses[0] {
          @abi.Virtual(vreg) => Some(vreg)
          _ => None
        }
        let dst_vreg_opt = match inst.defs[0].reg {
          @abi.Virtual(vreg) => Some(vreg)
          _ => None
        }
        // Set hint on destination interval
        if (src_vreg_opt, dst_vreg_opt) is (Some(src_vreg), Some(dst_vreg)) {
          // Skip if same vreg (shouldn't happen but be safe)
          if src_vreg.id == dst_vreg.id {
            continue
          }
          // Set hint_vreg on destination's interval (forward hint)
          if liveness.intervals.get(dst_vreg.id) is Some(dst_interval) {
            dst_interval.hint_vreg = Some(src_vreg.id)
          }
          // Record forward and reverse hints for bidirectional coalescing
          info.forward_hints.set(dst_vreg.id, src_vreg.id)
          info.reverse_hints.set(src_vreg.id, dst_vreg.id)
        }
      }
    }
  }
  info
}

///|
/// Resolve vreg hints to physical register hints
/// Called during allocation after some intervals have been assigned
/// Supports bidirectional hints from coalescing
fn resolve_vreg_hint(
  interval : LiveInterval,
  assignments : Map[Int, @abi.PReg],
  coalescing : CoalescingInfo,
) -> @abi.PReg? {
  // First check if we have an explicit physical register hint
  if interval.hint is Some(preg) {
    return Some(preg)
  }
  // Check forward hint: we want to use the source's register (dst = mov src)
  if interval.hint_vreg is Some(hint_vreg_id) {
    if assignments.get(hint_vreg_id) is Some(preg) {
      return Some(preg)
    }
  }
  // Check reverse hint: src wants to use dst's register (dst = mov src, but dst allocated first)
  if coalescing.reverse_hints.get(interval.vreg.id) is Some(dst_vreg_id) {
    if assignments.get(dst_vreg_id) is Some(preg) {
      return Some(preg)
    }
  }
  None
}

// ============ Linear Scan Register Allocator ============

///|
/// A register move instruction (from regalloc constraint processing)
/// Move operation between registers
pub(all) struct RegMove {
  from : @abi.PReg // Source register (or spill slot encoded as negative index)
  to : @abi.PReg // Destination register
  class : @abi.RegClass
}

///|
fn RegMove::to_string(self : RegMove) -> String {
  "mov \{self.to} <- \{self.from}"
}

///|
pub impl Show for RegMove with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Edits to insert before/after an instruction
/// Register constraint handling
pub(all) struct InstEdits {
  before : Array[RegMove] // Moves to insert before the instruction
  after : Array[RegMove] // Moves to insert after the instruction
}

///|
fn InstEdits::new() -> InstEdits {
  { before: [], after: [] }
}

// ============ Parallel Move Resolver ============
// Resolves parallel moves to avoid conflicts when moves have cyclic dependencies.
// For example: X2->X3, X3->X2 cannot be executed in sequence without a temp.
// This implements a standard parallel move algorithm:
// 1. Find moves whose dest is not a src of any other move, emit those first
// 2. For cycles, use a temp register (X16) to break the cycle

///|
/// Resolve parallel moves and emit them in the correct order.
/// Returns a list of moves that can be safely executed in sequence.
fn resolve_parallel_moves(moves : Array[RegMove]) -> Array[RegMove] {
  if moves.length() <= 1 {
    return moves
  }
  let result : Array[RegMove] = []
  let pending : Array[RegMove] = []
  for mv in moves {
    // Skip identity moves (same register index and same class)
    let same_class = match (mv.from.class, mv.to.class) {
      (@abi.Int, @abi.Int) => true
      (@abi.Float32, @abi.Float32) => true
      (@abi.Float64, @abi.Float64) => true
      _ => false
    }
    if mv.from.index != mv.to.index || not(same_class) {
      pending.push(mv)
    }
  }

  // Float32/Float64 registers alias the same Vn hardware register.
  // When resolving parallel moves we must treat them as the same location to
  // avoid clobbering (e.g. D1 <- D0 would overwrite S1).
  fn reg_kind(preg : @abi.PReg) -> Int {
    match preg.class {
      @abi.Int => 0
      @abi.Float32 | @abi.Float64 | @abi.Vector => 1 // Vector uses same Vn registers
    }
  }

  fn alias_key(preg : @abi.PReg) -> Int {
    preg.index * 2 + reg_kind(preg)
  }

  fn aliases(a : @abi.PReg, b : @abi.PReg) -> Bool {
    a.index == b.index && reg_kind(a) == reg_kind(b)
  }

  // Build a set of source registers for quick lookup
  fn rebuild_src_set(pending : Array[RegMove]) -> Set[Int] {
    let srcs : Set[Int] = Set::new()
    for mv in pending {
      if not(mv.from.is_spilled()) {
        srcs.add(alias_key(mv.from))
      }
    }
    srcs
  }

  fn make_key(preg : @abi.PReg) -> Int {
    alias_key(preg)
  }

  // Iterate until all moves are resolved
  while pending.length() > 0 {
    let src_set = rebuild_src_set(pending)

    // Find a move whose destination is not a source of any other pending move
    let mut found_idx : Int? = None
    for i, mv in pending {
      if mv.to.is_spilled() {
        // Spill destinations never conflict with register sources
        found_idx = Some(i)
        break
      }
      let dest_key = make_key(mv.to)
      if not(src_set.contains(dest_key)) {
        found_idx = Some(i)
        break
      }
    }
    match found_idx {
      Some(idx) =>
        // Safe to emit this move
        result.push(pending.remove(idx))
      None => {
        // All remaining moves form cycles - break with temp register
        // Use X16 as scratch for int, V16 for float (outside allocatable range)
        let mv = pending.remove(0)
        let temp_preg : @abi.PReg = { index: 16, class: mv.from.class }

        // mv: A -> B, where B is used by another move (B -> C)
        // Solution: A -> temp, then continue. Later emit temp -> B
        // But we need to also update the other move that uses B as src

        // 1. Emit: src -> temp
        result.push({ from: mv.from, to: temp_preg, class: mv.class })

        // 2. Replace all uses of mv.from as source with temp
        for i in 0..<pending.length() {
          if not(pending[i].from.is_spilled()) &&
            aliases(pending[i].from, mv.from) {
            pending[i] = {
              from: temp_preg,
              to: pending[i].to,
              class: pending[i].class,
            }
          }
        }

        // 3. Add the original move with temp as source
        pending.push({ from: temp_preg, to: mv.to, class: mv.class })
      }
    }
  }
  result
}

///|
/// Register allocation result
pub(all) struct RegAllocResult {
  // Map from vreg id to assigned physical register
  assignments : Map[Int, @abi.PReg]
  // Map from vreg id to spill slot (if spilled)
  spill_slots : Map[Int, Int]
  // Total number of spill slots used
  mut num_spill_slots : Int
  // Instructions to insert (for spills/reloads)
  spills : Array[SpillInfo]
  reloads : Array[ReloadInfo]
  // Constraint edits: (block_idx, inst_idx) -> edits to insert
  // Fixed register constraint handling
  inst_edits : Map[(Int, Int), InstEdits]
}

///|
/// Information about a spill
pub(all) struct SpillInfo {
  vreg : @abi.VReg
  slot : Int
  point : ProgPoint
}

///|
/// Information about a reload
pub(all) struct ReloadInfo {
  vreg : @abi.VReg
  slot : Int
  preg : @abi.PReg
  point : ProgPoint
}

///|
/// Linear scan register allocator
pub(all) struct LinearScanAllocator {
  // Available physical registers by class
  int_regs : Array[@abi.PReg]
  float_regs : Array[@abi.PReg]
  // Callee-saved registers for cross-call allocation (may exclude X23)
  callee_saved_int_regs : Array[@abi.PReg]
  // Callee-saved float registers for cross-call allocation (D8-D15)
  callee_saved_float_regs : Array[@abi.PReg]
  // Current state
  mut active : Array[LiveInterval] // Intervals currently occupying registers
  mut next_spill_slot : Int
  // Block order for correct interval comparison in non-linear CFGs
  // block_order[block_id] = execution order (O(1) lookup)
  mut block_order : Array[Int]
  // Reserved registers at each instruction point (for FixedReg constraints)
  // Key: (block_idx, inst_idx), Value: set of reserved register indices
  // Note: constraints must be respected during allocation
  reserved_int_regs : Map[(Int, Int), Set[Int]]
  reserved_float_regs : Map[(Int, Int), Set[Int]]
}

///|
pub fn LinearScanAllocator::new(
  int_regs : Array[@abi.PReg],
  float_regs : Array[@abi.PReg],
  callee_saved_int_regs : Array[@abi.PReg],
  callee_saved_float_regs? : Array[@abi.PReg] = [],
) -> LinearScanAllocator {
  {
    int_regs,
    float_regs,
    callee_saved_int_regs,
    callee_saved_float_regs,
    active: [],
    next_spill_slot: 0,
    block_order: [],
    reserved_int_regs: {},
    reserved_float_regs: {},
  }
}

///|
/// Collect FixedReg constraints from all instructions
/// This must be called before allocation so that constrained registers
/// can be avoided during the allocation process.
/// Design: constraints are known before allocation.
fn LinearScanAllocator::collect_constraints(
  self : LinearScanAllocator,
  func : VCodeFunction,
) -> Unit {
  for block_idx, block in func.blocks {
    for inst_idx, inst in block.insts {
      // Collect use constraints
      for constraint in inst.use_constraints {
        if constraint is @abi.FixedReg(preg) {
          let key = (block_idx, inst_idx)
          match preg.class {
            @abi.Int => {
              if self.reserved_int_regs.get(key) is None {
                self.reserved_int_regs.set(key, Set::new())
              }
              self.reserved_int_regs.get(key).unwrap().add(preg.index)
            }
            @abi.Float32 | @abi.Float64 | @abi.Vector => {
              if self.reserved_float_regs.get(key) is None {
                self.reserved_float_regs.set(key, Set::new())
              }
              self.reserved_float_regs.get(key).unwrap().add(preg.index)
            }
          }
        }
      }
      // Collect def constraints
      for constraint in inst.def_constraints {
        if constraint is @abi.FixedReg(preg) {
          let key = (block_idx, inst_idx)
          match preg.class {
            @abi.Int => {
              if self.reserved_int_regs.get(key) is None {
                self.reserved_int_regs.set(key, Set::new())
              }
              self.reserved_int_regs.get(key).unwrap().add(preg.index)
            }
            @abi.Float32 | @abi.Float64 | @abi.Vector => {
              if self.reserved_float_regs.get(key) is None {
                self.reserved_float_regs.set(key, Set::new())
              }
              self.reserved_float_regs.get(key).unwrap().add(preg.index)
            }
          }
        }
      }
    }
  }
}

///|
/// Check if a register is reserved at any point in an interval's live range
fn LinearScanAllocator::is_reserved_in_range(
  self : LinearScanAllocator,
  preg : @abi.PReg,
  interval : LiveInterval,
) -> Bool {
  let reserved_map = match preg.class {
    @abi.Int => self.reserved_int_regs
    @abi.Float32 | @abi.Float64 | @abi.Vector => self.reserved_float_regs
  }
  let block_order = self.block_order

  // Check all reserved points to see if any overlap with this interval
  for entry in reserved_map {
    let ((block_idx, inst_idx), reserved_set) = entry
    if !reserved_set.contains(preg.index) {
      continue
    }
    // Check if this point is within the interval's live range
    let point : ProgPoint = { block: block_idx, inst: inst_idx, pos: Before }
    let start_cmp = interval.start.compare_with_order(point, block_order)
    let end_cmp = interval.end.compare_with_order(point, block_order)
    // interval.start <= point <= interval.end
    if start_cmp <= 0 && end_cmp >= 0 {
      return true
    }
  }
  false
}

///|
/// Allocate registers for a function
pub fn LinearScanAllocator::allocate(
  self : LinearScanAllocator,
  func : VCodeFunction,
  liveness : LivenessResult,
) -> RegAllocResult {
  // Step 0: Collect constraints from all instructions
  // This allows us to avoid constrained registers during allocation
  self.collect_constraints(func)

  // Copy block order from liveness result (just reference the array)
  self.block_order = liveness.block_order

  // Step 1: Collect coalescing hints from Move instructions
  let coalescing = collect_coalescing_hints(func, liveness)
  let result : RegAllocResult = {
    assignments: {},
    spill_slots: {},
    num_spill_slots: 0,
    spills: [],
    reloads: [],
    inst_edits: {},
  }

  // Pre-assign function parameters to ABI registers
  // Note: all params use X0-X7 (int) or V0-V7 (float)
  // vmctx is an explicit param in the function signature, not special-cased here
  // NOTE: Only pre-assign if the parameter doesn't cross a call, otherwise
  // it will be handled by the normal allocation process (which will use callee-saved)
  let max_int_params = @abi.MAX_REG_PARAMS // 8
  let max_float_params = @abi.MAX_FLOAT_REG_PARAMS // 8
  let mut int_idx = 0
  let mut float_idx = 0
  for param in func.params {
    if liveness.intervals.get(param.id) is Some(interval) {
      // Determine which register this param comes in
      let (preg_opt, is_int) : (@abi.PReg?, Bool) = match param.class {
        @abi.Int =>
          if int_idx < max_int_params {
            (Some(@abi.PReg::{ index: int_idx, class: @abi.Int }), true)
          } else {
            (None, true) // Stack param
          }
        @abi.Float32 | @abi.Float64 | @abi.Vector =>
          // Vector uses same Vn registers as Float
          if float_idx < max_float_params {
            (Some(@abi.PReg::{ index: float_idx, class: param.class }), false)
          } else {
            (None, false) // Stack param
          }
      }
      // Update counters
      if is_int {
        int_idx = int_idx + 1
      } else {
        float_idx = float_idx + 1
      }
      // Skip if crosses call or no register available
      if interval.crosses_call || preg_opt is None {
        continue
      }
      // Safe to pre-assign to ABI register
      let preg = preg_opt.unwrap()
      result.assignments.set(param.id, preg)
      interval.assigned = Some(preg)
      self.active.push(interval)
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
      if interval.vreg.class is @abi.Int {
        self.callee_saved_int_regs
      } else {
        // Use callee-saved FPRs (D8-D15) for floats that must survive across calls
        self.callee_saved_float_regs
      }
    } else if interval.vreg.class is @abi.Int {
      self.int_regs
    } else {
      self.float_regs
    }

    // Try to allocate a register (pass assignments and coalescing info for hints)
    let assigned = self.try_allocate_reg(
      interval,
      avail_regs,
      result.assignments,
      coalescing,
    )
    if assigned is Some(preg) {
      let assigned_preg : @abi.PReg = {
        index: preg.index,
        class: interval.vreg.class,
      }
      interval.assigned = Some(assigned_preg)
      self.active.push(interval)
      result.assignments.set(interval.vreg.id, assigned_preg)
    } else {
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
fn reg_class_eq(a : @abi.RegClass, b : @abi.RegClass) -> Bool {
  match (a, b) {
    (@abi.Int, @abi.Int) => true
    // Float32, Float64, and Vector all use V0-V31 registers
    (@abi.Float32, @abi.Float32)
    | (@abi.Float32, @abi.Float64)
    | (@abi.Float32, @abi.Vector)
    | (@abi.Float64, @abi.Float32)
    | (@abi.Float64, @abi.Float64)
    | (@abi.Float64, @abi.Vector)
    | (@abi.Vector, @abi.Float32)
    | (@abi.Vector, @abi.Float64)
    | (@abi.Vector, @abi.Vector) => true
    _ => false
  }
}

///|
/// Try to allocate a physical register for an interval
/// Note: avoid registers that are reserved by constraints
fn LinearScanAllocator::try_allocate_reg(
  self : LinearScanAllocator,
  interval : LiveInterval,
  avail_regs : Array[@abi.PReg],
  assignments : Map[Int, @abi.PReg],
  coalescing : CoalescingInfo,
) -> @abi.PReg? {
  // Build set of registers currently in use by active intervals
  let used : Set[Int] = Set::new()
  for active in self.active {
    if active.assigned is Some(preg) &&
      reg_class_eq(preg.class, interval.vreg.class) {
      used.add(preg.index)
    }
  }

  // Try hint first if available and not reserved
  // This supports copy coalescing: if dst = mov src, dst will try to use src's register
  // Also supports reverse hints for cases where dst is allocated before src
  let resolved_hint = resolve_vreg_hint(interval, assignments, coalescing)
  if resolved_hint is Some(hint) &&
    !used.contains(hint.index) &&
    !self.is_reserved_in_range(hint, interval) {
    return Some(hint)
  }

  // Find a free register that is not reserved by any constraint
  // in the interval's live range
  for preg in avail_regs {
    if !used.contains(preg.index) && !self.is_reserved_in_range(preg, interval) {
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
  if interval.start.pos is After {
    result.spills.push({ vreg: interval.vreg, slot, point: interval.start })
  }

  // For each use, we need to reload into a temporary
  // This is a simplified approach - a real allocator would be smarter
  for use_point in interval.uses {
    // Get a register for this reload (use first available)
    let avail_regs = match interval.vreg.class {
      @abi.Int => self.int_regs
      @abi.Float32 | @abi.Float64 | @abi.Vector => self.float_regs
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

// ============ Constraint Processing ============

///|
/// Process operand constraints and generate RegMove edits
/// Design: constraints are processed after allocation
/// and moves are inserted when the allocated register doesn't match the constraint
pub fn process_constraints(
  func : VCodeFunction,
  alloc : RegAllocResult,
) -> Unit {
  for block_idx, block in func.blocks {
    for inst_idx, inst in block.insts {
      // Skip if no constraints
      if inst.use_constraints.is_empty() && inst.def_constraints.is_empty() {
        continue
      }
      let edits = InstEdits::new()

      // Process use constraints (moves before the instruction)
      for i, constraint in inst.use_constraints {
        if constraint is @abi.FixedReg(required_preg) {
          let use_reg = inst.uses[i]
          if use_reg is @abi.Virtual(vreg) {
            // Check if already allocated to the required register
            match alloc.assignments.get(vreg.id) {
              Some(assigned_preg) =>
                if assigned_preg.index != required_preg.index {
                  // Need to move from assigned to required
                  edits.before.push({
                    from: assigned_preg,
                    to: required_preg,
                    class: vreg.class,
                  })
                }
              // If already at required_preg, no move needed
              None =>
                // Spilled: need to reload to the required register
                if alloc.spill_slots.get(vreg.id) is Some(slot) {
                  // Encode spill slot as negative index in 'from'
                  // The emit phase will interpret this as a reload
                  let spilled_preg = @abi.PReg::spilled(slot, vreg.class)
                  edits.before.push({
                    from: spilled_preg,
                    to: required_preg,
                    class: vreg.class,
                  })
                }
            }
          }
        }
      }

      // Process def constraints (moves after the instruction)
      for i, constraint in inst.def_constraints {
        if constraint is @abi.FixedReg(required_preg) {
          let def = inst.defs[i]
          if def.reg is @abi.Virtual(vreg) {
            // Check if already allocated to the required register
            match alloc.assignments.get(vreg.id) {
              Some(assigned_preg) =>
                if assigned_preg.index != required_preg.index {
                  // Need to move from required to assigned
                  // (the instruction produces in required_preg, we need to move to assigned)
                  edits.after.push({
                    from: required_preg,
                    to: assigned_preg,
                    class: vreg.class,
                  })
                }
              None =>
                // Spilled: need to store from required register to spill slot
                if alloc.spill_slots.get(vreg.id) is Some(slot) {
                  let spilled_preg = @abi.PReg::spilled(slot, vreg.class)
                  edits.after.push({
                    from: required_preg,
                    to: spilled_preg,
                    class: vreg.class,
                  })
                }
            }
          }
        }
      }

      // Store edits if any
      if !edits.before.is_empty() || !edits.after.is_empty() {
        alloc.inst_edits.set((block_idx, inst_idx), edits)
      }
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
  let new_func = func.clone_base()
  new_func.set_num_spill_slots(alloc.num_spill_slots)

  // Convert function parameters
  // Note: all params use X0-X7 (int) or V0-V7 (float)
  // vmctx is an explicit param in the function signature
  let max_int_params = @abi.MAX_REG_PARAMS // 8
  let max_float_params = @abi.MAX_FLOAT_REG_PARAMS // 8
  let mut int_idx = 0
  let mut float_idx = 0
  for param in func.params {
    match alloc.assignments.get(param.id) {
      Some(preg) => {
        // Parameter is assigned to physical register
        let new_vreg : @abi.VReg = { id: param.id, class: param.class }
        new_func.params.push(new_vreg)
        // Check if param is in register or on stack, and whether it needs a move
        let (default_preg_opt, is_int) : (@abi.PReg?, Bool) = match
          param.class {
          @abi.Int =>
            if int_idx < max_int_params {
              (Some(@abi.PReg::{ index: int_idx, class: @abi.Int }), true)
            } else {
              (None, true) // Stack param
            }
          @abi.Float32 =>
            if float_idx < max_float_params {
              (
                Some(@abi.PReg::{ index: float_idx, class: @abi.Float32 }),
                false,
              )
            } else {
              (None, false)
            }
          @abi.Float64 =>
            if float_idx < max_float_params {
              (
                Some(@abi.PReg::{ index: float_idx, class: @abi.Float64 }),
                false,
              )
            } else {
              (None, false)
            }
          @abi.Vector =>
            // Vector uses same Vn registers as Float
            if float_idx < max_float_params {
              (Some(@abi.PReg::{ index: float_idx, class: @abi.Vector }), false)
            } else {
              (None, false)
            }
        }
        // Update counters
        if is_int {
          int_idx += 1
        } else {
          float_idx += 1
        }
        // Decide whether to store preg in param_pregs
        match default_preg_opt {
          Some(default_preg) =>
            if preg.index != default_preg.index {
              new_func.param_pregs.push(Some(preg))
            } else {
              new_func.param_pregs.push(None) // No move needed
            }
          None =>
            // Stack param - always store the assigned register
            new_func.param_pregs.push(Some(preg))
        }
      }
      None => {
        new_func.params.push(param)
        new_func.param_pregs.push(None)
        // Still need to increment indices for unassigned params
        match param.class {
          @abi.Int => int_idx += 1
          @abi.Float32 | @abi.Float64 | @abi.Vector => float_idx += 1
        }
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
  for block_idx, block in func.blocks {
    let new_block = new_func.new_block()

    // Copy block params
    for param in block.params {
      new_block.params.push(param)
    }

    // Block-level scratch register counter to avoid aliasing across instructions
    let mut block_scratch_idx = 0

    // Process instructions
    for inst_idx, inst in block.insts {
      // First, insert reload instructions for any spilled uses
      // Track which scratch registers are used for each spilled vreg
      let spill_regs : Map[Int, @abi.PReg] = {}

      // Check if this is a tail call instruction - needs special handling
      // Note: CallPtr uses FixedReg constraints, so regalloc handles it normally
      let is_call_indirect = inst.opcode is ReturnCallIndirect(_, _)

      // For ReturnCallIndirect with many spilled args, we use a special strategy:
      // - func_ptr (uses[0]): reload to X18
      // - register args (uses[1-8]): if spilled, reload to X16/X17 (max 2)
      // - stack args (uses[9+]): if spilled, use spilled register encoding (emit handles them)
      //
      // X16, X17 are the only truly safe scratch registers because:
      // - X3-X10: may hold function parameters
      // - X11-X15: used by call marshalling
      // - X18: used for func_ptr
      // - X19+: allocatable callee-saved registers

      // First, collect registers that are in use by non-spilled uses
      // to avoid clobbering them with scratch register reloads
      let used_regs : @hashset.HashSet[Int] = @hashset.HashSet::new()
      for use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) {
          match alloc.assignments.get(vreg.id) {
            Some(preg) => used_regs.add(preg.index) |> ignore
            None => ()
          }
        }
      }
      let mut inst_spill_idx = 0
      for i, use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) &&
          alloc.assignments.get(vreg.id) is None {
          // This vreg is spilled, need to reload
          if alloc.spill_slots.get(vreg.id) is Some(slot) {
            let scratch_class = match vreg.class {
              @abi.Float32 | @abi.Float64 => @abi.Float64
              _ => vreg.class
            }

            // Determine how to handle this spilled use
            if is_call_indirect && i == 0 {
              // CallIndirect's func_ptr (first use): reload directly to X18
              let scratch_preg : @abi.PReg = { index: 18, class: scratch_class }
              spill_regs.set(vreg.id, scratch_preg)
              let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: @abi.Physical(scratch_preg) })
              new_block.add_inst(reload_inst)
            } else if is_call_indirect && i >= 1 {
              // CallIndirect's args (all args, including register args 0-7 and stack args 8+)
              // Use spilled register encoding - emit code will handle the load directly
              // This avoids X16/X17 aliasing when many args are spilled
              let spilled_preg = @abi.PReg::spilled(slot, scratch_class)
              spill_regs.set(vreg.id, spilled_preg)
              // Don't insert reload - emit code will load directly from spill slot
            } else {
              // Regular spilled uses (non-CallIndirect instructions)
              // Use X16, X17, X18 as scratch registers, but avoid registers
              // that are already in use by other operands in this instruction
              let scratch_candidates = [16, 17, 18]
              let mut scratch_idx = inst_spill_idx % 3
              // Find a scratch register that's not already in use
              let mut attempts = 0
              while used_regs.contains(scratch_candidates[scratch_idx]) &&
                    attempts < 3 {
                scratch_idx = (scratch_idx + 1) % 3
                attempts += 1
              }
              let scratch_preg : @abi.PReg = {
                index: scratch_candidates[scratch_idx],
                class: scratch_class,
              }
              inst_spill_idx = inst_spill_idx + 1
              block_scratch_idx = block_scratch_idx + 1
              spill_regs.set(vreg.id, scratch_preg)
              let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: @abi.Physical(scratch_preg) })
              new_block.add_inst(reload_inst)
            }
          }
        }
      }

      // Check if any definitions are spilled - collect spilled defs WITHOUT fixed constraints
      // Defs with fixed constraints are handled by process_constraints, not here
      let spilled_defs : Array[(@abi.VReg, Int)] = []
      for i, def in inst.defs {
        if def.reg is @abi.Virtual(vreg) &&
          alloc.assignments.get(vreg.id) is None &&
          alloc.spill_slots.get(vreg.id) is Some(slot) {
          // Skip defs with fixed constraints - they are handled by constraint processing
          let has_fixed_constraint = if i < inst.def_constraints.length() {
            inst.def_constraints[i] is @abi.FixedReg(_)
          } else {
            false
          }
          if !has_fixed_constraint {
            spilled_defs.push((vreg, slot))
          }
        }
      }

      // Create new instruction with rewritten registers
      let new_inst = @instr.VCodeInst::new(inst.opcode)

      // Rewrite definitions - use X16, X17 as scratch for spilled defs
      // But for defs with fixed constraints, use the fixed register
      let spill_scratch_map : Map[Int, @abi.PReg] = {} // vreg.id -> scratch preg
      for i, def in inst.defs {
        match def.reg {
          @abi.Virtual(vreg) =>
            match alloc.assignments.get(vreg.id) {
              Some(preg) => new_inst.add_def({ reg: @abi.Physical(preg) })
              None => {
                // Check if this def has a fixed constraint
                let fixed_preg_opt = if i < inst.def_constraints.length() {
                  match inst.def_constraints[i] {
                    @abi.FixedReg(preg) => Some(preg)
                    _ => None
                  }
                } else {
                  None
                }
                match fixed_preg_opt {
                  Some(fixed_preg) =>
                    // Use the fixed register - constraint processing handles the spill
                    new_inst.add_def({ reg: @abi.Physical(fixed_preg) })
                  None => {
                    // Spilled without constraint: use X16, X17 as scratch registers
                    let scratch_class = match vreg.class {
                      @abi.Float32 | @abi.Float64 => @abi.Float64
                      _ => vreg.class
                    }
                    let scratch_indices = [16, 17]
                    let scratch_preg : @abi.PReg = {
                      index: scratch_indices[block_scratch_idx % 2],
                      class: scratch_class,
                    }
                    block_scratch_idx = block_scratch_idx + 1
                    spill_scratch_map.set(vreg.id, scratch_preg)
                    new_inst.add_def({ reg: @abi.Physical(scratch_preg) })
                  }
                }
              }
            }
          @abi.Physical(_) => new_inst.add_def(def)
        }
      }

      // Rewrite uses
      for use_reg in inst.uses {
        match use_reg {
          @abi.Virtual(vreg) =>
            match alloc.assignments.get(vreg.id) {
              Some(preg) => new_inst.add_use(@abi.Physical(preg))
              None =>
                // Spilled: use the scratch register we reloaded into
                match spill_regs.get(vreg.id) {
                  Some(scratch_preg) =>
                    new_inst.add_use(@abi.Physical(scratch_preg))
                  None => {
                    // Fallback: use X16 if somehow not in spill_regs
                    let scratch_preg : @abi.PReg = {
                      index: 16,
                      class: vreg.class,
                    }
                    new_inst.add_use(@abi.Physical(scratch_preg))
                  }
                }
            }
          @abi.Physical(_) => new_inst.add_use(use_reg)
        }
      }

      // Process constraint edits: insert moves before the instruction
      // Fixed register constraint handling
      // Use parallel move resolver to handle cyclic dependencies
      if alloc.inst_edits.get((block_idx, inst_idx)) is Some(edits) {
        let resolved_moves = resolve_parallel_moves(edits.before)
        for mv in resolved_moves {
          if mv.from.is_spilled() {
            // Reload from spill slot to target register
            let slot = mv.from.get_spill_slot()
            let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
            reload_inst.add_def({ reg: @abi.Physical(mv.to) })
            new_block.add_inst(reload_inst)
          } else {
            // Register to register move
            let move_inst = @instr.VCodeInst::new(Move)
            move_inst.add_def({ reg: @abi.Physical(mv.to) })
            move_inst.add_use(@abi.Physical(mv.from))
            new_block.add_inst(move_inst)
          }
        }
      }
      new_block.add_inst(new_inst)

      // Process constraint edits: insert moves after the instruction
      // Use parallel move resolver for consistency (though after moves rarely conflict)
      if alloc.inst_edits.get((block_idx, inst_idx)) is Some(edits) {
        let resolved_moves = resolve_parallel_moves(edits.after)
        for mv in resolved_moves {
          if mv.to.is_spilled() {
            // Store to spill slot from source register
            let slot = mv.to.get_spill_slot()
            let store_inst = @instr.VCodeInst::new(StackStore(slot * 8))
            store_inst.add_use(@abi.Physical(mv.from))
            new_block.add_inst(store_inst)
          } else {
            // Register to register move
            let move_inst = @instr.VCodeInst::new(Move)
            move_inst.add_def({ reg: @abi.Physical(mv.to) })
            move_inst.add_use(@abi.Physical(mv.from))
            new_block.add_inst(move_inst)
          }
        }
      }

      // Insert spill instructions after the defining instruction for ALL spilled defs
      for entry in spilled_defs {
        let (vreg, slot) = entry
        let spill_inst = @instr.VCodeInst::new(StackStore(slot * 8))
        let scratch_preg = spill_scratch_map.get(vreg.id).unwrap()
        spill_inst.add_use(@abi.Physical(scratch_preg))
        new_block.add_inst(spill_inst)
      }
    }

    // Rewrite terminator
    if block.terminator is Some(term) {
      let new_term = match term {
        Jump(target) => @instr.Jump(target)
        Branch(cond, then_b, else_b) => {
          // Handle spilled condition register
          let new_cond = rewrite_reg_with_spill(cond, alloc, new_block)
          Branch(new_cond, then_b, else_b)
        }
        BranchCmp(lhs, rhs, cond, is_64, then_b, else_b) => {
          // Handle spilled registers
          let new_lhs = rewrite_reg_with_spill(lhs, alloc, new_block)
          let new_rhs = rewrite_reg_with_spill(rhs, alloc, new_block)
          BranchCmp(new_lhs, new_rhs, cond, is_64, then_b, else_b)
        }
        BranchCmpImm(lhs, imm, cond, is_64, then_b, else_b) => {
          // Handle spilled register
          let new_lhs = rewrite_reg_with_spill(lhs, alloc, new_block)
          BranchCmpImm(new_lhs, imm, cond, is_64, then_b, else_b)
        }
        BranchZero(reg, is_nonzero, is_64, then_b, else_b) => {
          // Handle spilled register
          let new_reg = rewrite_reg_with_spill(reg, alloc, new_block)
          BranchZero(new_reg, is_nonzero, is_64, then_b, else_b)
        }
        BrTable(index, targets, default) => {
          // Handle spilled index register
          let new_index = rewrite_reg_with_spill(index, alloc, new_block)
          BrTable(new_index, targets, default)
        }
        Return(values) => {
          // Handle Return specially to use block-level scratch counter
          // This ensures each spilled value uses a different scratch register
          let new_values : Array[@abi.Reg] = []
          for v in values {
            if v is @abi.Virtual(vreg) &&
              alloc.assignments.get(vreg.id) is Some(preg) {
              new_values.push(@abi.Physical(preg))
              // Spilled: insert reload and use scratch register from block pool
            } else if v is @abi.Virtual(vreg) &&
              alloc.spill_slots.get(vreg.id) is Some(slot) {
              // Use X16, X17 as scratch registers
              // These are the only safe scratch registers
              let scratch_class = match vreg.class {
                @abi.Float32 | @abi.Float64 => @abi.Float64
                _ => vreg.class
              }
              let scratch_indices = [16, 17]
              let scratch_preg : @abi.PReg = {
                index: scratch_indices[block_scratch_idx % 2],
                class: scratch_class,
              }
              block_scratch_idx = block_scratch_idx + 1
              let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: @abi.Physical(scratch_preg) })
              new_block.add_inst(reload_inst)
              new_values.push(@abi.Physical(scratch_preg))
            } else {
              new_values.push(v)
            }
          }
          Return(new_values)
        }
        Trap(msg) => Trap(msg)
      }
      new_block.set_terminator(new_term)
    }
  }
  new_func
}

///|
/// Rewrite a register, inserting reload if spilled
fn rewrite_reg_with_spill(
  reg : @abi.Reg,
  alloc : RegAllocResult,
  block : @block.VCodeBlock,
) -> @abi.Reg {
  match reg {
    @abi.Virtual(vreg) =>
      match alloc.assignments.get(vreg.id) {
        Some(preg) => @abi.Physical(preg)
        None =>
          // Spilled: insert reload and use scratch register
          match alloc.spill_slots.get(vreg.id) {
            Some(slot) => {
              let scratch_preg : @abi.PReg = { index: 16, class: vreg.class }
              let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: @abi.Physical(scratch_preg) })
              block.add_inst(reload_inst)
              @abi.Physical(scratch_preg)
            }
            None => reg // Should not happen
          }
      }
    @abi.Physical(_) => reg
  }
}

// ============ Dead Code Elimination ============

///|
/// Check if an opcode has side effects (cannot be eliminated even if dead)
fn has_side_effects(opcode : @instr.VCodeOpcode) -> Bool {
  match opcode {
    // Memory stores have side effects
    Store(_, _) | StackStore(_) | StorePtr(_, _) => true
    // Type check can trap
    TypeCheckIndirect(_) => true
    // Function calls have side effects
    ReturnCallIndirect(_, _) | CallPtr(_, _, _) => true
    // Traps must not be eliminated
    TrapIfZero(_, _) | TrapIfUge(_) | TrapIfUgt(_) | TrapIf(_, _) => true
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
        if use_reg is @abi.Virtual(vreg) {
          used_vregs.add(vreg.id)
        }
      }
    }

    // Terminator uses
    if block.terminator is Some(term) {
      match term {
        Branch(cond, _, _) =>
          if cond is @abi.Virtual(vreg) {
            used_vregs.add(vreg.id)
          }
        BranchCmp(lhs, rhs, _, _, _, _) => {
          if lhs is @abi.Virtual(vreg) {
            used_vregs.add(vreg.id)
          }
          if rhs is @abi.Virtual(vreg) {
            used_vregs.add(vreg.id)
          }
        }
        BranchCmpImm(lhs, _, _, _, _, _) =>
          if lhs is @abi.Virtual(vreg) {
            used_vregs.add(vreg.id)
          }
        BranchZero(reg, _, _, _, _) =>
          if reg is @abi.Virtual(vreg) {
            used_vregs.add(vreg.id)
          }
        BrTable(index, _, _) =>
          if index is @abi.Virtual(vreg) {
            used_vregs.add(vreg.id)
          }
        Return(values) =>
          for v in values {
            if v is @abi.Virtual(vreg) {
              used_vregs.add(vreg.id)
            }
          }
        Jump(_) | Trap(_) => ()
      }
    }
  }

  // Step 2: Build new function without dead instructions
  let new_func = VCodeFunction::new(func.name)
  new_func.next_vreg_id = func.next_vreg_id
  new_func.int_stack_params = func.int_stack_params
  new_func.max_outgoing_args_size = func.max_outgoing_args_size

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
          if def.reg is @abi.Virtual(vreg) {
            if used_vregs.contains(vreg.id) {
              any_def_used = true
            }
          } else {
            any_def_used = true // Always keep physical reg defs
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
    if block.terminator is Some(term) {
      new_block.set_terminator(term)
    }
  }
  new_func
}

// ============ Convenience API ============

///|
/// Build the register pools for AArch64 allocation
fn build_aarch64_reg_pools(
  func : VCodeFunction,
) -> (Array[@abi.PReg], Array[@abi.PReg], Array[@abi.PReg], Array[@abi.PReg]) {
  // Check if function needs extra results buffer (uses X23)
  let calls_multi = func.calls_multi_value_function()
  let needs_extra = func.needs_extra_results_ptr()
  let needs_x23_reserved = needs_extra || calls_multi

  // Build allocatable register pool:
  // 1. Scratch regs (caller-saved, no save needed) - use first
  // 2. Callee-saved regs (must save/restore) - use when scratch exhausted
  let int_regs : Array[@abi.PReg] = []
  let callee_saved_int_regs : Array[@abi.PReg] = []
  for r in @abi.allocatable_scratch_regs() {
    int_regs.push(r)
  }
  for r in @abi.allocatable_callee_saved_regs() {
    // X23 (index 23) is reserved for extra_results_buffer when needed
    if needs_x23_reserved && r.index == 23 {
      continue
    }
    int_regs.push(r)
    callee_saved_int_regs.push(r)
  }

  // Float regs pool: D0-D7 (caller-saved) + D8-D15 (callee-saved)
  let float_regs : Array[@abi.PReg] = []
  for r in @abi.aapcs64_arg_fprs() {
    float_regs.push(r)
  }
  for r in @abi.callee_saved_fprs() {
    float_regs.push(r)
  }
  let callee_saved_float_regs = @abi.callee_saved_fprs()
  (int_regs, float_regs, callee_saved_int_regs, callee_saved_float_regs)
}

///|
/// Allocate registers for a function using default AArch64 register set
pub fn allocate_registers_aarch64(func : VCodeFunction) -> VCodeFunction {
  // Step 0: Eliminate dead code first
  let func = eliminate_dead_code(func)

  // Build register pools
  let (int_regs, float_regs, callee_saved_int_regs, callee_saved_float_regs) = build_aarch64_reg_pools(
    func,
  )

  // Compute liveness
  let liveness = compute_liveness(func)

  // Allocate using linear scan
  let allocator = LinearScanAllocator::new(
    int_regs,
    float_regs,
    callee_saved_int_regs,
    callee_saved_float_regs~,
  )
  let alloc_result = allocator.allocate(func, liveness)

  // Process constraints and generate RegMove edits
  process_constraints(func, alloc_result)

  // Apply allocation
  apply_allocation(func, alloc_result)
}

///|
/// Allocate registers using the Ion-style backtracking allocator
/// This allocator supports:
/// - Bundle merging for copy coalescing
/// - Priority-based allocation with eviction
/// - Bundle splitting instead of immediate spilling
pub fn allocate_registers_backtracking(func : VCodeFunction) -> VCodeFunction {
  // Step 0: Eliminate dead code first
  let func = eliminate_dead_code(func)

  // Build register pools
  let (int_regs, float_regs, callee_saved_int_regs, callee_saved_float_regs) = build_aarch64_reg_pools(
    func,
  )

  // Compute liveness (Phase 1)
  let liveness = compute_liveness(func)

  // Use backtracking allocator (Phases 2-4)
  let alloc_result = allocate_backtracking(
    func, liveness, int_regs, float_regs, callee_saved_int_regs, callee_saved_float_regs,
  )

  // Process constraints and generate RegMove edits
  process_constraints(func, alloc_result)

  // Apply allocation
  apply_allocation(func, alloc_result)
}

///|
/// Allocation statistics for comparison
pub(all) struct AllocStats {
  mut num_vregs : Int // Total virtual registers
  mut num_spill_slots : Int // Number of spill slots used
  num_spills : Int // Number of spill operations
  num_reloads : Int // Number of reload operations
  num_moves : Int // Number of move operations inserted
  total_insts : Int // Total instructions after allocation
}

///|
fn AllocStats::to_string(self : AllocStats) -> String {
  "vregs=\{self.num_vregs}, spill_slots=\{self.num_spill_slots}, spills=\{self.num_spills}, reloads=\{self.num_reloads}, moves=\{self.num_moves}, total_insts=\{self.total_insts}"
}

///|
pub impl Show for AllocStats with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Count instructions by type in allocated function
fn count_instructions(func : VCodeFunction) -> AllocStats {
  let mut num_spills = 0
  let mut num_reloads = 0
  let mut num_moves = 0
  let mut total_insts = 0
  for block in func.blocks {
    for inst in block.insts {
      total_insts += 1
      match inst.opcode {
        @instr.StackStore(_) => num_spills += 1
        @instr.StackLoad(_) => num_reloads += 1
        @instr.Move => num_moves += 1
        _ => ()
      }
    }
  }
  {
    num_vregs: 0,
    num_spill_slots: 0,
    num_spills,
    num_reloads,
    num_moves,
    total_insts,
  }
}

///|
/// Get allocation statistics using linear scan allocator
pub fn get_linear_scan_stats(func : VCodeFunction) -> AllocStats {
  let func = eliminate_dead_code(func)
  let (int_regs, float_regs, callee_saved_int_regs, callee_saved_float_regs) = build_aarch64_reg_pools(
    func,
  )
  let liveness = compute_liveness(func)

  // Count vregs
  let num_vregs = liveness.intervals.length()
  let allocator = LinearScanAllocator::new(
    int_regs,
    float_regs,
    callee_saved_int_regs,
    callee_saved_float_regs~,
  )
  let alloc_result = allocator.allocate(func, liveness)
  process_constraints(func, alloc_result)
  let allocated = apply_allocation(func, alloc_result)
  let stats = count_instructions(allocated)
  stats.num_vregs = num_vregs
  stats.num_spill_slots = alloc_result.num_spill_slots
  stats
}

///|
/// Get allocation statistics using backtracking allocator
pub fn get_backtracking_stats(func : VCodeFunction) -> AllocStats {
  let func = eliminate_dead_code(func)
  let (int_regs, float_regs, callee_saved_int_regs, callee_saved_float_regs) = build_aarch64_reg_pools(
    func,
  )
  let liveness = compute_liveness(func)

  // Count vregs
  let num_vregs = liveness.intervals.length()
  let alloc_result = allocate_backtracking(
    func, liveness, int_regs, float_regs, callee_saved_int_regs, callee_saved_float_regs,
  )
  process_constraints(func, alloc_result)
  let allocated = apply_allocation(func, alloc_result)
  let stats = count_instructions(allocated)
  stats.num_vregs = num_vregs
  stats.num_spill_slots = alloc_result.num_spill_slots
  stats
}

///|
/// Compare both allocators and return formatted comparison string
pub fn compare_allocators(func : VCodeFunction) -> String {
  let linear_stats = get_linear_scan_stats(func)
  let backtrack_stats = get_backtracking_stats(func)
  let mut result = "=== Register Allocator Comparison ===\n"
  result = result + "Linear Scan:  \{linear_stats}\n"
  result = result + "Backtracking: \{backtrack_stats}\n"

  // Calculate improvements
  let spill_diff = linear_stats.num_spill_slots -
    backtrack_stats.num_spill_slots
  let inst_diff = linear_stats.total_insts - backtrack_stats.total_insts
  if spill_diff > 0 {
    result = result + "Improvement: \{spill_diff} fewer spill slots\n"
  } else if spill_diff < 0 {
    result = result + "Regression: \{-spill_diff} more spill slots\n"
  }
  if inst_diff > 0 {
    result = result + "Improvement: \{inst_diff} fewer instructions\n"
  } else if inst_diff < 0 {
    result = result + "Regression: \{-inst_diff} more instructions\n"
  }
  result
}
