///|
#derive(Eq)
#valtype
priv struct ProgramPoint {
  block : Int32
  inst : Int32
}

///|
fn ProgramPoint::ProgramPoint(block : Int32, inst : Int32) -> ProgramPoint {
  { block, inst, }
}

///|
fn ProgramPoint::compare_with_order(
  self : ProgramPoint,
  other : ProgramPoint,
  block_order : Array[Int32],
) -> Int32 {
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
  compare_program_positions(lhs_block, self.inst, rhs_block, other.inst)
}

///|
fn compare_program_positions(
  lhs_block : Int32,
  lhs_inst : Int32,
  rhs_block : Int32,
  rhs_inst : Int32,
) -> Int32 {
  if lhs_block < rhs_block {
    -1
  } else if lhs_block > rhs_block {
    1
  } else if lhs_inst < rhs_inst {
    -1
  } else if lhs_inst > rhs_inst {
    1
  } else {
    0
  }
}

///|
#valtype
priv struct ProgramRange {
  start : ProgramPoint
  end : ProgramPoint
}

///|
fn ProgramRange::ProgramRange(
  start : ProgramPoint,
  end : ProgramPoint,
) -> ProgramRange {
  { start, end, }
}

///|
fn ProgramRange::overlaps(
  self : ProgramRange,
  other : ProgramRange,
  block_order : Array[Int32],
) -> Bool {
  self.start.compare_with_order(other.end, block_order) <= 0 &&
  other.start.compare_with_order(self.end, block_order) <= 0
}

///|
fn ProgramRange::contains(
  self : ProgramRange,
  point : ProgramPoint,
  block_order : Array[Int32],
) -> Bool {
  self.start.compare_with_order(point, block_order) <= 0 &&
  point.compare_with_order(self.end, block_order) <= 0
}

///|
priv enum UseKind {
  LiveDef
  LiveUse
  LiveUseDef
}

///|
priv struct UsePosition {
  point : ProgramPoint
  kind : UseKind
  constraint : OperandConstraint
  preference : PhysicalReg?
}

///|
fn UsePosition::UsePosition(
  point : ProgramPoint,
  kind : UseKind,
  constraint : OperandConstraint,
) -> UsePosition {
  { point, kind, constraint, preference: None, }
}

///|
priv struct LiveRange {
  id : Int32
  vreg : VirtualReg
  ranges : Array[ProgramRange]
  uses : Array[UsePosition]
}

///|
fn LiveRange::LiveRange(id : Int32, vreg : VirtualReg) -> LiveRange {
  { id, vreg, ranges: [], uses: [], }
}

///|
fn LiveRange::range_count(self : LiveRange) -> Int32 {
  self.ranges.length()
}

///|
fn LiveRange::range_at(self : LiveRange, index : Int32) -> ProgramRange? {
  self.ranges.get(index)
}

///|
fn LiveRange::add_range(self : LiveRange, range : ProgramRange) -> Unit {
  self.ranges.push(range)
}

///|
fn LiveRange::sort_ranges(self : LiveRange, block_order : Array[Int32]) -> Unit {
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
  block_order : Array[Int32],
  block_ends : Array[Int32],
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
fn LiveRange::add_use(self : LiveRange, use_pos : UsePosition) -> Unit {
  self.uses.push(use_pos)
}

///|
fn later_point(
  lhs : ProgramPoint,
  rhs : ProgramPoint,
  block_order : Array[Int32],
) -> ProgramPoint {
  if lhs.compare_with_order(rhs, block_order) >= 0 {
    lhs
  } else {
    rhs
  }
}

///|
priv struct LiveRangeSet {
  ranges : Array[LiveRange]
  block_order : Array[Int32]
  block_ends : Array[Int32]
  block_offsets : Array[Int64]
  int_ranges_by_id : Array[LiveRange?]
  float_ranges_by_id : Array[LiveRange?]
  vector_ranges_by_id : Array[LiveRange?]
}

///|
fn LiveRangeSet::LiveRangeSet(block_order : Array[Int32]) -> LiveRangeSet {
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
  block_ends : Array[Int32],
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
) -> Int32 {
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
fn LiveRangeSet::add_range(self : LiveRangeSet, range : LiveRange) -> Unit {
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
fn LiveRangeSet::length(self : LiveRangeSet) -> Int32 {
  self.ranges.length()
}

///|
fn LiveRangeSet::get_by_vreg(
  self : LiveRangeSet,
  vreg : VirtualReg,
) -> LiveRange? {
  if vreg.id < 0 {
    return None
  }
  let ranges = self.ranges_by_id_for_class(vreg.class)
  if vreg.id < ranges.length() {
    ranges[vreg.id]
  } else {
    None
  }
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

///|
fn ProgramPoint::compare_natural(
  self : ProgramPoint,
  other : ProgramPoint,
) -> Int32 {
  compare_program_positions(self.block, self.inst, other.block, other.inst)
}

///|
fn ProgramRange::contains_natural(
  self : ProgramRange,
  point : ProgramPoint,
) -> Bool {
  self.start.compare_natural(point) <= 0 && point.compare_natural(self.end) <= 0
}
