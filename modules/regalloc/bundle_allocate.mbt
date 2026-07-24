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
fn allocation_bundle(
  id : Int,
  segment_ids : Array[Int],
  segments : Array[AllocationSegment],
) -> AllocationBundle {
  let mut priority = 0
  let mut weight = 0
  let mut has_fixed_constraint = false
  for segment_id in segment_ids {
    priority += allocation_segment_priority(segments[segment_id])
    weight += segments[segment_id].weight
    has_fixed_constraint = has_fixed_constraint ||
      segments[segment_id].has_fixed_constraint
  }
  {
    id,
    segments: segment_ids.copy(),
    priority: priority.max(1),
    weight: weight.max(1),
    has_fixed_constraint,
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
) -> (Array[AllocationBundle], Array[Int]) {
  let bundles : Array[AllocationBundle] = []
  let segment_owner = Array::make(segments.length(), -1)
  for segment_ids in plan.bundle_segments {
    let bundle = allocation_bundle(bundles.length(), segment_ids, segments)
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
  occupied : Array[Array[Int]],
  clobbers : RegisterClobberIndex,
  block_order : Array[Int],
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
    for
      conflict_segment in conflicting_segments(
        segments,
        occupied[register],
        segment,
        block_order,
      ) {
      let owner = segment_owner[conflict_segment]
      if owner == bundle.id || conflicts.contains(owner) {
        continue
      }
      conflicts.push(owner)
      conflict_cost += bundles[owner].weight
      let point = later_point(
        segment.range.start,
        segments[conflict_segment].range.start,
        block_order,
      )
      first_conflict = Some(
        earlier_conflict_point(first_conflict, point, block_order),
      )
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
  edge_affinities : Array[Array[Int]],
  is_edge_argument : Array[Bool],
  edge_target_registers : Array[Bool],
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
    for related in edge_affinities[segment.value.id] {
      push_bundle_register_candidates(
        order,
        environment.allocatable_regs,
        preferred_by_value[related],
      )
    }
  }
  let mut has_edge_argument = false
  for segment_id in bundle.segments {
    has_edge_argument = has_edge_argument ||
      is_edge_argument[segments[segment_id].value.id]
  }
  if has_edge_argument {
    for register in 0..<environment.allocatable_regs.length() {
      if !edge_target_registers[register] {
        push_register_candidate(order, Some(register))
      }
    }
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
  occupied : Array[Array[Int]],
) -> Unit {
  guard bundle.state is BundleReg(reg) else { return }
  let register = register_index(environment.allocatable_regs, reg).unwrap()
  for segment_id in bundle.segments {
    remove_occupied_segment(occupied, register, segment_id)
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
  occupied : Array[Array[Int]],
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
  occupied : Array[Array[Int]],
  block_order : Array[Int],
  preferred_by_value : Array[PhysicalReg?],
  is_edge_target : Array[Bool],
  edge_target_registers : Array[Bool],
) -> Unit {
  let reg = environment.allocatable_regs[register]
  for segment_id in bundle.segments {
    let segment = segments[segment_id]
    segment.location = Some(SegmentReg(reg))
    preferred_by_value[segment.value.id] = Some(reg)
    if is_edge_target[segment.value.id] {
      edge_target_registers[register] = true
    }
    insert_occupied_segment(
      segments,
      occupied[register],
      segment_id,
      block_order,
    )
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
  hint : PhysicalReg?,
) -> Unit {
  let child = allocation_bundle(bundles.length(), segment_ids, segments)
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
  if !before.is_empty() && !after.is_empty() {
    enqueue_child_bundle(bundles, segment_owner, queue, segments, before, hint)
    enqueue_child_bundle(bundles, segment_owner, queue, segments, after, hint)
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
      if first {
        hint
      } else {
        None
      },
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
fn validate_bundle_allocations(
  bundles : Array[AllocationBundle],
  segments : Array[AllocationSegment],
  segment_owner : Array[Int],
) -> Unit {
  for bundle in bundles {
    if bundle.state is BundlePending {
      abort("pending allocation bundle after allocation")
    }
    let mut priority = 0
    let mut weight = 0
    let mut has_fixed_constraint = false
    for segment_id in bundle.segments {
      priority += allocation_segment_priority(segments[segment_id])
      weight += segments[segment_id].weight
      has_fixed_constraint = has_fixed_constraint ||
        segments[segment_id].has_fixed_constraint
    }
    if bundle.priority != priority.max(1) {
      abort("allocation bundle lost queue priority")
    }
    if bundle.weight != weight.max(1) {
      abort("allocation bundle lost use weight")
    }
    if has_fixed_constraint != bundle.has_fixed_constraint {
      abort("allocation bundle lost fixed constraints")
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
      abort("invalid allocation bundle ownership")
    }
    match (bundles[owner].state, segment.location) {
      (BundleReg(expected), Some(SegmentReg(actual))) if expected == actual =>
        ()
      (BundleSpill, Some(SegmentSpill)) => ()
      _ => abort("incomplete atomic bundle allocation")
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
) -> (Array[AllocationBundle], Array[Int]) {
  let enable_eviction = strategy is Backtracking
  let (bundles, segment_owner) = build_allocation_bundles(bundle_plan, segments)
  let occupied : Array[Array[Int]] = []
  for _ in environment.allocatable_regs {
    occupied.push([])
  }
  let clobbers = build_register_clobber_index(function, ranges.block_order)
  let preferred_by_value : Array[PhysicalReg?] = Array::make(
    function.value_count(),
    None,
  )
  let (edge_affinities, is_edge_argument, is_edge_target) = build_edge_affinities(
    function,
  )
  let edge_target_registers = Array::make(
    environment.allocatable_regs.length(),
    false,
  )
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
      edge_affinities,
      is_edge_argument,
      edge_target_registers,
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
        bundle,
        free_register,
        environment,
        segments,
        occupied,
        ranges.block_order,
        preferred_by_value,
        is_edge_target,
        edge_target_registers,
      )
      continue
    }
    if eviction_register >= 0 {
      evict_bundle_conflicts(
        eviction_conflicts, bundles, environment, segments, occupied, queue,
      )
      record_bundle_allocation(
        bundle,
        eviction_register,
        environment,
        segments,
        occupied,
        ranges.block_order,
        preferred_by_value,
        is_edge_target,
        edge_target_registers,
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
