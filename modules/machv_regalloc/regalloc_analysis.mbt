// Register-allocation analysis for MachV MachV.
//
// This module provides:
// 1. Liveness analysis (live intervals, use-def chains)
// 2. Program-point ordering for non-linear CFGs
// 3. Spill-weight and call-crossing facts consumed by allocation adapters

// ============ Live Interval ============

///|
/// A program point - identifies a position in the MachV function
/// Using #valtype for stack allocation - this struct is created/compared frequently
#valtype
pub struct ProgPoint {
  block : Int // Block index
  inst : Int // Instruction index within block (-1 for block params)
  pos : ProgPos // Before or after the instruction
} derive(Debug, Eq, Hash)

///|
/// Position relative to an instruction
pub(all) enum ProgPos {
  Before // Before the instruction executes (uses happen here)
  After // After the instruction executes (defs happen here)
} derive(Debug, Eq, Hash)

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
pub impl Show for ProgPoint with fn output(self, logger) {
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
  // Whether this interval crosses a foreign/helper call.
  mut crosses_foreign_call : Bool
}

///|
fn LiveInterval::LiveInterval(
  vreg : @abi.VReg,
  start : ProgPoint,
) -> LiveInterval {
  {
    vreg,
    start,
    end: start,
    uses: [start],
    hint: None,
    assigned: None,
    spill_slot: None,
    crosses_call: false,
    crosses_foreign_call: false,
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
pub impl Show for LiveInterval with fn output(self, logger) {
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
fn UseDefInfo::UseDefInfo(vreg : @abi.VReg) -> UseDefInfo {
  { vreg, def_point: None, use_points: [] }
}

///|
fn preg_option_to_string(preg : @abi.PReg?) -> String {
  match preg {
    Some(p) => "Some(\{p})"
    None => "None"
  }
}

///|
fn def_point_to_string(def_point : (ProgPoint, @abi.PReg?)?) -> String {
  match def_point {
    Some((point, fixed)) => "Some((\{point}, \{preg_option_to_string(fixed)}))"
    None => "None"
  }
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
fn build_block_id_to_index_dense(func : @machv.Function) -> Array[Int] {
  let mut max_block_id = -1
  for block in func.blocks {
    if block.id > max_block_id {
      max_block_id = block.id
    }
  }
  if max_block_id < 0 {
    return []
  }
  let block_id_to_index = Array::make(max_block_id + 1, -1)
  for i, block in func.blocks {
    if block.id >= 0 && block.id < block_id_to_index.length() {
      block_id_to_index[block.id] = i
    }
  }
  block_id_to_index
}

///|
/// Build CFG edges once (O(B + E))
fn build_cfg_edges(func : @machv.Function) -> CFGEdges {
  let blocks = func.blocks
  let n = func.blocks.length()
  let preds : Array[Array[Int]] = []
  let succs : Array[Array[Int]] = []
  let block_id_to_index = build_block_id_to_index_dense(func)

  // Initialize arrays
  for _ in 0..<n {
    preds.push([])
    succs.push([])
  }

  // Build edges from terminators
  for block_idx, block in blocks {
    if block.terminator is Some(term) {
      let block_succs : Array[Int] = []
      fn push_succ(
        block_id_to_index : Array[Int],
        block_succs : Array[Int],
        preds : Array[Array[Int]],
        block_idx : Int,
        succ_id : Int,
      ) -> Unit {
        if succ_id >= 0 && succ_id < block_id_to_index.length() {
          let succ_idx = block_id_to_index[succ_id]
          if succ_idx >= 0 {
            block_succs.push(succ_idx)
            preds[succ_idx].push(block_idx)
          }
        }
      }
      match term {
        Jump(target, _) =>
          push_succ(block_id_to_index, block_succs, preds, block_idx, target)
        Branch(_, then_b, else_b) => {
          push_succ(block_id_to_index, block_succs, preds, block_idx, then_b)
          push_succ(block_id_to_index, block_succs, preds, block_idx, else_b)
        }
        BranchCmp(_, _, _, _, then_b, else_b) => {
          push_succ(block_id_to_index, block_succs, preds, block_idx, then_b)
          push_succ(block_id_to_index, block_succs, preds, block_idx, else_b)
        }
        BranchCmpImm(_, _, _, _, then_b, else_b) => {
          push_succ(block_id_to_index, block_succs, preds, block_idx, then_b)
          push_succ(block_id_to_index, block_succs, preds, block_idx, else_b)
        }
        BranchZero(_, _, _, then_b, else_b) => {
          push_succ(block_id_to_index, block_succs, preds, block_idx, then_b)
          push_succ(block_id_to_index, block_succs, preds, block_idx, else_b)
        }
        BrTable(_, targets, default) => {
          for target in targets {
            push_succ(block_id_to_index, block_succs, preds, block_idx, target)
          }
          push_succ(block_id_to_index, block_succs, preds, block_idx, default)
        }
        Return(_) | Trap(_) => ()
      }
      succs[block_idx] = block_succs
    }
  }
  { preds, succs }
}

// ============ Worklist ============

///|
/// Worklist with O(1) membership check
priv struct LivenessWorklist {
  queue : Array[Int]
  in_worklist : Array[Bool]
}

///|
fn LivenessWorklist::LivenessWorklist(size : Int) -> LivenessWorklist {
  { queue: [], in_worklist: Array::make(size, false) }
}

///|
fn LivenessWorklist::push(self : LivenessWorklist, block_id : Int) -> Unit {
  if !self.in_worklist[block_id] {
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
    result = result +
      "  v\{vreg_id}: def=\{def_point_to_string(info.def_point)}, uses=["
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
    result = result +
      "  block\{i}: in=\{to_repr(in_list)}, out=\{to_repr(out_list)}\n"
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
  call_points : Array[(ProgPoint, @instr.CallClobberClass)]
}

///|
/// Compute reverse postorder of blocks (for linearizing the CFG)
/// Returns a FixedArray where order[block_idx] = position in reverse postorder
fn compute_reverse_postorder(func : @machv.Function) -> FixedArray[Int] {
  let n = func.blocks.length()
  let visited : Array[Bool] = Array::make(n, false)
  let postorder : Array[Int] = []
  let block_id_to_index = build_block_id_to_index_dense(func)

  // DFS to compute postorder
  fn dfs(
    func : @machv.Function,
    block_id_to_index : Array[Int],
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
      fn visit_succ(
        func : @machv.Function,
        block_id_to_index : Array[Int],
        succ_id : Int,
        visited : Array[Bool],
        postorder : Array[Int],
      ) -> Unit {
        if succ_id >= 0 && succ_id < block_id_to_index.length() {
          let succ_idx = block_id_to_index[succ_id]
          if succ_idx >= 0 {
            dfs(func, block_id_to_index, succ_idx, visited, postorder)
          }
        }
      }
      match term {
        Jump(target, _) =>
          visit_succ(func, block_id_to_index, target, visited, postorder)
        Branch(_, then_b, else_b) => {
          visit_succ(func, block_id_to_index, then_b, visited, postorder)
          visit_succ(func, block_id_to_index, else_b, visited, postorder)
        }
        BranchCmp(_, _, _, _, then_b, else_b) => {
          visit_succ(func, block_id_to_index, then_b, visited, postorder)
          visit_succ(func, block_id_to_index, else_b, visited, postorder)
        }
        BranchCmpImm(_, _, _, _, then_b, else_b) => {
          visit_succ(func, block_id_to_index, then_b, visited, postorder)
          visit_succ(func, block_id_to_index, else_b, visited, postorder)
        }
        BranchZero(_, _, _, then_b, else_b) => {
          visit_succ(func, block_id_to_index, then_b, visited, postorder)
          visit_succ(func, block_id_to_index, else_b, visited, postorder)
        }
        BrTable(_, targets, default) => {
          for target in targets {
            visit_succ(func, block_id_to_index, target, visited, postorder)
          }
          visit_succ(func, block_id_to_index, default, visited, postorder)
        }
        Return(_) | Trap(_) => ()
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
/// Compute liveness information for a MachV function.
fn compute_liveness_with_options(
  func : @machv.Function,
  build_live_intervals : Bool,
  record_sparse_use_def_map : Bool,
) -> LivenessResult {
  let num_blocks = func.blocks.length()
  let live_in : Array[Set[Int]] = []
  let live_out : Array[Set[Int]] = []
  if build_live_intervals {
    for _ in 0..<num_blocks {
      live_in.push(Set([]))
      live_out.push(Set([]))
    }
  }
  // Compute block order directly as FixedArray
  let block_order = compute_reverse_postorder(func)
  let result : LivenessResult = {
    intervals: Map([]),
    use_def: Map([]),
    use_def_dense: Array::make(func.next_vreg_id, None),
    live_in,
    live_out,
    live_in_dense: None,
    live_out_dense: None,
    block_order,
    call_points: [],
  }

  // Phase 1: Collect definitions and uses
  collect_defs_uses(func, result, record_sparse_use_def_map)

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
pub fn compute_liveness(
  func : @machv.Function,
) -> LivenessResult raise @machv.VerifyError {
  func.verify_for_regalloc()
  compute_liveness_with_options(func, true, true)
}

///|
/// Compute liveness for regalloc hot path (no interval map construction).
pub fn compute_liveness_for_regalloc(
  func : @machv.Function,
) -> LivenessResult raise @machv.VerifyError {
  func.verify_for_regalloc()
  compute_liveness_with_options(func, false, false)
}

///|
fn ensure_use_def_info(
  result : LivenessResult,
  vreg : @abi.VReg,
  record_sparse_use_def_map : Bool,
) -> UseDefInfo {
  if vreg.id >= 0 && vreg.id < result.use_def_dense.length() {
    match result.use_def_dense[vreg.id] {
      Some(info) => info
      None => {
        let info = UseDefInfo::UseDefInfo(vreg)
        result.use_def_dense[vreg.id] = Some(info)
        if record_sparse_use_def_map {
          result.use_def.set(vreg.id, info)
        }
        info
      }
    }
  } else {
    match result.use_def.get(vreg.id) {
      Some(existing) => existing
      None => {
        let info = UseDefInfo::UseDefInfo(vreg)
        result.use_def.set(vreg.id, info)
        info
      }
    }
  }
}

///|
/// Phase 1: Collect all definitions and uses
fn collect_defs_uses(
  func : @machv.Function,
  result : LivenessResult,
  record_sparse_use_def_map : Bool,
) -> Unit {
  // Record function parameters as definitions at the start
  for param in func.params {
    let info = ensure_use_def_info(result, param, record_sparse_use_def_map)
    info.def_point = Some(({ block: 0, inst: -1, pos: After }, None))
  }

  // Process each block
  for block_idx, block in func.blocks {
    // Block parameters are SSA definitions at block entry.
    // Their incoming values are passed via Jump(target, args) on CFG edges.
    for param in block.params {
      let info = ensure_use_def_info(result, param, record_sparse_use_def_map)
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
      if inst.opcode.call_type() is Regular {
        let conv = match inst.opcode {
          CallPtr(_, _, call_conv) => call_conv
          CallDirect(_, _, _, call_conv) => call_conv
          CallExternal(_, _, _, call_conv) => call_conv
          CallExternalIfI32NeImm(_, _) => Foreign
          _ => Internal
        }
        result.call_points.push(
          ({ block: block_idx, inst: inst_idx, pos: After }, conv),
        )
      }

      // Record uses (before the instruction)
      for i, use_reg in inst.uses {
        if use_reg is Virtual(vreg) {
          let info = ensure_use_def_info(
            result, vreg, record_sparse_use_def_map,
          )
          let fixed = if i < inst.use_constraints.length() &&
            inst.use_constraints[i] is FixedReg(preg) {
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
        if def.reg is Virtual(vreg) {
          let info = ensure_use_def_info(
            result, vreg, record_sparse_use_def_map,
          )
          let new_def : ProgPoint = {
            block: block_idx,
            inst: inst_idx,
            pos: After,
          }
          if info.def_point is Some(_) {
            abort("vreg defined multiple times (SSA violation)")
          }
          let fixed = if i < inst.def_constraints.length() &&
            inst.def_constraints[i] is FixedReg(preg) {
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
        if reg is Virtual(vreg) {
          let info = ensure_use_def_info(
            result, vreg, record_sparse_use_def_map,
          )
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
  func : @machv.Function,
  result : LivenessResult,
  materialize_sets : Bool,
) -> Unit {
  // Fixed-point iteration for dataflow analysis
  // live_in[B] = use[B] ∪ (live_out[B] - def[B])
  // live_out[B] = ∪{S ∈ succ[B]} live_in[S]
  let num_blocks = func.blocks.length()
  let num_vregs = func.next_vreg_id

  fn mask_index(block_idx : Int, vreg_id : Int, row_width : Int) -> Int {
    block_idx * row_width + vreg_id
  }

  // First, compute per-block use/def sets from collected SSA use-def info.
  // This avoids a second full instruction walk after collect_defs_uses().
  // Use contiguous block×vreg bit-matrices to avoid allocating one FixedArray
  // per block row in the hot liveness path.
  let matrix_size = num_blocks * num_vregs
  let block_def_mask : FixedArray[Bool] = FixedArray::make(matrix_size, false)
  let live_in_mask : FixedArray[Bool] = FixedArray::make(matrix_size, false)
  let live_out_mask : FixedArray[Bool] = FixedArray::make(matrix_size, false)
  let live_in_list : Array[Array[Int]] = []
  let live_out_list : Array[Array[Int]] = []
  for _ in 0..<num_blocks {
    live_in_list.push([])
    live_out_list.push([])
  }
  let is_func_param_vreg : FixedArray[Bool] = FixedArray::make(num_vregs, false)
  for param in func.params {
    if param.id >= 0 && param.id < num_vregs {
      is_func_param_vreg[param.id] = true
    }
  }

  fn point_before(a : ProgPoint, b : ProgPoint) -> Bool {
    if a.inst < b.inst {
      true
    } else if a.inst > b.inst {
      false
    } else {
      match (a.pos, b.pos) {
        (Before, After) => true
        _ => false
      }
    }
  }

  for vreg_id in 0..<result.use_def_dense.length() {
    if result.use_def_dense[vreg_id] is Some(info) {
      let mut def_point : ProgPoint? = None
      if info.def_point is Some((def, _)) {
        let is_entry_param_def = def.block == 0 &&
          def.inst == -1 &&
          vreg_id >= 0 &&
          vreg_id < num_vregs &&
          is_func_param_vreg[vreg_id]
        if !is_entry_param_def {
          def_point = Some(def)
        }
        if !is_entry_param_def && def.block >= 0 && def.block < num_blocks {
          let idx = mask_index(def.block, vreg_id, num_vregs)
          if idx >= 0 && idx < block_def_mask.length() {
            block_def_mask[idx] = true
          }
        }
      }
      for use_entry in info.use_points {
        let use_point = use_entry.0
        let block_idx = use_point.block
        if block_idx < 0 || block_idx >= num_blocks {
          continue
        }
        let include_use = match def_point {
          Some(def) =>
            if def.block != block_idx {
              true
            } else {
              point_before(use_point, def)
            }
          None => true
        }
        if include_use {
          let idx = mask_index(block_idx, vreg_id, num_vregs)
          if idx >= 0 && idx < live_in_mask.length() && !live_in_mask[idx] {
            live_in_mask[idx] = true
            live_in_list[block_idx].push(vreg_id)
          }
        }
      }
    }
  }

  // Pre-compute CFG edges (O(B + E), only once)
  let cfg = build_cfg_edges(func)

  // Worklist-based dataflow with incremental update
  let worklist = LivenessWorklist::LivenessWorklist(num_blocks)

  // Initialize worklist - push in forward order so pop() gives reverse order
  // (pop removes from end, so queue [0,1,..,n-1] pops n-1, n-2, .., 0)
  // For backward dataflow, we want to process successors before predecessors
  for i in 0..<num_blocks {
    worklist.push(i)
  }
  while worklist.pop() is Some(block_idx) {
    let old_live_in_size = live_in_list[block_idx].length()
    let row_base = block_idx * num_vregs

    // live_out[B] = ∪ live_in[S] for S in succs[B]
    // Monotone: only adds, never removes
    for succ in cfg.succs[block_idx] {
      for vreg_id in live_in_list[succ] {
        let out_idx = row_base + vreg_id
        if out_idx < 0 || out_idx >= live_out_mask.length() {
          continue
        }
        if !live_out_mask[out_idx] {
          live_out_mask[out_idx] = true
          live_out_list[block_idx].push(vreg_id)
          let def_idx = row_base + vreg_id
          let in_idx = row_base + vreg_id
          if def_idx >= 0 &&
            def_idx < block_def_mask.length() &&
            !block_def_mask[def_idx] &&
            in_idx >= 0 &&
            in_idx < live_in_mask.length() &&
            !live_in_mask[in_idx] {
            live_in_mask[in_idx] = true
            live_in_list[block_idx].push(vreg_id)
          }
        }
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
fn build_intervals(func : @machv.Function, result : LivenessResult) -> Unit {
  // Get block order for correct interval comparison
  let block_order = result.block_order
  let sorted_call_points = result.call_points.copy()
  sorted_call_points.sort_by(fn(a, b) {
    a.0.compare_with_order(b.0, block_order)
  })
  let call_prog_points : Array[ProgPoint] = []
  let foreign_call_prefix : Array[Int] = [0]
  for entry in sorted_call_points {
    let (call_point, call_class) = entry
    call_prog_points.push(call_point)
    let prev = foreign_call_prefix[foreign_call_prefix.length() - 1]
    let add = if call_class is Foreign { 1 } else { 0 }
    foreign_call_prefix.push(prev + add)
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
    let interval = LiveInterval::LiveInterval(info.vreg, start)

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
        let foreign_calls = foreign_call_prefix[first_at_or_after_end] -
          foreign_call_prefix[first_after_start]
        if foreign_calls > 0 {
          interval.crosses_foreign_call = true
        }
      }
    }
    result.intervals.set(vreg_id, interval)
  }
}
