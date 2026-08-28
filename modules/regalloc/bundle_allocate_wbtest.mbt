///|
priv enum BundleStateSnapshot {
  SnapshotPending
  SnapshotReg(PhysicalReg)
  SnapshotDeferredSpill
  SnapshotSpill
  SnapshotSplit
} derive(Debug)

///|
priv enum SegmentLocationSnapshot {
  SnapshotUnallocated
  SnapshotSegmentReg(PhysicalReg)
  SnapshotSegmentSpill
} derive(Debug)

///|
priv struct BundleSnapshot {
  id : Int
  segments : Array[Int]
  priority : Int
  weight : Int
  has_fixed_constraint : Bool
  state : BundleStateSnapshot
} derive(Debug)

///|
priv struct BundleQueueSnapshot {
  bundles : Array[BundleSnapshot]
  order : Array[Int]
} derive(Debug)

///|
priv struct BundleAllocationSnapshot {
  bundles : Array[BundleSnapshot]
  segment_owner : Array[Int]
  segment_locations : Array[SegmentLocationSnapshot]
} derive(Debug)

///|
priv struct BundleProbeSnapshot {
  conflicts : Array[Int]
  conflict_cost : Int
  first_conflict : ProgramPoint?
  clobbered : Bool
  can_evict : Bool
} derive(Debug)

///|
priv struct BundleEvictionSnapshot {
  bundles : Array[BundleSnapshot]
  segment_locations : Array[SegmentLocationSnapshot]
  occupied : Array[Array[Int]]
  requeued : Array[Int]
} derive(Debug)

///|
priv struct GapSplitSnapshot {
  before : Int?
  spill : Int
  after : Int?
  ranges : Array[ProgramRange]
  owners : Array[Int]
  spill_sets : Array[Int]
  use_free : Array[Bool]
  weights : Array[Int]
} derive(Debug)

///|
fn snapshot_bundle_state(state : AllocationBundleState) -> BundleStateSnapshot {
  match state {
    BundlePending => SnapshotPending
    BundleReg(reg) => SnapshotReg(reg)
    BundleDeferredSpill => SnapshotDeferredSpill
    BundleSpill => SnapshotSpill
    BundleSplit => SnapshotSplit
  }
}

///|
fn snapshot_segment_location(
  location : SegmentLocation?,
) -> SegmentLocationSnapshot {
  match location {
    None => SnapshotUnallocated
    Some(SegmentReg(reg)) => SnapshotSegmentReg(reg)
    Some(SegmentSpill) => SnapshotSegmentSpill
  }
}

///|
fn snapshot_bundles(bundles : Array[AllocationBundle]) -> Array[BundleSnapshot] {
  bundles.map(bundle => {
    id: bundle.id,
    segments: bundle.segments,
    priority: bundle.priority,
    weight: bundle.weight,
    has_fixed_constraint: bundle.has_fixed_constraint,
    state: snapshot_bundle_state(bundle.state),
  })
}

///|
fn snapshot_bundle_allocation(
  bundles : Array[AllocationBundle],
  segments : Array[AllocationSegment],
  segment_owner : Array[Int],
) -> BundleAllocationSnapshot {
  {
    bundles: snapshot_bundles(bundles),
    segment_owner,
    segment_locations: segments.map(segment => {
      snapshot_segment_location(segment.location)
    }),
  }
}

///|
test "range split isolates the use-free gap and preserves spillset lineage" {
  let ranges = LiveRangeSet::LiveRangeSet([0])
  let live_range = bundle_test_range(0, Int, 0, 10, [])
  live_range.add_use(UsePosition(ProgramPoint(0, 0), LiveDef, AnyLocation))
  live_range.add_use(UsePosition(ProgramPoint(0, 10), LiveUse, AnyReg))
  ranges.add_range(live_range)
  let (segments, segments_by_value) = build_allocation_segments(ranges)
  let owners = [4]
  let spill_sets = [0]
  let occupied = RegisterAllocationIndex::new(1, segments, [0])
  let parts = split_segment_around_gap(
    0,
    ProgramPoint(0, 5),
    segments,
    segments_by_value,
    owners,
    spill_sets,
    occupied,
    ranges,
    [0],
    [],
  ).unwrap()
  debug_inspect(
    GapSplitSnapshot::{
      before: parts.before,
      spill: parts.spill,
      after: parts.after,
      ranges: segments.map(segment => segment.range),
      owners,
      spill_sets,
      use_free: segments.map(segment => segment_carries_no_use(segment, ranges)),
      weights: segments.map(segment => segment.weight),
    },
    content=(
      #|{
      #|  before: Some(0),
      #|  spill: 1,
      #|  after: Some(2),
      #|  ranges: [
      #|    { start: { block: 0, inst: 0 }, end: { block: 0, inst: 0 } },
      #|    { start: { block: 0, inst: 1 }, end: { block: 0, inst: 9 } },
      #|    { start: { block: 0, inst: 10 }, end: { block: 0, inst: 10 } },
      #|  ],
      #|  owners: [4, 4, 4],
      #|  spill_sets: [0, 0, 0],
      #|  use_free: [false, true, false],
      #|  weights: [3000, 1, 2000],
      #|}
    ),
  )
}

///|
test "spill bundle is normalized before conflict probes" {
  let r0 : PhysicalReg = { id: 0, class: Int, }
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value: { id: 0, class: Int, },
      range: ProgramRange(ProgramPoint(0, 5), ProgramPoint(0, 20)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: Some(SegmentReg(r0)),
    },
    {
      id: 1,
      value: { id: 1, class: Int, },
      range: ProgramRange(ProgramPoint(1, 0), ProgramPoint(1, 0)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
    {
      id: 2,
      value: { id: 2, class: Int, },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 10)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
  ]
  let bundles = [allocation_bundle(0, [0], segments, [0, 1])]
  bundles[0].state = BundleReg(r0)
  let owners = [0, -1, -1]
  let spill_sets : Array[SpillSet] = [
    { hint: None, spill_bundle: None, splits: 0, },
  ]
  add_to_spill_bundle(0, 1, bundles, owners, spill_sets, segments, [0, 1])
  add_to_spill_bundle(0, 2, bundles, owners, spill_sets, segments, [0, 1])
  prepare_spill_bundle(bundles[1], segments, [0, 1])
  let occupied = RegisterAllocationIndex::new(1, segments, [0, 1])
  occupied.insert(0, 0)
  let probe_conflicts : Array[Int] = []
  let probe = BundleRegisterProbe::new(probe_conflicts)
  let statistics = BundleAllocationStatistics::new()
  probe_bundle_register(
    bundles[1],
    0,
    r0,
    bundles,
    segments,
    owners,
    occupied,
    { points_by_reg: Map([]), block_order: [0, 1], },
    [0, 1],
    Array::make(bundles.length(), 0),
    1,
    [],
    probe_conflicts,
    probe,
    statistics,
    conflict_policy=RejectAnyConflict,
  )
  debug_inspect(
    (bundles[1].segments, probe.cutoff_exceeded, probe.conflicts),
    content="([2, 1], true, [0])",
  )
}

///|
test "spillset defers to second chance after two normal splits" {
  let ranges = LiveRangeSet::LiveRangeSet([0])
  let range = bundle_test_range(0, Int, 0, 30, [])
  for instruction in [0, 10, 20, 30] {
    range.add_use(UsePosition(ProgramPoint(0, instruction), LiveUse, AnyReg))
  }
  ranges.add_range(range)
  let (segments, segments_by_value) = build_allocation_segments(ranges)
  let plan : ProductionBundlePlan = {
    range_to_bundle: [0],
    segment_to_bundle: [0],
    bundle_ranges: [[0]],
    bundle_segments: [[0]],
  }
  let (bundles, owners, spill_sets, segment_spill_sets) = build_allocation_bundles(
    plan,
    segments,
    [0],
  )
  let queue = BundleQueue::new(bundles)
  let occupied = RegisterAllocationIndex::new(1, segments, [0])
  let split_points = [5, 15, 25]
  let statistics = BundleAllocationStatistics::new()
  let mut current_bundle = 0
  for index, instruction in split_points {
    inspect(
      split_bundle_at_conflict(
        bundles[current_bundle],
        Some(ProgramPoint(0, instruction)),
        None,
        bundles,
        owners,
        queue,
        segments,
        segments_by_value,
        segment_spill_sets,
        spill_sets,
        occupied,
        ranges,
        [0],
        [],
        statistics,
      ),
      content="true",
    )
    if index + 1 < split_points.length() {
      let next_point = ProgramPoint(0, split_points[index + 1])
      let mut next_bundle = -1
      for candidate in bundles {
        if candidate.state is BundlePending {
          for segment_id in candidate.segments {
            if segments[segment_id].range.contains(next_point, [0]) {
              next_bundle = candidate.id
            }
          }
        }
      }
      inspect(next_bundle >= 0, content="true")
      current_bundle = next_bundle
    }
  }
  let spill_bundle = bundles[spill_sets[0].spill_bundle.unwrap()]
  let pending = bundles.filter(bundle => bundle.state is BundlePending)
  let deferred = bundles.filter(bundle => bundle.state is BundleDeferredSpill)
  debug_inspect(
    (
      spill_sets[0].splits,
      pending.length(),
      pending.all(bundle => bundle.minimal),
      deferred.length(),
      bundles[current_bundle].state is BundleDeferredSpill,
    ),
    content="(2, 2, true, 2, true)",
  )
  debug_inspect(
    spill_bundle.segments.map(segment_id => segments[segment_id].range),
    content=(
      #|[
      #|  { start: { block: 0, inst: 1 }, end: { block: 0, inst: 9 } },
      #|  { start: { block: 0, inst: 11 }, end: { block: 0, inst: 19 } },
      #|]
    ),
  )
}

///|
test "production allocation assigns an SSA bundle atomically" {
  let ranges = LiveRangeSet::LiveRangeSet([0, 1, 2])
  ranges.add_range(bundle_test_range(0, Int, 0, 2, []))
  ranges.add_range(bundle_test_range(1, Int, 4, 6, []))
  ranges.add_range(bundle_test_range(2, Int, 8, 10, []))
  let function : BundleTestFunction = {
    classes: [Int, Int, Int],
    spill_kinds: [0, 0, 0],
    successors: [[1], [2], []],
    parameters: [[], [{ id: 1, class: Int, }], [{ id: 2, class: Int, }]],
    edge_arguments: [[[{ id: 0, class: Int, }]], [[{ id: 1, class: Int, }]], []],
  }
  let (segments, _, bundles, segment_owner, _, _) = allocate_segments_with_bundles(
    function,
    MachineEnv::new([{ id: 0, class: Int, }], []),
    ranges,
  )
  debug_inspect(
    snapshot_bundle_allocation(bundles, segments, segment_owner),
    content=(
      #|{
      #|  bundles: [
      #|    {
      #|      id: 0,
      #|      segments: [0, 1, 2],
      #|      priority: 9,
      #|      weight: 1,
      #|      has_fixed_constraint: false,
      #|      state: SnapshotReg({ id: 0, class: Int }),
      #|    },
      #|  ],
      #|  segment_owner: [0, 0, 0],
      #|  segment_locations: [
      #|    SnapshotSegmentReg({ id: 0, class: Int }),
      #|    SnapshotSegmentReg({ id: 0, class: Int }),
      #|    SnapshotSegmentReg({ id: 0, class: Int }),
      #|  ],
      #|}
    ),
  )
}

///|
test "production allocation evicts then splits a cheaper long bundle" {
  let r0 : PhysicalReg = { id: 0, class: Int, }
  let ranges = LiveRangeSet::LiveRangeSet([0])
  ranges.add_range(bundle_test_range(0, Int, 0, 2, [(LiveUse, r0)]))
  ranges.add_range(bundle_test_range(1, Int, 4, 6, []))
  ranges.add_range(bundle_test_range(2, Int, 4, 6, []))
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value: { id: 0, class: Int, },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 2)),
      weight: 2,
      has_fixed_constraint: true,
      fixed_hint: Some(r0),
      preference_hint: None,
      location: None,
    },
    {
      id: 1,
      value: { id: 1, class: Int, },
      range: ProgramRange(ProgramPoint(0, 4), ProgramPoint(0, 6)),
      weight: 3,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
    {
      id: 2,
      value: { id: 2, class: Int, },
      range: ProgramRange(ProgramPoint(0, 4), ProgramPoint(0, 6)),
      weight: 20,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
  ]
  let plan : ProductionBundlePlan = {
    range_to_bundle: [0, 0, 1],
    segment_to_bundle: [0, 0, 1],
    bundle_ranges: [[0, 1], [2]],
    bundle_segments: [[0, 1], [2]],
  }
  plan.validate(3, 3)
  let function : BundleTestFunction = {
    classes: [Int, Int, Int],
    spill_kinds: [0, 0, 0],
    successors: [[]],
    parameters: [[]],
    edge_arguments: [[]],
  }
  let (bundles, segment_owner, _, _, statistics) = allocate_bundles(
    function,
    MachineEnv::new([r0], []),
    ranges,
    segments,
    [[0], [1], [2]],
    [0],
    plan,
  )
  debug_inspect(
    snapshot_bundle_allocation(bundles, segments, segment_owner),
    content=(
      #|{
      #|  bundles: [
      #|    {
      #|      id: 0,
      #|      segments: [0, 1],
      #|      priority: 6,
      #|      weight: 3,
      #|      has_fixed_constraint: true,
      #|      state: SnapshotSplit,
      #|    },
      #|    {
      #|      id: 1,
      #|      segments: [2],
      #|      priority: 3,
      #|      weight: 20,
      #|      has_fixed_constraint: false,
      #|      state: SnapshotReg({ id: 0, class: Int }),
      #|    },
      #|    {
      #|      id: 2,
      #|      segments: [1],
      #|      priority: 3,
      #|      weight: 3,
      #|      has_fixed_constraint: false,
      #|      state: SnapshotSpill,
      #|    },
      #|    {
      #|      id: 3,
      #|      segments: [0],
      #|      priority: 3,
      #|      weight: 1,
      #|      has_fixed_constraint: true,
      #|      state: SnapshotReg({ id: 0, class: Int }),
      #|    },
      #|  ],
      #|  segment_owner: [3, 2, 1],
      #|  segment_locations: [
      #|    SnapshotSegmentReg({ id: 0, class: Int }),
      #|    SnapshotSegmentSpill,
      #|    SnapshotSegmentReg({ id: 0, class: Int }),
      #|  ],
      #|}
    ),
  )
  inspect(statistics.queue_pops() > 0, content="true")
  inspect(statistics.register_probes() > 0, content="true")
  inspect(statistics.occupied_segments_scanned() > 0, content="true")
  inspect(statistics.bundle_splits() > 0, content="true")
}

///|
test "production eviction accounts for and removes every conflicting bundle" {
  let r0 : PhysicalReg = { id: 0, class: Int, }
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value: { id: 0, class: Int, },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 4)),
      weight: 4,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: Some(SegmentReg(r0)),
    },
    {
      id: 1,
      value: { id: 1, class: Int, },
      range: ProgramRange(ProgramPoint(0, 6), ProgramPoint(0, 10)),
      weight: 5,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: Some(SegmentReg(r0)),
    },
    {
      id: 2,
      value: { id: 2, class: Int, },
      range: ProgramRange(ProgramPoint(0, 1), ProgramPoint(0, 3)),
      weight: 6,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
    {
      id: 3,
      value: { id: 2, class: Int, },
      range: ProgramRange(ProgramPoint(0, 7), ProgramPoint(0, 9)),
      weight: 6,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
  ]
  let bundles : Array[AllocationBundle] = [
    allocation_bundle(0, [0], segments, [0]),
    allocation_bundle(1, [1], segments, [0]),
    allocation_bundle(2, [2, 3], segments, [0]),
  ]
  bundles[0].state = BundleReg(r0)
  bundles[1].state = BundleReg(r0)
  let occupied = RegisterAllocationIndex::new(1, segments, [0])
  occupied.insert(0, 0)
  occupied.insert(0, 1)
  let occupied_stack : Array[Int] = []
  let probe_conflicts : Array[Int] = []
  let probe = BundleRegisterProbe::new(probe_conflicts)
  let statistics = BundleAllocationStatistics::new()
  probe_bundle_register(
    bundles[2],
    0,
    r0,
    bundles,
    segments,
    [0, 1, 2, 2],
    occupied,
    { points_by_reg: Map([]), block_order: [0], },
    [0],
    Array::make(bundles.length(), 0),
    1,
    occupied_stack,
    probe_conflicts,
    probe,
    statistics,
    conflict_policy=Unlimited,
  )
  let probe_snapshot : BundleProbeSnapshot = {
    conflicts: probe.conflicts,
    conflict_cost: probe.conflict_cost,
    first_conflict: probe.first_conflict,
    clobbered: probe.clobbered,
    can_evict: !probe.clobbered &&
    !probe.conflicts.is_empty() &&
    probe.conflict_cost < bundles[2].weight,
  }
  debug_inspect(
    probe_snapshot,
    content=(
      #|{
      #|  conflicts: [0, 1],
      #|  conflict_cost: 5,
      #|  first_conflict: Some({ block: 0, inst: 1 }),
      #|  clobbered: false,
      #|  can_evict: true,
      #|}
    ),
  )
  let queue = BundleQueue::new(bundles)
  evict_bundle_conflicts(
    probe.conflicts,
    bundles,
    MachineEnv::new([r0], []),
    segments,
    occupied,
    queue,
    statistics,
  )
  let requeued : Array[Int] = []
  while queue.pop() is Some(entry) {
    requeued.push(entry.bundle)
  }
  let remaining : Array[Int] = []
  occupied.seek(0, ProgramPoint(0, -1), occupied_stack)
  while occupied.next(occupied_stack) is Some(segment) {
    remaining.push(segment)
  }
  let eviction_snapshot : BundleEvictionSnapshot = {
    bundles: snapshot_bundles(bundles),
    segment_locations: segments.map(segment => {
      snapshot_segment_location(segment.location)
    }),
    occupied: [remaining],
    requeued,
  }
  debug_inspect(
    eviction_snapshot,
    content=(
      #|{
      #|  bundles: [
      #|    {
      #|      id: 0,
      #|      segments: [0],
      #|      priority: 5,
      #|      weight: 4,
      #|      has_fixed_constraint: false,
      #|      state: SnapshotPending,
      #|    },
      #|    {
      #|      id: 1,
      #|      segments: [1],
      #|      priority: 5,
      #|      weight: 5,
      #|      has_fixed_constraint: false,
      #|      state: SnapshotPending,
      #|    },
      #|    {
      #|      id: 2,
      #|      segments: [2, 3],
      #|      priority: 6,
      #|      weight: 6,
      #|      has_fixed_constraint: false,
      #|      state: SnapshotPending,
      #|    },
      #|  ],
      #|  segment_locations: [
      #|    SnapshotUnallocated,
      #|    SnapshotUnallocated,
      #|    SnapshotUnallocated,
      #|    SnapshotUnallocated,
      #|  ],
      #|  occupied: [[]],
      #|  requeued: [0, 1],
      #|}
    ),
  )
  let cutoff_occupied = RegisterAllocationIndex::new(1, segments, [0])
  cutoff_occupied.insert(0, 0)
  cutoff_occupied.insert(0, 1)
  let cutoff_conflicts : Array[Int] = []
  let cutoff_probe = BundleRegisterProbe::new(cutoff_conflicts)
  probe_bundle_register(
    bundles[2],
    0,
    r0,
    bundles,
    segments,
    [0, 1, 2, 2],
    cutoff_occupied,
    { points_by_reg: Map([]), block_order: [0], },
    [0],
    Array::make(bundles.length(), 0),
    1,
    occupied_stack,
    cutoff_conflicts,
    cutoff_probe,
    statistics,
    conflict_policy=CostLimit(4),
  )
  debug_inspect(
    (
      cutoff_probe.cutoff_exceeded,
      cutoff_probe.conflicts,
      cutoff_probe.conflict_cost,
      cutoff_probe.first_conflict,
    ),
    content="(true, [0, 1], 5, Some({ block: 0, inst: 1 }))",
  )
}

///|
test "production bundle queue keeps live extent separate from spill weight" {
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value: { id: 0, class: Int, },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 0)),
      weight: 100,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
    {
      id: 1,
      value: { id: 1, class: Int, },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 4)),
      weight: 10,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
    {
      id: 2,
      value: { id: 2, class: Int, },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 2)),
      weight: 50,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
  ]
  let bundles : Array[AllocationBundle] = []
  for segment in segments {
    bundles.push(
      allocation_bundle(bundles.length(), [segment.id], segments, [0]),
    )
  }
  let queue = BundleQueue::new(bundles)
  for bundle in bundles {
    queue.push(bundle.id, None)
  }
  let order : Array[Int] = []
  while queue.pop() is Some(entry) {
    order.push(entry.bundle)
  }
  let snapshot : BundleQueueSnapshot = {
    bundles: snapshot_bundles(bundles),
    order,
  }
  debug_inspect(
    snapshot,
    content=(
      #|{
      #|  bundles: [
      #|    {
      #|      id: 0,
      #|      segments: [0],
      #|      priority: 1,
      #|      weight: 100,
      #|      has_fixed_constraint: false,
      #|      state: SnapshotPending,
      #|    },
      #|    {
      #|      id: 1,
      #|      segments: [1],
      #|      priority: 5,
      #|      weight: 10,
      #|      has_fixed_constraint: false,
      #|      state: SnapshotPending,
      #|    },
      #|    {
      #|      id: 2,
      #|      segments: [2],
      #|      priority: 3,
      #|      weight: 50,
      #|      has_fixed_constraint: false,
      #|      state: SnapshotPending,
      #|    },
      #|  ],
      #|  order: [1, 2, 0],
      #|}
    ),
  )
}

///|
test "two-fragment bundle keeps density eviction cost" {
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value: { id: 0, class: Int, },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 0)),
      weight: 40,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
    {
      id: 1,
      value: { id: 0, class: Int, },
      range: ProgramRange(ProgramPoint(1, 0), ProgramPoint(1, 0)),
      weight: 20,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
  ]
  inspect(allocation_bundle(0, [0, 1], segments, [0, 1]).weight, content="30")
}

///|
priv struct ClobberIndexTestFunction {
  blocks : Array[Array[Int]]
  operands : Array[Array[Operand]]
  clobbers : Array[Array[PhysicalReg]]
}

///|
impl FunctionView for ClobberIndexTestFunction with fn value_count(_self) -> Int {
  1
}

///|
impl FunctionView for ClobberIndexTestFunction with fn value_class(
  _self,
  _value,
) -> RegClass {
  Int
}

///|
impl FunctionView for ClobberIndexTestFunction with fn value_spill_size(
  _self,
  _value,
) -> Int {
  8
}

///|
impl FunctionView for ClobberIndexTestFunction with fn value_spill_alignment(
  _self,
  _value,
) -> Int {
  8
}

///|
impl FunctionView for ClobberIndexTestFunction with fn values_share_spill_slot(
  _self,
  _lhs,
  _rhs,
) -> Bool {
  true
}

///|
impl FunctionView for ClobberIndexTestFunction with fn entry_values(_self) -> ArrayView[
  VirtualReg,
] {
  let empty : Array[VirtualReg] = []
  empty[:]
}

///|
impl FunctionView for ClobberIndexTestFunction with fn block_count(self) -> Int {
  self.blocks.length()
}

///|
impl FunctionView for ClobberIndexTestFunction with fn block_id_at(_self, block) -> Int {
  block + 100
}

///|
impl FunctionView for ClobberIndexTestFunction with fn block_parameters(
  _self,
  _block,
) -> ArrayView[VirtualReg] {
  let empty : Array[VirtualReg] = []
  empty[:]
}

///|
impl FunctionView for ClobberIndexTestFunction with fn block_instructions(
  self,
  block,
) -> ArrayView[Int] {
  self.blocks[block][:]
}

///|
impl FunctionView for ClobberIndexTestFunction with fn block_successors(
  _self,
  _block,
) -> ArrayView[Int] {
  let empty : Array[Int] = []
  empty[:]
}

///|
impl FunctionView for ClobberIndexTestFunction with fn edge_arguments(
  _self,
  _block,
  _successor,
) -> ArrayView[VirtualReg] {
  let empty : Array[VirtualReg] = []
  empty[:]
}

///|
impl FunctionView for ClobberIndexTestFunction with fn instruction_operands(
  self,
  instruction,
) -> ArrayView[Operand] {
  self.operands[instruction][:]
}

///|
impl FunctionView for ClobberIndexTestFunction with fn instruction_clobbers(
  self,
  instruction,
) -> ArrayView[PhysicalReg] {
  self.clobbers[instruction][:]
}

///|
test "clobber index follows custom block order and fixed operands" {
  let r0 : PhysicalReg = { id: 0, class: Int, }
  let r1 : PhysicalReg = { id: 1, class: Int, }
  let r2 : PhysicalReg = { id: 2, class: Int, }
  let value : VirtualReg = { id: 0, class: Int, }
  let function : ClobberIndexTestFunction = {
    blocks: [[0], [1], [2]],
    operands: [[], [Operand::use_reg(value).with_constraint(FixedReg(r1))], []],
    clobbers: [[r0], [], [r0]],
  }
  let index = build_register_clobber_index(function, [2, 0, 1])
  debug_inspect(
    (
      index.points_by_reg.get(physical_reg_key(r0)),
      index.points_by_reg.get(physical_reg_key(r1)),
      index.points_by_reg.get(physical_reg_key(r2)),
    ),
    content=(
      #|(
      #|  Some([{ block: 2, inst: 0 }, { block: 0, inst: 0 }]),
      #|  Some([{ block: 1, inst: 0 }]),
      #|  None,
      #|)
    ),
  )
}

///|
test "clobber intersection includes starts and excludes ends" {
  let r0 : PhysicalReg = { id: 0, class: Int, }
  let index : RegisterClobberIndex = {
    points_by_reg: Map([
      (
        physical_reg_key(r0),
        [
          ProgramPoint(0, 1),
          ProgramPoint(0, 3),
          ProgramPoint(0, 5),
          ProgramPoint(0, 7),
          ProgramPoint(0, 9),
        ],
      ),
    ]),
    block_order: [0],
  }
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value: { id: 0, class: Int, },
      range: ProgramRange(ProgramPoint(0, 1), ProgramPoint(0, 3)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
    {
      id: 1,
      value: { id: 0, class: Int, },
      range: ProgramRange(ProgramPoint(0, 6), ProgramPoint(0, 9)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
  ]
  debug_inspect(
    index.first_intersection(r0, [0, 1], segments),
    content="Some({ block: 0, inst: 1 })",
  )
}
