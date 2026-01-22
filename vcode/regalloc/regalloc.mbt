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
/// Using #valtype for stack allocation - this struct is created/compared frequently
#valtype
struct ProgPoint {
  block : Int // Block index
  inst : Int // Instruction index within block (-1 for block params)
  pos : ProgPos // Before or after the instruction
} derive(Eq)

///|
/// Position relative to an instruction
pub enum ProgPos {
  Before // Before the instruction executes (uses happen here)
  After // After the instruction executes (defs happen here)
} derive(Eq)

///|
/// Compare two program points using a block order array
/// This is used by the register allocator to correctly order points in non-linear CFGs
/// Note: block_order[block_id] = execution order (O(1) lookup vs O(log n) for Map)
fn ProgPoint::compare_with_order(
  self : ProgPoint,
  other : ProgPoint,
  block_order : FixedArray[Int],
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
pub struct LiveInterval {
  vreg : @abi.VReg
  start : ProgPoint // First use or definition
  mut end : ProgPoint // Last use
  // Use positions within the interval (for spill cost calculation)
  uses : Array[ProgPoint]
  // Register hint (e.g., from a move instruction)
  hint : @abi.PReg?
  // Assigned physical register (for display in debug output)
  assigned : @abi.PReg?
  // Spill slot if spilled (for display in debug output)
  spill_slot : Int?
  // Whether this interval crosses a function call (cannot use caller-saved registers)
  mut crosses_call : Bool
  // Whether this interval crosses a C call (stricter ABI assumptions)
  mut crosses_c_call : Bool
}

///|
fn LiveInterval::new(vreg : @abi.VReg, start : ProgPoint) -> LiveInterval {
  {
    vreg,
    start,
    end: start,
    uses: [start],
    hint: None,
    assigned: None,
    spill_slot: None,
    crosses_call: false,
    crosses_c_call: false,
  }
}

///|
/// Extend interval using block execution order for comparison
fn LiveInterval::extend_with_order(
  self : LiveInterval,
  point : ProgPoint,
  block_order : FixedArray[Int],
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
struct UseDefInfo {
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
    Jump(target, _) => [target]
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
pub struct LivenessResult {
  // Live intervals for each vreg
  intervals : Map[Int, LiveInterval]
  // Use-def chains
  use_def : Map[Int, UseDefInfo]
  // Block live-in sets (vregs live at block entry)
  live_in : Array[Set[Int]]
  // Block live-out sets (vregs live at block exit)
  live_out : Array[Set[Int]]
  // Block order: block_order[block_id] = linear position (O(1) lookup)
  block_order : FixedArray[Int]
  // Call points (block_idx, inst_idx) - instructions that clobber caller-saved registers
  call_points : Array[(ProgPoint, @instr.CallConv)]
}

///|
/// Compute reverse postorder of blocks (for linearizing the CFG)
/// Returns a FixedArray where order[block_id] = position in reverse postorder
fn compute_reverse_postorder(func : VCodeFunction) -> FixedArray[Int] {
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
          Jump(target, _) => dfs(func, target, visited, postorder)
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
  let order : FixedArray[Int] = FixedArray::make(n, 0)
  let len = postorder.length()
  for i, block_id in postorder {
    order[block_id] = len - 1 - i
  }
  order
}

///|
/// Compute liveness information for a VCode function
pub fn compute_liveness(func : VCodeFunction) -> LivenessResult {
  let num_blocks = func.blocks.length()
  let live_in : Array[Set[Int]] = []
  let live_out : Array[Set[Int]] = []
  for _ in 0..<num_blocks {
    live_in.push(Set::new())
    live_out.push(Set::new())
  }
  // Compute block order directly as FixedArray
  let block_order = compute_reverse_postorder(func)
  let result : LivenessResult = {
    intervals: {},
    use_def: {},
    live_in,
    live_out,
    block_order,
    call_points: [],
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
    // Block parameters are SSA definitions at block entry.
    // Their incoming values are passed via Jump(target, args) on CFG edges.
    for param in block.params {
      let info = if result.use_def.get(param.id) is Some(existing) {
        existing
      } else {
        let new_info = UseDefInfo::new(param)
        result.use_def.set(param.id, new_info)
        new_info
      }
      let def_point : ProgPoint = { block: block_idx, inst: -1, pos: After }
      if info.def_point is Some(_) {
        abort("block param defined twice")
      }
      info.def_point = Some(def_point)
      // Also add a use point at block entry to keep it live through the block.
      info.use_points.push({ block: block_idx, inst: 0, pos: Before })
    }

    // Process instructions
    for inst_idx, inst in block.insts {
      // Record call points for caller-saved register handling
      // Design: use call_type() to determine if an instruction
      // behaves like a call (clobbers caller-saved registers)
      if inst.opcode.call_type() is @instr.Regular {
        let conv = match inst.opcode {
          @instr.CallPtr(_, _, call_conv) => call_conv
          _ => @instr.Wasm
        }
        result.call_points.push(
          ({ block: block_idx, inst: inst_idx, pos: After }, conv),
        )
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
          let new_def : ProgPoint = {
            block: block_idx,
            inst: inst_idx,
            pos: After,
          }
          if info.def_point is Some(_) {
            abort("vreg defined multiple times (SSA violation)")
          }
          info.def_point = Some(new_def)
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
        Jump(_, args) =>
          for a in args {
            record_term_use(a, result, block_idx, inst_idx)
          }
        Branch(cond, _, _) => record_term_use(cond, result, block_idx, inst_idx)
        BranchCmp(lhs, rhs, _, _, _, _) => {
          record_term_use(lhs, result, block_idx, inst_idx)
          record_term_use(rhs, result, block_idx, inst_idx)
        }
        BranchCmpImm(lhs, _, _, _, _, _) =>
          record_term_use(lhs, result, block_idx, inst_idx)
        BranchZero(reg, _, _, _, _) =>
          record_term_use(reg, result, block_idx, inst_idx)
        BrTable(index, _, _) =>
          record_term_use(index, result, block_idx, inst_idx)
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

    // Block parameters are SSA definitions at block entry.
    for param in block.params {
      def_set.add(param.id)
    }

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
        Jump(_, args) =>
          for a in args {
            if a is @abi.Virtual(vreg) && !def_set.contains(vreg.id) {
              use_set.add(vreg.id)
            }
          }
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
        BrTable(index, _, _) =>
          if index is @abi.Virtual(vreg) && !def_set.contains(vreg.id) {
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
    for entry in result.call_points {
      let (call_point, call_conv) = entry
      // An interval crosses a call if:
      // - The call is strictly after the interval's start AND before the interval's end
      //   (Values defined by the call itself start at the same progpoint and do not
      //    need to survive across the call.)
      let start_cmp = interval.start.compare_with_order(call_point, block_order)
      let end_cmp = interval.end.compare_with_order(call_point, block_order)
      // start < call_point < end (interval is live across the call)
      if start_cmp < 0 && end_cmp > 0 {
        interval.crosses_call = true
        if call_conv is @instr.C {
          interval.crosses_c_call = true
        }
        break
      }
    }
    result.intervals.set(vreg_id, interval)
  }
}

// ============ RegMove for Constraint Processing ============

///|
/// A register move instruction (from regalloc constraint processing)
/// Move operation between registers
struct RegMove {
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
struct InstEdits {
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
// 2. For cycles, use reserved scratch registers to break the cycle.

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
        // All remaining moves form cycles. Break the cycle by saving one
        // destination register to a reserved scratch register, then continue.
        let mv = pending.remove(0)
        guard !mv.to.is_spilled() else {
          abort("cycle breaker requires register destination")
        }
        // Select a scratch register in the right bank that doesn't alias mv.to.
        let scratch_idx = if mv.to.index == 16 { 17 } else { 16 }
        let temp_preg : @abi.PReg = { index: scratch_idx, class: mv.to.class }

        // Save the destination's original value: temp <- dst
        result.push({ from: mv.to, to: temp_preg, class: mv.class })

        // Redirect all uses of the saved destination as a source to read from temp.
        for i in 0..<pending.length() {
          if !pending[i].from.is_spilled() && aliases(pending[i].from, mv.to) {
            pending[i] = {
              from: temp_preg,
              to: pending[i].to,
              class: pending[i].class,
            }
          }
        }

        // Re-add the original move; it should now be schedulable.
        pending.push(mv)
      }
    }
  }
  result
}

///|
/// Register allocation result
pub struct RegAllocResult {
  // Map from vreg id to assigned physical register
  assignments : Map[Int, @abi.PReg]
  // Map from vreg id to spill slot (if spilled)
  spill_slots : Map[Int, Int]
  // Total number of spill slots used
  num_spill_slots : Int
  // Constraint edits: (block_idx, inst_idx) -> edits to insert
  // Fixed register constraint handling
  inst_edits : Map[(Int, Int), InstEdits]
}

// ============ Reload Coalescing ============

///|
/// A reload interval tracks where a reloaded value can be kept alive
/// to eliminate redundant loads from the same spill slot
priv struct ReloadInterval {
  vreg_class : @abi.RegClass // Register class
  mut preg : @abi.PReg? // Allocated register (None = use scratch)
}

///|
/// Compute reload intervals for spilled values in each block
/// Returns a map: (block_idx, spill_slot) -> ReloadInterval
fn compute_reload_intervals(
  func : VCodeFunction,
  alloc : RegAllocResult,
) -> Map[(Int, Int), ReloadInterval] {
  let intervals : Map[(Int, Int), ReloadInterval] = {}
  for block_idx, block in func.blocks {
    // Track uses of spilled vregs in this block
    // Key: spill_slot, Value: (first_inst, last_inst, vreg_class)
    let slot_uses : Map[Int, (Int, Int, @abi.RegClass)] = {}
    for inst_idx, inst in block.insts {
      for use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) {
          if alloc.spill_slots.get(vreg.id) is Some(slot) {
            // Do not reload-coalesce vector values: there is no safe
            // non-allocatable vector scratch register bank, and AAPCS64 only
            // guarantees preserving the low 64 bits of V8-V15.
            if vreg.class is @abi.Vector {
              continue
            }
            match slot_uses.get(slot) {
              Some((first, _, cls)) =>
                slot_uses.set(slot, (first, inst_idx, cls))
              None => slot_uses.set(slot, (inst_idx, inst_idx, vreg.class))
            }
          }
        }
      }
    }
    // Create reload intervals for slots used multiple times
    for slot, info in slot_uses {
      let (first_inst, last_inst, vreg_class) = info
      if last_inst > first_inst {
        // Multiple uses - worth coalescing
        intervals.set((block_idx, slot), { vreg_class, preg: None })
      }
    }
  }
  intervals
}

///|
/// Try to allocate registers for reload intervals
/// Uses callee-saved registers that aren't already in use
fn allocate_reload_registers(
  func : VCodeFunction,
  alloc : RegAllocResult,
  intervals : Map[(Int, Int), ReloadInterval],
) -> Unit {
  // Collect which registers are already allocated to virtual registers.
  // Reload coalescing must NOT clobber any register that the allocator uses
  // (including live-ins like vmctx), otherwise a StackLoad can overwrite a
  // still-live value and cause memory corruption / traps.
  let used_int_regs : @hashset.HashSet[Int] = @hashset.HashSet::new()
  let used_float_regs : @hashset.HashSet[Int] = @hashset.HashSet::new()
  for _, preg in alloc.assignments {
    match preg.class {
      @abi.Int => used_int_regs.add(preg.index) |> ignore
      _ => used_float_regs.add(preg.index) |> ignore
    }
  }

  // Reserve special registers that are not part of the allocator pool but are
  // used by the ABI / codegen.
  // - X19 is reserved for vmctx-related loads in the prologue when needed.
  used_int_regs.add(19) |> ignore
  // - X21 is the pinned VMContext register (enable_pinned_reg).
  used_int_regs.add(@abi.REG_VMCTX) |> ignore
  // - X20 is reserved for cached memory0 descriptor pointer when needed.
  if func.uses_mem0() {
    used_int_regs.add(@abi.REG_MEM0_DESC) |> ignore
  }
  // - X23 is reserved for extra_results_buffer when needed.
  let calls_multi = func.calls_multi_value_function()
  let needs_extra = func.needs_extra_results_ptr()
  let needs_x23_reserved = needs_extra || calls_multi
  if needs_x23_reserved {
    used_int_regs.add(23) |> ignore
  }

  // Candidate callee-saved registers for reload coalescing.
  // Only use registers that are NOT allocated to any vreg to avoid clobbering
  // live values (including parameters that may stay live across a block).
  let reload_int_regs = [20, 22, 23, 24, 25, 26, 27, 28]
  let reload_float_regs = [8, 9, 10, 11, 12, 13, 14, 15]

  // Per-block allocation to avoid conflicts within a block
  for block_idx, _block in func.blocks {
    // Track which reload registers are in use within this block
    let block_int_used : @hashset.HashSet[Int] = @hashset.HashSet::new()
    let block_float_used : @hashset.HashSet[Int] = @hashset.HashSet::new()
    // Allocate reload registers for intervals in this block
    for key, interval in intervals {
      let (b_idx, _) = key
      if b_idx != block_idx {
        continue
      }
      match interval.vreg_class {
        @abi.Int =>
          for idx in reload_int_regs {
            if used_int_regs.contains(idx) || block_int_used.contains(idx) {
              continue
            }
            interval.preg = Some({ index: idx, class: interval.vreg_class })
            block_int_used.add(idx) |> ignore
            break
          }
        @abi.Vector => ()
        _ =>
          for idx in reload_float_regs {
            if used_float_regs.contains(idx) || block_float_used.contains(idx) {
              continue
            }
            interval.preg = Some({ index: idx, class: interval.vreg_class })
            block_float_used.add(idx) |> ignore
            break
          }
      }
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
          } else if use_reg is @abi.Physical(preg) {
            if preg.index != required_preg.index {
              edits.before.push({
                from: preg,
                to: required_preg,
                class: preg.class,
              })
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

  // Compute reload intervals for spill coalescing
  let reload_intervals = compute_reload_intervals(func, alloc)
  allocate_reload_registers(func, alloc, reload_intervals)

  // Convert function parameters
  // Note: all params use X0-X7 (int) or V0-V7 (float)
  // vmctx is an explicit param in the function signature
  let max_int_params = @abi.MAX_REG_PARAMS // 8
  let max_float_params = @abi.MAX_FLOAT_REG_PARAMS // 8
  let mut int_idx = 0
  let mut float_idx = 0

  // For spilled params, we must store the incoming ABI register to the spill slot
  // in the entry block so subsequent reloads see the correct value.
  let spilled_param_stores : Array[(@abi.PReg, Int)] = []
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

        // If the param is spilled, capture a store from the incoming ABI register
        // to its spill slot. This makes spilling params safe.
        if alloc.spill_slots.get(param.id) is Some(slot) {
          match param.class {
            @abi.Int =>
              if int_idx < max_int_params {
                spilled_param_stores.push(
                  ({ index: int_idx, class: @abi.Int }, slot),
                )
              }
            @abi.Float32 | @abi.Float64 =>
              if float_idx < max_float_params {
                spilled_param_stores.push(
                  ({ index: float_idx, class: @abi.Float64 }, slot),
                )
              }
            @abi.Vector =>
              if float_idx < max_float_params {
                spilled_param_stores.push(
                  ({ index: float_idx, class: @abi.Vector }, slot),
                )
              }
          }
        }

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

    // Entry block: materialize spilled params into spill slots.
    if block_idx == 0 {
      for entry in spilled_param_stores {
        let (src_preg, slot) = entry
        let store_inst = @instr.VCodeInst::new(@instr.StackStore(slot * 8))
        store_inst.add_use(@abi.Physical(src_preg))
        new_block.add_inst(store_inst)
      }
    }

    // Copy block params
    for param in block.params {
      new_block.params.push(param)
    }

    // Block-level scratch register counter to avoid aliasing across instructions
    let mut block_scratch_idx = 0

    // Track which spill slots have been loaded into coalesced reload registers
    // Key: spill_slot, Value: preg holding the reloaded value
    let active_reloads : Map[Int, @abi.PReg] = {}

    // Precompute per-block defs/uses for swap-aware jump-arg handling.
    let vreg_def_info : Map[Int, (Int, Int)] = {}
    let vreg_used_in_insts : Set[Int] = Set::new()
    let vreg_used_in_term : Set[Int] = Set::new()
    for inst_idx, inst in block.insts {
      for use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) {
          vreg_used_in_insts.add(vreg.id)
        }
      }
      for def_pos, def in inst.defs {
        if def.reg is @abi.Virtual(vreg) {
          vreg_def_info.set(vreg.id, (inst_idx, def_pos))
        }
      }
    }
    if block.terminator is Some(term) {
      let term_uses = match term {
        @instr.VCodeTerminator::Jump(_, args)
        | @instr.VCodeTerminator::Return(args) => args
        @instr.VCodeTerminator::Branch(cond, _, _)
        | @instr.VCodeTerminator::BranchZero(cond, _, _, _, _)
        | @instr.VCodeTerminator::BrTable(cond, _, _) => [cond]
        @instr.VCodeTerminator::BranchCmp(lhs, rhs, _, _, _, _) => [lhs, rhs]
        @instr.VCodeTerminator::BranchCmpImm(lhs, _, _, _, _, _) => [lhs]
        @instr.VCodeTerminator::Trap(_) => []
      }
      for use_reg in term_uses {
        if use_reg is @abi.Virtual(vreg) {
          vreg_used_in_term.add(vreg.id)
        }
      }
    }
    let jump_arg_candidates : Map[Int, (Int, Int)] = {}
    let jump_arg_counts : Map[Int, Int] = {}
    if block.terminator is Some(@instr.VCodeTerminator::Jump(_, args)) {
      for arg in args {
        if arg is @abi.Virtual(vreg) &&
          vreg_used_in_term.contains(vreg.id) &&
          !vreg_used_in_insts.contains(vreg.id) {
          let count = jump_arg_counts.get(vreg.id).unwrap_or(0)
          jump_arg_counts.set(vreg.id, count + 1)
          if vreg_def_info.get(vreg.id) is Some((def_idx, def_pos)) {
            let def_inst = block.insts[def_idx]
            let has_fixed = def_pos < def_inst.def_constraints.length() &&
              def_inst.def_constraints[def_pos] is @abi.FixedReg(_)
            if !has_fixed {
              jump_arg_candidates.set(vreg.id, (def_idx, def_pos))
            }
          }
        }
      }
    }
    let orig_inst_to_new_idx : Map[Int, Int] = {}

    // Process instructions
    for inst_idx, inst in block.insts {
      // First, insert reload instructions for any spilled uses
      // Track which scratch registers are used for each spilled vreg
      let spill_regs : Map[Int, @abi.PReg] = {}

      // X16, X17 are the only truly safe scratch registers because:
      // - X0-X7: parameter registers
      // - X8-X15: caller-saved temporaries (may be in use)
      // - X18: platform reserved (TLS on some platforms)
      // - X19+: allocatable callee-saved registers
      //
      // For uses with FixedReg constraints (e.g., CallPtr/ReturnCallIndirect args),
      // constraint edits will handle the reload, so we skip normal spilled use handling.

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
            // Check FixedReg constraint first - constraint edits will handle the reload
            if i < inst.use_constraints.length() &&
              inst.use_constraints[i] is @abi.FixedReg(_) {
              // This use has a FixedReg constraint - constraint edits will handle the reload
              // Use spilled encoding so use rewriting puts the fixed register
              let spilled_preg = @abi.PReg::spilled(slot, scratch_class)
              spill_regs.set(vreg.id, spilled_preg)
            } else if active_reloads.get(slot) is Some(reload_preg) {
              // Regular spilled uses (non-CallIndirect instructions)
              // Check if we have a coalesced reload register for this slot
              // Value already loaded - reuse the register (no new load needed)
              spill_regs.set(vreg.id, reload_preg)
            } else if reload_intervals.get((block_idx, slot)) is Some(interval) &&
              interval.preg is Some(reload_preg) {
              // First use of this slot in the interval - load into coalesced register
              spill_regs.set(vreg.id, reload_preg)
              active_reloads.set(slot, reload_preg)
              let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: @abi.Physical(reload_preg) })
              new_block.add_inst(reload_inst)
            } else {
              // No coalescing available - use scratch registers X16, X17
              let scratch_candidates = [16, 17]
              let mut scratch_idx = inst_spill_idx % 2
              // Find a scratch register that's not already in use
              let mut attempts = 0
              while used_regs.contains(scratch_candidates[scratch_idx]) &&
                    attempts < 2 {
                scratch_idx = (scratch_idx + 1) % 2
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
          @abi.Virtual(vreg) => {
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
                // Use the fixed register - constraint processing handles any move/spill.
                new_inst.add_def({ reg: @abi.Physical(fixed_preg) })
              None =>
                match alloc.assignments.get(vreg.id) {
                  Some(preg) => new_inst.add_def({ reg: @abi.Physical(preg) })
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
      for i, use_reg in inst.uses {
        match use_reg {
          @abi.Virtual(vreg) =>
            match alloc.assignments.get(vreg.id) {
              Some(preg) => {
                // Preserve FixedReg constraints in the rewritten instruction.
                // Constraint processing already inserts the needed move(s).
                let fixed_preg_opt = if i < inst.use_constraints.length() {
                  match inst.use_constraints[i] {
                    @abi.FixedReg(fixed_preg) => Some(fixed_preg)
                    _ => None
                  }
                } else {
                  None
                }
                match fixed_preg_opt {
                  Some(fixed_preg) =>
                    new_inst.add_use(@abi.Physical(fixed_preg))
                  None => new_inst.add_use(@abi.Physical(preg))
                }
              }
              None =>
                // Spilled: use the scratch register we reloaded into
                match spill_regs.get(vreg.id) {
                  Some(scratch_preg) =>
                    // Check if scratch_preg is a spilled encoding (meaning FixedReg constraint)
                    if scratch_preg.is_spilled() {
                      // Use the fixed register from the constraint
                      // Constraint edits will load the value there
                      guard i < inst.use_constraints.length() else {
                        abort("spilled encoding without constraint")
                      }
                      guard inst.use_constraints[i] is @abi.FixedReg(fixed_preg) else {
                        abort("spilled encoding without FixedReg constraint")
                      }
                      new_inst.add_use(@abi.Physical(fixed_preg))
                    } else {
                      new_inst.add_use(@abi.Physical(scratch_preg))
                    }
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
          @abi.Physical(preg) => {
            let fixed_preg_opt = if i < inst.use_constraints.length() {
              match inst.use_constraints[i] {
                @abi.FixedReg(fixed_preg) => Some(fixed_preg)
                _ => None
              }
            } else {
              None
            }
            match fixed_preg_opt {
              Some(fixed_preg) => new_inst.add_use(@abi.Physical(fixed_preg))
              None => new_inst.add_use(@abi.Physical(preg))
            }
          }
        }
      }

      // Process constraint edits: insert moves before the instruction
      // Fixed register constraint handling
      // Use parallel move resolver to handle cyclic dependencies
      if alloc.inst_edits.get((block_idx, inst_idx)) is Some(edits) {
        let resolved_moves = resolve_parallel_moves(edits.before)
        // Track which spill slots have been reloaded in this batch for coalescing
        let reloaded_slots : Map[Int, @abi.PReg] = {}
        for mv in resolved_moves {
          if mv.to.is_spilled() {
            // Store to spill slot.
            let to_slot = mv.to.get_spill_slot()
            if mv.from.is_spilled() {
              // Spill-to-spill move: reload via scratch, then store.
              let from_slot = mv.from.get_spill_slot()
              if reloaded_slots.get(from_slot) is Some(source_preg) {
                let store_inst = @instr.VCodeInst::new(StackStore(to_slot * 8))
                store_inst.add_use(@abi.Physical(source_preg))
                new_block.add_inst(store_inst)
              } else {
                let scratch_class = match mv.class {
                  @abi.Float32 | @abi.Float64 => @abi.Float64
                  _ => mv.class
                }
                let scratch_preg : @abi.PReg = {
                  index: 16,
                  class: scratch_class,
                }
                let reload_inst = @instr.VCodeInst::new(
                  StackLoad(from_slot * 8),
                )
                reload_inst.add_def({ reg: @abi.Physical(scratch_preg) })
                new_block.add_inst(reload_inst)
                let store_inst = @instr.VCodeInst::new(StackStore(to_slot * 8))
                store_inst.add_use(@abi.Physical(scratch_preg))
                new_block.add_inst(store_inst)
              }
            } else {
              let store_inst = @instr.VCodeInst::new(StackStore(to_slot * 8))
              store_inst.add_use(@abi.Physical(mv.from))
              new_block.add_inst(store_inst)
            }
          } else if mv.from.is_spilled() {
            // Reload from spill slot into a register.
            let slot = mv.from.get_spill_slot()
            if reloaded_slots.get(slot) is Some(source_preg) {
              // This slot was already reloaded - use mov instead of another load
              let move_inst = @instr.VCodeInst::new(Move)
              move_inst.add_def({ reg: @abi.Physical(mv.to) })
              move_inst.add_use(@abi.Physical(source_preg))
              new_block.add_inst(move_inst)
            } else {
              // First reload of this slot - emit StackLoad and record
              let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: @abi.Physical(mv.to) })
              new_block.add_inst(reload_inst)
              reloaded_slots.set(slot, mv.to)
            }
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
      orig_inst_to_new_idx.set(inst_idx, new_block.insts.length() - 1)

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
        Jump(target, args) => {
          // Implement SSA block argument passing at the machine level.
          // Block params are SSA defs at target entry; here we materialize the
          // incoming values into the allocated locations for those params.

          fn vreg_location(vreg : @abi.VReg) -> @abi.PReg {
            match alloc.assignments.get(vreg.id) {
              Some(p) => p
              None =>
                match alloc.spill_slots.get(vreg.id) {
                  Some(slot) => @abi.PReg::spilled(slot, vreg.class)
                  None => abort("missing allocation")
                }
            }
          }

          fn reg_location(reg : @abi.Reg) -> @abi.PReg {
            match reg {
              @abi.Physical(p) => p
              @abi.Virtual(v) => vreg_location(v)
            }
          }

          let moves : Array[RegMove] = []
          let move_src_vregs : Array[Int?] = []
          if target >= 0 && target < func.blocks.length() {
            let target_block = func.blocks[target]
            for i, param in target_block.params {
              if i >= args.length() {
                break
              }
              let from = reg_location(args[i])
              let to = vreg_location(param)

              // Same location: nothing to do.
              // Compare both index and register bank (int vs float/vector).
              let same_bank = match (from.class, to.class) {
                (@abi.Int, @abi.Int) => true
                (
                  @abi.Float32
                  | @abi.Float64
                  | @abi.Vector,
                  @abi.Float32
                  | @abi.Float64
                  | @abi.Vector,
                ) => true
                _ => false
              }
              if from.index == to.index && same_bank {
                continue
              }
              moves.push({ from, to, class: param.class })
              let src_vreg_id = match args[i] {
                @abi.Virtual(vreg) => Some(vreg.id)
                _ => None
              }
              move_src_vregs.push(src_vreg_id)
            }
          }

          // Swap-aware jump-arg coalescing: avoid 2-cycle swaps by redirecting
          // a locally-defined jump arg into a scratch register when possible.
          if !moves.is_empty() && !jump_arg_candidates.is_empty() {
            fn same_preg(a : @abi.PReg, b : @abi.PReg) -> Bool {
              a.index == b.index
            }

            fn inst_uses_preg(
              inst : @instr.VCodeInst,
              preg : @abi.PReg,
            ) -> Bool {
              for def in inst.defs {
                if def.reg is @abi.Physical(p) && same_preg(p, preg) {
                  return true
                }
              }
              for use_reg in inst.uses {
                if use_reg is @abi.Physical(p) && same_preg(p, preg) {
                  return true
                }
              }
              false
            }

            fn scratch_available(
              new_block : @block.VCodeBlock,
              def_new_idx : Int,
              preg : @abi.PReg,
            ) -> Bool {
              for i in (def_new_idx + 1)..<new_block.insts.length() {
                if inst_uses_preg(new_block.insts[i], preg) {
                  return false
                }
              }
              true
            }

            fn pick_scratch_reg(
              new_block : @block.VCodeBlock,
              def_new_idx : Int,
            ) -> @abi.PReg? {
              let scratch_regs = [@abi.SCRATCH_REG_1, @abi.SCRATCH_REG_2]
              for reg_idx in scratch_regs {
                let preg : @abi.PReg = { index: reg_idx, class: @abi.Int }
                if scratch_available(new_block, def_new_idx, preg) {
                  return Some(preg)
                }
              }
              None
            }

            let rewritten : Set[Int] = Set::new()
            let mut broke_cycle = false
            for i in 0..<moves.length() {
              if broke_cycle {
                break
              }
              let mv_i = moves[i]
              if mv_i.from.is_spilled() || mv_i.to.is_spilled() {
                continue
              }
              if mv_i.class is @abi.Int {
                ()
              } else {
                continue
              }
              for j in (i + 1)..<moves.length() {
                let mv_j = moves[j]
                if mv_j.from.is_spilled() || mv_j.to.is_spilled() {
                  continue
                }
                if mv_j.class is @abi.Int {
                  ()
                } else {
                  continue
                }
                if !same_preg(mv_i.from, mv_j.to) ||
                  !same_preg(mv_i.to, mv_j.from) {
                  continue
                }
                fn try_rewrite_move(
                  move_idx : Int,
                  moves : Array[RegMove],
                  move_src_vregs : Array[Int?],
                  jump_arg_candidates : Map[Int, (Int, Int)],
                  jump_arg_counts : Map[Int, Int],
                  alloc : RegAllocResult,
                  orig_inst_to_new_idx : Map[Int, Int],
                  new_block : @block.VCodeBlock,
                  rewritten : Set[Int],
                ) -> Bool {
                  guard move_idx < move_src_vregs.length() else { return false }
                  guard move_src_vregs[move_idx] is Some(vreg_id) else {
                    return false
                  }
                  if jump_arg_counts.get(vreg_id).unwrap_or(0) != 1 {
                    return false
                  }
                  if rewritten.contains(vreg_id) {
                    return false
                  }
                  guard jump_arg_candidates.get(vreg_id)
                    is Some((def_idx, def_pos)) else {
                    return false
                  }
                  guard alloc.assignments.get(vreg_id) is Some(assigned_preg) else {
                    return false
                  }
                  if assigned_preg.class is @abi.Int {
                    ()
                  } else {
                    return false
                  }
                  guard orig_inst_to_new_idx.get(def_idx) is Some(def_new_idx) else {
                    return false
                  }
                  let new_inst = new_block.insts[def_new_idx]
                  if new_inst.defs.length() != 1 {
                    return false
                  }
                  guard pick_scratch_reg(new_block, def_new_idx)
                    is Some(scratch_preg) else {
                    return false
                  }
                  new_inst.defs[def_pos] = { reg: @abi.Physical(scratch_preg) }
                  moves[move_idx] = {
                    from: scratch_preg,
                    to: moves[move_idx].to,
                    class: moves[move_idx].class,
                  }
                  rewritten.add(vreg_id)
                  true
                }

                if try_rewrite_move(
                    i, moves, move_src_vregs, jump_arg_candidates, jump_arg_counts,
                    alloc, orig_inst_to_new_idx, new_block, rewritten,
                  ) ||
                  try_rewrite_move(
                    j, moves, move_src_vregs, jump_arg_candidates, jump_arg_counts,
                    alloc, orig_inst_to_new_idx, new_block, rewritten,
                  ) {
                  broke_cycle = true
                  break
                }
              }
            }
          }

          // Resolve all moves together (including spill destinations), otherwise
          // a register move can clobber a source before it is stored to a spill slot.
          let resolved_moves = resolve_parallel_moves(moves)
          for mv in resolved_moves {
            if mv.to.is_spilled() {
              let to_slot = mv.to.get_spill_slot()
              if mv.from.is_spilled() {
                let from_slot = mv.from.get_spill_slot()
                let scratch_class = match mv.class {
                  @abi.Float32 | @abi.Float64 => @abi.Float64
                  _ => mv.class
                }
                let scratch_preg : @abi.PReg = {
                  index: 16,
                  class: scratch_class,
                }
                let reload_inst = @instr.VCodeInst::new(
                  StackLoad(from_slot * 8),
                )
                reload_inst.add_def({ reg: @abi.Physical(scratch_preg) })
                new_block.add_inst(reload_inst)
                let store_inst = @instr.VCodeInst::new(StackStore(to_slot * 8))
                store_inst.add_use(@abi.Physical(scratch_preg))
                new_block.add_inst(store_inst)
              } else {
                let store_inst = @instr.VCodeInst::new(StackStore(to_slot * 8))
                store_inst.add_use(@abi.Physical(mv.from))
                new_block.add_inst(store_inst)
              }
            } else if mv.from.is_spilled() {
              let slot = mv.from.get_spill_slot()
              let reload_inst = @instr.VCodeInst::new(StackLoad(slot * 8))
              reload_inst.add_def({ reg: @abi.Physical(mv.to) })
              new_block.add_inst(reload_inst)
            } else {
              let move_inst = @instr.VCodeInst::new(Move)
              move_inst.add_def({ reg: @abi.Physical(mv.to) })
              move_inst.add_use(@abi.Physical(mv.from))
              new_block.add_inst(move_inst)
            }
          }

          // After materializing block args, the jump itself has no args.
          @instr.Jump(target, [])
        }
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
  eliminate_trivial_moves(new_func)
}

///|
/// Remove redundant Move instructions where source and destination alias.
fn eliminate_trivial_moves(func : VCodeFunction) -> VCodeFunction {
  fn same_location(a : @abi.PReg, b : @abi.PReg) -> Bool {
    let same_bank = match (a.class, b.class) {
      (@abi.Int, @abi.Int) => true
      (
        @abi.Float32
        | @abi.Float64
        | @abi.Vector,
        @abi.Float32
        | @abi.Float64
        | @abi.Vector,
      ) => true
      _ => false
    }
    a.index == b.index && same_bank
  }

  let new_func = func.clone_base()
  new_func.set_num_spill_slots(func.num_spill_slots)
  for param in func.params {
    new_func.params.push(param)
  }
  for preg in func.param_pregs {
    new_func.param_pregs.push(preg)
  }
  for result in func.results {
    new_func.results.push(result)
  }
  for ty in func.result_types {
    new_func.result_types.push(ty)
  }
  for block in func.blocks {
    let new_block = new_func.new_block()
    for param in block.params {
      new_block.params.push(param)
    }
    for inst in block.insts {
      let mut skip = false
      if inst.opcode is @instr.Move &&
        inst.defs.length() == 1 &&
        inst.uses.length() == 1 {
        match (inst.defs[0].reg, inst.uses[0]) {
          (@abi.Physical(dst), @abi.Physical(src)) =>
            if same_location(src, dst) {
              skip = true
            }
          _ => ()
        }
      }
      if !skip {
        new_block.add_inst(inst)
      }
    }
    if block.terminator is Some(term) {
      new_block.set_terminator(term)
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
    // Loads can trap (e.g. guard pages / invalid pointers), so must not be eliminated.
    LoadPtr(_, _) | LoadPtrNarrow(_, _, _) => true
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
        Jump(_, args) =>
          for a in args {
            if a is @abi.Virtual(vreg) {
              used_vregs.add(vreg.id)
            }
          }
        Trap(_) => ()
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
  settings : @abi.ABISettings,
) -> (
  Array[@abi.PReg],
  Array[@abi.PReg],
  Array[@abi.PReg],
  Array[@abi.PReg],
  Array[@abi.PReg],
) {
  // Check if function needs extra results buffer (uses X23)
  let calls_multi = func.calls_multi_value_function()
  let needs_extra = func.needs_extra_results_ptr()
  let needs_x23_reserved = needs_extra || calls_multi
  // Cache memory0 descriptor pointer in X20 when needed.
  let needs_x20_reserved = func.uses_mem0()
  // Cache func_table pointer in X21 when needed.
  let needs_x21_reserved = func.uses_func_table()

  // Build MachineEnv (Cranelift-inspired) and derive pools.
  let env = @abi.build_aarch64_machine_env(
    settings~,
    reserve_mem0_desc=needs_x20_reserved,
    reserve_func_table=needs_x21_reserved,
    reserve_x23=needs_x23_reserved,
  )
  let int_regs : Array[@abi.PReg] = []
  for r in env.preferred_int {
    int_regs.push(r)
  }
  let callee_saved_int_regs = env.callee_saved_int
  for r in env.nonpreferred_int {
    int_regs.push(r)
  }
  let float_regs : Array[@abi.PReg] = []
  for r in env.preferred_float {
    float_regs.push(r)
  }
  let callee_saved_float_regs = env.callee_saved_float
  for r in env.nonpreferred_float {
    float_regs.push(r)
  }
  let vector_regs : Array[@abi.PReg] = []
  for r in env.preferred_vector {
    vector_regs.push(r)
  }
  for r in env.nonpreferred_vector {
    vector_regs.push(r)
  }
  (
    int_regs, float_regs, vector_regs, callee_saved_int_regs, callee_saved_float_regs,
  )
}

///|
/// Allocate registers using the Ion-style backtracking allocator
/// This allocator supports:
/// - Bundle merging for copy coalescing
/// - Priority-based allocation with eviction
/// - Bundle splitting instead of immediate spilling
pub fn allocate_registers_backtracking(
  func : VCodeFunction,
  settings? : @abi.ABISettings = @abi.ABISettings::default(),
) -> VCodeFunction {
  // Step 0: Eliminate dead code first
  let func = eliminate_dead_code(func)

  // Build register pools
  let (
    int_regs,
    float_regs,
    vector_regs,
    callee_saved_int_regs,
    callee_saved_float_regs,
  ) = build_aarch64_reg_pools(func, settings)

  // Compute liveness (Phase 1)
  let liveness = compute_liveness(func)

  // Use backtracking allocator (Phases 2-4)
  let alloc_result = allocate_backtracking(
    func, liveness, int_regs, float_regs, vector_regs, callee_saved_int_regs, callee_saved_float_regs,
  )

  // Optional safety net (Cranelift-like checker).
  // Keeps invariants honest as allocator logic evolves.
  verify_allocation_aarch64(func, liveness, alloc_result, settings~)

  // Process constraints and generate RegMove edits
  process_constraints(func, alloc_result)

  // Apply allocation
  apply_allocation(func, alloc_result)
}

///|
/// Allocation statistics for comparison
struct AllocStats {
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
/// Get allocation statistics
pub fn get_alloc_stats(
  func : VCodeFunction,
  settings? : @abi.ABISettings = @abi.ABISettings::default(),
) -> AllocStats {
  let func = eliminate_dead_code(func)
  let (
    int_regs,
    float_regs,
    vector_regs,
    callee_saved_int_regs,
    callee_saved_float_regs,
  ) = build_aarch64_reg_pools(func, settings)
  let liveness = compute_liveness(func)

  // Count vregs
  let num_vregs = liveness.intervals.length()
  let alloc_result = allocate_backtracking(
    func, liveness, int_regs, float_regs, vector_regs, callee_saved_int_regs, callee_saved_float_regs,
  )
  process_constraints(func, alloc_result)
  let allocated = apply_allocation(func, alloc_result)
  let stats = count_instructions(allocated)
  stats.num_vregs = num_vregs
  stats.num_spill_slots = alloc_result.num_spill_slots
  stats
}
