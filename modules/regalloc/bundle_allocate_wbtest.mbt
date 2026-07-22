///|
priv enum BundleStateSnapshot {
  SnapshotPending
  SnapshotReg(PhysicalReg)
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
fn snapshot_bundle_state(state : AllocationBundleState) -> BundleStateSnapshot {
  match state {
    BundlePending => SnapshotPending
    BundleReg(reg) => SnapshotReg(reg)
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
test "production allocation assigns an SSA bundle atomically" {
  let ranges = LiveRangeSet::LiveRangeSet([0, 1, 2])
  ranges.add_range(bundle_test_range(0, Int, 0, 2, []))
  ranges.add_range(bundle_test_range(1, Int, 4, 6, []))
  ranges.add_range(bundle_test_range(2, Int, 8, 10, []))
  let function : BundleTestFunction = {
    classes: [Int, Int, Int],
    successors: [[1], [2], []],
    parameters: [[], [{ id: 1, class: Int }], [{ id: 2, class: Int }]],
    edge_arguments: [[[{ id: 0, class: Int }]], [[{ id: 1, class: Int }]], []],
  }
  let (segments, _, bundles, segment_owner) = allocate_segments_backtracking(
    function,
    MachineEnv::new([{ id: 0, class: Int }], []),
    ranges,
    true,
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
      #|      weight: 3,
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
  let r0 : PhysicalReg = { id: 0, class: Int }
  let ranges = LiveRangeSet::LiveRangeSet([0])
  ranges.add_range(bundle_test_range(0, Int, 0, 2, [(LiveUse, r0)]))
  ranges.add_range(bundle_test_range(1, Int, 4, 6, []))
  ranges.add_range(bundle_test_range(2, Int, 4, 6, []))
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value: { id: 0, class: Int },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 2)),
      weight: 2,
      has_fixed_constraint: true,
      location: None,
    },
    {
      id: 1,
      value: { id: 1, class: Int },
      range: ProgramRange(ProgramPoint(0, 4), ProgramPoint(0, 6)),
      weight: 3,
      has_fixed_constraint: false,
      location: None,
    },
    {
      id: 2,
      value: { id: 2, class: Int },
      range: ProgramRange(ProgramPoint(0, 4), ProgramPoint(0, 6)),
      weight: 20,
      has_fixed_constraint: false,
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
    successors: [[]],
    parameters: [[]],
    edge_arguments: [[]],
  }
  let (bundles, segment_owner) = allocate_production_bundles(
    function,
    MachineEnv::new([r0], []),
    ranges,
    segments,
    plan,
    true,
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
      #|      weight: 5,
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
      #|      segments: [0],
      #|      priority: 3,
      #|      weight: 2,
      #|      has_fixed_constraint: true,
      #|      state: SnapshotReg({ id: 0, class: Int }),
      #|    },
      #|    {
      #|      id: 3,
      #|      segments: [1],
      #|      priority: 3,
      #|      weight: 3,
      #|      has_fixed_constraint: false,
      #|      state: SnapshotSpill,
      #|    },
      #|  ],
      #|  segment_owner: [2, 3, 1],
      #|  segment_locations: [
      #|    SnapshotSegmentReg({ id: 0, class: Int }),
      #|    SnapshotSegmentSpill,
      #|    SnapshotSegmentReg({ id: 0, class: Int }),
      #|  ],
      #|}
    ),
  )
}

///|
test "production eviction accounts for and removes every conflicting bundle" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value: { id: 0, class: Int },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 4)),
      weight: 4,
      has_fixed_constraint: false,
      location: Some(SegmentReg(r0)),
    },
    {
      id: 1,
      value: { id: 1, class: Int },
      range: ProgramRange(ProgramPoint(0, 6), ProgramPoint(0, 10)),
      weight: 5,
      has_fixed_constraint: false,
      location: Some(SegmentReg(r0)),
    },
    {
      id: 2,
      value: { id: 2, class: Int },
      range: ProgramRange(ProgramPoint(0, 1), ProgramPoint(0, 3)),
      weight: 5,
      has_fixed_constraint: false,
      location: None,
    },
    {
      id: 3,
      value: { id: 2, class: Int },
      range: ProgramRange(ProgramPoint(0, 7), ProgramPoint(0, 9)),
      weight: 5,
      has_fixed_constraint: false,
      location: None,
    },
  ]
  let bundles : Array[AllocationBundle] = [
    allocation_bundle(0, [0], segments),
    allocation_bundle(1, [1], segments),
    allocation_bundle(2, [2, 3], segments),
  ]
  bundles[0].state = BundleReg(r0)
  bundles[1].state = BundleReg(r0)
  let occupied = [[0, 1]]
  let probe = probe_bundle_register(
    bundles[2],
    0,
    r0,
    bundles,
    segments,
    [0, 1, 2, 2],
    occupied,
    Map([]),
    [0],
  )
  let probe_snapshot : BundleProbeSnapshot = {
    conflicts: probe.conflicts,
    conflict_cost: probe.conflict_cost,
    first_conflict: probe.first_conflict,
    clobbered: probe.clobbered,
    can_evict: bundle_can_evict(true, bundles[2], probe),
  }
  debug_inspect(
    probe_snapshot,
    content=(
      #|{
      #|  conflicts: [0, 1],
      #|  conflict_cost: 9,
      #|  first_conflict: Some({ block: 0, inst: 1 }),
      #|  clobbered: false,
      #|  can_evict: true,
      #|}
    ),
  )
  let queue = BundleQueue::new(bundles, true)
  evict_bundle_conflicts(
    probe.conflicts,
    bundles,
    MachineEnv::new([r0], []),
    segments,
    occupied,
    queue,
  )
  let requeued : Array[Int] = []
  while queue.pop() is Some(entry) {
    requeued.push(entry.bundle)
  }
  let eviction_snapshot : BundleEvictionSnapshot = {
    bundles: snapshot_bundles(bundles),
    segment_locations: segments.map(segment => {
      snapshot_segment_location(segment.location)
    }),
    occupied,
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
      #|      weight: 10,
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
}

///|
test "production bundle queue keeps live extent separate from spill weight" {
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value: { id: 0, class: Int },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 0)),
      weight: 100,
      has_fixed_constraint: false,
      location: None,
    },
    {
      id: 1,
      value: { id: 1, class: Int },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 4)),
      weight: 10,
      has_fixed_constraint: false,
      location: None,
    },
    {
      id: 2,
      value: { id: 2, class: Int },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 2)),
      weight: 50,
      has_fixed_constraint: false,
      location: None,
    },
  ]
  let bundles : Array[AllocationBundle] = []
  for segment in segments {
    bundles.push(allocation_bundle(bundles.length(), [segment.id], segments))
  }
  let queue = BundleQueue::new(bundles, true)
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
