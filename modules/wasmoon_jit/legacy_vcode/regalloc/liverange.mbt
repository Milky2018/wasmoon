// Ion-Style LiveRange Data Structures
// Enhanced live interval representation with multiple precise spans
// and use position constraints for the backtracking allocator.

///|
/// A contiguous program point range (start inclusive, end exclusive)
struct ProgPointRange {
  start : ProgPoint
  end : ProgPoint
}

///|
fn ProgPointRange::new(start : ProgPoint, end : ProgPoint) -> ProgPointRange {
  { start, end }
}

///|
fn ProgPointRange::to_string(self : ProgPointRange) -> String {
  "\{self.start}-\{self.end}"
}

///|
pub impl Show for ProgPointRange with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Check if two ranges overlap (using block order for comparison)
fn ProgPointRange::overlaps(
  self : ProgPointRange,
  other : ProgPointRange,
  block_order : FixedArray[Int],
) -> Bool {
  // Ranges overlap if: self.start < other.end AND other.start < self.end
  let self_start_cmp = self.start.compare_with_order(other.end, block_order)
  let other_start_cmp = other.start.compare_with_order(self.end, block_order)
  self_start_cmp < 0 && other_start_cmp < 0
}

///|
/// Check if a point is within this range
pub fn ProgPointRange::contains(
  self : ProgPointRange,
  point : ProgPoint,
  block_order : FixedArray[Int],
) -> Bool {
  let start_cmp = self.start.compare_with_order(point, block_order)
  let end_cmp = point.compare_with_order(self.end, block_order)
  start_cmp <= 0 && end_cmp < 0
}

///|
/// Kind of use at a program point
/// Note: For tied operands (same reg as both def and use), add a DefUse variant
/// when VCodeInst supports tied operand representation.
enum UseKind {
  Def // Definition (value produced)
  Use // Use (value consumed)
}

///|
fn UseKind::to_string(self : UseKind) -> String {
  match self {
    Def => "def"
    Use => "use"
  }
}

///|
pub impl Show for UseKind with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Operand constraint for a use position
pub enum OperandConstraint {
  AnyReg // Any register in the class
  FixedReg(@abi.PReg) // Must be this specific register
}

///|
fn OperandConstraint::to_string(self : OperandConstraint) -> String {
  match self {
    AnyReg => "any"
    FixedReg(preg) => "fixed(\{preg})"
  }
}

///|
pub impl Show for OperandConstraint with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// A use position within a LiveRange
struct UsePosition {
  point : ProgPoint
  kind : UseKind
  constraint : OperandConstraint
}

///|
fn UsePosition::new(
  point : ProgPoint,
  kind : UseKind,
  constraint : OperandConstraint,
) -> UsePosition {
  { point, kind, constraint }
}

///|
fn UsePosition::to_string(self : UsePosition) -> String {
  "\{self.point}:\{self.kind}:\{self.constraint}"
}

///|
pub impl Show for UsePosition with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Allocation result for a LiveRange or Bundle
pub enum Allocation {
  Reg(@abi.PReg) // Allocated to a physical register
  Spill(Int) // Spilled to stack slot
  Unallocated // Not yet allocated
}

///|
fn Allocation::to_string(self : Allocation) -> String {
  match self {
    Reg(preg) => "\{preg}"
    Spill(slot) => "[sp+\{slot}]"
    Unallocated => "?"
  }
}

///|
pub impl Show for Allocation with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// A LiveRange represents the liveness of a single virtual register
/// with precise span information and use constraints.
struct LiveRange {
  id : Int
  vreg : @abi.VReg
  ranges : Array[ProgPointRange] // Multiple non-overlapping spans
  uses : Array[UsePosition] // Use positions with constraints
  mut bundle_id : Int // Owning Bundle ID (-1 if none)
  mut allocation : Allocation // Allocation result
  // Cached properties
  mut crosses_call : Bool // Spans across any function call
  mut crosses_wasm_call : Bool // Spans across a Wasm call
  mut crosses_c_call : Bool // Spans across a C call
}

///|
pub fn LiveRange::new(id : Int, vreg : @abi.VReg) -> LiveRange {
  {
    id,
    vreg,
    ranges: [],
    uses: [],
    bundle_id: -1,
    allocation: Unallocated,
    crosses_call: false,
    crosses_wasm_call: false,
    crosses_c_call: false,
  }
}

///|
/// Add a span to this LiveRange
fn LiveRange::add_range(self : LiveRange, range : ProgPointRange) -> Unit {
  self.ranges.push(range)
}

///|
/// Add a use position
fn LiveRange::add_use(self : LiveRange, use_pos : UsePosition) -> Unit {
  self.uses.push(use_pos)
}

///|
/// Check if this LiveRange has any fixed register constraint
pub fn LiveRange::has_fixed_constraint(self : LiveRange) -> Bool {
  for use_pos in self.uses {
    if use_pos.constraint is FixedReg(_) {
      return true
    }
  }
  false
}

///|
/// Get the fixed register constraint if all uses require the same fixed reg
pub fn LiveRange::get_fixed_reg(self : LiveRange) -> @abi.PReg? {
  fn is_allocatable_fixed(preg : @abi.PReg) -> Bool {
    if preg.class is Int {
      // Keep architectural reserved/scratch regs out of fixed allocation.
      // Argument regs (x0-x7) are allowed so fixed-arg constraints can be
      // satisfied by allocation when profitable, matching regalloc2 style.
      preg.index != 16 &&
      preg.index != 17 &&
      preg.index != 18 &&
      preg.index != 19 &&
      preg.index != 29 &&
      preg.index != 30 &&
      preg.index != 31
    } else {
      // For float/vector bank, keep v16/v17 reserved as scratch.
      preg.index != 16 && preg.index != 17
    }
  }

  let mut fixed : @abi.PReg? = None
  for use_pos in self.uses {
    if use_pos.constraint is FixedReg(preg) {
      if !is_allocatable_fixed(preg) {
        // Treat non-allocatable fixed regs as "use-time constraints" only.
        // They are satisfied via inserted moves, not by pinning allocation.
        continue
      }
      match fixed {
        None => fixed = Some(preg)
        Some(existing) =>
          if existing.index != preg.index {
            return None // Conflicting constraints
          }
      }
    }
  }
  fixed
}

///|
/// Check if this LiveRange overlaps with another
pub fn LiveRange::overlaps(
  self : LiveRange,
  other : LiveRange,
  block_order : FixedArray[Int],
) -> Bool {
  for self_range in self.ranges {
    for other_range in other.ranges {
      if self_range.overlaps(other_range, block_order) {
        return true
      }
    }
  }
  false
}

///|
/// Get the start point (earliest point in all ranges)
pub fn LiveRange::start(
  self : LiveRange,
  block_order : FixedArray[Int],
) -> ProgPoint? {
  ignore(block_order)
  if self.ranges.is_empty() {
    return None
  }
  Some(self.ranges[0].start)
}

///|
/// Get the end point (latest point in all ranges)
pub fn LiveRange::end(
  self : LiveRange,
  block_order : FixedArray[Int],
) -> ProgPoint? {
  ignore(block_order)
  if self.ranges.is_empty() {
    return None
  }
  Some(self.ranges[self.ranges.length() - 1].end)
}

///|
/// Compute total length of all ranges (in instruction count)
pub fn LiveRange::total_length(self : LiveRange) -> Int {
  let mut total = 0
  for range in self.ranges {
    // Simple approximation: count instructions
    // Same block: inst difference
    // Different blocks: add a fixed cost
    if range.start.block == range.end.block {
      total += range.end.inst - range.start.inst + 1
    } else {
      // Cross-block: use a larger estimate
      total += (range.end.block - range.start.block) * 10 +
        (range.end.inst - range.start.inst).abs() +
        1
    }
  }
  if total <= 0 {
    1
  } else {
    total
  }
}

///|
fn LiveRange::to_string(self : LiveRange) -> String {
  let mut result = "LR\{self.id} \{self.vreg}: ["
  for i, range in self.ranges {
    if i > 0 {
      result = result + ", "
    }
    result = result + range.to_string()
  }
  result = result + "] -> \{self.allocation}"
  if self.bundle_id >= 0 {
    result = result + " (bundle \{self.bundle_id})"
  }
  result
}

///|
pub impl Show for LiveRange with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Collection of LiveRanges built from liveness analysis
struct LiveRangeSet {
  ranges : Array[LiveRange]
  vreg_to_range_dense : Array[Int] // vreg.id -> range index (-1 if absent)
  block_order : FixedArray[Int] // Block execution order (O(1) lookup)
  blockparam_out_pairs : Array[(Int, Int)] // (to_range_idx, from_range_idx)
}

///|
fn LiveRangeSet::new(
  block_order : FixedArray[Int],
  max_vreg_id : Int,
) -> LiveRangeSet {
  {
    ranges: [],
    vreg_to_range_dense: Array::make(max_vreg_id, -1),
    block_order,
    blockparam_out_pairs: [],
  }
}

///|
/// Add a new LiveRange
fn LiveRangeSet::add_range(self : LiveRangeSet, range : LiveRange) -> Unit {
  let idx = self.ranges.length()
  guard range.vreg.id >= 0 && range.vreg.id < self.vreg_to_range_dense.length() else {
    abort("vreg id out of range when building live ranges")
  }
  self.vreg_to_range_dense[range.vreg.id] = idx
  self.ranges.push(range)
}

///|
/// Get LiveRange by vreg id
pub fn LiveRangeSet::get_by_vreg(
  self : LiveRangeSet,
  vreg_id : Int,
) -> LiveRange? {
  if vreg_id < 0 || vreg_id >= self.vreg_to_range_dense.length() {
    return None
  }
  let idx = self.vreg_to_range_dense[vreg_id]
  if idx >= 0 {
    Some(self.ranges[idx])
  } else {
    None
  }
}

///|
/// Get LiveRange index by vreg id
fn LiveRangeSet::get_range_index_by_vreg(
  self : LiveRangeSet,
  vreg_id : Int,
) -> Int? {
  if vreg_id < 0 || vreg_id >= self.vreg_to_range_dense.length() {
    return None
  }
  let idx = self.vreg_to_range_dense[vreg_id]
  if idx >= 0 {
    Some(idx)
  } else {
    None
  }
}

///|
/// Get LiveRange by index
pub fn LiveRangeSet::get(self : LiveRangeSet, idx : Int) -> LiveRange {
  self.ranges[idx]
}

///|
/// Get number of ranges
pub fn LiveRangeSet::length(self : LiveRangeSet) -> Int {
  self.ranges.length()
}

///|
/// Build LiveRanges from liveness analysis result
/// This is Phase 2 of the Ion allocator
pub fn build_live_ranges(
  func : VCodeFunction,
  liveness : LivenessResult,
) -> LiveRangeSet {
  let result = LiveRangeSet::new(liveness.block_order, func.next_vreg_id)
  let mut next_id = 0
  let block_order = liveness.block_order
  let num_blocks = func.blocks.length()
  // Match regalloc2's dense global ProgPoint ordering:
  // order points by block order, and within each block by inst/pos.
  let block_idx_by_order : Array[Int] = Array::make(num_blocks, 0)
  for block_idx in 0..<num_blocks {
    block_idx_by_order[block_order[block_idx]] = block_idx
  }
  let block_point_base : Array[Int] = Array::make(num_blocks, 0)
  let mut point_cursor = 0
  for ord in 0..<num_blocks {
    block_point_base[ord] = point_cursor
    let block_idx = block_idx_by_order[ord]
    let block_len = func.blocks[block_idx].insts.length()
    point_cursor = point_cursor + (block_len + 2) * 2
  }
  fn point_order(
    point : ProgPoint,
    block_order : FixedArray[Int],
    block_point_base : Array[Int],
  ) -> Int {
    let block_ord = block_order[point.block]
    let pos_ord = match point.pos {
      Before => 0
      After => 1
    }
    block_point_base[block_ord] + (point.inst + 1) * 2 + pos_ord
  }
  let sorted_call_points = liveness.call_points.copy()
  sorted_call_points.sort_by(fn(a, b) {
    let a_ord = point_order(a.0, block_order, block_point_base)
    let b_ord = point_order(b.0, block_order, block_point_base)
    if a_ord < b_ord {
      -1
    } else if a_ord > b_ord {
      1
    } else {
      0
    }
  })
  let block_call_point_orders : Array[Array[Int]] = []
  let block_c_call_point_orders : Array[Array[Int]] = []
  for _ in 0..<num_blocks {
    block_call_point_orders.push([])
    block_c_call_point_orders.push([])
  }
  let call_prog_point_orders : Array[Int] = []
  let c_call_prefix : Array[Int] = [0]
  for entry in sorted_call_points {
    let (call_point, call_conv) = entry
    let call_ord = point_order(call_point, block_order, block_point_base)
    call_prog_point_orders.push(call_ord)
    if call_point.block >= 0 && call_point.block < num_blocks {
      block_call_point_orders[call_point.block].push(call_ord)
      if call_conv is C {
        block_c_call_point_orders[call_point.block].push(call_ord)
      }
    }
    let prev = c_call_prefix[c_call_prefix.length() - 1]
    let add = if call_conv is C { 1 } else { 0 }
    c_call_prefix.push(prev + add)
  }
  let calls_per_block_order : Array[Int] = Array::make(num_blocks, 0)
  let c_calls_per_block_order : Array[Int] = Array::make(num_blocks, 0)
  for block_idx in 0..<num_blocks {
    let ord = block_order[block_idx]
    if ord >= 0 && ord < num_blocks {
      calls_per_block_order[ord] = block_call_point_orders[block_idx].length()
      c_calls_per_block_order[ord] = block_c_call_point_orders[block_idx].length()
    }
  }
  let call_prefix_by_block_order : Array[Int] = [0]
  let c_call_prefix_by_block_order : Array[Int] = [0]
  for ord in 0..<num_blocks {
    call_prefix_by_block_order.push(
      call_prefix_by_block_order[call_prefix_by_block_order.length() - 1] +
      calls_per_block_order[ord],
    )
    c_call_prefix_by_block_order.push(
      c_call_prefix_by_block_order[c_call_prefix_by_block_order.length() - 1] +
      c_calls_per_block_order[ord],
    )
  }
  fn count_call_points_in_range(
    point_orders : Array[Int],
    start_ord : Int,
    end_ord : Int,
  ) -> Int {
    @core_regalloc.count_sorted_ints_in_open_range(
      point_orders, start_ord, end_ord,
    )
  }
  fn point_after(point : ProgPoint, block_len : Int) -> ProgPoint {
    match point.pos {
      Before => { block: point.block, inst: point.inst, pos: After }
      After =>
        if point.inst < block_len {
          { block: point.block, inst: point.inst + 1, pos: Before }
        } else {
          { block: point.block, inst: block_len, pos: After }
        }
    }
  }

  fn pp_lt(
    a : ProgPoint,
    b : ProgPoint,
    block_order : FixedArray[Int],
    block_point_base : Array[Int],
  ) -> Bool {
    point_order(a, block_order, block_point_base) <
    point_order(b, block_order, block_point_base)
  }

  fn pp_le(
    a : ProgPoint,
    b : ProgPoint,
    block_order : FixedArray[Int],
    block_point_base : Array[Int],
  ) -> Bool {
    point_order(a, block_order, block_point_base) <=
    point_order(b, block_order, block_point_base)
  }

  fn pp_min(
    a : ProgPoint,
    b : ProgPoint,
    block_order : FixedArray[Int],
    block_point_base : Array[Int],
  ) -> ProgPoint {
    if pp_le(a, b, block_order, block_point_base) {
      a
    } else {
      b
    }
  }

  fn pp_max(
    a : ProgPoint,
    b : ProgPoint,
    block_order : FixedArray[Int],
    block_point_base : Array[Int],
  ) -> ProgPoint {
    if pp_lt(a, b, block_order, block_point_base) {
      b
    } else {
      a
    }
  }

  fn add_live_block_dense(
    block_map : Array[Array[Int]?],
    vreg_id : Int,
    block_idx : Int,
  ) -> Unit {
    if vreg_id < 0 || vreg_id >= block_map.length() {
      return
    }
    match block_map[vreg_id] {
      Some(blocks) => blocks.push(block_idx)
      None => block_map[vreg_id] = Some([block_idx])
    }
  }

  // Precompute vreg -> live block mapping once (dense by vreg id).
  // This avoids O(vregs × blocks × contains) scans when forming spans.
  let max_vreg_id = func.next_vreg_id
  let vreg_live_in_blocks : Array[Array[Int]?] = Array::make(max_vreg_id, None)
  let vreg_live_out_blocks : Array[Array[Int]?] = Array::make(max_vreg_id, None)
  let live_in_rows : Array[Array[Int]] = match liveness.live_in_dense {
    Some(rows) => rows
    None => {
      let rows : Array[Array[Int]] = []
      for block_idx in 0..<num_blocks {
        let row : Array[Int] = []
        for vreg_id in liveness.live_in[block_idx] {
          row.push(vreg_id)
        }
        rows.push(row)
      }
      rows
    }
  }
  let live_out_rows : Array[Array[Int]] = match liveness.live_out_dense {
    Some(rows) => rows
    None => {
      let rows : Array[Array[Int]] = []
      for block_idx in 0..<num_blocks {
        let row : Array[Int] = []
        for vreg_id in liveness.live_out[block_idx] {
          row.push(vreg_id)
        }
        rows.push(row)
      }
      rows
    }
  }
  // Build per-vreg live-in/live-out block lists in block-order sequence, so we
  // can merge them later without per-vreg full sort.
  for order_idx in 0..<num_blocks {
    let block_idx = block_idx_by_order[order_idx]
    for vreg_id in live_in_rows[block_idx] {
      add_live_block_dense(vreg_live_in_blocks, vreg_id, block_idx)
    }
    for vreg_id in live_out_rows[block_idx] {
      add_live_block_dense(vreg_live_out_blocks, vreg_id, block_idx)
    }
  }
  // Scratch structures reused across vregs (epoch-tagged) to avoid per-vreg
  // HashMap churn in hot live-range construction paths.
  let use_first_points : Array[ProgPoint?] = Array::make(num_blocks, None)
  let use_last_points : Array[ProgPoint?] = Array::make(num_blocks, None)
  let use_block_epoch : FixedArray[Int] = FixedArray::make(num_blocks, 0)
  let covered_block_epoch : FixedArray[Int] = FixedArray::make(num_blocks, 0)
  let use_blocks_scratch : Array[Int] = []
  let def_blocks_scratch : Array[Int] = []
  let mut scratch_epoch = 1
  // Process each vreg from use-def info (dense walk; regalloc2-style).
  for vreg_id in 0..<liveness.use_def_dense.length() {
    if liveness.use_def_dense[vreg_id] is Some(info) {
      scratch_epoch = scratch_epoch + 1
      let epoch = scratch_epoch
      let range = LiveRange::new(next_id, info.vreg)
      next_id += 1

      // Add use positions (for constraints / heuristics)
      if info.def_point is Some((def, fixed)) {
        let constraint = match fixed {
          Some(preg) => FixedReg(preg)
          None => AnyReg
        }
        range.add_use(UsePosition::new(def, Def, constraint))
      }
      for use_entry in info.use_points {
        let (use_point, fixed) = use_entry
        let constraint = match fixed {
          Some(preg) => FixedReg(preg)
          None => AnyReg
        }
        range.add_use(UsePosition::new(use_point, Use, constraint))
      }

      // Build multi-span ranges (with holes) from per-block liveness plus use/def.
      // This is a conservative refinement over the previous single [start, end] span:
      // it never drops blocks where the value is live-in/out, but it avoids spanning
      // across blocks where the value is not live, reducing register pressure.
      use_blocks_scratch.clear()
      for use_entry in info.use_points {
        let p = use_entry.0
        let block_idx = p.block
        if use_block_epoch[block_idx] != epoch {
          use_block_epoch[block_idx] = epoch
          use_first_points[block_idx] = Some(p)
          use_last_points[block_idx] = Some(p)
          use_blocks_scratch.push(block_idx)
        } else {
          let first = use_first_points[block_idx].unwrap()
          let last = use_last_points[block_idx].unwrap()
          use_first_points[block_idx] = Some(
            pp_min(first, p, block_order, block_point_base),
          )
          use_last_points[block_idx] = Some(
            pp_max(last, p, block_order, block_point_base),
          )
        }
      }
      fn block_less(a : Int, b : Int, block_order : FixedArray[Int]) -> Bool {
        let ord_a = block_order[a]
        let ord_b = block_order[b]
        ord_a < ord_b || (ord_a == ord_b && a < b)
      }

      let live_in_blocks = if vreg_id >= 0 &&
        vreg_id < max_vreg_id &&
        vreg_live_in_blocks[vreg_id] is Some(blocks) {
        blocks
      } else {
        []
      }
      let live_out_blocks = if vreg_id >= 0 &&
        vreg_id < max_vreg_id &&
        vreg_live_out_blocks[vreg_id] is Some(blocks) {
        blocks
      } else {
        []
      }
      def_blocks_scratch.clear()
      if info.def_point is Some((def, _)) {
        def_blocks_scratch.push(def.block)
      }

      // Merge live-in/live-out/use/def block lists in block-order without
      // sorting the union every iteration (regalloc2-style list walk), and
      // emit per-block spans directly in one pass.
      let mut i_in = 0
      let mut i_out = 0
      let mut i_def = 0
      while i_in < live_in_blocks.length() ||
            i_out < live_out_blocks.length() ||
            i_def < def_blocks_scratch.length() {
        let mut next_block = -1
        if i_in < live_in_blocks.length() {
          next_block = live_in_blocks[i_in]
        }
        if i_out < live_out_blocks.length() {
          let candidate = live_out_blocks[i_out]
          if next_block < 0 || block_less(candidate, next_block, block_order) {
            next_block = candidate
          }
        }
        if i_def < def_blocks_scratch.length() {
          let candidate = def_blocks_scratch[i_def]
          if next_block < 0 || block_less(candidate, next_block, block_order) {
            next_block = candidate
          }
        }
        if next_block < 0 {
          break
        }
        let mut live_in = false
        while i_in < live_in_blocks.length() &&
              live_in_blocks[i_in] == next_block {
          live_in = true
          i_in = i_in + 1
        }
        let mut live_out = false
        while i_out < live_out_blocks.length() &&
              live_out_blocks[i_out] == next_block {
          live_out = true
          i_out = i_out + 1
        }
        let mut has_def_in_block = false
        while i_def < def_blocks_scratch.length() &&
              def_blocks_scratch[i_def] == next_block {
          has_def_in_block = true
          i_def = i_def + 1
        }
        let block_idx = next_block
        covered_block_epoch[block_idx] = epoch
        let block = func.blocks[block_idx]
        let use_bounds = if use_block_epoch[block_idx] == epoch {
          Some(
            (
              use_first_points[block_idx].unwrap(),
              use_last_points[block_idx].unwrap(),
            ),
          )
        } else {
          None
        }
        let block_len = block.insts.length()
        let entry_point : ProgPoint = {
          block: block_idx,
          inst: -1,
          pos: Before,
        }
        let exit_point : ProgPoint = {
          block: block_idx,
          inst: block_len,
          pos: After,
        }
        let start = if has_def_in_block {
          info.def_point.unwrap().0
        } else if live_in {
          entry_point
        } else if use_bounds is Some((first_use, _)) {
          // Should not normally happen (use implies live_in or local def),
          // but be conservative.
          pp_min(entry_point, first_use, block_order, block_point_base)
        } else {
          entry_point
        }
        let end = if live_out {
          exit_point
        } else if use_bounds is Some((_, last_use)) {
          point_after(last_use, block_len)
        } else if has_def_in_block {
          // Defined in this block and dead here: keep a minimal span to avoid
          // surprising empty ranges in allocator internals.
          point_after(info.def_point.unwrap().0, block_len)
        } else {
          point_after(start, block_len)
        }
        let end_ord = point_order(end, block_order, block_point_base)
        let start_ord = point_order(start, block_order, block_point_base)
        let (start, end) = if end_ord <= start_ord {
          (start, point_after(start, block_len))
        } else {
          (start, end)
        }
        range.add_range(ProgPointRange::new(start, end))
      }
      // Fallback for malformed/edge cases where a use block was not covered by
      // live-in/live-out/def (should not happen in SSA; kept for safety).
      for block_idx in use_blocks_scratch {
        if covered_block_epoch[block_idx] == epoch {
          continue
        }
        let block = func.blocks[block_idx]
        let block_len = block.insts.length()
        let use_bounds = (
          use_first_points[block_idx].unwrap(),
          use_last_points[block_idx].unwrap(),
        )
        let start = pp_min(
          { block: block_idx, inst: -1, pos: Before },
          use_bounds.0,
          block_order,
          block_point_base,
        )
        let end = point_after(use_bounds.1, block_len)
        range.add_range(ProgPointRange::new(start, end))
      }
      use_blocks_scratch.clear()

      // Compute call-crossing from normalized spans.
      // This is more precise than coarse def..end intervals (which can over-mark
      // values as call-crossing across dead holes between live spans).
      if !call_prog_point_orders.is_empty() {
        for span in range.ranges {
          let span_start_ord = point_order(
            span.start,
            block_order,
            block_point_base,
          )
          let span_end_ord = point_order(
            span.end,
            block_order,
            block_point_base,
          )
          let mut call_count = 0
          let mut c_call_count = 0
          let mut used_block_fast_path = false
          let start_block = span.start.block
          let end_block = span.end.block
          if start_block >= 0 &&
            start_block < num_blocks &&
            end_block >= 0 &&
            end_block < num_blocks {
            let start_block_ord = block_order[start_block]
            let end_block_ord = block_order[end_block]
            if start_block_ord <= end_block_ord {
              used_block_fast_path = true
              if start_block == end_block {
                call_count = count_call_points_in_range(
                  block_call_point_orders[start_block],
                  span_start_ord,
                  span_end_ord,
                )
                c_call_count = count_call_points_in_range(
                  block_c_call_point_orders[start_block],
                  span_start_ord,
                  span_end_ord,
                )
              } else {
                call_count = call_count +
                  count_call_points_in_range(
                    block_call_point_orders[start_block],
                    span_start_ord,
                    span_end_ord,
                  )
                c_call_count = c_call_count +
                  count_call_points_in_range(
                    block_c_call_point_orders[start_block],
                    span_start_ord,
                    span_end_ord,
                  )
                call_count = call_count +
                  count_call_points_in_range(
                    block_call_point_orders[end_block],
                    span_start_ord,
                    span_end_ord,
                  )
                c_call_count = c_call_count +
                  count_call_points_in_range(
                    block_c_call_point_orders[end_block],
                    span_start_ord,
                    span_end_ord,
                  )
                if end_block_ord - start_block_ord > 1 {
                  let mid_lo = start_block_ord + 1
                  let mid_hi = end_block_ord
                  call_count = call_count +
                    (
                      call_prefix_by_block_order[mid_hi] -
                      call_prefix_by_block_order[mid_lo]
                    )
                  c_call_count = c_call_count +
                    (
                      c_call_prefix_by_block_order[mid_hi] -
                      c_call_prefix_by_block_order[mid_lo]
                    )
                }
              }
            }
          }
          if !used_block_fast_path {
            let first_after_start = @core_regalloc.upper_bound_sorted_int(
              call_prog_point_orders, span_start_ord,
            )
            let first_at_or_after_end = @core_regalloc.lower_bound_sorted_int(
              call_prog_point_orders, span_end_ord,
            )
            if first_after_start < first_at_or_after_end {
              call_count = first_at_or_after_end - first_after_start
              c_call_count = c_call_prefix[first_at_or_after_end] -
                c_call_prefix[first_after_start]
            }
          }
          if call_count > 0 {
            range.crosses_call = true
            if c_call_count > 0 {
              range.crosses_c_call = true
            }
            if range.crosses_c_call {
              break
            }
          }
        }
        range.crosses_wasm_call = range.crosses_call && !range.crosses_c_call
      }
      result.add_range(range)
    }
  }
  // Build blockparam-out merge pairs once (regalloc2-style `blockparam_outs`):
  // each pair links `to` (block param) <- `from` (incoming edge arg).
  let mut max_block_id = -1
  for block in func.blocks {
    if block.id > max_block_id {
      max_block_id = block.id
    }
  }
  let block_idx_dense : Array[Int] = Array::make(max_block_id + 1, -1)
  for i, block in func.blocks {
    if block.id >= 0 && block.id < block_idx_dense.length() {
      block_idx_dense[block.id] = i
    }
  }
  // Keep blockparam-out pairs unique. Repeated (param,arg) edges are a no-op
  // for union-find coalescing but can amplify merge-phase cost on large CFGs.
  let seen_blockparam_pairs : Map[(Int, Int), Unit] = {}
  for pred_block in func.blocks {
    if pred_block.terminator is Some(Jump(target, args)) {
      if target < 0 || target >= block_idx_dense.length() {
        continue
      }
      let target_idx = block_idx_dense[target]
      if target_idx < 0 {
        continue
      }
      let target_block = func.blocks[target_idx]
      for i, param in target_block.params {
        if i >= args.length() {
          break
        }
        guard args[i] is Virtual(arg_vreg) else { continue }
        guard result.get_range_index_by_vreg(param.id) is Some(param_idx) else {
          continue
        }
        guard result.get_range_index_by_vreg(arg_vreg.id) is Some(arg_idx) else {
          continue
        }
        if arg_idx != param_idx {
          let pair = (param_idx, arg_idx)
          if seen_blockparam_pairs.get(pair) is None {
            seen_blockparam_pairs.set(pair, ())
            result.blockparam_out_pairs.push(pair)
          }
        }
      }
    }
  }
  result
}
