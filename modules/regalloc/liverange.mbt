///|
pub(all) struct ProgramPoint {
  block : Int
  inst : Int
} derive(Eq, Debug)

///|
pub fn ProgramPoint::new(block : Int, inst : Int) -> ProgramPoint {
  { block, inst }
}

///|
fn ProgramPoint::order(self : ProgramPoint, block_order : Array[Int]) -> Int {
  let block_ord = if self.block >= 0 && self.block < block_order.length() {
    block_order[self.block]
  } else {
    self.block
  }
  block_ord * 1_000_000 + self.inst
}

///|
pub fn ProgramPoint::compare_with_order(
  self : ProgramPoint,
  other : ProgramPoint,
  block_order : Array[Int],
) -> Int {
  let lhs = self.order(block_order)
  let rhs = other.order(block_order)
  if lhs < rhs {
    -1
  } else if lhs > rhs {
    1
  } else {
    0
  }
}

///|
pub(all) struct ProgramRange {
  start : ProgramPoint
  end : ProgramPoint
} derive(Eq, Debug)

///|
pub fn ProgramRange::new(
  start : ProgramPoint,
  end : ProgramPoint,
) -> ProgramRange {
  { start, end }
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
pub(all) enum OperandConstraint {
  AnyReg
  FixedReg(PhysicalReg)
} derive(Eq, Debug)

///|
pub(all) struct UsePosition {
  point : ProgramPoint
  kind : UseKind
  constraint : OperandConstraint
} derive(Eq, Debug)

///|
pub fn UsePosition::new(
  point : ProgramPoint,
  kind : UseKind,
  constraint : OperandConstraint,
) -> UsePosition {
  { point, kind, constraint }
}

///|
pub(all) struct LiveRange {
  id : Int
  vreg : VirtualReg
  ranges : Array[ProgramRange]
  uses : Array[UsePosition]
  mut bundle_id : Int
  mut allocation : Location?
  mut crosses_call : Bool
} derive(Debug)

///|
pub fn LiveRange::new(id : Int, vreg : VirtualReg) -> LiveRange {
  {
    id,
    vreg,
    ranges: [],
    uses: [],
    bundle_id: -1,
    allocation: None,
    crosses_call: false,
  }
}

///|
pub fn LiveRange::add_range(self : LiveRange, range : ProgramRange) -> Unit {
  self.ranges.push(range)
}

///|
pub fn LiveRange::add_use(self : LiveRange, use_pos : UsePosition) -> Unit {
  self.uses.push(use_pos)
}

///|
pub fn LiveRange::touch(self : LiveRange, point : ProgramPoint) -> Unit {
  if self.ranges.length() == 0 {
    self.ranges.push(ProgramRange::new(point, point))
    return
  }
  let first = self.ranges[0]
  if point.compare_with_order(first.start, []) < 0 {
    self.ranges[0] = ProgramRange::new(point, first.end)
  }
  let last_idx = self.ranges.length() - 1
  let last = self.ranges[last_idx]
  if last.end.compare_with_order(point, []) < 0 {
    self.ranges[last_idx] = ProgramRange::new(last.start, point)
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
fn LiveRange::is_live_across(
  self : LiveRange,
  point : ProgramPoint,
  block_order : Array[Int],
) -> Bool {
  match (self.start(), self.end()) {
    (Some(start), Some(end)) =>
      start.compare_with_order(point, block_order) < 0 &&
      point.compare_with_order(end, block_order) < 0
    _ => false
  }
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
pub(all) struct LiveRangeSet {
  ranges : Array[LiveRange]
  block_order : Array[Int]
} derive(Debug)

///|
pub fn LiveRangeSet::new(block_order : Array[Int]) -> LiveRangeSet {
  { ranges: [], block_order }
}

///|
pub fn LiveRangeSet::add_range(self : LiveRangeSet, range : LiveRange) -> Unit {
  self.ranges.push(range)
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
  for range in self.ranges {
    if range.vreg == vreg {
      return Some(range)
    }
  }
  None
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
      let range = LiveRange::new(ranges.ranges.length(), vreg)
      ranges.add_range(range)
      range
    }
  }
}

///|
pub fn build_live_ranges(program : Program) -> LiveRangeSet {
  let block_order : Array[Int] = []
  for order, block in program.blocks {
    while block.id >= block_order.length() {
      block_order.push(block_order.length())
    }
    block_order[block.id] = order
  }
  let ranges = LiveRangeSet::new(block_order)
  for block in program.blocks {
    for inst_index, inst in block.instructions {
      let point = ProgramPoint::new(block.id, inst_index)
      for operand in inst.operands {
        let range = find_or_create_live_range(ranges, operand.vreg)
        range.touch(point)
        range.add_use(
          UsePosition::new(
            point,
            use_kind_of_role(operand.role),
            operand.constraint,
          ),
        )
      }
    }
  }
  ranges.ranges.sort_by(fn(a, b) {
    match (a.start(), b.start()) {
      (Some(lhs), Some(rhs)) => {
        let by_point = lhs.compare_with_order(rhs, ranges.block_order)
        if by_point != 0 {
          by_point
        } else {
          a.vreg.id - b.vreg.id
        }
      }
      (None, Some(_)) => 1
      (Some(_), None) => -1
      (None, None) => a.vreg.id - b.vreg.id
    }
  })
  ranges
}
