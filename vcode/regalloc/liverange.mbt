// Ion-Style LiveRange Data Structures
// Enhanced live interval representation with multiple precise spans
// and use position constraints for the backtracking allocator.

///|
/// A contiguous program point range (start inclusive, end exclusive)
pub(all) struct ProgPointRange {
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
  block_order : Map[Int, Int],
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
  block_order : Map[Int, Int],
) -> Bool {
  let start_cmp = self.start.compare_with_order(point, block_order)
  let end_cmp = point.compare_with_order(self.end, block_order)
  start_cmp <= 0 && end_cmp < 0
}

///|
/// Kind of use at a program point
pub(all) enum UseKind {
  Def // Definition (value produced)
  Use // Use (value consumed)
  DefUse // Both def and use (e.g., tied operand)
}

///|
fn UseKind::to_string(self : UseKind) -> String {
  match self {
    Def => "def"
    Use => "use"
    DefUse => "def+use"
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
pub(all) struct UsePosition {
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
pub(all) struct LiveRange {
  id : Int
  vreg : @abi.VReg
  ranges : Array[ProgPointRange] // Multiple non-overlapping spans
  uses : Array[UsePosition] // Use positions with constraints
  mut bundle_id : Int // Owning Bundle ID (-1 if none)
  mut allocation : Allocation // Allocation result
  // Cached properties
  mut crosses_call : Bool // Spans across a function call
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
  let mut fixed : @abi.PReg? = None
  for use_pos in self.uses {
    match use_pos.constraint {
      FixedReg(preg) =>
        match fixed {
          None => fixed = Some(preg)
          Some(existing) =>
            if existing.index != preg.index {
              return None // Conflicting constraints
            }
        }
      AnyReg => ()
    }
  }
  fixed
}

///|
/// Check if this LiveRange overlaps with another
pub fn LiveRange::overlaps(
  self : LiveRange,
  other : LiveRange,
  block_order : Map[Int, Int],
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
  block_order : Map[Int, Int],
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
  block_order : Map[Int, Int],
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
pub(all) struct LiveRangeSet {
  ranges : Array[LiveRange]
  vreg_to_range : Map[Int, Int] // vreg.id -> range index
  block_order : Map[Int, Int] // Block execution order
}

///|
fn LiveRangeSet::new(block_order : Map[Int, Int]) -> LiveRangeSet {
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

  // Process each vreg from use-def info
  for entry in liveness.use_def {
    let (vreg_id, info) = entry
    let range = LiveRange::new(next_id, info.vreg)
    next_id += 1

    // Build ranges from def point to uses
    // For now, use a single range from earliest to latest point
    // TODO: Build precise multi-span ranges
    let interval = liveness.intervals.get(vreg_id)
    match interval {
      Some(iv) => {
        range.add_range(ProgPointRange::new(iv.start, iv.end))
        range.crosses_call = iv.crosses_call

        // Add use positions
        if info.def_point is Some(def) {
          let constraint = find_constraint_at_for_vreg(func, def, vreg_id)
          range.add_use(UsePosition::new(def, Def, constraint))
        }
        for use_point in info.use_points {
          let constraint = find_constraint_at_for_vreg(func, use_point, vreg_id)
          range.add_use(UsePosition::new(use_point, Use, constraint))
        }
      }
      None => ()
    }
    result.add_range(range)
  }
  result
}

///|
/// Find operand constraint at a program point for a specific vreg
/// We need the vreg to match against the correct operand position
fn find_constraint_at_for_vreg(
  func : VCodeFunction,
  point : ProgPoint,
  vreg_id : Int,
) -> OperandConstraint {
  if point.block >= func.blocks.length() {
    return AnyReg
  }
  let block = func.blocks[point.block]
  if point.inst < 0 || point.inst >= block.insts.length() {
    return AnyReg
  }
  let inst = block.insts[point.inst]

  // Check use constraints - find the constraint that matches our vreg
  if point.pos is Before {
    for i, use_reg in inst.uses {
      if use_reg is @abi.Virtual(vreg) && vreg.id == vreg_id {
        if i < inst.use_constraints.length() {
          let constraint = inst.use_constraints[i]
          if constraint is @abi.FixedReg(preg) {
            return FixedReg(preg)
          }
        }
        break
      }
    }
  }

  // Check def constraints - find the constraint that matches our vreg
  if point.pos is After {
    for i, def in inst.defs {
      if def.reg is @abi.Virtual(vreg) && vreg.id == vreg_id {
        if i < inst.def_constraints.length() {
          let constraint = inst.def_constraints[i]
          if constraint is @abi.FixedReg(preg) {
            return FixedReg(preg)
          }
        }
        break
      }
    }
  }
  AnyReg
}
