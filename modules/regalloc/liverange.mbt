///|
#valtype
pub(all) struct ProgramPoint {
  block : Int
  inst : Int
} derive(Eq, Debug)

///|
pub fn ProgramPoint::ProgramPoint(block : Int, inst : Int) -> ProgramPoint {
  { block, inst, }
}

///|
pub fn ProgramPoint::compare_with_order(
  self : ProgramPoint,
  other : ProgramPoint,
  block_order : Array[Int],
) -> Int {
  let lhs_block = if self.block >= 0 && self.block < block_order.length() {
    block_order[self.block]
  } else {
    self.block
  }
  let rhs_block = if other.block >= 0 && other.block < block_order.length() {
    block_order[other.block]
  } else {
    other.block
  }
  if lhs_block < rhs_block {
    -1
  } else if lhs_block > rhs_block {
    1
  } else if self.inst < other.inst {
    -1
  } else if self.inst > other.inst {
    1
  } else {
    0
  }
}

///|
#valtype
pub(all) struct ProgramRange {
  start : ProgramPoint
  end : ProgramPoint
} derive(Eq, Debug)

///|
pub fn ProgramRange::ProgramRange(
  start : ProgramPoint,
  end : ProgramPoint,
) -> ProgramRange {
  { start, end, }
}

///|
pub fn ProgramRange::overlaps(
  self : ProgramRange,
  other : ProgramRange,
  block_order : Array[Int],
) -> Bool {
  self.start.compare_with_order(other.end, block_order) <= 0 &&
  other.start.compare_with_order(self.end, block_order) <= 0
}

///|
pub fn ProgramRange::contains(
  self : ProgramRange,
  point : ProgramPoint,
  block_order : Array[Int],
) -> Bool {
  self.start.compare_with_order(point, block_order) <= 0 &&
  point.compare_with_order(self.end, block_order) <= 0
}

///|
pub(all) enum UseKind {
  LiveDef
  LiveUse
  LiveUseDef
} derive(Eq, Debug)

///|
pub(all) struct UsePosition {
  point : ProgramPoint
  kind : UseKind
  constraint : OperandConstraint
  preference : PhysicalReg?
  tie_id : Int
} derive(Eq, Debug)

///|
pub fn UsePosition::UsePosition(
  point : ProgramPoint,
  kind : UseKind,
  constraint : OperandConstraint,
) -> UsePosition {
  { point, kind, constraint, preference: None, tie_id: -1, }
}

///|
pub fn UsePosition::with_tie(self : UsePosition, tie_id : Int) -> UsePosition {
  { ..self, tie_id, }
}

///|
pub fn UsePosition::with_preference(
  self : UsePosition,
  preference : PhysicalReg?,
) -> UsePosition {
  { ..self, preference, }
}

///|
struct LiveRange {
  id : Int
  vreg : VirtualReg
  ranges : Array[ProgramRange]
  uses : Array[UsePosition]
} derive(Debug)

///|
pub fn LiveRange::LiveRange(id : Int, vreg : VirtualReg) -> LiveRange {
  { id, vreg, ranges: [], uses: [], }
}

///|
pub fn LiveRange::id(self : LiveRange) -> Int {
  self.id
}

///|
pub fn LiveRange::vreg(self : LiveRange) -> VirtualReg {
  self.vreg
}

///|
pub fn LiveRange::range_count(self : LiveRange) -> Int {
  self.ranges.length()
}

///|
pub fn LiveRange::range_at(self : LiveRange, index : Int) -> ProgramRange? {
  self.ranges.get(index)
}

///|
pub fn LiveRange::add_range(self : LiveRange, range : ProgramRange) -> Unit {
  self.ranges.push(range)
}

///|
fn LiveRange::sort_ranges(self : LiveRange, block_order : Array[Int]) -> Unit {
  self.ranges.sort_by(fn(a, b) {
    let by_start = a.start.compare_with_order(b.start, block_order)
    if by_start != 0 {
      by_start
    } else {
      a.end.compare_with_order(b.end, block_order)
    }
  })
}

///|
fn LiveRange::coalesce_contiguous_ranges(
  self : LiveRange,
  block_order : Array[Int],
  block_ends : Array[Int],
) -> Unit {
  guard self.ranges.length() > 1 else { return }
  let mut write_index = 1
  for read_index in 1..<self.ranges.length() {
    let previous = self.ranges[write_index - 1]
    let next = self.ranges[read_index]
    let previous_block = previous.end.block
    let next_block = next.start.block
    let contiguous = previous_block >= 0 &&
      previous_block < block_order.length() &&
      previous_block < block_ends.length() &&
      next_block >= 0 &&
      next_block < block_order.length() &&
      block_order[next_block] == block_order[previous_block] + 1 &&
      previous.end.inst == block_ends[previous_block] &&
      next.start.inst == -1
    if contiguous {
      self.ranges[write_index - 1] = ProgramRange(previous.start, next.end)
    } else {
      self.ranges[write_index] = next
      write_index = write_index + 1
    }
  }
  self.ranges.truncate(write_index)
}

///|
pub fn LiveRange::use_count(self : LiveRange) -> Int {
  self.uses.length()
}

///|
pub fn LiveRange::use_at(self : LiveRange, index : Int) -> UsePosition? {
  self.uses.get(index)
}

///|
pub fn LiveRange::add_use(self : LiveRange, use_pos : UsePosition) -> Unit {
  self.uses.push(use_pos)
}

///|
pub fn LiveRange::touch(self : LiveRange, point : ProgramPoint) -> Unit {
  self.touch_with_order(point, [])
}

///|
pub fn LiveRange::touch_with_order(
  self : LiveRange,
  point : ProgramPoint,
  block_order : Array[Int],
) -> Unit {
  if self.ranges.length() == 0 {
    self.ranges.push(ProgramRange(point, point))
    return
  }
  let first = self.ranges[0]
  if point.compare_with_order(first.start, block_order) < 0 {
    self.ranges[0] = ProgramRange(point, first.end)
  }
  let last_idx = self.ranges.length() - 1
  let last = self.ranges[last_idx]
  if last.end.compare_with_order(point, block_order) < 0 {
    self.ranges[last_idx] = ProgramRange(last.start, point)
  }
}

///|
pub fn LiveRange::has_fixed_constraint(self : LiveRange) -> Bool {
  for use_pos in self.uses {
    if use_pos.constraint is FixedReg(_) {
      return true
    }
  }
  false
}

///|
pub fn LiveRange::get_fixed_reg(self : LiveRange) -> PhysicalReg? {
  let mut fixed : PhysicalReg? = None
  for use_pos in self.uses {
    if use_pos.constraint is FixedReg(preg) {
      match fixed {
        None => fixed = Some(preg)
        Some(existing) => if existing != preg { return None }
      }
    }
  }
  fixed
}

///|
pub fn LiveRange::overlaps(
  self : LiveRange,
  other : LiveRange,
  block_order : Array[Int],
) -> Bool {
  for range in self.ranges {
    for other_range in other.ranges {
      if range.overlaps(other_range, block_order) {
        return true
      }
    }
  }
  false
}

///|
fn later_point(
  lhs : ProgramPoint,
  rhs : ProgramPoint,
  block_order : Array[Int],
) -> ProgramPoint {
  if lhs.compare_with_order(rhs, block_order) >= 0 {
    lhs
  } else {
    rhs
  }
}

///|
fn earlier_point(
  lhs : ProgramPoint,
  rhs : ProgramPoint,
  block_order : Array[Int],
) -> ProgramPoint {
  if lhs.compare_with_order(rhs, block_order) <= 0 {
    lhs
  } else {
    rhs
  }
}

///|
pub fn LiveRange::has_tie_at(
  self : LiveRange,
  other : LiveRange,
  point : ProgramPoint,
) -> Bool {
  for lhs in self.uses {
    if lhs.tie_id < 0 || lhs.point != point {
      continue
    }
    for rhs in other.uses {
      if rhs.point == point && rhs.tie_id == lhs.tie_id {
        return true
      }
    }
  }
  false
}

///|
pub fn LiveRange::overlap_allowed_by_tie(
  self : LiveRange,
  other : LiveRange,
  block_order : Array[Int],
) -> Bool {
  for lhs in self.ranges {
    for rhs in other.ranges {
      if !lhs.overlaps(rhs, block_order) {
        continue
      }
      let start = later_point(lhs.start, rhs.start, block_order)
      let end = earlier_point(lhs.end, rhs.end, block_order)
      if start.compare_with_order(end, block_order) != 0 ||
        !self.has_tie_at(other, start) {
        return false
      }
    }
  }
  true
}

///|
pub fn LiveRange::is_live_across(
  self : LiveRange,
  point : ProgramPoint,
  block_order : Array[Int],
) -> Bool {
  for range in self.ranges {
    if range.start.compare_with_order(point, block_order) < 0 &&
      point.compare_with_order(range.end, block_order) < 0 {
      return true
    }
  }
  false
}

///|
pub fn LiveRange::start(self : LiveRange) -> ProgramPoint? {
  if self.ranges.length() == 0 {
    None
  } else {
    Some(self.ranges[0].start)
  }
}

///|
pub fn LiveRange::end(self : LiveRange) -> ProgramPoint? {
  if self.ranges.length() == 0 {
    None
  } else {
    Some(self.ranges[self.ranges.length() - 1].end)
  }
}

///|
pub fn LiveRange::total_length(self : LiveRange) -> Int {
  let mut total = 0
  for range in self.ranges {
    if range.start.block == range.end.block {
      total = total + (range.end.inst - range.start.inst).abs() + 1
    } else {
      total = total +
        (range.end.block - range.start.block).abs() * 10 +
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
struct LiveRangeSet {
  ranges : Array[LiveRange]
  block_order : Array[Int]
  block_ends : Array[Int]
  block_offsets : Array[Int64]
  int_ranges_by_id : Array[LiveRange?]
  float_ranges_by_id : Array[LiveRange?]
  vector_ranges_by_id : Array[LiveRange?]
} derive(Debug)

///|
pub fn LiveRangeSet::LiveRangeSet(block_order : Array[Int]) -> LiveRangeSet {
  {
    ranges: [],
    block_order,
    block_ends: Array::make(block_order.length(), -1),
    block_offsets: Array::make(block_order.length(), 0L),
    int_ranges_by_id: [],
    float_ranges_by_id: [],
    vector_ranges_by_id: [],
  }
}

///|
fn LiveRangeSet::record_block_ends(
  self : LiveRangeSet,
  block_ends : Array[Int],
) -> Unit {
  self.block_ends.clear()
  for end in block_ends {
    self.block_ends.push(end)
  }
  self.block_offsets.clear()
  self.block_offsets.resize(block_ends.length(), 0L)
  let blocks_by_order = Array::make(block_ends.length(), -1)
  for block, order in self.block_order {
    if order >= 0 && order < blocks_by_order.length() {
      blocks_by_order[order] = block
    }
  }
  let mut offset = 0L
  for block in blocks_by_order {
    if block >= 0 {
      self.block_offsets[block] = offset
      offset = offset + self.block_ends[block].to_int64() + 2L
    }
  }
}

///|
fn LiveRangeSet::program_range_length(
  self : LiveRangeSet,
  range : ProgramRange,
) -> Int {
  if range.start.block == range.end.block {
    return (range.end.inst - range.start.inst).abs() + 1
  }
  let start_block = range.start.block
  let end_block = range.end.block
  if start_block < 0 ||
    start_block >= self.block_offsets.length() ||
    end_block < 0 ||
    end_block >= self.block_offsets.length() {
    return 1
  }
  let start = self.block_offsets[start_block] + range.start.inst.to_int64() + 1L
  let end = self.block_offsets[end_block] + range.end.inst.to_int64() + 1L
  (end - start + 1L).max(1L).min(2_147_483_647L).to_int()
}

///|
fn LiveRangeSet::ranges_by_id_for_class(
  self : LiveRangeSet,
  class : RegClass,
) -> Array[LiveRange?] {
  match class {
    Int => self.int_ranges_by_id
    Float => self.float_ranges_by_id
    Vector => self.vector_ranges_by_id
    FpVector => self.float_ranges_by_id
  }
}

///|
pub fn LiveRangeSet::block_order_count(self : LiveRangeSet) -> Int {
  self.block_order.length()
}

///|
pub fn LiveRangeSet::block_order(self : LiveRangeSet) -> Array[Int] {
  self.block_order.copy()
}

///|
pub fn LiveRangeSet::block_order_at(self : LiveRangeSet, index : Int) -> Int? {
  self.block_order.get(index)
}

///|
pub fn LiveRangeSet::add_range(self : LiveRangeSet, range : LiveRange) -> Unit {
  self.ranges.push(range)
  if range.vreg.id >= 0 {
    let ranges_by_id = self.ranges_by_id_for_class(range.vreg.class)
    while range.vreg.id >= ranges_by_id.length() {
      ranges_by_id.push(None)
    }
    ranges_by_id[range.vreg.id] = Some(range)
  }
}

///|
pub fn LiveRangeSet::get(self : LiveRangeSet, idx : Int) -> LiveRange {
  self.ranges[idx]
}

///|
pub fn LiveRangeSet::length(self : LiveRangeSet) -> Int {
  self.ranges.length()
}

///|
pub fn LiveRangeSet::get_by_vreg(
  self : LiveRangeSet,
  vreg : VirtualReg,
) -> LiveRange? {
  if vreg.id < 0 {
    return None
  }
  self.ranges_by_id_for_class(vreg.class).get(vreg.id).bind(range => range)
}

///|
fn use_kind_of_role(role : OperandRole) -> UseKind {
  match role {
    Def => LiveDef
    Use => LiveUse
    UseDef => LiveUseDef
  }
}

///|
fn find_or_create_live_range(
  ranges : LiveRangeSet,
  vreg : VirtualReg,
) -> LiveRange {
  match ranges.get_by_vreg(vreg) {
    Some(range) => range
    None => {
      let range = LiveRange::LiveRange(ranges.ranges.length(), vreg)
      ranges.add_range(range)
      range
    }
  }
}

///|
fn add_live_range_fragment(
  ranges : LiveRangeSet,
  vreg : VirtualReg,
  start : ProgramPoint,
  end : ProgramPoint,
) -> Unit {
  find_or_create_live_range(ranges, vreg).add_range(ProgramRange(start, end))
}
