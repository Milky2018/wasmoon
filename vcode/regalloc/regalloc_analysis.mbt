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
pub struct ProgPoint {
  block : Int // Block index
  inst : Int // Instruction index within block (-1 for block params)
  pos : ProgPos // Before or after the instruction
} derive(Eq, Hash)

///|
/// Position relative to an instruction
pub(all) enum ProgPos {
  Before // Before the instruction executes (uses happen here)
  After // After the instruction executes (defs happen here)
} derive(Eq, Hash)

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
  mut def_point : (ProgPoint, @abi.PReg?)? // Where this vreg is defined
  use_points : Array[(ProgPoint, @abi.PReg?)] // Where this vreg is used
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
  preds : Array[Array[Int]] // preds[block_idx] = predecessor block indices
  succs : Array[Array[Int]] // succs[block_idx] = successor block indices
}

///|
/// Build CFG edges once (O(B + E))
fn build_cfg_edges(func : VCodeFunction) -> CFGEdges {
  let blocks = func.blocks
  let n = func.blocks.length()
  let preds : Array[Array[Int]] = []
  let succs : Array[Array[Int]] = []
  let block_id_to_index : Map[Int, Int] = {}

  // Initialize arrays
  for _ in 0..<n {
    preds.push([])
    succs.push([])
  }
  for i, block in blocks {
    block_id_to_index.set(block.id, i)
  }

  // Build edges from terminators
  for block_idx, block in blocks {
    if block.terminator is Some(term) {
      let block_succ_ids = get_terminator_succ_ids(term)
      let block_succs : Array[Int] = []
      for succ_id in block_succ_ids {
        if block_id_to_index.get(succ_id) is Some(succ_idx) {
          block_succs.push(succ_idx)
          preds[succ_idx].push(block_idx)
        }
      }
      succs[block_idx] = block_succs
    }
  }
  { preds, succs }
}

///|
/// Extract successor block IDs from terminator
fn get_terminator_succ_ids(term : @instr.VCodeTerminator) -> Array[Int] {
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
    for i, use_entry in info.use_points {
      if i > 0 {
        result = result + ", "
      }
      result = result + "\{use_entry.0}"
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
  // Dense UseDef side table (vreg_id -> info) for regalloc hot path.
  use_def_dense : Array[UseDefInfo?]
  // Block live-in sets (vregs live at block entry)
  live_in : Array[Set[Int]]
  // Block live-out sets (vregs live at block exit)
  live_out : Array[Set[Int]]
  // Dense live-in rows per block (regalloc hot path).
  mut live_in_dense : Array[Array[Int]]?
  // Dense live-out rows per block (regalloc hot path).
  mut live_out_dense : Array[Array[Int]]?
  // Block order: block_order[block_id] = linear position (O(1) lookup)
  block_order : FixedArray[Int]
  // Call points (block_idx, inst_idx) - instructions that clobber caller-saved registers
  call_points : Array[(ProgPoint, @instr.CallConv)]
}

///|
/// Compute reverse postorder of blocks (for linearizing the CFG)
/// Returns a FixedArray where order[block_idx] = position in reverse postorder
fn compute_reverse_postorder(func : VCodeFunction) -> FixedArray[Int] {
  let blocks = func.blocks
  let n = func.blocks.length()
  let visited : Array[Bool] = Array::make(n, false)
  let postorder : Array[Int] = []
  let block_id_to_index : Map[Int, Int] = {}
  for i, block in blocks {
    block_id_to_index.set(block.id, i)
  }

  // DFS to compute postorder
  fn dfs(
    func : VCodeFunction,
    block_id_to_index : Map[Int, Int],
    block_idx : Int,
    visited : Array[Bool],
    postorder : Array[Int],
  ) {
    if block_idx < 0 || block_idx >= func.blocks.length() || visited[block_idx] {
      return
    }
    visited[block_idx] = true

    // Visit successors first
    let block = func.blocks[block_idx]
    if block.terminator is Some(term) {
      let succ_ids = get_terminator_succ_ids(term)
      for succ_id in succ_ids {
        if block_id_to_index.get(succ_id) is Some(succ_idx) {
          dfs(func, block_id_to_index, succ_idx, visited, postorder)
        }
      }
    }

    // Add to postorder after visiting all successors
    postorder.push(block_idx)
  }

  // Start DFS from entry block index 0.
  if n > 0 {
    dfs(func, block_id_to_index, 0, visited, postorder)
  }

  // Also visit any unreachable blocks.
  for block_idx in 0..<n {
    if !visited[block_idx] {
      dfs(func, block_id_to_index, block_idx, visited, postorder)
    }
  }

  // Reverse postorder: order[block_idx] = position in reverse postorder.
  let order : FixedArray[Int] = FixedArray::make(n, 0)
  let len = postorder.length()
  for i, block_idx in postorder {
    order[block_idx] = len - 1 - i
  }
  order
}

///|
/// Compute liveness information for a VCode function.
fn compute_liveness_with_options(
  func : VCodeFunction,
  build_live_intervals : Bool,
) -> LivenessResult {
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
    use_def_dense: Array::make(func.next_vreg_id, None),
    live_in,
    live_out,
    live_in_dense: None,
    live_out_dense: None,
    block_order,
    call_points: [],
  }

  // Phase 1: Collect definitions and uses
  collect_defs_uses(func, result)

  // Phase 2: Compute live-in and live-out sets using dataflow analysis
  compute_live_sets(func, result, build_live_intervals)

  // Phase 3: Build live intervals from the live sets (debug/stats path).
  if build_live_intervals {
    build_intervals(func, result)
  }
  result
}

///|
/// Compute full liveness information including interval maps.
pub fn compute_liveness(func : VCodeFunction) -> LivenessResult {
  compute_liveness_with_options(func, true)
}

///|
/// Compute liveness for regalloc hot path (no interval map construction).
pub fn compute_liveness_for_regalloc(func : VCodeFunction) -> LivenessResult {
  compute_liveness_with_options(func, false)
}

///|
fn ensure_use_def_info(result : LivenessResult, vreg : @abi.VReg) -> UseDefInfo {
  if vreg.id >= 0 && vreg.id < result.use_def_dense.length() {
    match result.use_def_dense[vreg.id] {
      Some(info) => info
      None => {
        let info = UseDefInfo::new(vreg)
        result.use_def_dense[vreg.id] = Some(info)
        result.use_def.set(vreg.id, info)
        info
      }
    }
  } else {
    match result.use_def.get(vreg.id) {
      Some(existing) => existing
      None => {
        let info = UseDefInfo::new(vreg)
        result.use_def.set(vreg.id, info)
        info
      }
    }
  }
}

///|
/// Phase 1: Collect all definitions and uses
fn collect_defs_uses(func : VCodeFunction, result : LivenessResult) -> Unit {
  // Record function parameters as definitions at the start
  for param in func.params {
    let info = ensure_use_def_info(result, param)
    info.def_point = Some(({ block: 0, inst: -1, pos: After }, None))
  }

  // Process each block
  for block_idx, block in func.blocks {
    // Block parameters are SSA definitions at block entry.
    // Their incoming values are passed via Jump(target, args) on CFG edges.
    for param in block.params {
      let info = ensure_use_def_info(result, param)
      let def_point : ProgPoint = { block: block_idx, inst: -1, pos: After }
      if info.def_point is Some(_) {
        abort("block param defined twice")
      }
      info.def_point = Some((def_point, None))
      // Also add a use point at block entry to keep it live through the block.
      info.use_points.push(({ block: block_idx, inst: 0, pos: Before }, None))
    }

    // Process instructions
    for inst_idx, inst in block.insts {
      // Record call points for caller-saved register handling
      // Design: use call_type() to determine if an instruction
      // behaves like a call (clobbers caller-saved registers)
      if inst.opcode.call_type() is @instr.Regular {
        let conv = match inst.opcode {
          @instr.CallPtr(_, _, call_conv) => call_conv
          @instr.CallDirect(_, _, _, call_conv) => call_conv
          // This pseudo-op may call a C helper on a slow path.
          @instr.TypeCheckSubtypeIndirect(_) => @instr.C
          @instr.GCAllocStructInline(_, _) => @instr.C
          @instr.GCAllocArrayFixedInline(_, _) => @instr.C
          _ => @instr.Wasm
        }
        result.call_points.push(
          ({ block: block_idx, inst: inst_idx, pos: After }, conv),
        )
      }

      // Record uses (before the instruction)
      for i, use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) {
          let info = ensure_use_def_info(result, vreg)
          let fixed = if i < inst.use_constraints.length() &&
            inst.use_constraints[i] is @abi.FixedReg(preg) {
            Some(preg)
          } else {
            None
          }
          info.use_points.push(
            ({ block: block_idx, inst: inst_idx, pos: Before }, fixed),
          )
        }
      }

      // Record definitions (after the instruction)
      for i, def in inst.defs {
        if def.reg is @abi.Virtual(vreg) {
          let info = ensure_use_def_info(result, vreg)
          let new_def : ProgPoint = {
            block: block_idx,
            inst: inst_idx,
            pos: After,
          }
          if info.def_point is Some(_) {
            abort("vreg defined multiple times (SSA violation)")
          }
          let fixed = if i < inst.def_constraints.length() &&
            inst.def_constraints[i] is @abi.FixedReg(preg) {
            Some(preg)
          } else {
            None
          }
          info.def_point = Some((new_def, fixed))
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
          let info = ensure_use_def_info(result, vreg)
          info.use_points.push(
            ({ block: block_idx, inst: inst_idx, pos: Before }, None),
          )
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
fn compute_live_sets(
  func : VCodeFunction,
  result : LivenessResult,
  materialize_sets : Bool,
) -> Unit {
  // Fixed-point iteration for dataflow analysis
  // live_in[B] = use[B] ∪ (live_out[B] - def[B])
  // live_out[B] = ∪{S ∈ succ[B]} live_in[S]
  let num_blocks = func.blocks.length()
  let num_vregs = func.next_vreg_id

  fn make_bool_rows(num_rows : Int, num_cols : Int) -> Array[FixedArray[Bool]] {
    let rows : Array[FixedArray[Bool]] = []
    for _ in 0..<num_rows {
      rows.push(FixedArray::make(num_cols, false))
    }
    rows
  }

  fn add_once(
    mask : FixedArray[Bool],
    dense : Array[Int],
    vreg_id : Int,
  ) -> Unit {
    if vreg_id >= 0 && vreg_id < mask.length() && !mask[vreg_id] {
      mask[vreg_id] = true
      dense.push(vreg_id)
    }
  }

  fn add_once_epoch(
    epoch_map : FixedArray[Int],
    epoch : Int,
    dense : Array[Int],
    vreg_id : Int,
  ) -> Unit {
    if vreg_id >= 0 &&
      vreg_id < epoch_map.length() &&
      epoch_map[vreg_id] != epoch {
      epoch_map[vreg_id] = epoch
      dense.push(vreg_id)
    }
  }

  fn mark_once(mask : FixedArray[Bool], vreg_id : Int) -> Unit {
    if vreg_id >= 0 && vreg_id < mask.length() && !mask[vreg_id] {
      mask[vreg_id] = true
    }
  }

  // First, compute use/def sets for each block in dense form.
  let block_use_list : Array[Array[Int]] = []
  let block_def_mask = make_bool_rows(num_blocks, num_vregs)
  let use_seen_epoch : FixedArray[Int] = FixedArray::make(num_vregs, 0)
  let mut use_epoch = 1
  for block_idx, block in func.blocks {
    use_epoch = use_epoch + 1
    let cur_use_epoch = use_epoch
    let use_list : Array[Int] = []
    let def_mask = block_def_mask[block_idx]

    // Block parameters are SSA definitions at block entry.
    for param in block.params {
      mark_once(def_mask, param.id)
    }

    // Process instructions
    for inst in block.insts {
      // Uses that are not already defined locally
      for use_reg in inst.uses {
        if use_reg is @abi.Virtual(vreg) && !def_mask[vreg.id] {
          add_once_epoch(use_seen_epoch, cur_use_epoch, use_list, vreg.id)
        }
      }
      // Definitions
      for def in inst.defs {
        if def.reg is @abi.Virtual(vreg) {
          mark_once(def_mask, vreg.id)
        }
      }
    }

    // Terminator uses
    if block.terminator is Some(term) {
      match term {
        Jump(_, args) =>
          for a in args {
            if a is @abi.Virtual(vreg) && !def_mask[vreg.id] {
              add_once_epoch(use_seen_epoch, cur_use_epoch, use_list, vreg.id)
            }
          }
        Branch(cond, _, _) =>
          if cond is @abi.Virtual(vreg) && !def_mask[vreg.id] {
            add_once_epoch(use_seen_epoch, cur_use_epoch, use_list, vreg.id)
          }
        BranchCmp(lhs, rhs, _, _, _, _) => {
          if lhs is @abi.Virtual(vreg) && !def_mask[vreg.id] {
            add_once_epoch(use_seen_epoch, cur_use_epoch, use_list, vreg.id)
          }
          if rhs is @abi.Virtual(vreg) && !def_mask[vreg.id] {
            add_once_epoch(use_seen_epoch, cur_use_epoch, use_list, vreg.id)
          }
        }
        BranchCmpImm(lhs, _, _, _, _, _) =>
          if lhs is @abi.Virtual(vreg) && !def_mask[vreg.id] {
            add_once_epoch(use_seen_epoch, cur_use_epoch, use_list, vreg.id)
          }
        BranchZero(reg, _, _, _, _) =>
          if reg is @abi.Virtual(vreg) && !def_mask[vreg.id] {
            add_once_epoch(use_seen_epoch, cur_use_epoch, use_list, vreg.id)
          }
        BrTable(index, _, _) =>
          if index is @abi.Virtual(vreg) && !def_mask[vreg.id] {
            add_once_epoch(use_seen_epoch, cur_use_epoch, use_list, vreg.id)
          }
        Return(values) =>
          for value in values {
            if value is @abi.Virtual(vreg) && !def_mask[vreg.id] {
              add_once_epoch(use_seen_epoch, cur_use_epoch, use_list, vreg.id)
            }
          }
        _ => ()
      }
    }
    block_use_list.push(use_list)
  }

  // Pre-compute CFG edges (O(B + E), only once)
  let cfg = build_cfg_edges(func)

  let live_in_mask = make_bool_rows(num_blocks, num_vregs)
  let live_out_mask = make_bool_rows(num_blocks, num_vregs)
  let live_in_list : Array[Array[Int]] = []
  let live_out_list : Array[Array[Int]] = []

  // Initialize live_in with use sets.
  for block_idx in 0..<num_blocks {
    let initial_in : Array[Int] = []
    for vreg_id in block_use_list[block_idx] {
      add_once(live_in_mask[block_idx], initial_in, vreg_id)
    }
    live_in_list.push(initial_in)
    live_out_list.push([])
  }

  // Worklist-based dataflow with incremental update
  let worklist = LivenessWorklist::new(num_blocks)

  // Initialize worklist - push in forward order so pop() gives reverse order
  // (pop removes from end, so queue [0,1,..,n-1] pops n-1, n-2, .., 0)
  // For backward dataflow, we want to process successors before predecessors
  for i in 0..<num_blocks {
    worklist.push(i)
  }
  while worklist.pop() is Some(block_idx) {
    let old_live_in_size = live_in_list[block_idx].length()
    let added_live_out : Array[Int] = []

    // live_out[B] = ∪ live_in[S] for S in succs[B]
    // Monotone: only adds, never removes
    for succ in cfg.succs[block_idx] {
      for vreg_id in live_in_list[succ] {
        if !live_out_mask[block_idx][vreg_id] {
          live_out_mask[block_idx][vreg_id] = true
          live_out_list[block_idx].push(vreg_id)
          added_live_out.push(vreg_id)
        }
      }
    }

    // live_in[B] = use[B] ∪ (live_out[B] - def[B])
    // Incrementally add only newly-grown live_out values (use was added in init).
    for vreg_id in added_live_out {
      if !block_def_mask[block_idx][vreg_id] &&
        !live_in_mask[block_idx][vreg_id] {
        live_in_mask[block_idx][vreg_id] = true
        live_in_list[block_idx].push(vreg_id)
      }
    }

    // If live_in grew, propagate to predecessors
    if live_in_list[block_idx].length() > old_live_in_size {
      for pred in cfg.preds[block_idx] {
        worklist.push(pred)
      }
    }
  }

  result.live_in_dense = Some(live_in_list)
  result.live_out_dense = Some(live_out_list)

  // Materialize to set-backed API only for full/debug liveness mode.
  if materialize_sets {
    for block_idx in 0..<num_blocks {
      for vreg_id in live_in_list[block_idx] {
        result.live_in[block_idx].add(vreg_id)
      }
      for vreg_id in live_out_list[block_idx] {
        result.live_out[block_idx].add(vreg_id)
      }
    }
  }
}

///|
/// Phase 3: Build live intervals from use-def info
fn build_intervals(func : VCodeFunction, result : LivenessResult) -> Unit {
  // Get block order for correct interval comparison
  let block_order = result.block_order
  let sorted_call_points = result.call_points.copy()
  sorted_call_points.sort_by(fn(a, b) {
    a.0.compare_with_order(b.0, block_order)
  })
  let call_prog_points : Array[ProgPoint] = []
  let c_call_prefix : Array[Int] = [0]
  for entry in sorted_call_points {
    let (call_point, call_conv) = entry
    call_prog_points.push(call_point)
    let prev = c_call_prefix[c_call_prefix.length() - 1]
    let add = if call_conv is @instr.C { 1 } else { 0 }
    c_call_prefix.push(prev + add)
  }

  fn upper_bound_call_points(
    points : Array[ProgPoint],
    point : ProgPoint,
    block_order : FixedArray[Int],
  ) -> Int {
    let mut lo = 0
    let mut hi = points.length()
    while lo < hi {
      let mid = lo + (hi - lo) / 2
      if points[mid].compare_with_order(point, block_order) <= 0 {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    lo
  }

  fn lower_bound_call_points(
    points : Array[ProgPoint],
    point : ProgPoint,
    block_order : FixedArray[Int],
  ) -> Int {
    let mut lo = 0
    let mut hi = points.length()
    while lo < hi {
      let mid = lo + (hi - lo) / 2
      if points[mid].compare_with_order(point, block_order) < 0 {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    lo
  }

  // Summarize liveness boundaries once:
  // - earliest live-in block per vreg
  // - latest live-out block per vreg
  //
  // Use fixed arrays keyed by vreg id (like Cranelift SecondaryMap style)
  // to avoid repeated hashmap lookups in large functions.
  let max_vreg_id = func.next_vreg_id
  let vreg_first_live_in_block : FixedArray[Int] = FixedArray::make(
    max_vreg_id, -1,
  )
  let vreg_last_live_out_block : FixedArray[Int] = FixedArray::make(
    max_vreg_id, -1,
  )
  for block_idx, live_in_set in result.live_in {
    for vreg_id in live_in_set {
      if vreg_id >= 0 && vreg_id < max_vreg_id {
        let old_block_idx = vreg_first_live_in_block[vreg_id]
        if old_block_idx < 0 ||
          block_order[block_idx] < block_order[old_block_idx] {
          vreg_first_live_in_block[vreg_id] = block_idx
        }
      }
    }
  }
  for block_idx, live_out_set in result.live_out {
    for vreg_id in live_out_set {
      if vreg_id >= 0 && vreg_id < max_vreg_id {
        let old_block_idx = vreg_last_live_out_block[vreg_id]
        if old_block_idx < 0 ||
          block_order[block_idx] > block_order[old_block_idx] {
          vreg_last_live_out_block[vreg_id] = block_idx
        }
      }
    }
  }

  // For each vreg, create an interval spanning from def to last use
  for entry in result.use_def {
    let (vreg_id, info) = entry
    let start = if info.def_point is Some((def, _)) {
      def
      // If no def point, use the first use (shouldn't happen in valid code)
    } else if info.use_points.length() > 0 {
      info.use_points[0].0
    } else {
      continue // No uses or defs, skip
    }
    let interval = LiveInterval::new(info.vreg, start)

    // Extend to cover all uses (using block order for correct comparison)
    for use_entry in info.use_points {
      let use_point = use_entry.0
      interval.extend_with_order(use_point, block_order)
    }

    // Extend interval using summarized live-in/live-out boundaries.
    if vreg_id >= 0 &&
      vreg_id < max_vreg_id &&
      vreg_first_live_in_block[vreg_id] >= 0 {
      let block_idx = vreg_first_live_in_block[vreg_id]
      let entry_point = { block: block_idx, inst: -1, pos: Before }
      interval.extend_with_order(entry_point, block_order)
    }
    if vreg_id >= 0 &&
      vreg_id < max_vreg_id &&
      vreg_last_live_out_block[vreg_id] >= 0 {
      let block_idx = vreg_last_live_out_block[vreg_id]
      let block = func.blocks[block_idx]
      let end_point = {
        block: block_idx,
        inst: block.insts.length(),
        pos: After,
      }
      interval.extend_with_order(end_point, block_order)
    }

    // Check if this interval crosses any call point.
    // start < call_point < end (strict bounds).
    if !call_prog_points.is_empty() {
      let first_after_start = upper_bound_call_points(
        call_prog_points,
        interval.start,
        block_order,
      )
      let first_at_or_after_end = lower_bound_call_points(
        call_prog_points,
        interval.end,
        block_order,
      )
      if first_after_start < first_at_or_after_end {
        interval.crosses_call = true
        let c_calls = c_call_prefix[first_at_or_after_end] -
          c_call_prefix[first_after_start]
        if c_calls > 0 {
          interval.crosses_c_call = true
        }
      }
    }
    result.intervals.set(vreg_id, interval)
  }
}
