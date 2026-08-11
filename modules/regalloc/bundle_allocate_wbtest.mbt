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
    spill_kinds: [0, 0, 0],
    successors: [[1], [2], []],
    parameters: [[], [{ id: 1, class: Int }], [{ id: 2, class: Int }]],
    edge_arguments: [[[{ id: 0, class: Int }]], [[{ id: 1, class: Int }]], []],
  }
  let (segments, _, bundles, segment_owner, _) = allocate_segments_with_bundles(
    function,
    MachineEnv::new([{ id: 0, class: Int }], []),
    ranges,
    Backtracking,
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
    spill_kinds: [0, 0, 0],
    successors: [[]],
    parameters: [[]],
    edge_arguments: [[]],
  }
  let (bundles, segment_owner) = allocate_bundles(
    function,
    MachineEnv::new([r0], []),
    ranges,
    segments,
    plan,
    Backtracking,
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
      weight: 6,
      has_fixed_constraint: false,
      location: None,
    },
    {
      id: 3,
      value: { id: 2, class: Int },
      range: ProgramRange(ProgramPoint(0, 7), ProgramPoint(0, 9)),
      weight: 6,
      has_fixed_constraint: false,
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
  let probe = probe_bundle_register(
    bundles[2],
    0,
    r0,
    bundles,
    segments,
    [0, 1, 2, 2],
    occupied,
    { points_by_reg: Map([]), block_order: [0] },
    [0],
    Array::make(bundles.length(), 0),
    1,
    occupied_stack,
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
      #|  conflict_cost: 5,
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
    bundles.push(
      allocation_bundle(bundles.length(), [segment.id], segments, [0]),
    )
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

///|
test "two-fragment bundle keeps density eviction cost" {
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value: { id: 0, class: Int },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 0)),
      weight: 40,
      has_fixed_constraint: false,
      location: None,
    },
    {
      id: 1,
      value: { id: 0, class: Int },
      range: ProgramRange(ProgramPoint(1, 0), ProgramPoint(1, 0)),
      weight: 20,
      has_fixed_constraint: false,
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
impl FunctionView for ClobberIndexTestFunction with fn entry_values(_self) -> Array[
  VirtualReg,
] {
  []
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
) -> Array[VirtualReg] {
  []
}

///|
impl FunctionView for ClobberIndexTestFunction with fn block_instructions(
  self,
  block,
) -> Array[Int] {
  self.blocks[block].copy()
}

///|
impl FunctionView for ClobberIndexTestFunction with fn block_successors(
  _self,
  _block,
) -> Array[Int] {
  []
}

///|
impl FunctionView for ClobberIndexTestFunction with fn edge_arguments(
  _self,
  _block,
  _successor,
) -> Array[VirtualReg] {
  []
}

///|
impl FunctionView for ClobberIndexTestFunction with fn instruction_operands(
  self,
  instruction,
) -> Array[Operand] {
  self.operands[instruction].copy()
}

///|
impl FunctionView for ClobberIndexTestFunction with fn instruction_clobbers(
  self,
  instruction,
) -> Array[PhysicalReg] {
  self.clobbers[instruction].copy()
}

///|
test "clobber index follows custom block order and fixed operands" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let r2 : PhysicalReg = { id: 2, class: Int }
  let value : VirtualReg = { id: 0, class: Int }
  let function : ClobberIndexTestFunction = {
    blocks: [[0], [1], [2]],
    operands: [[], [Operand::use_reg(value).with_constraint(FixedReg(r1))], []],
    clobbers: [[r0], [], [r0]],
  }
  let index = build_register_clobber_index(function, [2, 0, 1])
  let query = index.query(
    r0,
    ProgramRange(ProgramPoint(1, -1), ProgramPoint(0, 2)),
  )
  debug_inspect(
    (
      index.points_by_reg.get(physical_reg_key(r0)),
      index.points_by_reg.get(physical_reg_key(r1)),
      query,
      index.query(r2, ProgramRange(ProgramPoint(1, -1), ProgramPoint(0, 2))),
    ),
    content=(
      #|(
      #|  Some([{ block: 2, inst: 1 }, { block: 0, inst: 1 }]),
      #|  Some([{ block: 1, inst: 0 }]),
      #|  (Some({ block: 2, inst: 1 }), 3),
      #|  (None, 0),
      #|)
    ),
  )
}

///|
test "clobber query excludes range boundaries and scales logarithmically" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let points = Array::makei(4096, index => ProgramPoint(0, index * 2 + 1))
  let index : RegisterClobberIndex = {
    points_by_reg: Map([(physical_reg_key(r0), points)]),
    block_order: [0],
  }
  debug_inspect(
    (
      index.query(r0, ProgramRange(ProgramPoint(0, 1), ProgramPoint(0, 3))),
      index.query(r0, ProgramRange(ProgramPoint(0, -1), ProgramPoint(0, 1))),
      index.query(r0, ProgramRange(ProgramPoint(0, -1), ProgramPoint(0, 8193))),
    ),
    content="((None, 14), (None, 14), (Some({ block: 0, inst: 1 }), 14))",
  )
}
