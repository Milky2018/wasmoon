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
fn UseDefInfo::new(vreg : @abi.VReg) -> UseDefInfo {
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
/// Build CFG edges once (O(B + E))
fn build_cfg_edges(func : VCodeFunction) -> CFGEdges {
  let blocks = func.blocks
  let block_ids : Array[Int] = []
  let block_successor_ids : Array[Array[Int]] = []
  for _, block in blocks {
    block_ids.push(block.id)
  }
  for _, block in blocks {
    let block_succs : Array[Int] = []
    if block.terminator is Some(term) {
      match term {
        Jump(target, _) => block_succs.push(target)
        Branch(_, then_b, else_b) => {
          block_succs.push(then_b)
          block_succs.push(else_b)
        }
        BranchCmp(_, _, _, _, then_b, else_b) => {
          block_succs.push(then_b)
          block_succs.push(else_b)
        }
        BranchCmpImm(_, _, _, _, then_b, else_b) => {
          block_succs.push(then_b)
          block_succs.push(else_b)
        }
        BranchZero(_, _, _, then_b, else_b) => {
          block_succs.push(then_b)
          block_succs.push(else_b)
        }
        BrTable(_, targets, default) => {
          for target in targets {
            block_succs.push(target)
          }
          block_succs.push(default)
        }
        Return(_) | Trap(_) => ()
      }
    }
    block_successor_ids.push(block_succs)
  }
  let edges = @core_regalloc.build_dense_successor_edges(
    block_ids, block_successor_ids,
  )
  { preds: edges.preds, succs: edges.succs }
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
  call_points : Array[(ProgPoint, @instr.CallConv)]
}

///|
/// Compute reverse postorder of blocks (for linearizing the CFG)
/// Returns a FixedArray where order[block_idx] = position in reverse postorder
fn compute_reverse_postorder(func : VCodeFunction) -> FixedArray[Int] {
  let n = func.blocks.length()
  let order_array = @core_regalloc.compute_reverse_postorder_from_successors(
    build_cfg_edges(func).succs,
  )
  let order : FixedArray[Int] = FixedArray::make(n, 0)
  for i, rank in order_array {
    order[i] = rank
  }
  order
}

///|
/// Compute liveness information for a VCode function.
fn compute_liveness_with_options(
  func : VCodeFunction,
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
pub fn compute_liveness(func : VCodeFunction) -> LivenessResult {
  compute_liveness_with_options(func, true, true)
}

///|
/// Compute liveness for regalloc hot path (no interval map construction).
pub fn compute_liveness_for_regalloc(func : VCodeFunction) -> LivenessResult {
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
        let info = UseDefInfo::new(vreg)
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
        let info = UseDefInfo::new(vreg)
        result.use_def.set(vreg.id, info)
        info
      }
    }
  }
}

///|
/// Phase 1: Collect all definitions and uses
fn collect_defs_uses(
  func : VCodeFunction,
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
          // This pseudo-op may call a C helper on a slow path.
          TypeCheckSubtypeIndirect(_) => C
          GCAllocStructInline(_, _) => C
          GCAllocStructSlowPrecise(_, _) => C
          GCAllocArrayFixedInline(_, _) => C
          GCAllocArraySlowPrecise(_) => C
          _ => Wasm
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
  func : VCodeFunction,
  result : LivenessResult,
  materialize_sets : Bool,
) -> Unit {
  let num_blocks = func.blocks.length()
  let num_vregs = func.next_vreg_id
  let is_func_param_vreg : FixedArray[Bool] = FixedArray::make(num_vregs, false)
  for param in func.params {
    if param.id >= 0 && param.id < num_vregs {
      is_func_param_vreg[param.id] = true
    }
  }

  fn to_core_point(point : ProgPoint) -> @core_regalloc.ProgramPoint {
    let pos = match point.pos {
      Before => 0
      After => 1
    }
    @core_regalloc.ProgramPoint::new(point.block, point.inst * 2 + pos)
  }

  let use_defs : Array[@core_regalloc.LiveSetUseDef] = []
  for vreg_id in 0..<result.use_def_dense.length() {
    if result.use_def_dense[vreg_id] is Some(info) {
      let mut def_point : @core_regalloc.ProgramPoint? = None
      let mut is_entry_param_def = false
      if info.def_point is Some((def, _)) {
        is_entry_param_def = def.block == 0 &&
          def.inst == -1 &&
          vreg_id >= 0 &&
          vreg_id < num_vregs &&
          is_func_param_vreg[vreg_id]
        def_point = Some(to_core_point(def))
      }
      let use_points : Array[@core_regalloc.ProgramPoint] = []
      for use_entry in info.use_points {
        use_points.push(to_core_point(use_entry.0))
      }
      use_defs.push({ vreg_id, def_point, is_entry_param_def, use_points })
    }
  }
  let cfg = build_cfg_edges(func)
  let live_sets = @core_regalloc.compute_dense_live_sets(
    num_blocks,
    num_vregs,
    { preds: cfg.preds, succs: cfg.succs },
    use_defs,
  )

  result.live_in_dense = Some(live_sets.live_in)
  result.live_out_dense = Some(live_sets.live_out)

  // Materialize to set-backed API only for full/debug liveness mode.
  if materialize_sets {
    for block_idx in 0..<num_blocks {
      for vreg_id in live_sets.live_in[block_idx] {
        result.live_in[block_idx].add(vreg_id)
      }
      for vreg_id in live_sets.live_out[block_idx] {
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
  let block_order_array : Array[Int] = []
  let block_lengths : Array[Int] = []
  for block_idx in 0..<func.blocks.length() {
    block_order_array.push(block_order[block_idx])
    block_lengths.push(func.blocks[block_idx].insts.length())
  }
  let block_point_base = @core_regalloc.compute_block_point_bases(
    block_order_array, block_lengths,
  )
  fn point_order(point : ProgPoint) -> Int {
    let block_ord = block_order[point.block]
    let pos_ord = match point.pos {
      Before => 0
      After => 1
    }
    block_point_base[block_ord] + (point.inst + 1) * 2 + pos_ord
  }
  let sorted_call_points = result.call_points.copy()
  sorted_call_points.sort_by(fn(a, b) {
    point_order(a.0).compare(point_order(b.0))
  })
  let call_point_orders : Array[Int] = []
  let c_call_prefix : Array[Int] = [0]
  for entry in sorted_call_points {
    let (call_point, call_conv) = entry
    call_point_orders.push(point_order(call_point))
    let prev = c_call_prefix[c_call_prefix.length() - 1]
    let add = if call_conv is C { 1 } else { 0 }
    c_call_prefix.push(prev + add)
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
    if !call_point_orders.is_empty() {
      let first_after_start = @core_regalloc.upper_bound_sorted_int(
        call_point_orders,
        point_order(interval.start),
      )
      let first_at_or_after_end = @core_regalloc.lower_bound_sorted_int(
        call_point_orders,
        point_order(interval.end),
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
