///|
priv enum AllocationBundleState {
  BundlePending
  BundleReg(PhysicalReg)
  BundleSpill
  BundleSplit
}

///|
priv struct AllocationBundle {
  id : Int
  segments : Array[Int]
  priority : Int
  weight : Int
  has_fixed_constraint : Bool
  split_count : Int
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
  production_priority : Bool
}

///|
fn BundleQueue::new(
  bundles : Array[AllocationBundle],
  production_priority : Bool,
) -> BundleQueue {
  {
    bundles,
    items: [],
    in_queue: Array::make(bundles.length(), false),
    production_priority,
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
  if self.production_priority && left.priority != right.priority {
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
  split_count? : Int = 0,
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
    split_count,
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
) -> (Array[AllocationBundle], Array[Int]) {
  let bundles : Array[AllocationBundle] = []
  let segment_owner = Array::make(segments.length(), -1)
  for segment_ids in plan.bundle_segments {
    let bundle = allocation_bundle(
      bundles.length(),
      segment_ids,
      segments,
      block_order,
    )
    bundles.push(bundle)
    for segment_id in segment_ids {
      segment_owner[segment_id] = bundle.id
    }
  }
  (bundles, segment_owner)
}

///|
fn bundle_class(
  bundle : AllocationBundle,
  segments : Array[AllocationSegment],
) -> RegClass {
  segments[bundle.segments[0]].value.class
}

///|
fn first_clobber_point(
  segment : AllocationSegment,
  reg : PhysicalReg,
  clobbers : RegisterClobberIndex,
) -> ProgramPoint? {
  clobbers.query(reg, segment.range).0
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
  segments : Array[AllocationSegment],
  segment_owner : Array[Int],
  occupied : RegisterAllocationIndex,
  clobbers : RegisterClobberIndex,
  block_order : Array[Int],
  conflict_marks : Array[Int],
  probe_id : Int,
  occupied_stack : Array[Int],
) -> BundleRegisterProbe {
  let conflicts : Array[Int] = []
  let mut conflict_cost = 0
  let mut first_conflict : ProgramPoint? = None
  let mut clobbered = false
  for segment_id in bundle.segments {
    let segment = segments[segment_id]
    if first_clobber_point(segment, reg, clobbers) is Some(point) {
      clobbered = true
      first_conflict = Some(
        earlier_conflict_point(first_conflict, point, block_order),
      )
    }
  }
  guard !bundle.segments.is_empty() else {
    return { conflicts, conflict_cost, first_conflict, clobbered }
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
      conflict_cost = conflict_cost.max(bundles[owner].weight)
      first_conflict = Some(
        earlier_conflict_point(
          first_conflict,
          later_point(current.range.start, conflict.range.start, block_order),
          block_order,
        ),
      )
    }
    if conflict.range.end.compare_with_order(current.range.end, block_order) <=
      0 {
      assigned = occupied.next(occupied_stack)
    } else {
      bundle_index = bundle_index + 1
    }
  }
  { conflicts, conflict_cost, first_conflict, clobbered }
}

///|
fn push_bundle_register_candidates(
  order : Array[Int],
  registers : Array[PhysicalReg],
  candidate : PhysicalReg?,
) -> Unit {
  if candidate is Some(reg) {
    push_register_candidate(order, register_index(registers, reg))
  }
}

///|
fn bundle_register_order(
  bundle : AllocationBundle,
  hint : PhysicalReg?,
  segments : Array[AllocationSegment],
  ranges : LiveRangeSet,
  environment : MachineEnv,
  preferred_by_value : Array[PhysicalReg?],
) -> Array[Int] {
  let order : Array[Int] = []
  push_bundle_register_candidates(order, environment.allocatable_regs, hint)
  for segment_id in bundle.segments {
    let segment = segments[segment_id]
    push_bundle_register_candidates(
      order,
      environment.allocatable_regs,
      segment_fixed_hint(ranges, segment),
    )
    push_bundle_register_candidates(
      order,
      environment.allocatable_regs,
      segment_preference_hint(ranges, segment, environment.allocatable_regs),
    )
    push_bundle_register_candidates(
      order,
      environment.allocatable_regs,
      preferred_by_value[segment.value.id],
    )
  }
  for register in 0..<environment.allocatable_regs.length() {
    push_register_candidate(order, Some(register))
  }
  order
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
  enable_eviction : Bool,
  bundle : AllocationBundle,
  probe : BundleRegisterProbe,
) -> Bool {
  enable_eviction &&
  !probe.clobbered &&
  !probe.conflicts.is_empty() &&
  probe.conflict_cost < bundle.weight
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
    remove_bundle_allocation(evicted, environment, segments, occupied)
    queue.push(evicted.id, None)
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
) -> Unit {
  let reg = environment.allocatable_regs[register]
  for segment_id in bundle.segments {
    let segment = segments[segment_id]
    segment.location = Some(SegmentReg(reg))
    preferred_by_value[segment.value.id] = Some(reg)
    occupied.insert(register, segment_id)
  }
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
fn enqueue_child_bundle(
  bundles : Array[AllocationBundle],
  segment_owner : Array[Int],
  queue : BundleQueue,
  segments : Array[AllocationSegment],
  segment_ids : Array[Int],
  block_order : Array[Int],
  hint : PhysicalReg?,
  split_count : Int,
) -> Unit {
  let child = allocation_bundle(
    bundles.length(),
    segment_ids,
    segments,
    block_order,
    split_count~,
  )
  bundles.push(child)
  for segment_id in segment_ids {
    segment_owner[segment_id] = child.id
  }
  queue.push(child.id, hint)
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
  block_order : Array[Int],
) -> Unit {
  if bundle.segments.length() <= 1 {
    force_spill_bundle(bundle, segments)
    return
  }
  let before : Array[Int] = []
  let after : Array[Int] = []
  if split_point is Some(point) {
    for segment_id in bundle.segments {
      if segments[segment_id].range.end.compare_with_order(point, block_order) <=
        0 {
        before.push(segment_id)
      } else {
        after.push(segment_id)
      }
    }
  }
  bundle.state = BundleSplit
  let child_split_count = bundle.split_count + 1
  if bundle.split_count < 2 && !before.is_empty() && !after.is_empty() {
    enqueue_child_bundle(
      bundles, segment_owner, queue, segments, before, block_order, hint, child_split_count,
    )
    enqueue_child_bundle(
      bundles, segment_owner, queue, segments, after, block_order, hint, child_split_count,
    )
    return
  }
  let mut first = true
  for segment_id in bundle.segments {
    enqueue_child_bundle(
      bundles,
      segment_owner,
      queue,
      segments,
      [segment_id],
      block_order,
      if first {
        hint
      } else {
        None
      },
      child_split_count,
    )
    first = false
  }
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
) -> Unit raise VerifyError {
  for bundle in bundles {
    if bundle.state is BundlePending {
      raise InvalidPlan(message="pending allocation bundle after allocation")
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
    if bundle.state is BundleSplit {
      continue
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
  bundle_plan : ProductionBundlePlan,
  strategy : AllocatorStrategy,
) -> (Array[AllocationBundle], Array[Int]) raise VerifyError {
  let enable_eviction = strategy is Backtracking
  let (bundles, segment_owner) = build_allocation_bundles(
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
  let mut probe_id = 0
  let queue = BundleQueue::new(bundles, enable_eviction)
  for bundle in bundles {
    queue.push(bundle.id, None)
  }
  while queue.pop() is Some(entry) {
    let bundle = bundles[entry.bundle]
    if !(bundle.state is BundlePending) {
      continue
    }
    let register_order = bundle_register_order(
      bundle,
      entry.hint,
      segments,
      ranges,
      environment,
      preferred_by_value,
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
      let probe = probe_bundle_register(
        bundle,
        register,
        reg,
        bundles,
        segments,
        segment_owner,
        occupied,
        clobbers,
        ranges.block_order,
        conflict_marks,
        probe_id,
        occupied_stack,
      )
      if !probe.clobbered && probe.conflicts.is_empty() {
        free_register = register
        break
      }
      if bundle_can_evict(enable_eviction, bundle, probe) &&
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
      )
      continue
    }
    if eviction_register >= 0 {
      evict_bundle_conflicts(
        eviction_conflicts, bundles, environment, segments, occupied, queue,
      )
      record_bundle_allocation(
        bundle, eviction_register, environment, segments, occupied, preferred_by_value,
      )
      continue
    }
    let split_hint = if split_register >= 0 {
      Some(environment.allocatable_regs[split_register])
    } else {
      None
    }
    split_bundle_at_conflict(
      bundle,
      split_point,
      split_hint,
      bundles,
      segment_owner,
      queue,
      segments,
      ranges.block_order,
    )
  }
  validate_bundle_allocations(bundles, segments, segment_owner)
  (bundles, segment_owner)
}
