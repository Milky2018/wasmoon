///|
priv struct BundleTestFunction {
  classes : Array[RegClass]
  spill_kinds : Array[Int]
  successors : Array[Array[Int]]
  parameters : Array[Array[VirtualReg]]
  edge_arguments : Array[Array[Array[VirtualReg]]]
}

///|
priv struct BundlePlanSnapshot {
  range_to_bundle : Array[Int]
  segment_to_bundle : Array[Int]
  bundle_ranges : Array[Array[Int]]
  bundle_segments : Array[Array[Int]]
} derive(Debug)

///|
fn bundle_plan_snapshot(plan : ProductionBundlePlan) -> BundlePlanSnapshot {
  {
    range_to_bundle: plan.range_to_bundle,
    segment_to_bundle: plan.segment_to_bundle,
    bundle_ranges: plan.bundle_ranges,
    bundle_segments: plan.bundle_segments,
  }
}

///|
impl FunctionView for BundleTestFunction with fn value_count(self) -> Int {
  self.classes.length()
}

///|
impl FunctionView for BundleTestFunction with fn value_class(self, value) -> RegClass {
  self.classes[value]
}

///|
impl FunctionView for BundleTestFunction with fn value_spill_size(_self, _value) -> Int {
  8
}

///|
impl FunctionView for BundleTestFunction with fn value_spill_alignment(
  _self,
  _value,
) -> Int {
  8
}

///|
impl FunctionView for BundleTestFunction with fn values_share_spill_slot(
  self,
  lhs,
  rhs,
) -> Bool {
  self.spill_kinds[lhs] == self.spill_kinds[rhs]
}

///|
impl FunctionView for BundleTestFunction with fn entry_values(_self) -> ArrayView[
  VirtualReg,
] {
  let empty : Array[VirtualReg] = []
  empty[:]
}

///|
impl FunctionView for BundleTestFunction with fn block_count(self) -> Int {
  self.successors.length()
}

///|
impl FunctionView for BundleTestFunction with fn block_id_at(_self, block) -> Int {
  block
}

///|
impl FunctionView for BundleTestFunction with fn block_parameters(self, block) -> ArrayView[
  VirtualReg,
] {
  self.parameters[block][:]
}

///|
impl FunctionView for BundleTestFunction with fn block_instructions(
  _self,
  _block,
) -> ArrayView[Int] {
  let empty : Array[Int] = []
  empty[:]
}

///|
impl FunctionView for BundleTestFunction with fn block_successors(self, block) -> ArrayView[
  Int,
] {
  self.successors[block][:]
}

///|
impl FunctionView for BundleTestFunction with fn edge_arguments(
  self,
  block,
  successor,
) -> ArrayView[VirtualReg] {
  self.edge_arguments[block][successor][:]
}

///|
impl FunctionView for BundleTestFunction with fn instruction_operands(
  _self,
  _instruction,
) -> ArrayView[Operand] {
  let empty : Array[Operand] = []
  empty[:]
}

///|
impl FunctionView for BundleTestFunction with fn instruction_clobbers(
  _self,
  _instruction,
) -> ArrayView[PhysicalReg] {
  let empty : Array[PhysicalReg] = []
  empty[:]
}

///|
fn bundle_test_range(
  id : Int,
  class : RegClass,
  start : Int,
  end : Int,
  fixed_uses : Array[(UseKind, PhysicalReg)],
) -> LiveRange {
  let range = LiveRange::LiveRange(id, { id, class, })
  range.add_range(ProgramRange(ProgramPoint(0, start), ProgramPoint(0, end)))
  for entry in fixed_uses {
    let (kind, reg) = entry
    range.add_use(UsePosition(ProgramPoint(0, start), kind, FixedReg(reg)))
  }
  range
}

///|
test "segment metadata follows custom block order in one use pass" {
  let r0 : PhysicalReg = { id: 0, class: Int, }
  let r1 : PhysicalReg = { id: 1, class: Int, }
  let ranges = LiveRangeSet::LiveRangeSet([1, 0])
  let range = LiveRange::LiveRange(0, { id: 0, class: Int, })
  range.add_range(ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 1)))
  range.add_range(ProgramRange(ProgramPoint(1, 10), ProgramPoint(1, 11)))
  range.add_use(
    UsePosition(ProgramPoint(0, 0), LiveUse, AnyReg).with_preference(Some(r1)),
  )
  range.add_use(UsePosition(ProgramPoint(1, 10), LiveDef, FixedReg(r0)))
  range.add_use(
    UsePosition(ProgramPoint(0, 1), LiveUse, AnyLocation).with_preference(
      Some(r1),
    ),
  )
  ranges.add_range(range)
  let (segments, _) = build_allocation_segments(ranges, loop_depths=[0], allocatable=[
    r0, r1,
  ])
  debug_inspect(
    segments.map(segment => {
      (
        segment.weight,
        segment.has_fixed_constraint,
        segment.fixed_hint,
        segment.preference_hint,
      )
    }),
    content=(
      #|[
      #|  (2500, true, Some({ id: 0, class: Int }), None),
      #|  (1500, false, None, Some({ id: 1, class: Int })),
      #|]
    ),
  )
}

///|
test "production bundle plan follows transitive SSA edge affinities" {
  let ranges = LiveRangeSet::LiveRangeSet([0, 1, 2])
  let first = bundle_test_range(0, Int, 0, 2, [])
  first.add_range(ProgramRange(ProgramPoint(0, 12), ProgramPoint(0, 14)))
  ranges.add_range(first)
  ranges.add_range(bundle_test_range(1, Int, 4, 6, []))
  ranges.add_range(bundle_test_range(2, Int, 8, 10, []))
  let (segments, _) = build_allocation_segments(ranges)
  let function : BundleTestFunction = {
    classes: [Int, Int, Int],
    spill_kinds: [0, 0, 0],
    successors: [[1], [2], []],
    parameters: [[], [{ id: 1, class: Int, }], [{ id: 2, class: Int, }]],
    edge_arguments: [[[{ id: 0, class: Int, }]], [[{ id: 1, class: Int, }]], []],
  }
  debug_inspect(
    bundle_plan_snapshot(
      build_production_bundle_plan(function, ranges, segments),
    ),
    content=(
      #|{
      #|  range_to_bundle: [0, 0, 0],
      #|  segment_to_bundle: [0, 0, 0, 0],
      #|  bundle_ranges: [[0, 1, 2]],
      #|  bundle_segments: [[0, 2, 3, 1]],
      #|}
    ),
  )
}

///|
test "spill-home groups follow spillset lineage after layout sorting" {
  let ranges = LiveRangeSet::LiveRangeSet([0])
  ranges.add_range(bundle_test_range(2, Int, 4, 6, []))
  ranges.add_range(bundle_test_range(0, Int, 0, 2, []))
  ranges.add_range(bundle_test_range(1, Int, 8, 10, []))
  let (segments, _) = build_allocation_segments(ranges)
  let function : BundleTestFunction = {
    classes: [Int, Int, Int],
    spill_kinds: [0, 0, 1],
    successors: [[]],
    parameters: [[]],
    edge_arguments: [[]],
  }
  let plan = build_production_bundle_plan_from_range_edges(ranges, segments, [
    (0, 1),
  ])
  let spill_sets : Array[SpillSet] = plan.bundle_segments.map(_ => {
    hint: -1,
    spill_bundle: None,
    splits: 0,
  })
  debug_inspect(
    build_spill_home_groups(
      function,
      segments,
      spill_sets,
      plan.segment_to_bundle,
      [true, true, true],
    ),
    content="([0, 0, -1], [[{ id: 0, class: Int }, { id: 1, class: Int }]])",
  )
  debug_inspect(
    build_spill_home_groups(
      { ..function, spill_kinds: [0, 1, 2], },
      segments,
      spill_sets,
      plan.segment_to_bundle,
      [true, true, true],
    ),
    content="([-1, -1, -1], [])",
  )
}

///|
test "production bundle plan rejects incompatible range contracts" {
  let r0 : PhysicalReg = { id: 0, class: Int, }
  let r1 : PhysicalReg = { id: 1, class: Int, }
  let ranges = LiveRangeSet::LiveRangeSet([0])
  ranges.add_range(bundle_test_range(0, Int, 0, 2, []))
  ranges.add_range(bundle_test_range(1, Int, 1, 3, []))
  ranges.add_range(bundle_test_range(2, Float, 4, 6, []))
  ranges.add_range(bundle_test_range(3, Int, 4, 6, [(LiveUse, r0)]))
  ranges.add_range(bundle_test_range(4, Int, 8, 10, [(LiveUse, r1)]))
  ranges.add_range(
    bundle_test_range(5, Int, 12, 14, [(LiveUse, r0), (LiveUse, r1)]),
  )
  ranges.add_range(bundle_test_range(6, Int, 16, 18, []))
  ranges.add_range(bundle_test_range(7, Int, 20, 23, []))
  ranges.add_range(bundle_test_range(8, Int, 23, 25, [(LiveDef, r0)]))
  ranges.add_range(bundle_test_range(9, Int, 26, 28, [(LiveUse, r0)]))
  ranges.add_range(bundle_test_range(10, Int, 30, 32, [(LiveUse, r0)]))
  ranges.add_range(bundle_test_range(11, Int, 34, 37, []))
  ranges.add_range(bundle_test_range(12, Int, 37, 39, []))
  let (segments, _) = build_allocation_segments(ranges)
  debug_inspect(
    bundle_plan_snapshot(
      build_production_bundle_plan_from_range_edges(ranges, segments, [
        (0, 1),
        (0, 2),
        (3, 4),
        (5, 6),
        (7, 8),
        (9, 10),
        (11, 12),
      ]),
    ),
    content=(
      #|{
      #|  range_to_bundle: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 10, 10],
      #|  segment_to_bundle: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 10, 10],
      #|  bundle_ranges: [[0], [1], [2], [3], [4], [5], [6], [7], [8], [9, 10], [11, 12]],
      #|  bundle_segments: [[0], [1], [2], [3], [4], [5], [6], [7], [8], [9, 10], [11, 12]],
      #|}
    ),
  )
}
