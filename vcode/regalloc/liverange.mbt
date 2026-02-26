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
pub impl Show for ProgPointRange with output(self, logger) {
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
pub impl Show for UseKind with output(self, logger) {
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
pub impl Show for OperandConstraint with output(self, logger) {
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
pub impl Show for UsePosition with output(self, logger) {
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
pub impl Show for Allocation with output(self, logger) {
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
    if preg.class is @abi.Int {
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
  if self.ranges.is_empty() {
    return None
  }
  let mut earliest = self.ranges[0].start
  for range in self.ranges {
    if range.start.compare_with_order(earliest, block_order) < 0 {
      earliest = range.start
    }
  }
  Some(earliest)
}

///|
/// Get the end point (latest point in all ranges)
pub fn LiveRange::end(
  self : LiveRange,
  block_order : FixedArray[Int],
) -> ProgPoint? {
  if self.ranges.is_empty() {
    return None
  }
  let mut latest = self.ranges[0].end
  for range in self.ranges {
    if range.end.compare_with_order(latest, block_order) > 0 {
      latest = range.end
    }
  }
  Some(latest)
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
pub impl Show for LiveRange with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Collection of LiveRanges built from liveness analysis
struct LiveRangeSet {
  ranges : Array[LiveRange]
  vreg_to_range : Map[Int, Int] // vreg.id -> range index
  block_order : FixedArray[Int] // Block execution order (O(1) lookup)
}

///|
fn LiveRangeSet::new(block_order : FixedArray[Int]) -> LiveRangeSet {
  { ranges: [], vreg_to_range: {}, block_order }
}

///|
/// Add a new LiveRange
fn LiveRangeSet::add_range(self : LiveRangeSet, range : LiveRange) -> Unit {
  let idx = self.ranges.length()
  self.vreg_to_range.set(range.vreg.id, idx)
  self.ranges.push(range)
}

///|
/// Get LiveRange by vreg id
pub fn LiveRangeSet::get_by_vreg(
  self : LiveRangeSet,
  vreg_id : Int,
) -> LiveRange? {
  match self.vreg_to_range.get(vreg_id) {
    Some(idx) => Some(self.ranges[idx])
    None => None
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
  let result = LiveRangeSet::new(liveness.block_order)
  let mut next_id = 0
  let block_order = liveness.block_order
  let sorted_call_points = liveness.call_points.copy()
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
  ) -> Bool {
    a.compare_with_order(b, block_order) < 0
  }

  fn pp_le(
    a : ProgPoint,
    b : ProgPoint,
    block_order : FixedArray[Int],
  ) -> Bool {
    a.compare_with_order(b, block_order) <= 0
  }

  fn pp_min(
    a : ProgPoint,
    b : ProgPoint,
    block_order : FixedArray[Int],
  ) -> ProgPoint {
    if pp_le(a, b, block_order) {
      a
    } else {
      b
    }
  }

  fn pp_max(
    a : ProgPoint,
    b : ProgPoint,
    block_order : FixedArray[Int],
  ) -> ProgPoint {
    if pp_lt(a, b, block_order) {
      b
    } else {
      a
    }
  }

  fn normalize_ranges(
    ranges : Array[ProgPointRange],
    block_order : FixedArray[Int],
  ) -> Array[ProgPointRange] {
    if ranges.length() <= 1 {
      return ranges
    }
    ranges.sort_by(fn(a, b) { a.start.compare_with_order(b.start, block_order) })
    let out : Array[ProgPointRange] = []
    out.push(ranges[0])
    for i in 1..<ranges.length() {
      let r = ranges[i]
      let last_idx = out.length() - 1
      let last = out[last_idx]
      if r.start.compare_with_order(last.end, block_order) < 0 {
        let end = pp_max(last.end, r.end, block_order)
        out[last_idx] = ProgPointRange::new(last.start, end)
      } else {
        out.push(r)
      }
    }
    out
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
  for block_idx, live_in_set in liveness.live_in {
    for vreg_id in live_in_set {
      add_live_block_dense(vreg_live_in_blocks, vreg_id, block_idx)
    }
  }
  for block_idx, live_out_set in liveness.live_out {
    for vreg_id in live_out_set {
      add_live_block_dense(vreg_live_out_blocks, vreg_id, block_idx)
    }
  }
  let num_blocks = func.blocks.length()
  // Scratch structures reused across vregs (epoch-tagged) to avoid per-vreg
  // HashMap churn in hot live-range construction paths.
  let use_first_points : Array[ProgPoint?] = Array::make(num_blocks, None)
  let use_last_points : Array[ProgPoint?] = Array::make(num_blocks, None)
  let use_block_epoch : FixedArray[Int] = FixedArray::make(num_blocks, 0)
  let covered_block_epoch : FixedArray[Int] = FixedArray::make(num_blocks, 0)
  let live_in_epoch : FixedArray[Int] = FixedArray::make(num_blocks, 0)
  let live_out_epoch : FixedArray[Int] = FixedArray::make(num_blocks, 0)
  let mut scratch_epoch = 1

  // Process each vreg from use-def info
  for entry in liveness.use_def {
    let (vreg_id, info) = entry
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
    let use_blocks : Array[Int] = []
    for use_entry in info.use_points {
      let p = use_entry.0
      let block_idx = p.block
      if use_block_epoch[block_idx] != epoch {
        use_block_epoch[block_idx] = epoch
        use_first_points[block_idx] = Some(p)
        use_last_points[block_idx] = Some(p)
        use_blocks.push(block_idx)
      } else {
        let first = use_first_points[block_idx].unwrap()
        let last = use_last_points[block_idx].unwrap()
        use_first_points[block_idx] = Some(pp_min(first, p, block_order))
        use_last_points[block_idx] = Some(pp_max(last, p, block_order))
      }
    }

    let covered_blocks_ordered : Array[Int] = []
    fn push_covered_once(
      block_idx : Int,
      epoch : Int,
      covered_block_epoch : FixedArray[Int],
      covered_blocks_ordered : Array[Int],
    ) -> Unit {
      if covered_block_epoch[block_idx] != epoch {
        covered_block_epoch[block_idx] = epoch
        covered_blocks_ordered.push(block_idx)
      }
    }

    if vreg_id >= 0 && vreg_id < max_vreg_id {
      if vreg_live_in_blocks[vreg_id] is Some(blocks) {
        for block_idx in blocks {
          live_in_epoch[block_idx] = epoch
          push_covered_once(
            block_idx, epoch, covered_block_epoch, covered_blocks_ordered,
          )
        }
      }
      if vreg_live_out_blocks[vreg_id] is Some(blocks) {
        for block_idx in blocks {
          live_out_epoch[block_idx] = epoch
          push_covered_once(
            block_idx, epoch, covered_block_epoch, covered_blocks_ordered,
          )
        }
      }
    }
    for block_idx in use_blocks {
      push_covered_once(
        block_idx, epoch, covered_block_epoch, covered_blocks_ordered,
      )
    }
    if info.def_point is Some((def, _)) {
      push_covered_once(
        def.block,
        epoch,
        covered_block_epoch,
        covered_blocks_ordered,
      )
    }
    covered_blocks_ordered.sort_by(fn(a, b) { block_order[a] - block_order[b] })

    let spans_unmerged : Array[ProgPointRange] = []
    for block_idx in covered_blocks_ordered {
      let block = func.blocks[block_idx]
      let live_in = live_in_epoch[block_idx] == epoch
      let live_out = live_out_epoch[block_idx] == epoch
      let has_def_in_block = info.def_point is Some((def, _)) &&
        def.block == block_idx
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
      let entry_point : ProgPoint = { block: block_idx, inst: -1, pos: Before }
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
        pp_min(entry_point, first_use, block_order)
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
      let (start, end) = if end.compare_with_order(start, block_order) <= 0 {
        (start, point_after(start, block_len))
      } else {
        (start, end)
      }
      spans_unmerged.push(ProgPointRange::new(start, end))
    }
    let spans = normalize_ranges(spans_unmerged, block_order)
    for span in spans {
      range.add_range(span)
    }

    // Compute call-crossing from normalized spans.
    // This is more precise than coarse def..end intervals (which can over-mark
    // values as call-crossing across dead holes between live spans).
    if !call_prog_points.is_empty() {
      for span in range.ranges {
        let first_after_start = upper_bound_call_points(
          call_prog_points,
          span.start,
          block_order,
        )
        let first_at_or_after_end = lower_bound_call_points(
          call_prog_points,
          span.end,
          block_order,
        )
        if first_after_start < first_at_or_after_end {
          range.crosses_call = true
          let c_calls = c_call_prefix[first_at_or_after_end] -
            c_call_prefix[first_after_start]
          if c_calls > 0 {
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
  result
}
