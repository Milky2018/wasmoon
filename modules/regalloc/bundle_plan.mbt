///|
priv struct BundlePlanSpan {
  start : ProgramPoint
  start_before : ProgramPoint
  end : ProgramPoint
}

///|
priv struct BundleRangeFact {
  class : RegClass
  spans : Array[BundlePlanSpan]
  fixed_reg : PhysicalReg?
  fixed_conflict : Bool
  has_fixed_def : Bool
}

///|
priv struct BundleSpanRuns {
  levels : Array[Array[BundlePlanSpan]?]
}

///|
priv struct ProductionBundlePlan {
  range_to_bundle : Array[Int]
  segment_to_bundle : Array[Int]
  bundle_ranges : Array[Array[Int]]
  bundle_segments : Array[Array[Int]]
}

///|
/// Check that the plan just built maps every range and segment exactly once.
///
/// A violation means this allocator is broken, not that the input was bad, so
/// it reports through `VerifyError::InvalidPlan` — the same channel
/// `verify_plan.mbt` uses for the same class of claim. Killing the process
/// instead would give whoever is bringing up a target a signal they cannot
/// catch and cannot see the shape of.
fn ProductionBundlePlan::validate(
  self : ProductionBundlePlan,
  range_count : Int,
  segment_count : Int,
) -> Unit raise VerifyError {
  if self.range_to_bundle.length() != range_count ||
    self.segment_to_bundle.length() != segment_count ||
    self.bundle_ranges.length() != self.bundle_segments.length() {
    raise InvalidPlan(message="invalid production bundle plan dimensions")
  }
  let seen_ranges = Array::make(range_count, false)
  for bundle, range_ids in self.bundle_ranges {
    for range_id in range_ids {
      if range_id < 0 ||
        range_id >= range_count ||
        seen_ranges[range_id] ||
        self.range_to_bundle[range_id] != bundle {
        raise InvalidPlan(
          message="invalid production bundle range mapping for range \{range_id} in bundle \{bundle}",
        )
      }
      seen_ranges[range_id] = true
    }
  }
  for range_id in 0..<range_count {
    if !seen_ranges[range_id] ||
      self.range_to_bundle[range_id] < 0 ||
      self.range_to_bundle[range_id] >= self.bundle_ranges.length() {
      raise InvalidPlan(
        message="incomplete production bundle range mapping for range \{range_id}",
      )
    }
  }
  let seen_segments = Array::make(segment_count, false)
  for bundle, segment_ids in self.bundle_segments {
    for segment_id in segment_ids {
      if segment_id < 0 ||
        segment_id >= segment_count ||
        seen_segments[segment_id] ||
        self.segment_to_bundle[segment_id] != bundle {
        raise InvalidPlan(
          message="invalid production bundle segment mapping for segment \{segment_id} in bundle \{bundle}",
        )
      }
      seen_segments[segment_id] = true
    }
  }
  for segment_id in 0..<segment_count {
    if !seen_segments[segment_id] ||
      self.segment_to_bundle[segment_id] < 0 ||
      self.segment_to_bundle[segment_id] >= self.bundle_segments.length() {
      raise InvalidPlan(
        message="incomplete production bundle segment mapping for segment \{segment_id}",
      )
    }
  }
}

///|
fn bundle_range_fixed_contract(range : LiveRange) -> (PhysicalReg?, Bool, Bool) {
  let mut fixed_reg : PhysicalReg? = None
  let mut fixed_conflict = false
  let mut has_fixed_def = false
  for use_position in range.uses {
    if use_position.constraint is FixedReg(reg) {
      match fixed_reg {
        None => fixed_reg = Some(reg)
        Some(existing) => if existing != reg { fixed_conflict = true }
      }
      if use_position.kind is LiveDef || use_position.kind is LiveUseDef {
        has_fixed_def = true
      }
    }
  }
  (fixed_reg, fixed_conflict, has_fixed_def)
}

///|
fn bundle_span(
  range : ProgramRange,
  block_order : Array[Int],
) -> BundlePlanSpan {
  let start_block = block_order
    .get(range.start.block)
    .unwrap_or(range.start.block)
  let end_block = block_order.get(range.end.block).unwrap_or(range.end.block)
  let start_before_inst = if range.start.inst >= 0 && range.start.inst % 2 == 1 {
    range.start.inst - 1
  } else {
    range.start.inst
  }
  {
    start: ProgramPoint(start_block, range.start.inst),
    start_before: ProgramPoint(start_block, start_before_inst),
    end: ProgramPoint(end_block, range.end.inst),
  }
}

///|
fn compare_bundle_span_point(lhs : ProgramPoint, rhs : ProgramPoint) -> Int {
  if lhs.block != rhs.block {
    lhs.block - rhs.block
  } else {
    lhs.inst - rhs.inst
  }
}

///|
fn build_bundle_range_facts(ranges : LiveRangeSet) -> Array[BundleRangeFact] {
  let facts : Array[BundleRangeFact?] = Array::make(ranges.length(), None)
  for range in ranges.ranges {
    let spans : Array[BundlePlanSpan] = []
    for span in range.ranges {
      spans.push(bundle_span(span, ranges.block_order))
    }
    let (fixed_reg, fixed_conflict, has_fixed_def) = bundle_range_fixed_contract(
      range,
    )
    facts[range.id] = Some({
      class: range.vreg.class,
      spans,
      fixed_reg,
      fixed_conflict,
      has_fixed_def,
    })
  }
  facts.map(fact => fact.unwrap())
}

///|
fn bundle_span_runs_for_root(
  facts : Array[BundleRangeFact],
  span_cache : Array[BundleSpanRuns?],
  root : Int,
) -> BundleSpanRuns {
  match span_cache[root] {
    Some(runs) => runs
    None => {
      let runs : BundleSpanRuns = { levels: [Some(facts[root].spans)], }
      span_cache[root] = Some(runs)
      runs
    }
  }
}

///|
fn bundle_spans_conflict(
  lhs : Array[BundlePlanSpan],
  lhs_has_fixed_def : Bool,
  rhs : Array[BundlePlanSpan],
  rhs_has_fixed_def : Bool,
) -> Bool {
  let mut lhs_index = 0
  let mut rhs_index = 0
  while lhs_index < lhs.length() && rhs_index < rhs.length() {
    let left = lhs[lhs_index]
    let right = rhs[rhs_index]
    let left_start = if lhs_has_fixed_def {
      left.start_before
    } else {
      left.start
    }
    let right_start = if rhs_has_fixed_def {
      right.start_before
    } else {
      right.start
    }
    if compare_bundle_span_point(left_start, right.end) >= 0 {
      rhs_index += 1
    } else if compare_bundle_span_point(right_start, left.end) >= 0 {
      lhs_index += 1
    } else {
      return true
    }
  }
  false
}

///|
fn BundleSpanRuns::conflicts(
  self : BundleSpanRuns,
  self_has_fixed_def : Bool,
  other : BundleSpanRuns,
  other_has_fixed_def : Bool,
) -> Bool {
  for left in self.levels {
    if left is Some(left) {
      for right in other.levels {
        if right is Some(right) &&
          bundle_spans_conflict(
            left, self_has_fixed_def, right, other_has_fixed_def,
          ) {
          return true
        }
      }
    }
  }
  false
}

///|
fn merge_bundle_spans(
  lhs : Array[BundlePlanSpan],
  rhs : Array[BundlePlanSpan],
) -> Array[BundlePlanSpan] {
  let merged : Array[BundlePlanSpan] = []
  let mut lhs_index = 0
  let mut rhs_index = 0
  while lhs_index < lhs.length() && rhs_index < rhs.length() {
    if compare_bundle_span_point(lhs[lhs_index].start, rhs[rhs_index].start) <=
      0 {
      merged.push(lhs[lhs_index])
      lhs_index += 1
    } else {
      merged.push(rhs[rhs_index])
      rhs_index += 1
    }
  }
  while lhs_index < lhs.length() {
    merged.push(lhs[lhs_index])
    lhs_index += 1
  }
  while rhs_index < rhs.length() {
    merged.push(rhs[rhs_index])
    rhs_index += 1
  }
  merged
}

///|
fn BundleSpanRuns::merge_run(
  self : BundleSpanRuns,
  start_level : Int,
  run : Array[BundlePlanSpan],
) -> Unit {
  let mut level = start_level
  let mut carry = run
  while true {
    while self.levels.length() <= level {
      self.levels.push(None)
    }
    match self.levels[level] {
      None => {
        self.levels[level] = Some(carry)
        return
      }
      Some(existing) => {
        self.levels[level] = None
        carry = merge_bundle_spans(existing, carry)
        level = level + 1
      }
    }
  }
}

///|
fn BundleSpanRuns::merge_from(
  self : BundleSpanRuns,
  other : BundleSpanRuns,
) -> Unit {
  for level, run in other.levels {
    if run is Some(run) {
      self.merge_run(level, run)
    }
  }
}

///|
fn try_merge_bundle_edge(
  union_find : @unionfind.UnionFind,
  facts : Array[BundleRangeFact],
  edge : (Int, Int),
  fixed_reg_cache : Array[PhysicalReg?],
  fixed_conflict_cache : Array[Bool],
  fixed_def_cache : Array[Bool],
  span_cache : Array[BundleSpanRuns?],
) -> Unit {
  let (target, source) = edge
  if target < 0 ||
    source < 0 ||
    target >= facts.length() ||
    source >= facts.length() {
    return
  }
  let target_root = union_find.find(target)
  let source_root = union_find.find(source)
  if target_root == source_root ||
    facts[target_root].class != facts[source_root].class ||
    fixed_conflict_cache[target_root] ||
    fixed_conflict_cache[source_root] {
    return
  }
  match (fixed_reg_cache[target_root], fixed_reg_cache[source_root]) {
    (Some(lhs), Some(rhs)) => if lhs != rhs { return }
    _ => ()
  }
  let target_spans = bundle_span_runs_for_root(facts, span_cache, target_root)
  let source_spans = bundle_span_runs_for_root(facts, span_cache, source_root)
  if target_spans.conflicts(
      fixed_def_cache[target_root],
      source_spans,
      fixed_def_cache[source_root],
    ) {
    return
  }
  if !union_find.union_into(source_root, target_root) {
    return
  }
  fixed_def_cache[target_root] = fixed_def_cache[target_root] ||
    fixed_def_cache[source_root]
  fixed_reg_cache[target_root] = match
    (fixed_reg_cache[target_root], fixed_reg_cache[source_root]) {
    (Some(reg), _) => Some(reg)
    (_, Some(reg)) => Some(reg)
    _ => None
  }
  fixed_conflict_cache[target_root] = false
  target_spans.merge_from(source_spans)
  span_cache[source_root] = None
}

///|
fn build_production_bundle_plan_from_range_edges(
  ranges : LiveRangeSet,
  segments : Array[AllocationSegment],
  edges : Array[(Int, Int)],
  verify? : Bool = true,
) -> ProductionBundlePlan raise VerifyError {
  let facts = build_bundle_range_facts(ranges)
  let union_find = @unionfind.UnionFind::UnionFind(facts.length())
  let fixed_reg_cache : Array[PhysicalReg?] = []
  let fixed_conflict_cache : Array[Bool] = []
  let fixed_def_cache : Array[Bool] = []
  let span_cache : Array[BundleSpanRuns?] = Array::make(facts.length(), None)
  for fact in facts {
    fixed_reg_cache.push(fact.fixed_reg)
    fixed_conflict_cache.push(fact.fixed_conflict)
    fixed_def_cache.push(fact.has_fixed_def)
  }
  for edge in edges {
    try_merge_bundle_edge(
      union_find, facts, edge, fixed_reg_cache, fixed_conflict_cache, fixed_def_cache,
      span_cache,
    )
  }
  let range_to_bundle = Array::make(facts.length(), -1)
  let root_to_bundle = Array::make(facts.length(), -1)
  let bundle_ranges : Array[Array[Int]] = []
  for range_id in 0..<facts.length() {
    let root = union_find.find(range_id)
    let bundle = if root_to_bundle[root] >= 0 {
      root_to_bundle[root]
    } else {
      let bundle = bundle_ranges.length()
      root_to_bundle[root] = bundle
      bundle_ranges.push([])
      bundle
    }
    range_to_bundle[range_id] = bundle
    bundle_ranges[bundle].push(range_id)
  }
  let segment_to_bundle = Array::make(segments.length(), -1)
  let bundle_segments : Array[Array[Int]] = Array::makei(
    bundle_ranges.length(),
    _ => [],
  )
  for segment in segments {
    let range = ranges.get_by_vreg(segment.value).unwrap()
    let bundle = range_to_bundle[range.id]
    segment_to_bundle[segment.id] = bundle
    bundle_segments[bundle].push(segment.id)
  }
  for segment_ids in bundle_segments {
    segment_ids.sort_by((left, right) => {
      let by_end = segments[left].range.end.compare_with_order(
        segments[right].range.end,
        ranges.block_order,
      )
      if by_end != 0 {
        by_end
      } else {
        left - right
      }
    })
  }
  let plan : ProductionBundlePlan = {
    range_to_bundle,
    segment_to_bundle,
    bundle_ranges,
    bundle_segments,
  }
  if verify {
    plan.validate(facts.length(), segments.length())
  }
  plan
}

///|
fn[F : FunctionView] collect_production_bundle_edges(
  function : F,
  ranges : LiveRangeSet,
) -> Array[(Int, Int)] {
  let edges : Array[(Int, Int)] = []
  for block in 0..<function.block_count() {
    for successor_index, target in function.block_successors(block) {
      let arguments = function.edge_arguments(block, successor_index)
      let parameters = function.block_parameters(target)
      for index in 0..<arguments.length().min(parameters.length()) {
        match
          (
            ranges.get_by_vreg(parameters[index]),
            ranges.get_by_vreg(arguments[index]),
          ) {
          (Some(target_range), Some(source_range)) => {
            let edge = (target_range.id, source_range.id)
            if target_range.id != source_range.id {
              edges.push(edge)
            }
          }
          _ => ()
        }
      }
    }
  }
  edges
}

///|
fn[F : FunctionView] build_production_bundle_plan(
  function : F,
  ranges : LiveRangeSet,
  segments : Array[AllocationSegment],
  verify? : Bool = true,
) -> ProductionBundlePlan raise VerifyError {
  build_production_bundle_plan_from_range_edges(
    ranges,
    segments,
    collect_production_bundle_edges(function, ranges),
    verify~,
  )
}
