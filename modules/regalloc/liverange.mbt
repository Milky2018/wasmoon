///|
pub(all) struct ProgramPoint {
  block : Int
  inst : Int
} derive(Eq, Debug)

///|
pub fn ProgramPoint::ProgramPoint(block : Int, inst : Int) -> ProgramPoint {
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
pub fn ProgramRange::ProgramRange(
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
  tie_id : Int
} derive(Eq, Debug)

///|
pub fn UsePosition::UsePosition(
  point : ProgramPoint,
  kind : UseKind,
  constraint : OperandConstraint,
) -> UsePosition {
  { point, kind, constraint, tie_id: -1 }
}

///|
pub fn UsePosition::with_tie(self : UsePosition, tie_id : Int) -> UsePosition {
  { point: self.point, kind: self.kind, constraint: self.constraint, tie_id }
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
pub fn LiveRange::LiveRange(id : Int, vreg : VirtualReg) -> LiveRange {
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
fn LiveRange::has_tie_at(
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
pub fn LiveRangeSet::LiveRangeSet(block_order : Array[Int]) -> LiveRangeSet {
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
      let range = LiveRange::LiveRange(ranges.ranges.length(), vreg)
      ranges.add_range(range)
      range
    }
  }
}

///|
fn contains_vreg(values : Array[VirtualReg], vreg : VirtualReg) -> Bool {
  for value in values {
    if value == vreg {
      return true
    }
  }
  false
}

///|
fn add_vreg(values : Array[VirtualReg], vreg : VirtualReg) -> Unit {
  if !contains_vreg(values, vreg) {
    values.push(vreg)
  }
}

///|
fn collect_block_uses_defs(
  block : Block,
) -> (Array[VirtualReg], Array[VirtualReg]) {
  let uses : Array[VirtualReg] = []
  let defs : Array[VirtualReg] = []
  for inst in block.instructions {
    for operand in inst.operands {
      match operand.role {
        Use =>
          if !contains_vreg(defs, operand.vreg) {
            add_vreg(uses, operand.vreg)
          }
        Def => add_vreg(defs, operand.vreg)
        UseDef => {
          if !contains_vreg(defs, operand.vreg) {
            add_vreg(uses, operand.vreg)
          }
          add_vreg(defs, operand.vreg)
        }
      }
    }
  }
  (uses, defs)
}

///|
fn compute_live_sets(
  program : Program,
) -> (Array[Array[VirtualReg]], Array[Array[VirtualReg]]) {
  let uses_by_block : Array[Array[VirtualReg]] = []
  let defs_by_block : Array[Array[VirtualReg]] = []
  let block_ids : Array[Int] = []
  let block_successor_ids : Array[Array[Int]] = []
  let mut max_vreg_id = -1
  for block in program.blocks {
    let (uses, defs) = collect_block_uses_defs(block)
    for vreg in uses {
      if vreg.id > max_vreg_id {
        max_vreg_id = vreg.id
      }
    }
    for vreg in defs {
      if vreg.id > max_vreg_id {
        max_vreg_id = vreg.id
      }
    }
    uses_by_block.push(uses)
    defs_by_block.push(defs)
    block_ids.push(block.id)
    block_successor_ids.push(block.successors)
  }
  if max_vreg_id < 0 {
    let empty_live_in : Array[Array[VirtualReg]] = []
    let empty_live_out : Array[Array[VirtualReg]] = []
    for _ in program.blocks {
      empty_live_in.push([])
      empty_live_out.push([])
    }
    return (empty_live_in, empty_live_out)
  }

  let vregs_by_id : Array[VirtualReg?] = Array::make(max_vreg_id + 1, None)
  let def_points : Array[ProgramPoint?] = Array::make(max_vreg_id + 1, None)
  let use_points_by_vreg : Array[Array[ProgramPoint]] = []
  for _ in 0..<=max_vreg_id {
    use_points_by_vreg.push([])
  }
  for block_index, block in program.blocks {
    for vreg in uses_by_block[block_index] {
      if vreg.id >= 0 && vreg.id < vregs_by_id.length() {
        vregs_by_id[vreg.id] = Some(vreg)
        use_points_by_vreg[vreg.id].push(ProgramPoint(block.id, 0))
      }
    }
    for vreg in defs_by_block[block_index] {
      if vreg.id >= 0 && vreg.id < vregs_by_id.length() {
        vregs_by_id[vreg.id] = Some(vreg)
        if def_points[vreg.id] is None {
          def_points[vreg.id] = Some(ProgramPoint(block.id, 0))
        }
      }
    }
  }

  let use_defs : Array[LiveSetUseDef] = []
  for vreg_id in 0..<=max_vreg_id {
    if vregs_by_id[vreg_id] is Some(_) {
      use_defs.push({
        vreg_id,
        def_point: def_points[vreg_id],
        is_entry_param_def: false,
        use_points: use_points_by_vreg[vreg_id],
      })
    }
  }
  let dense = compute_dense_live_sets(
    program.blocks.length(),
    max_vreg_id + 1,
    build_dense_successor_edges(block_ids, block_successor_ids),
    use_defs,
  )

  fn materialize(
    dense_sets : Array[Array[Int]],
    vregs_by_id : Array[VirtualReg?],
  ) -> Array[Array[VirtualReg]] {
    let out : Array[Array[VirtualReg]] = []
    for dense_row in dense_sets {
      let row : Array[VirtualReg] = []
      for vreg_id in dense_row {
        if vreg_id >= 0 &&
          vreg_id < vregs_by_id.length() &&
          vregs_by_id[vreg_id] is Some(vreg) {
          row.push(vreg)
        }
      }
      out.push(row)
    }
    out
  }

  (
    materialize(dense.live_in, vregs_by_id),
    materialize(dense.live_out, vregs_by_id),
  )
}

///|
fn block_end_point(block : Block) -> ProgramPoint {
  let inst = if block.instructions.length() == 0 {
    0
  } else {
    block.instructions.length() - 1
  }
  ProgramPoint(block.id, inst)
}

///|
fn extend_ranges_for_block_liveness(
  ranges : LiveRangeSet,
  program : Program,
  live_in : Array[Array[VirtualReg]],
  live_out : Array[Array[VirtualReg]],
) -> Unit {
  for block_index, block in program.blocks {
    let start = ProgramPoint::ProgramPoint(block.id, 0)
    let end = block_end_point(block)
    for vreg in live_in[block_index] {
      let range = find_or_create_live_range(ranges, vreg)
      range.touch_with_order(start, ranges.block_order)
    }
    for vreg in live_out[block_index] {
      let range = find_or_create_live_range(ranges, vreg)
      range.touch_with_order(end, ranges.block_order)
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
  let ranges = LiveRangeSet::LiveRangeSet(block_order)
  for block in program.blocks {
    for inst_index, inst in block.instructions {
      let point = ProgramPoint::ProgramPoint(block.id, inst_index)
      for operand in inst.operands {
        let range = find_or_create_live_range(ranges, operand.vreg)
        range.touch_with_order(point, ranges.block_order)
        let use_pos = UsePosition::UsePosition(
          point,
          use_kind_of_role(operand.role),
          operand.constraint,
        ).with_tie(operand.tie_id)
        range.add_use(use_pos)
      }
    }
  }
  let (live_in, live_out) = compute_live_sets(program)
  extend_ranges_for_block_liveness(ranges, program, live_in, live_out)
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
