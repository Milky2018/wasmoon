///|
priv enum AllocationBundleState {
  BundlePending
  BundleReg(PhysicalReg)
  BundleDeferredSpill
  BundleSpill
  BundleSplit
}

///|
priv struct SpillSet {
  mut hint : Int
  mut spill_bundle : Int?
  mut splits : Int
}

///|
const MAX_NORMAL_SPLITS_PER_SPILL_SET : Int = 2

///|
priv struct AllocationContext {
  segments : Array[Array[Int]]
  priorities : Array[Int]
  weights : Array[Int]
  fixed_constraints : Array[Bool]
  boundary_costs : Array[Int]
  minimals : Array[Bool]
  spill_sets : Array[Int]
  states : Array[AllocationBundleState]
}

///|
priv struct BundleQueue {
  items : Array[Int]
  priorities : Array[Int]
  weights : Array[Int]
  in_queue : Array[Bool]
  hints : Array[Int]
  mut prioritize_weight : Bool
}

///|
pub fn AllocationSession::new() -> AllocationSession {
  {
    context_priorities: [],
    context_weights: [],
    context_fixed_constraints: [],
    context_boundary_costs: [],
    context_minimals: [],
    context_spill_sets: [],
    segment_owner: [],
    segment_spill_set: [],
    owner_run_count: [],
    occupied_block_order: [],
    occupied_roots: [],
    occupied_left: [],
    occupied_right: [],
    occupied_parent: [],
    occupied_previous: [],
    occupied_next: [],
    occupied_starts: [],
    occupied_ends: [],
    occupied_stack: [],
    preferred_by_value: [],
    conflict_marks: [],
    probe_conflicts: [],
    eviction_conflicts: [],
    register_order: [],
    register_order_marks: [],
    physical_register_indexes: [],
    queue_items: [],
    queue_priorities: [],
    queue_weights: [],
    queue_in_queue: [],
    queue_hints: [],
  }
}

///|
fn BundleQueue::for_session(
  session : AllocationSession,
  bundle_count : Int,
) -> BundleQueue {
  reset_dense_array(session.queue_in_queue, bundle_count, false)
  session.queue_items.clear()
  session.queue_priorities.clear()
  session.queue_weights.clear()
  session.queue_hints.clear()
  {
    items: session.queue_items,
    priorities: session.queue_priorities,
    weights: session.queue_weights,
    in_queue: session.queue_in_queue,
    hints: session.queue_hints,
    prioritize_weight: false,
  }
}

///|
fn BundleQueue::ensure_slot(self : BundleQueue, bundle : Int) -> Unit {
  while bundle >= self.in_queue.length() {
    self.in_queue.push(false)
  }
}

///|
fn BundleQueue::reset(
  self : BundleQueue,
  bundle_count : Int,
  prioritize_weight : Bool,
) -> Unit {
  self.items.clear()
  self.priorities.clear()
  self.weights.clear()
  self.in_queue.clear()
  self.hints.clear()
  for _ in 0..<bundle_count {
    self.in_queue.push(false)
  }
  self.prioritize_weight = prioritize_weight
}

///|
fn BundleQueue::higher(self : BundleQueue, lhs : Int, rhs : Int) -> Bool {
  if self.prioritize_weight && self.weights[lhs] != self.weights[rhs] {
    self.weights[lhs] > self.weights[rhs]
  } else if self.priorities[lhs] != self.priorities[rhs] {
    self.priorities[lhs] > self.priorities[rhs]
  } else {
    self.items[lhs] < self.items[rhs]
  }
}

///|
fn BundleQueue::push(
  self : BundleQueue,
  bundle : Int,
  context : AllocationContext,
  hint : Int,
) -> Unit {
  self.ensure_slot(bundle)
  if self.in_queue[bundle] {
    return
  }
  self.in_queue[bundle] = true
  self.items.push(bundle)
  self.priorities.push(context.priorities[bundle])
  self.weights.push(context.weights[bundle])
  self.hints.push(hint)
  let mut index = self.items.length() - 1
  while index > 0 {
    let parent = (index - 1) / 2
    if !self.higher(index, parent) {
      break
    }
    let temporary = self.items[index]
    self.items[index] = self.items[parent]
    self.items[parent] = temporary
    let priority = self.priorities[index]
    self.priorities[index] = self.priorities[parent]
    self.priorities[parent] = priority
    let weight = self.weights[index]
    self.weights[index] = self.weights[parent]
    self.weights[parent] = weight
    let hint = self.hints[index]
    self.hints[index] = self.hints[parent]
    self.hints[parent] = hint
    index = parent
  }
}

///|
fn BundleQueue::pop(self : BundleQueue) -> (Int, Int)? {
  if self.items.is_empty() {
    return None
  }
  let first = self.items[0]
  self.in_queue[first] = false
  let hint = self.hints[0]
  let last = self.items.pop().unwrap()
  let last_priority = self.priorities.pop().unwrap()
  let last_weight = self.weights.pop().unwrap()
  let last_hint = self.hints.pop().unwrap()
  if !self.items.is_empty() {
    self.items[0] = last
    self.priorities[0] = last_priority
    self.weights[0] = last_weight
    self.hints[0] = last_hint
    let mut index = 0
    while true {
      let left = index * 2 + 1
      if left >= self.items.length() {
        break
      }
      let right = left + 1
      let mut higher = left
      if right < self.items.length() && self.higher(right, left) {
        higher = right
      }
      if !self.higher(higher, index) {
        break
      }
      let temporary = self.items[index]
      self.items[index] = self.items[higher]
      self.items[higher] = temporary
      let priority = self.priorities[index]
      self.priorities[index] = self.priorities[higher]
      self.priorities[higher] = priority
      let weight = self.weights[index]
      self.weights[index] = self.weights[higher]
      self.weights[higher] = weight
      let hint = self.hints[index]
      self.hints[index] = self.hints[higher]
      self.hints[higher] = hint
      index = higher
    }
  }
  Some((first, hint))
}

///|
priv struct BundleRegisterProbe {
  conflicts : Array[Int]
  mut conflict_cost : Int
  mut has_first_conflict : Bool
  mut first_conflict : ProgramPoint
  mut clobbered : Bool
  mut cutoff_exceeded : Bool
}

///|
fn BundleRegisterProbe::new(conflicts : Array[Int]) -> BundleRegisterProbe {
  {
    conflicts,
    conflict_cost: 0,
    has_first_conflict: false,
    first_conflict: ProgramPoint(-1, -1),
    clobbered: false,
    cutoff_exceeded: false,
  }
}

///|
/// Probe conflict policy is numeric control state carried through the hottest
/// allocation loop. Keep it inline instead of allocating the payload-bearing
/// cost-limit case for every register probe.
#valtype
priv struct BundleProbeConflictPolicy {
  kind : Int
  limit : Int
}

///|
fn unlimited_conflicts() -> BundleProbeConflictPolicy {
  { kind: 0, limit: 0, }
}

///|
fn limited_conflicts(limit : Int) -> BundleProbeConflictPolicy {
  { kind: 1, limit, }
}

///|
fn reject_conflicts() -> BundleProbeConflictPolicy {
  { kind: 2, limit: 0, }
}

///|
fn allocation_bundle_metrics(
  segment_ids : Array[Int],
  segments : Array[AllocationSegment],
  boundary_cost? : Int = 0,
  ranges? : LiveRangeSet = LiveRangeSet([]),
) -> (Int, Int, Bool) {
  let mut priority = 0
  let mut weighted_cost = 0L
  let mut has_fixed_constraint = false
  for segment_id in segment_ids {
    let segment_priority = ranges.program_range_length(
      segments[segment_id].range,
    )
    priority = priority + segment_priority
    weighted_cost = weighted_cost +
      segments[segment_id].weight.to_int64() * segment_priority.to_int64()
    has_fixed_constraint = has_fixed_constraint ||
      segments[segment_id].has_fixed_constraint
  }
  let normalized_priority = priority.max(1)
  let net_cost = (weighted_cost - boundary_cost.to_int64()).max(1L)
  let weight = ((net_cost + normalized_priority.to_int64() - 1L) /
    normalized_priority.to_int64())
    .min(2_147_483_647L)
    .to_int()
  (normalized_priority, weight.max(1), has_fixed_constraint)
}

///|
fn AllocationContext::for_session(
  initial_segments : Array[Array[Int]],
  session : AllocationSession,
) -> AllocationContext {
  session.context_priorities.clear()
  session.context_weights.clear()
  session.context_fixed_constraints.clear()
  session.context_boundary_costs.clear()
  session.context_minimals.clear()
  session.context_spill_sets.clear()
  {
    segments: initial_segments,
    priorities: session.context_priorities,
    weights: session.context_weights,
    fixed_constraints: session.context_fixed_constraints,
    boundary_costs: session.context_boundary_costs,
    minimals: session.context_minimals,
    spill_sets: session.context_spill_sets,
    states: [],
  }
}

///|
fn AllocationContext::add_bundle(
  self : AllocationContext,
  segment_ids : Array[Int],
  segments : Array[AllocationSegment],
  spill_set : Int,
  minimal? : Bool = false,
  boundary_cost? : Int = 0,
  ranges? : LiveRangeSet = LiveRangeSet([]),
) -> Int {
  let id = self.states.length()
  if id == self.segments.length() {
    self.segments.push(segment_ids)
  }
  let (priority, weight, has_fixed_constraint) = allocation_bundle_metrics(
    segment_ids,
    segments,
    boundary_cost~,
    ranges~,
  )
  self.priorities.push(priority)
  self.weights.push(weight)
  self.fixed_constraints.push(has_fixed_constraint)
  self.boundary_costs.push(boundary_cost)
  self.minimals.push(minimal)
  self.spill_sets.push(spill_set)
  self.states.push(BundlePending)
  id
}

///|
fn build_allocation_context(
  plan : ProductionBundlePlan,
  segments : Array[AllocationSegment],
  session : AllocationSession,
  ranges? : LiveRangeSet = LiveRangeSet([]),
) -> (AllocationContext, Array[Int], Array[SpillSet], Array[Int]) {
  let context = AllocationContext::for_session(plan.bundle_segments, session)
  let segment_owner = session.segment_owner
  reset_dense_array(segment_owner, segments.length(), -1)
  let spill_sets : Array[SpillSet] = []
  let segment_spill_set = session.segment_spill_set
  reset_dense_array(segment_spill_set, segments.length(), -1)
  for bundle, segment_ids in context.segments {
    let spill_set = spill_sets.length()
    context.add_bundle(segment_ids, segments, spill_set, ranges~) |> ignore
    spill_sets.push({ hint: -1, spill_bundle: None, splits: 0, })
    for segment_id in segment_ids {
      segment_owner[segment_id] = bundle
      segment_spill_set[segment_id] = spill_set
    }
  }
  (context, segment_owner, spill_sets, segment_spill_set)
}

///|
fn bundle_class(
  bundle : Int,
  context : AllocationContext,
  segments : Array[AllocationSegment],
) -> RegClass {
  segments[context.segments[bundle][0]].value.class
}

///|
fn earlier_conflict_point(
  has_current : Bool,
  current : ProgramPoint,
  candidate : ProgramPoint,
  block_order : Array[Int],
) -> ProgramPoint {
  if has_current && candidate.compare_with_order(current, block_order) >= 0 {
    current
  } else {
    candidate
  }
}

///|
fn probe_bundle_register(
  bundle : Int,
  register : Int,
  context : AllocationContext,
  segments : Array[AllocationSegment],
  segment_owner : Array[Int],
  occupied : RegisterAllocationIndex,
  clobbers : RegisterClobberIndex,
  block_order : Array[Int],
  conflict_marks : Array[Int],
  probe_id : Int,
  occupied_stack : Array[Int],
  conflicts : Array[Int],
  result : BundleRegisterProbe,
  statistics : BundleAllocationStatistics,
  conflict_policy~ : BundleProbeConflictPolicy,
) -> Unit {
  statistics.register_probes = statistics.register_probes + 1
  conflicts.clear()
  result.conflict_cost = 0
  result.has_first_conflict = false
  result.clobbered = false
  result.cutoff_exceeded = false
  let bundle_segments = context.segments[bundle]
  let clobber = clobbers.first_intersection(register, bundle_segments, occupied)
  if clobber.present {
    result.clobbered = true
    result.has_first_conflict = true
    result.first_conflict = clobber.point
  }
  if result.clobbered && conflict_policy.kind == 2 {
    result.cutoff_exceeded = true
    return
  }
  guard !bundle_segments.is_empty() else { return }
  occupied.seek(
    register,
    segments[bundle_segments[0]].range.start,
    occupied_stack,
  )
  let mut assigned = occupied.next(occupied_stack)
  let mut bundle_index = 0
  let mut skipped_occupied = 0
  let mut skipped_bundle = 0
  while bundle_index < bundle_segments.length() && assigned is Some(_) {
    statistics.occupied_segments_scanned = statistics.occupied_segments_scanned +
      1
    let conflict_segment = assigned.unwrap()
    // Keep reference-counted segment records out of the scan-only path. Most
    // visits only compare cached coordinates; ranges are needed only when a
    // previously unseen conflict contributes its first overlap point.
    let current_segment = bundle_segments[bundle_index]
    if occupied.segment_end_before_start(conflict_segment, current_segment) {
      skipped_bundle = 0
      assigned = occupied.next(occupied_stack)
      skipped_occupied = skipped_occupied + 1
      if skipped_occupied >= 16 {
        occupied.seek(
          register,
          segments[current_segment].range.start,
          occupied_stack,
        )
        assigned = occupied.next(occupied_stack)
        skipped_occupied = 0
      }
      continue
    }
    skipped_occupied = 0
    if occupied.segment_end_before_start(current_segment, conflict_segment) {
      bundle_index = bundle_index + 1
      skipped_bundle = skipped_bundle + 1
      if skipped_bundle >= 4 {
        bundle_index = occupied.first_not_ending_before(
          bundle_segments, bundle_index, conflict_segment,
        )
        skipped_bundle = 0
      }
      continue
    }
    skipped_bundle = 0
    let owner = segment_owner[conflict_segment]
    if owner != bundle && conflict_marks[owner] != probe_id {
      conflict_marks[owner] = probe_id
      conflicts.push(owner)
      statistics.conflicts = statistics.conflicts + 1
      result.conflict_cost = result.conflict_cost.max(context.weights[owner])
      let current = segments[current_segment]
      let conflict = segments[conflict_segment]
      result.first_conflict = earlier_conflict_point(
        result.has_first_conflict,
        result.first_conflict,
        later_point(current.range.start, conflict.range.start, block_order),
        block_order,
      )
      result.has_first_conflict = true
      let cutoff_exceeded = conflict_policy.kind == 2 ||
        (
          conflict_policy.kind == 1 &&
          result.conflict_cost > conflict_policy.limit
        )
      if cutoff_exceeded {
        result.cutoff_exceeded = true
        return
      }
    }
    if owner != bundle && occupied.owner_is_contiguous(owner) {
      let owner_segments = context.segments[owner]
      occupied.skip_after(
        owner_segments[owner_segments.length() - 1],
        occupied_stack,
      )
      assigned = occupied.next(occupied_stack)
      continue
    }
    if occupied.segment_end_before_or_equal(conflict_segment, current_segment) {
      assigned = occupied.next(occupied_stack)
    } else {
      bundle_index = bundle_index + 1
    }
  }
}

///|
fn push_bundle_register_candidates(
  order : Array[Int],
  order_marks : Array[Bool],
  register_indexes : PhysicalRegisterIndex,
  registers : Array[PhysicalReg],
  candidate : PhysicalReg?,
) -> Unit {
  if candidate is Some(reg) &&
    register_indexes.find(registers, reg) is Some(index) &&
    !order_marks[index] {
    order_marks[index] = true
    order.push(index)
  }
}

///|
fn push_bundle_register_index(
  order : Array[Int],
  order_marks : Array[Bool],
  candidate : Int,
) -> Unit {
  if candidate >= 0 && !order_marks[candidate] {
    order_marks[candidate] = true
    order.push(candidate)
  }
}

///|
fn bundle_register_order(
  bundle : Int,
  context : AllocationContext,
  hint : Int,
  segments : Array[AllocationSegment],
  environment : MachineEnv,
  preferred_by_value : Array[Int],
  register_indexes : PhysicalRegisterIndex,
  order : Array[Int],
  order_marks : Array[Bool],
) -> Unit {
  for register in order {
    order_marks[register] = false
  }
  order.clear()
  push_bundle_register_index(order, order_marks, hint)
  for segment_id in context.segments[bundle] {
    let segment = segments[segment_id]
    push_bundle_register_candidates(
      order,
      order_marks,
      register_indexes,
      environment.allocatable_regs,
      segment.fixed_hint,
    )
    push_bundle_register_candidates(
      order,
      order_marks,
      register_indexes,
      environment.allocatable_regs,
      segment.preference_hint,
    )
    push_bundle_register_index(
      order,
      order_marks,
      preferred_by_value[segment.value.id],
    )
  }
  let class = bundle_class(bundle, context, segments)
  for register, reg in environment.allocatable_regs {
    if reg.class == class && !order_marks[register] {
      order_marks[register] = true
      order.push(register)
    }
  }
}

///|
fn remove_bundle_allocation(
  bundle : Int,
  context : AllocationContext,
  environment : MachineEnv,
  segments : Array[AllocationSegment],
  occupied : RegisterAllocationIndex,
) -> Unit {
  guard context.states[bundle] is BundleReg(reg) else { return }
  let register = register_index(environment.allocatable_regs, reg).unwrap()
  for segment_id in context.segments[bundle] {
    occupied.remove(register, segment_id)
    segments[segment_id].location = None
  }
  context.states[bundle] = BundlePending
}

///|
fn evict_bundle_conflicts(
  conflicts : Array[Int],
  context : AllocationContext,
  environment : MachineEnv,
  segments : Array[AllocationSegment],
  occupied : RegisterAllocationIndex,
  queue : BundleQueue,
  statistics : BundleAllocationStatistics,
) -> Unit {
  for conflict in conflicts {
    let hint = match context.states[conflict] {
      BundleReg(reg) =>
        register_index(environment.allocatable_regs, reg).unwrap()
      _ => -1
    }
    remove_bundle_allocation(conflict, context, environment, segments, occupied)
    queue.push(conflict, context, hint)
    statistics.evictions = statistics.evictions + 1
  }
}

///|
fn record_bundle_allocation(
  bundle : Int,
  context : AllocationContext,
  register : Int,
  environment : MachineEnv,
  segments : Array[AllocationSegment],
  occupied : RegisterAllocationIndex,
  preferred_by_value : Array[Int],
  spill_sets : Array[SpillSet],
) -> Unit {
  let reg = environment.allocatable_regs[register]
  for segment_id in context.segments[bundle] {
    let segment = segments[segment_id]
    segment.location = Some(SegmentReg(reg))
    preferred_by_value[segment.value.id] = register
    occupied.insert(register, segment_id)
  }
  spill_sets[context.spill_sets[bundle]].hint = register
  context.states[bundle] = BundleReg(reg)
}

///|
fn force_spill_bundle(
  bundle : Int,
  context : AllocationContext,
  segments : Array[AllocationSegment],
) -> Unit {
  for segment_id in context.segments[bundle] {
    segments[segment_id].location = Some(SegmentSpill)
  }
  context.states[bundle] = BundleSpill
}

///|
fn refresh_bundle_metrics(
  bundle : Int,
  context : AllocationContext,
  segments : Array[AllocationSegment],
  ranges : LiveRangeSet,
) -> Unit {
  let (priority, weight, fixed) = allocation_bundle_metrics(
    context.segments[bundle],
    segments,
    ranges~,
  )
  context.priorities[bundle] = priority
  context.weights[bundle] = weight
  context.fixed_constraints[bundle] = fixed
}

///|
fn add_to_spill_bundle(
  spill_set : Int,
  segment : Int,
  context : AllocationContext,
  segment_owner : Array[Int],
  spill_sets : Array[SpillSet],
  segments : Array[AllocationSegment],
  ranges? : LiveRangeSet = LiveRangeSet([]),
) -> Unit {
  match spill_sets[spill_set].spill_bundle {
    Some(bundle_id) => {
      context.segments[bundle_id].push(segment)
      segment_owner[segment] = bundle_id
    }
    None => {
      let spill_bundle = context.add_bundle(
        [segment],
        segments,
        spill_set,
        ranges~,
      )
      context.states[spill_bundle] = BundleDeferredSpill
      segment_owner[segment] = spill_bundle
      spill_sets[spill_set].spill_bundle = Some(spill_bundle)
    }
  }
}

///|
fn prepare_spill_bundle(
  bundle : Int,
  context : AllocationContext,
  segments : Array[AllocationSegment],
  block_order : Array[Int],
  ranges? : LiveRangeSet = LiveRangeSet(block_order),
) -> Unit {
  context.segments[bundle].sort_by(fn(left, right) {
    let by_end = segments[left].range.end.compare_with_order(
      segments[right].range.end,
      block_order,
    )
    if by_end != 0 {
      by_end
    } else {
      left.compare(right)
    }
  })
  refresh_bundle_metrics(bundle, context, segments, ranges)
}

///|
fn enqueue_child_bundle(
  context : AllocationContext,
  segment_owner : Array[Int],
  queue : BundleQueue,
  segments : Array[AllocationSegment],
  segment_ids : Array[Int],
  ranges : LiveRangeSet,
  hint : Int,
  spill_set : Int,
  boundary_cost? : Int = 0,
) -> Unit {
  let point_bundle = segment_ids.length() == 1 &&
    segments[segment_ids[0]].range.start == segments[segment_ids[0]].range.end
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
  let child = context.add_bundle(
    segment_ids,
    segments,
    spill_set,
    minimal=point_bundle,
    boundary_cost~,
    ranges~,
  )
  for segment_id in segment_ids {
    segment_owner[segment_id] = child
  }
  queue.push(child, context, hint)
}

///|
priv struct SegmentGapSplit {
  before : Int?
  spill : Int
  after : Int?
}

///|
fn append_split_segment(
  source : Int,
  range : ProgramRange,
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  segment_owner : Array[Int],
  segment_spill_set : Array[Int],
  occupied : RegisterAllocationIndex,
  live_range : LiveRange,
  loop_depths : Array[Int],
  ranges : LiveRangeSet,
  allocatable : Array[PhysicalReg],
) -> Int {
  let segment = segments[source]
  let id = segments.length()
  let metadata = segment_metadata(
    live_range, range, loop_depths, ranges, allocatable,
  )
  segments.push({
    id,
    value: segment.value,
    range,
    weight: metadata.weight,
    has_fixed_constraint: metadata.has_fixed_constraint,
    fixed_hint: metadata.fixed_hint,
    preference_hint: metadata.preference_hint,
    location: None,
  })
  segments_by_value[segment.value.id].push(id)
  segment_owner.push(segment_owner[source])
  segment_spill_set.push(segment_spill_set[source])
  occupied.add_segment(id)
  id
}

///|
fn split_segment_around_gap(
  segment_id : Int,
  point : ProgramPoint,
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  segment_owner : Array[Int],
  segment_spill_set : Array[Int],
  occupied : RegisterAllocationIndex,
  ranges : LiveRangeSet,
  loop_depths : Array[Int],
  allocatable : Array[PhysicalReg],
) -> SegmentGapSplit? {
  let segment = segments[segment_id]
  if !segment.range.contains(point, ranges.block_order) ||
    point.block < 0 ||
    point.block >= ranges.block_ends.length() {
    return None
  }
  guard ranges.get_by_vreg(segment.value) is Some(live_range) else {
    return None
  }
  let mut previous_use : Int? = None
  let mut next_use : Int? = None
  for use_position in live_range.uses {
    if use_position.point.block != point.block ||
      !segment.range.contains(use_position.point, ranges.block_order) {
      continue
    }
    if use_position.point.inst == point.inst {
      return None
    }
    if use_position.point.inst < point.inst &&
      (previous_use is None || use_position.point.inst > previous_use.unwrap()) {
      previous_use = Some(use_position.point.inst)
    }
    if use_position.point.inst > point.inst &&
      (next_use is None || use_position.point.inst < next_use.unwrap()) {
      next_use = Some(use_position.point.inst)
    }
  }
  let block_start = if segment.range.start.block == point.block {
    segment.range.start.inst
  } else {
    -1
  }
  let block_end = if segment.range.end.block == point.block {
    segment.range.end.inst
  } else {
    ranges.block_ends[point.block]
  }
  let gap_start = previous_use.map_or(block_start, previous => previous + 1)
  let gap_end = next_use.map_or(block_end, next => next - 1)
  if gap_start > point.inst || gap_end < point.inst || gap_start > gap_end {
    return None
  }
  let original_range = segment.range
  let spill_range = ProgramRange(
    ProgramPoint(point.block, gap_start),
    ProgramPoint(point.block, gap_end),
  )
  let mut before : Int? = None
  if original_range.start.compare_with_order(
      spill_range.start,
      ranges.block_order,
    ) <
    0 {
    segments[segment_id] = segment.with_range(
      ProgramRange(
        original_range.start,
        ProgramPoint(point.block, gap_start - 1),
      ),
      live_range,
      loop_depths,
      ranges,
      allocatable,
    )
    before = Some(segment_id)
  } else {
    segments[segment_id] = segment.with_range(
      spill_range, live_range, loop_depths, ranges, allocatable,
    )
  }
  occupied.refresh_segment(segment_id)
  let spill = if before is Some(_) {
    append_split_segment(
      segment_id,
      ProgramRange(
        ProgramPoint(point.block, gap_start),
        ProgramPoint(point.block, gap_end),
      ),
      segments,
      segments_by_value,
      segment_owner,
      segment_spill_set,
      occupied,
      live_range,
      loop_depths,
      ranges,
      allocatable,
    )
  } else {
    segment_id
  }
  let after = if spill_range.end.compare_with_order(
      original_range.end,
      ranges.block_order,
    ) <
    0 {
    Some(
      append_split_segment(
        segment_id,
        ProgramRange(ProgramPoint(point.block, gap_end + 1), original_range.end),
        segments,
        segments_by_value,
        segment_owner,
        segment_spill_set,
        occupied,
        live_range,
        loop_depths,
        ranges,
        allocatable,
      ),
    )
  } else {
    None
  }
  Some({ before, spill, after, })
}

///|
fn segment_carries_no_use(
  segment : AllocationSegment,
  ranges : LiveRangeSet,
) -> Bool {
  match ranges.get_by_vreg(segment.value) {
    Some(live_range) => !segment_has_use(live_range, segment.range)
    None => false
  }
}

///|
/// A successful split moves a segment to spill, partitions a multi-segment
/// bundle, or removes a non-empty gap from a singleton range.
fn split_bundle_at_conflict(
  bundle : Int,
  split_point : ProgramPoint,
  hint : Int,
  context : AllocationContext,
  segment_owner : Array[Int],
  queue : BundleQueue,
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  segment_spill_set : Array[Int],
  spill_sets : Array[SpillSet],
  occupied : RegisterAllocationIndex,
  ranges : LiveRangeSet,
  loop_depths : Array[Int],
  allocatable : Array[PhysicalReg],
  statistics : BundleAllocationStatistics,
) -> Bool {
  if context.minimals[bundle] {
    return false
  }
  let spill_set = context.spill_sets[bundle]
  if spill_sets[spill_set].splits >= MAX_NORMAL_SPLITS_PER_SPILL_SET {
    context.states[bundle] = BundleDeferredSpill
    return true
  }
  let bundle_segments = context.segments[bundle]
  let bundle_start = segments[bundle_segments[0]].range.start
  let mut point = split_point
  if point.compare_with_order(bundle_start, ranges.block_order) <= 0 {
    point = ProgramPoint(bundle_start.block, bundle_start.inst + 1)
  }
  let boundary_cost = use_weight(
    UsePosition(point, LiveDef, AnyReg),
    loop_depths,
  )
  let before : Array[Int] = []
  let after : Array[Int] = []
  let spill : Array[Int] = []
  for segment_id in bundle_segments {
    let segment = segments[segment_id]
    if segment.range.end.compare_with_order(point, ranges.block_order) < 0 {
      before.push(segment_id)
    } else if segment.range.start.compare_with_order(point, ranges.block_order) >=
      0 {
      after.push(segment_id)
    } else if split_segment_around_gap(
        segment_id, point, segments, segments_by_value, segment_owner, segment_spill_set,
        occupied, ranges, loop_depths, allocatable,
      )
      is Some(parts) {
      if parts.before is Some(left) {
        before.push(left)
      }
      spill.push(parts.spill)
      if parts.after is Some(right) {
        after.push(right)
      }
    } else {
      after.push(segment_id)
    }
  }
  for side in [before, after] {
    let mut index = 0
    while index < side.length() {
      let segment_id = side[index]
      if segment_carries_no_use(segments[segment_id], ranges) {
        spill.push(segment_id)
        side.remove(index) |> ignore
      } else {
        index = index + 1
      }
    }
  }
  if (before.is_empty() || after.is_empty()) && spill.is_empty() {
    if bundle_segments.length() <= 1 {
      return false
    }
    spill_sets[spill_set].splits = spill_sets[spill_set].splits + 1
    context.states[bundle] = BundleSplit
    statistics.bundle_splits = statistics.bundle_splits + 1
    for segment_id in bundle_segments {
      if segment_carries_no_use(segments[segment_id], ranges) {
        add_to_spill_bundle(
          spill_set,
          segment_id,
          context,
          segment_owner,
          spill_sets,
          segments,
          ranges~,
        )
      } else {
        enqueue_child_bundle(
          context,
          segment_owner,
          queue,
          segments,
          [segment_id],
          ranges,
          hint,
          spill_set,
          boundary_cost~,
        )
      }
    }
    return true
  }
  spill_sets[spill_set].splits = spill_sets[spill_set].splits + 1
  context.states[bundle] = BundleSplit
  statistics.bundle_splits = statistics.bundle_splits + 1
  for segment_id in spill {
    add_to_spill_bundle(
      spill_set,
      segment_id,
      context,
      segment_owner,
      spill_sets,
      segments,
      ranges~,
    )
  }
  if !before.is_empty() {
    enqueue_child_bundle(
      context,
      segment_owner,
      queue,
      segments,
      before,
      ranges,
      hint,
      spill_set,
      boundary_cost~,
    )
  }
  if !after.is_empty() {
    enqueue_child_bundle(
      context,
      segment_owner,
      queue,
      segments,
      after,
      ranges,
      hint,
      spill_set,
      boundary_cost~,
    )
  }
  true
}

///|
fn should_take_bundle_split(
  has_best : Bool,
  best_cost : Int,
  best_point : ProgramPoint,
  candidate_cost : Int,
  candidate_point : ProgramPoint,
  block_order : Array[Int],
) -> Bool {
  !has_best ||
  candidate_cost < best_cost ||
  (
    candidate_cost == best_cost &&
    candidate_point.compare_with_order(best_point, block_order) > 0
  )
}

///|
/// Check that allocation left every bundle resolved and every segment owned.
///
/// Like `ProductionBundlePlan::validate`, a violation here is a defect in this
/// allocator rather than bad input, and it reports through
/// `VerifyError::InvalidPlan` so the caller can see which invariant broke.
fn validate_bundle_allocations(
  context : AllocationContext,
  segments : Array[AllocationSegment],
  segment_owner : Array[Int],
  ranges : LiveRangeSet,
) -> Unit raise VerifyError {
  for bundle, state in context.states {
    if state is BundlePending || state is BundleDeferredSpill {
      raise InvalidPlan(message="pending allocation bundle after allocation")
    }
    if state is BundleSplit {
      continue
    }
    let bundle_segments = context.segments[bundle]
    for index in 1..<bundle_segments.length() {
      let previous = bundle_segments[index - 1]
      let current = bundle_segments[index]
      let by_end = segments[previous].range.end.compare_with_order(
        segments[current].range.end,
        ranges.block_order,
      )
      if by_end > 0 || (by_end == 0 && previous > current) {
        raise InvalidPlan(
          message="allocation bundle segments are not ordered by live-range end",
        )
      }
    }
    let (priority, weight, has_fixed_constraint) = allocation_bundle_metrics(
      bundle_segments,
      segments,
      boundary_cost=context.boundary_costs[bundle],
      ranges~,
    )
    if context.priorities[bundle] != priority {
      raise InvalidPlan(
        message="allocation bundle lost queue priority: recorded \{context.priorities[bundle]}, recomputed \{priority}",
      )
    }
    if context.weights[bundle] != weight {
      raise InvalidPlan(
        message="allocation bundle lost use weight: recorded \{context.weights[bundle]}, recomputed \{weight}",
      )
    }
    if has_fixed_constraint != context.fixed_constraints[bundle] {
      raise InvalidPlan(
        message="allocation bundle lost fixed constraints: recorded \{context.fixed_constraints[bundle]}, recomputed \{has_fixed_constraint}",
      )
    }
  }
  let seen_segments = Array::make(segments.length(), false)
  for bundle, state in context.states {
    if state is BundleSplit {
      continue
    }
    for segment_id in context.segments[bundle] {
      if segment_id < 0 ||
        segment_id >= segments.length() ||
        seen_segments[segment_id] ||
        segment_owner[segment_id] != bundle {
        raise InvalidPlan(
          message="invalid allocation bundle ownership for segment \{segment_id}: owner \{bundle}",
        )
      }
      seen_segments[segment_id] = true
    }
  }
  for segment in segments {
    let owner = segment_owner[segment.id]
    if owner < 0 ||
      owner >= context.states.length() ||
      !seen_segments[segment.id] {
      raise InvalidPlan(
        message="invalid allocation bundle ownership for segment \{segment.id}: owner \{owner}",
      )
    }
    match (context.states[owner], segment.location) {
      (BundleReg(expected), Some(SegmentReg(actual))) if expected == actual =>
        ()
      (BundleSpill, Some(SegmentSpill)) => ()
      _ =>
        raise InvalidPlan(
          message="incomplete atomic bundle allocation for segment \{segment.id} in bundle \{owner}",
        )
    }
  }
}

///|
fn[F : FunctionView] allocate_bundles(
  function : F,
  environment : MachineEnv,
  ranges : LiveRangeSet,
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  loop_depths : Array[Int],
  bundle_plan : ProductionBundlePlan,
  session : AllocationSession,
  verify? : Bool = true,
) -> (
  AllocationContext,
  Array[Int],
  Array[SpillSet],
  Array[Int],
  BundleAllocationStatistics,
) raise VerifyError {
  let statistics = BundleAllocationStatistics::new()
  let (context, segment_owner, spill_sets, segment_spill_set) = build_allocation_context(
    bundle_plan,
    segments,
    session,
    ranges~,
  )
  let owner_run_count = session.owner_run_count
  reset_dense_array(owner_run_count, context.states.length(), 0)
  let occupied = RegisterAllocationIndex::for_session(
    session,
    environment.allocatable_regs.length(),
    segments,
    segment_owner,
    owner_run_count,
    ranges.block_order,
  )
  let occupied_stack = session.occupied_stack
  occupied_stack.clear()
  let register_indexes = PhysicalRegisterIndex::for_session(
    session,
    environment.allocatable_regs,
  )
  let clobbers = build_register_clobber_index(
    function,
    environment,
    ranges.block_order,
    register_indexes,
  )
  let preferred_by_value = session.preferred_by_value
  reset_dense_array(preferred_by_value, function.value_count(), -1)
  let conflict_marks = session.conflict_marks
  reset_dense_array(conflict_marks, context.states.length(), 0)
  let probe_conflicts = session.probe_conflicts
  probe_conflicts.clear()
  let probe = BundleRegisterProbe::new(probe_conflicts)
  let eviction_conflicts = session.eviction_conflicts
  eviction_conflicts.clear()
  let register_order = session.register_order
  register_order.clear()
  let register_order_marks = session.register_order_marks
  reset_dense_array(
    register_order_marks,
    environment.allocatable_regs.length(),
    false,
  )
  let mut probe_id = 0
  let queue = BundleQueue::for_session(session, context.states.length())
  for bundle in 0..<context.states.length() {
    queue.push(bundle, context, -1)
  }
  statistics.max_queue_length = queue.items.length()
  while queue.pop() is Some((bundle, queue_hint)) {
    statistics.queue_pops = statistics.queue_pops + 1
    if !(context.states[bundle] is BundlePending) {
      continue
    }
    bundle_register_order(
      bundle,
      context,
      if spill_sets[context.spill_sets[bundle]].hint >= 0 {
        spill_sets[context.spill_sets[bundle]].hint
      } else {
        queue_hint
      },
      segments,
      environment,
      preferred_by_value,
      register_indexes,
      register_order,
      register_order_marks,
    )
    let mut free_register = -1
    let mut eviction_register = -1
    eviction_conflicts.clear()
    let mut eviction_cost : Int? = None
    let mut split_register = -1
    let mut has_split = false
    let mut split_cost = 0
    let mut split_point = ProgramPoint(-1, -1)
    let class = bundle_class(bundle, context, segments)
    for register in register_order {
      let reg = environment.allocatable_regs[register]
      if reg.class != class {
        continue
      }
      while conflict_marks.length() < context.states.length() {
        conflict_marks.push(0)
      }
      probe_id = probe_id + 1
      let conflict_policy = if has_split && eviction_cost is Some(evict) {
        limited_conflicts(evict.max(split_cost))
      } else {
        unlimited_conflicts()
      }
      probe_bundle_register(
        bundle,
        register,
        context,
        segments,
        segment_owner,
        occupied,
        clobbers,
        ranges.block_order,
        conflict_marks,
        probe_id,
        occupied_stack,
        probe_conflicts,
        probe,
        statistics,
        conflict_policy~,
      )
      if probe.cutoff_exceeded {
        continue
      }
      if !probe.clobbered && probe.conflicts.is_empty() {
        free_register = register
        break
      }
      if !probe.clobbered &&
        !probe.conflicts.is_empty() &&
        (eviction_cost is None || probe.conflict_cost < eviction_cost.unwrap()) {
        eviction_register = register
        eviction_cost = Some(probe.conflict_cost)
        eviction_conflicts.clear()
        for conflict in probe.conflicts {
          eviction_conflicts.push(conflict)
        }
      }
      if probe.has_first_conflict && !context.minimals[bundle] {
        let conflict_point = probe.first_conflict
        let move_cost = use_weight(
          UsePosition(conflict_point, LiveDef, AnyReg),
          loop_depths,
        )
        let candidate_cost = (probe.conflict_cost.to_int64() +
          move_cost.to_int64())
          .min(2_147_483_647L)
          .to_int()
        if should_take_bundle_split(
            has_split,
            split_cost,
            split_point,
            candidate_cost,
            conflict_point,
            ranges.block_order,
          ) {
          split_register = register
          has_split = true
          split_cost = candidate_cost
          split_point = conflict_point
        }
      }
    }
    if free_register >= 0 {
      record_bundle_allocation(
        bundle, context, free_register, environment, segments, occupied, preferred_by_value,
        spill_sets,
      )
      continue
    }
    let choose_split = has_split &&
      (
        eviction_cost is None ||
        context.weights[bundle] <= eviction_cost.unwrap()
      )
    if choose_split {
      let split_hint = split_register
      if split_bundle_at_conflict(
          bundle,
          split_point,
          split_hint,
          context,
          segment_owner,
          queue,
          segments,
          segments_by_value,
          segment_spill_set,
          spill_sets,
          occupied,
          ranges,
          loop_depths,
          environment.allocatable_regs,
          statistics,
        ) {
        statistics.max_queue_length = statistics.max_queue_length.max(
          queue.items.length(),
        )
        continue
      }
    }
    if eviction_register >= 0 &&
      eviction_cost is Some(cost) &&
      context.weights[bundle] > cost &&
      (!context.minimals[bundle] || context.fixed_constraints[bundle]) {
      evict_bundle_conflicts(
        eviction_conflicts, context, environment, segments, occupied, queue, statistics,
      )
      statistics.max_queue_length = statistics.max_queue_length.max(
        queue.items.length(),
      )
      record_bundle_allocation(
        bundle, context, eviction_register, environment, segments, occupied, preferred_by_value,
        spill_sets,
      )
      continue
    }
    let split_hint = split_register
    if !has_split ||
      !split_bundle_at_conflict(
        bundle,
        split_point,
        split_hint,
        context,
        segment_owner,
        queue,
        segments,
        segments_by_value,
        segment_spill_set,
        spill_sets,
        occupied,
        ranges,
        loop_depths,
        environment.allocatable_regs,
        statistics,
      ) {
      context.states[bundle] = BundleDeferredSpill
    }
    statistics.max_queue_length = statistics.max_queue_length.max(
      queue.items.length(),
    )
  }
  queue.reset(context.states.length(), true)
  let second_chance = queue
  for bundle in 0..<context.states.length() {
    if context.states[bundle] is BundleDeferredSpill {
      if spill_sets[context.spill_sets[bundle]].spill_bundle == Some(bundle) {
        prepare_spill_bundle(
          bundle,
          context,
          segments,
          ranges.block_order,
          ranges~,
        )
      }
      second_chance.push(
        bundle,
        context,
        spill_sets[context.spill_sets[bundle]].hint,
      )
    }
  }
  while second_chance.pop() is Some((bundle, _)) {
    guard context.states[bundle] is BundleDeferredSpill else { continue }
    statistics.second_chance_attempts = statistics.second_chance_attempts + 1
    bundle_register_order(
      bundle,
      context,
      spill_sets[context.spill_sets[bundle]].hint,
      segments,
      environment,
      preferred_by_value,
      register_indexes,
      register_order,
      register_order_marks,
    )
    let mut free_register = -1
    for register in register_order {
      let reg = environment.allocatable_regs[register]
      if reg.class != bundle_class(bundle, context, segments) {
        continue
      }
      while conflict_marks.length() < context.states.length() {
        conflict_marks.push(0)
      }
      probe_id = probe_id + 1
      probe_bundle_register(
        bundle,
        register,
        context,
        segments,
        segment_owner,
        occupied,
        clobbers,
        ranges.block_order,
        conflict_marks,
        probe_id,
        occupied_stack,
        probe_conflicts,
        probe,
        statistics,
        conflict_policy=reject_conflicts(),
      )
      if !probe.clobbered && probe.conflicts.is_empty() {
        free_register = register
        break
      }
    }
    if free_register >= 0 {
      record_bundle_allocation(
        bundle, context, free_register, environment, segments, occupied, preferred_by_value,
        spill_sets,
      )
    } else {
      force_spill_bundle(bundle, context, segments)
    }
  }
  if verify {
    validate_bundle_allocations(context, segments, segment_owner, ranges)
  }
  (context, segment_owner, spill_sets, segment_spill_set, statistics)
}
