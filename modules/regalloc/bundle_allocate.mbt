///|
const MAX_SPLITS_PER_SPILL_SET : Int = 2

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
  weight : Int
  mut splits : Int
  mut hint : PhysicalReg?
  mut spill_bundle : Int?
}

///|
priv struct AllocationBundle {
  id : Int
  segments : Array[Int]
  mut priority : Int
  mut weight : Int
  mut has_fixed_constraint : Bool
  spill_set : Int
  mut state : AllocationBundleState
}

///|
priv struct BundleQueueEntry {
  bundle : Int
  hint : PhysicalReg?
}

///|
priv struct BundleQueue {
  bundles : Array[AllocationBundle]
  items : Array[BundleQueueEntry]
  in_queue : Array[Bool]
  spill_priorities : Array[Int]?
}

///|
fn BundleQueue::new(
  bundles : Array[AllocationBundle],
  spill_priorities? : Array[Int]? = None,
) -> BundleQueue {
  {
    bundles,
    items: [],
    in_queue: Array::make(bundles.length(), false),
    spill_priorities,
  }
}

///|
fn BundleQueue::ensure_slot(self : BundleQueue, bundle : Int) -> Unit {
  while bundle >= self.in_queue.length() {
    self.in_queue.push(false)
  }
}

///|
fn BundleQueue::higher(
  self : BundleQueue,
  lhs : BundleQueueEntry,
  rhs : BundleQueueEntry,
) -> Bool {
  let left = self.bundles[lhs.bundle]
  let right = self.bundles[rhs.bundle]
  if self.spill_priorities is Some(priorities) &&
    priorities[left.spill_set] != priorities[right.spill_set] {
    priorities[left.spill_set] > priorities[right.spill_set]
  } else if left.priority != right.priority {
    left.priority > right.priority
  } else {
    left.id < right.id
  }
}

///|
fn BundleQueue::push(
  self : BundleQueue,
  bundle : Int,
  hint : PhysicalReg?,
) -> Unit {
  self.ensure_slot(bundle)
  if self.in_queue[bundle] {
    return
  }
  self.in_queue[bundle] = true
  self.items.push({ bundle, hint })
  let mut index = self.items.length() - 1
  while index > 0 {
    let parent = (index - 1) / 2
    if !self.higher(self.items[index], self.items[parent]) {
      break
    }
    let temporary = self.items[index]
    self.items[index] = self.items[parent]
    self.items[parent] = temporary
    index = parent
  }
}

///|
fn BundleQueue::pop(self : BundleQueue) -> BundleQueueEntry? {
  if self.items.is_empty() {
    return None
  }
  let first = self.items[0]
  self.in_queue[first.bundle] = false
  let last = self.items.pop().unwrap()
  if !self.items.is_empty() {
    self.items[0] = last
    let mut index = 0
    while true {
      let left = index * 2 + 1
      if left >= self.items.length() {
        break
      }
      let right = left + 1
      let mut higher = left
      if right < self.items.length() &&
        self.higher(self.items[right], self.items[left]) {
        higher = right
      }
      if !self.higher(self.items[higher], self.items[index]) {
        break
      }
      let temporary = self.items[index]
      self.items[index] = self.items[higher]
      self.items[higher] = temporary
      index = higher
    }
  }
  Some(first)
}

///|
priv struct BundleRegisterProbe {
  conflicts : Array[Int]
  conflict_cost : Int
  first_conflict : ProgramPoint?
  clobbered : Bool
  cutoff_exceeded : Bool
}

///|
fn allocation_bundle_metrics(
  segment_ids : Array[Int],
  segments : Array[AllocationSegment],
) -> (Int, Int, Bool) {
  let mut priority = 0
  let mut weighted_cost = 0L
  let mut has_fixed_constraint = false
  for segment_id in segment_ids {
    let segment_priority = allocation_segment_priority(segments[segment_id])
    priority = priority + segment_priority
    weighted_cost = weighted_cost +
      segments[segment_id].weight.to_int64() * segment_priority.to_int64()
    has_fixed_constraint = has_fixed_constraint ||
      segments[segment_id].has_fixed_constraint
  }
  let normalized_priority = priority.max(1)
  let weight = ((weighted_cost + normalized_priority.to_int64() - 1L) /
    normalized_priority.to_int64())
    .min(2_147_483_647L)
    .to_int()
  (normalized_priority, weight.max(1), has_fixed_constraint)
}

///|
fn allocation_bundle(
  id : Int,
  segment_ids : Array[Int],
  segments : Array[AllocationSegment],
  block_order : Array[Int],
  spill_set? : Int = id,
) -> AllocationBundle {
  let ordered_segments = segment_ids.copy()
  ordered_segments.sort_by((left, right) => {
    let by_end = segments[left].range.end.compare_with_order(
      segments[right].range.end,
      block_order,
    )
    if by_end != 0 {
      by_end
    } else {
      left - right
    }
  })
  let (priority, weight, has_fixed_constraint) = allocation_bundle_metrics(
    ordered_segments, segments,
  )
  {
    id,
    segments: ordered_segments,
    priority,
    weight,
    has_fixed_constraint,
    spill_set,
    state: BundlePending,
  }
}

///|
/// Queue priority is live extent, while eviction uses local spill weight. The
/// two must remain distinct so a dense short bundle can evict a sparse long
/// bundle that was deliberately processed first.
fn allocation_segment_priority(segment : AllocationSegment) -> Int {
  if segment.range.start.block == segment.range.end.block {
    (segment.range.end.inst - segment.range.start.inst).abs() + 1
  } else {
    1
  }
}

///|
fn build_allocation_bundles(
  plan : ProductionBundlePlan,
  segments : Array[AllocationSegment],
  block_order : Array[Int],
) -> (Array[AllocationBundle], Array[Int], Array[SpillSet], Array[Int]) {
  let bundles : Array[AllocationBundle] = []
  let segment_owner = Array::make(segments.length(), -1)
  let spill_sets : Array[SpillSet] = []
  let segment_spill_set = Array::make(segments.length(), -1)
  for segment_ids in plan.bundle_segments {
    let spill_set = spill_sets.length()
    let bundle = allocation_bundle(
      bundles.length(),
      segment_ids,
      segments,
      block_order,
      spill_set~,
    )
    spill_sets.push({
      weight: bundle.weight,
      splits: 0,
      hint: None,
      spill_bundle: None,
    })
    bundles.push(bundle)
    for segment_id in segment_ids {
      segment_owner[segment_id] = bundle.id
      segment_spill_set[segment_id] = spill_set
    }
  }
  (bundles, segment_owner, spill_sets, segment_spill_set)
}

///|
fn bundle_class(
  bundle : AllocationBundle,
  segments : Array[AllocationSegment],
) -> RegClass {
  segments[bundle.segments[0]].value.class
}

///|
fn earlier_conflict_point(
  current : ProgramPoint?,
  candidate : ProgramPoint,
  block_order : Array[Int],
) -> ProgramPoint {
  match current {
    Some(point) =>
      if candidate.compare_with_order(point, block_order) < 0 {
        candidate
      } else {
        point
      }
    None => candidate
  }
}

///|
fn probe_bundle_register(
  bundle : AllocationBundle,
  register : Int,
  reg : PhysicalReg,
  bundles : Array[AllocationBundle],
  spill_sets : Array[SpillSet],
  segments : Array[AllocationSegment],
  segment_owner : Array[Int],
  occupied : RegisterAllocationIndex,
  clobbers : RegisterClobberIndex,
  block_order : Array[Int],
  conflict_marks : Array[Int],
  probe_id : Int,
  occupied_stack : Array[Int],
  conflicts : Array[Int],
  max_conflict_cost? : Int? = None,
) -> BundleRegisterProbe {
  conflicts.clear()
  let mut conflict_cost = 0
  let mut first_conflict : ProgramPoint? = None
  let mut clobbered = false
  if clobbers.first_intersection(reg, bundle.segments, segments) is Some(point) {
    clobbered = true
    first_conflict = Some(point)
  }
  if clobbered && max_conflict_cost is Some(limit) && 0 > limit {
    return {
      conflicts,
      conflict_cost,
      first_conflict,
      clobbered,
      cutoff_exceeded: true,
    }
  }
  guard !bundle.segments.is_empty() else {
    return {
      conflicts,
      conflict_cost,
      first_conflict,
      clobbered,
      cutoff_exceeded: false,
    }
  }
  occupied.seek(
    register,
    segments[bundle.segments[0]].range.start,
    occupied_stack,
  )
  let mut assigned = occupied.next(occupied_stack)
  let mut bundle_index = 0
  while bundle_index < bundle.segments.length() && assigned is Some(_) {
    let conflict_segment = assigned.unwrap()
    let current = segments[bundle.segments[bundle_index]]
    let conflict = segments[conflict_segment]
    if conflict.range.end.compare_with_order(current.range.start, block_order) <
      0 {
      assigned = occupied.next(occupied_stack)
      continue
    }
    if current.range.end.compare_with_order(conflict.range.start, block_order) <
      0 {
      bundle_index = bundle_index + 1
      continue
    }
    let owner = segment_owner[conflict_segment]
    if owner != bundle.id && conflict_marks[owner] != probe_id {
      conflict_marks[owner] = probe_id
      conflicts.push(owner)
      conflict_cost = conflict_cost.max(
        spill_sets[bundles[owner].spill_set].weight,
      )
      first_conflict = Some(
        earlier_conflict_point(
          first_conflict,
          later_point(current.range.start, conflict.range.start, block_order),
          block_order,
        ),
      )
      if max_conflict_cost is Some(limit) && conflict_cost > limit {
        return {
          conflicts,
          conflict_cost,
          first_conflict,
          clobbered,
          cutoff_exceeded: true,
        }
      }
    }
    if conflict.range.end.compare_with_order(current.range.end, block_order) <=
      0 {
      assigned = occupied.next(occupied_stack)
    } else {
      bundle_index = bundle_index + 1
    }
  }
  {
    conflicts,
    conflict_cost,
    first_conflict,
    clobbered,
    cutoff_exceeded: false,
  }
}

///|
fn push_bundle_register_candidates(
  order : Array[Int],
  order_marks : Array[Bool],
  register_indexes : Map[(Int, Int), Int],
  candidate : PhysicalReg?,
) -> Unit {
  if candidate is Some(reg) &&
    register_indexes.get(physical_reg_key(reg)) is Some(index) &&
    !order_marks[index] {
    order_marks[index] = true
    order.push(index)
  }
}

///|
fn bundle_register_order(
  bundle : AllocationBundle,
  hint : PhysicalReg?,
  segments : Array[AllocationSegment],
  environment : MachineEnv,
  preferred_by_value : Array[PhysicalReg?],
  register_indexes : Map[(Int, Int), Int],
  order : Array[Int],
  order_marks : Array[Bool],
) -> Unit {
  for register in order {
    order_marks[register] = false
  }
  order.clear()
  push_bundle_register_candidates(order, order_marks, register_indexes, hint)
  for segment_id in bundle.segments {
    let segment = segments[segment_id]
    push_bundle_register_candidates(
      order,
      order_marks,
      register_indexes,
      segment.fixed_hint,
    )
    push_bundle_register_candidates(
      order,
      order_marks,
      register_indexes,
      segment.preference_hint,
    )
    push_bundle_register_candidates(
      order,
      order_marks,
      register_indexes,
      preferred_by_value[segment.value.id],
    )
  }
  for register in 0..<environment.allocatable_regs.length() {
    if !order_marks[register] {
      order_marks[register] = true
      order.push(register)
    }
  }
}

///|
fn remove_bundle_allocation(
  bundle : AllocationBundle,
  environment : MachineEnv,
  segments : Array[AllocationSegment],
  occupied : RegisterAllocationIndex,
) -> Unit {
  guard bundle.state is BundleReg(reg) else { return }
  let register = register_index(environment.allocatable_regs, reg).unwrap()
  for segment_id in bundle.segments {
    occupied.remove(register, segment_id)
    segments[segment_id].location = None
  }
  bundle.state = BundlePending
}

///|
fn bundle_can_evict(
  bundle : AllocationBundle,
  probe : BundleRegisterProbe,
  spill_sets : Array[SpillSet],
) -> Bool {
  !probe.clobbered &&
  !probe.conflicts.is_empty() &&
  probe.conflict_cost < spill_sets[bundle.spill_set].weight
}

///|
fn evict_bundle_conflicts(
  conflicts : Array[Int],
  bundles : Array[AllocationBundle],
  environment : MachineEnv,
  segments : Array[AllocationSegment],
  occupied : RegisterAllocationIndex,
  queue : BundleQueue,
) -> Unit {
  for conflict in conflicts {
    let evicted = bundles[conflict]
    let hint = match evicted.state {
      BundleReg(reg) => Some(reg)
      _ => None
    }
    remove_bundle_allocation(evicted, environment, segments, occupied)
    queue.push(evicted.id, hint)
  }
}

///|
fn record_bundle_allocation(
  bundle : AllocationBundle,
  register : Int,
  environment : MachineEnv,
  segments : Array[AllocationSegment],
  occupied : RegisterAllocationIndex,
  preferred_by_value : Array[PhysicalReg?],
  spill_sets : Array[SpillSet],
) -> Unit {
  let reg = environment.allocatable_regs[register]
  for segment_id in bundle.segments {
    let segment = segments[segment_id]
    segment.location = Some(SegmentReg(reg))
    preferred_by_value[segment.value.id] = Some(reg)
    occupied.insert(register, segment_id)
  }
  spill_sets[bundle.spill_set].hint = Some(reg)
  bundle.state = BundleReg(reg)
}

///|
fn force_spill_bundle(
  bundle : AllocationBundle,
  segments : Array[AllocationSegment],
) -> Unit {
  for segment_id in bundle.segments {
    segments[segment_id].location = Some(SegmentSpill)
  }
  bundle.state = BundleSpill
}

///|
fn refresh_bundle_metrics(
  bundle : AllocationBundle,
  segments : Array[AllocationSegment],
) -> Unit {
  let (priority, weight, fixed) = allocation_bundle_metrics(
    bundle.segments,
    segments,
  )
  bundle.priority = priority
  bundle.weight = weight
  bundle.has_fixed_constraint = fixed
}

///|
fn add_to_spill_bundle(
  spill_set : Int,
  segment : Int,
  bundles : Array[AllocationBundle],
  segment_owner : Array[Int],
  spill_sets : Array[SpillSet],
  segments : Array[AllocationSegment],
  block_order : Array[Int],
) -> Unit {
  match spill_sets[spill_set].spill_bundle {
    Some(bundle_id) => {
      let bundle = bundles[bundle_id]
      bundle.segments.push(segment)
      segment_owner[segment] = bundle_id
    }
    None => {
      let spill_bundle = allocation_bundle(
        bundles.length(),
        [segment],
        segments,
        block_order,
        spill_set~,
      )
      spill_bundle.state = BundleDeferredSpill
      bundles.push(spill_bundle)
      segment_owner[segment] = spill_bundle.id
      spill_sets[spill_set].spill_bundle = Some(spill_bundle.id)
    }
  }
}

///|
fn prepare_spill_bundle(
  bundle : AllocationBundle,
  segments : Array[AllocationSegment],
  block_order : Array[Int],
) -> Unit {
  bundle.segments.sort_by(fn(left, right) {
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
  refresh_bundle_metrics(bundle, segments)
}

///|
fn enqueue_child_bundle(
  bundles : Array[AllocationBundle],
  segment_owner : Array[Int],
  queue : BundleQueue,
  segments : Array[AllocationSegment],
  segment_ids : Array[Int],
  block_order : Array[Int],
  hint : PhysicalReg?,
  spill_set : Int,
) -> Unit {
  let child = allocation_bundle(
    bundles.length(),
    segment_ids,
    segments,
    block_order,
    spill_set~,
  )
  bundles.push(child)
  for segment_id in segment_ids {
    segment_owner[segment_id] = child.id
  }
  queue.push(child.id, hint)
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
  block_order : Array[Int],
  allocatable : Array[PhysicalReg],
) -> Int {
  let segment = segments[source]
  let id = segments.length()
  let metadata = segment_metadata(
    live_range, range, loop_depths, block_order, allocatable,
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
  if segment.range.start.block != point.block ||
    segment.range.end.block != point.block ||
    point.inst < segment.range.start.inst ||
    point.inst > segment.range.end.inst {
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
  let gap_start = previous_use.map_or(segment.range.start.inst, previous => {
    previous + 1
  })
  let gap_end = next_use.map_or(segment.range.end.inst, next => next - 1)
  if gap_start > point.inst || gap_end < point.inst || gap_start > gap_end {
    return None
  }
  let original_range = segment.range
  let mut before : Int? = None
  if original_range.start.inst < gap_start {
    segment.range = ProgramRange(
      original_range.start,
      ProgramPoint(point.block, gap_start - 1),
    )
    segment.refresh_metadata(
      live_range,
      loop_depths,
      ranges.block_order,
      allocatable,
    )
    before = Some(segment_id)
  } else {
    segment.range = ProgramRange(
      ProgramPoint(point.block, gap_start),
      ProgramPoint(point.block, gap_end),
    )
  }
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
      ranges.block_order,
      allocatable,
    )
  } else {
    segment.refresh_metadata(
      live_range,
      loop_depths,
      ranges.block_order,
      allocatable,
    )
    segment_id
  }
  let after = if gap_end < original_range.end.inst {
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
        ranges.block_order,
        allocatable,
      ),
    )
  } else {
    None
  }
  Some({ before, spill, after })
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
fn split_bundle_at_conflict(
  bundle : AllocationBundle,
  split_point : ProgramPoint?,
  hint : PhysicalReg?,
  bundles : Array[AllocationBundle],
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
) -> Bool {
  guard split_point is Some(point) else { return false }
  let spill_set = spill_sets[bundle.spill_set]
  if spill_set.splits >= MAX_SPLITS_PER_SPILL_SET {
    // Operand assignment reserves registers around spilled uses, so the shared
    // spill bundle is this allocator's minimal fallback.
    bundle.state = BundleSplit
    for segment_id in bundle.segments {
      add_to_spill_bundle(
        bundle.spill_set,
        segment_id,
        bundles,
        segment_owner,
        spill_sets,
        segments,
        ranges.block_order,
      )
    }
    return true
  }
  spill_set.splits = spill_set.splits + 1
  let before : Array[Int] = []
  let after : Array[Int] = []
  let spill : Array[Int] = []
  for segment_id in bundle.segments {
    let segment = segments[segment_id]
    if segment.range.end.compare_with_order(point, ranges.block_order) < 0 {
      before.push(segment_id)
    } else if segment.range.start.compare_with_order(point, ranges.block_order) >=
      0 {
      after.push(segment_id)
    } else if bundle.segments.length() == 1 &&
      split_segment_around_gap(
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
    if bundle.segments.length() <= 1 {
      return false
    }
    bundle.state = BundleSplit
    for segment_id in bundle.segments {
      if segment_carries_no_use(segments[segment_id], ranges) {
        add_to_spill_bundle(
          bundle.spill_set,
          segment_id,
          bundles,
          segment_owner,
          spill_sets,
          segments,
          ranges.block_order,
        )
      } else {
        enqueue_child_bundle(
          bundles,
          segment_owner,
          queue,
          segments,
          [segment_id],
          ranges.block_order,
          hint,
          bundle.spill_set,
        )
      }
    }
    return true
  }
  bundle.state = BundleSplit
  for segment_id in spill {
    add_to_spill_bundle(
      bundle.spill_set,
      segment_id,
      bundles,
      segment_owner,
      spill_sets,
      segments,
      ranges.block_order,
    )
  }
  if !before.is_empty() {
    enqueue_child_bundle(
      bundles,
      segment_owner,
      queue,
      segments,
      before,
      ranges.block_order,
      hint,
      bundle.spill_set,
    )
  }
  if !after.is_empty() {
    enqueue_child_bundle(
      bundles,
      segment_owner,
      queue,
      segments,
      after,
      ranges.block_order,
      hint,
      bundle.spill_set,
    )
  }
  true
}

///|
fn should_take_bundle_split(
  best_cost : Int?,
  best_point : ProgramPoint?,
  candidate_cost : Int,
  candidate_point : ProgramPoint,
  block_order : Array[Int],
) -> Bool {
  match (best_cost, best_point) {
    (None, None) => true
    (Some(cost), Some(point)) =>
      candidate_cost < cost ||
      (
        candidate_cost == cost &&
        candidate_point.compare_with_order(point, block_order) > 0
      )
    _ => false
  }
}

///|
/// Check that allocation left every bundle resolved and every segment owned.
///
/// Like `ProductionBundlePlan::validate`, a violation here is a defect in this
/// allocator rather than bad input, and it reports through
/// `VerifyError::InvalidPlan` so the caller can see which invariant broke.
fn validate_bundle_allocations(
  bundles : Array[AllocationBundle],
  segments : Array[AllocationSegment],
  segment_owner : Array[Int],
  block_order : Array[Int],
) -> Unit raise VerifyError {
  for bundle in bundles {
    if bundle.state is BundlePending || bundle.state is BundleDeferredSpill {
      raise InvalidPlan(message="pending allocation bundle after allocation")
    }
    if bundle.state is BundleSplit {
      continue
    }
    for index in 1..<bundle.segments.length() {
      let previous = bundle.segments[index - 1]
      let current = bundle.segments[index]
      let by_end = segments[previous].range.end.compare_with_order(
        segments[current].range.end,
        block_order,
      )
      if by_end > 0 || (by_end == 0 && previous > current) {
        raise InvalidPlan(
          message="allocation bundle segments are not ordered by live-range end",
        )
      }
    }
    let (priority, weight, has_fixed_constraint) = allocation_bundle_metrics(
      bundle.segments,
      segments,
    )
    if bundle.priority != priority {
      raise InvalidPlan(
        message="allocation bundle lost queue priority: recorded \{bundle.priority}, recomputed \{priority}",
      )
    }
    if bundle.weight != weight {
      raise InvalidPlan(
        message="allocation bundle lost use weight: recorded \{bundle.weight}, recomputed \{weight}",
      )
    }
    if has_fixed_constraint != bundle.has_fixed_constraint {
      raise InvalidPlan(
        message="allocation bundle lost fixed constraints: recorded \{bundle.has_fixed_constraint}, recomputed \{has_fixed_constraint}",
      )
    }
  }
  for segment in segments {
    let owner = segment_owner[segment.id]
    if owner < 0 ||
      owner >= bundles.length() ||
      !bundles[owner].segments.contains(segment.id) {
      raise InvalidPlan(
        message="invalid allocation bundle ownership for segment \{segment.id}: owner \{owner}",
      )
    }
    match (bundles[owner].state, segment.location) {
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
) -> (Array[AllocationBundle], Array[Int], Array[SpillSet], Array[Int]) raise VerifyError {
  let (bundles, segment_owner, spill_sets, segment_spill_set) = build_allocation_bundles(
    bundle_plan,
    segments,
    ranges.block_order,
  )
  let occupied = RegisterAllocationIndex::new(
    environment.allocatable_regs.length(),
    segments,
    ranges.block_order,
  )
  let occupied_stack : Array[Int] = []
  let clobbers = build_register_clobber_index(function, ranges.block_order)
  let preferred_by_value : Array[PhysicalReg?] = Array::make(
    function.value_count(),
    None,
  )
  let conflict_marks : Array[Int] = Array::make(bundles.length(), 0)
  let probe_conflicts : Array[Int] = []
  let register_indexes : Map[(Int, Int), Int] = Map([])
  for index, reg in environment.allocatable_regs {
    register_indexes[physical_reg_key(reg)] = index
  }
  let register_order : Array[Int] = []
  let register_order_marks = Array::make(
    environment.allocatable_regs.length(),
    false,
  )
  let mut probe_id = 0
  let queue = BundleQueue::new(bundles)
  for bundle in bundles {
    queue.push(bundle.id, None)
  }
  while queue.pop() is Some(entry) {
    let bundle = bundles[entry.bundle]
    if !(bundle.state is BundlePending) {
      continue
    }
    bundle_register_order(
      bundle,
      match spill_sets[bundle.spill_set].hint {
        Some(reg) => Some(reg)
        None => entry.hint
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
    let eviction_conflicts : Array[Int] = []
    let mut eviction_cost : Int? = None
    let mut split_register = -1
    let mut split_cost : Int? = None
    let mut split_point : ProgramPoint? = None
    for register in register_order {
      let reg = environment.allocatable_regs[register]
      if reg.class != bundle_class(bundle, segments) {
        continue
      }
      while conflict_marks.length() < bundles.length() {
        conflict_marks.push(0)
      }
      probe_id = probe_id + 1
      let max_conflict_cost = match split_cost {
        Some(cost) => {
          let eviction_limit = eviction_cost
            .unwrap_or(spill_sets[bundle.spill_set].weight)
            .min(spill_sets[bundle.spill_set].weight)
          Some(cost.max(eviction_limit - 1))
        }
        None => None
      }
      let probe = probe_bundle_register(
        bundle,
        register,
        reg,
        bundles,
        spill_sets,
        segments,
        segment_owner,
        occupied,
        clobbers,
        ranges.block_order,
        conflict_marks,
        probe_id,
        occupied_stack,
        probe_conflicts,
        max_conflict_cost~,
      )
      if probe.cutoff_exceeded {
        continue
      }
      if !probe.clobbered && probe.conflicts.is_empty() {
        free_register = register
        break
      }
      if bundle_can_evict(bundle, probe, spill_sets) &&
        (eviction_cost is None || probe.conflict_cost < eviction_cost.unwrap()) {
        eviction_register = register
        eviction_cost = Some(probe.conflict_cost)
        eviction_conflicts.clear()
        for conflict in probe.conflicts {
          eviction_conflicts.push(conflict)
        }
      }
      if probe.first_conflict is Some(point) &&
        should_take_bundle_split(
          split_cost,
          split_point,
          probe.conflict_cost,
          point,
          ranges.block_order,
        ) {
        split_register = register
        split_cost = Some(probe.conflict_cost)
        split_point = Some(point)
      }
    }
    if free_register >= 0 {
      record_bundle_allocation(
        bundle, free_register, environment, segments, occupied, preferred_by_value,
        spill_sets,
      )
      continue
    }
    if eviction_register >= 0 {
      evict_bundle_conflicts(
        eviction_conflicts, bundles, environment, segments, occupied, queue,
      )
      record_bundle_allocation(
        bundle, eviction_register, environment, segments, occupied, preferred_by_value,
        spill_sets,
      )
      continue
    }
    let split_hint = if split_register >= 0 {
      Some(environment.allocatable_regs[split_register])
    } else {
      None
    }
    if !split_bundle_at_conflict(
        bundle,
        split_point,
        split_hint,
        bundles,
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
      ) {
      bundle.state = BundleDeferredSpill
    }
  }
  let second_chance = BundleQueue::new(
    bundles,
    spill_priorities=Some(spill_sets.map(set => set.weight)),
  )
  for bundle in bundles {
    if bundle.state is BundleDeferredSpill {
      if spill_sets[bundle.spill_set].spill_bundle == Some(bundle.id) {
        prepare_spill_bundle(bundle, segments, ranges.block_order)
      }
      second_chance.push(bundle.id, spill_sets[bundle.spill_set].hint)
    }
  }
  while second_chance.pop() is Some(entry) {
    let bundle = bundles[entry.bundle]
    guard bundle.state is BundleDeferredSpill else { continue }
    bundle_register_order(
      bundle,
      spill_sets[bundle.spill_set].hint,
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
      if reg.class != bundle_class(bundle, segments) {
        continue
      }
      while conflict_marks.length() < bundles.length() {
        conflict_marks.push(0)
      }
      probe_id = probe_id + 1
      let probe = probe_bundle_register(
        bundle,
        register,
        reg,
        bundles,
        spill_sets,
        segments,
        segment_owner,
        occupied,
        clobbers,
        ranges.block_order,
        conflict_marks,
        probe_id,
        occupied_stack,
        probe_conflicts,
        max_conflict_cost=Some(-1),
      )
      if !probe.clobbered && probe.conflicts.is_empty() {
        free_register = register
        break
      }
    }
    if free_register >= 0 {
      record_bundle_allocation(
        bundle, free_register, environment, segments, occupied, preferred_by_value,
        spill_sets,
      )
    } else {
      force_spill_bundle(bundle, segments)
    }
  }
  validate_bundle_allocations(
    bundles,
    segments,
    segment_owner,
    ranges.block_order,
  )
  (bundles, segment_owner, spill_sets, segment_spill_set)
}
