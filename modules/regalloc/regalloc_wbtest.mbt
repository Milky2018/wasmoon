///|
test "live range lookup uses a direct per-class dense index" {
  let ranges = LiveRangeSet::LiveRangeSet([])
  let int_reg : VirtualReg = { id: 4096, class: Int, }
  let float_reg : VirtualReg = { id: 4096, class: Float, }
  ranges.add_range(LiveRange(0, int_reg))
  ranges.add_range(LiveRange(1, float_reg))
  debug_inspect(
    (
      ranges.int_ranges_by_id.length(),
      ranges.float_ranges_by_id.length(),
      ranges.vector_ranges_by_id.length(),
      ranges.get_by_vreg(int_reg).map(range => range.id()),
      ranges.get_by_vreg(float_reg).map(range => range.id()),
    ),
    content="(4097, 4097, 0, Some(0), Some(1))",
  )
}

///|
test "sparse vreg set promotes and unions high virtual register ids" {
  let left = SparseVRegSet::new()
  for id in [0, 64, 128, 192, 256, 320, 384, 448, 512] {
    left.set(id, true)
  }
  let right = SparseVRegSet::new()
  right.set(1_000_000, true)
  right.set(128, true)
  inspect(left.union_with(right), content="true")
  inspect(left.union_with(right), content="false")
  debug_inspect(
    left.to_sorted_array(),
    content="[0, 64, 128, 192, 256, 320, 384, 448, 512, 1000000]",
  )
  left.set(1_000_000, false)
  debug_inspect(
    left.to_sorted_array(),
    content="[0, 64, 128, 192, 256, 320, 384, 448, 512]",
  )
}

///|
test "sparse live sets preserve defs and successor propagation" {
  let cfg : DenseCfgEdges = { preds: [[], [0], [1]], succs: [[1], [2], []], }
  let defs = [SparseVRegSet::new(), SparseVRegSet::new(), SparseVRegSet::new()]
  let live_in = [
    SparseVRegSet::new(),
    SparseVRegSet::new(),
    SparseVRegSet::new(),
  ]
  defs[0].set(1_000_000, true)
  live_in[2].set(1_000_000, true)
  let sets = propagate_live_sets(3, cfg, defs, live_in)
  debug_inspect(sets.live_in, content="[[], [1000000], [1000000]]")
  debug_inspect(sets.live_out, content="[[1000000], [1000000], []]")
}

///|
test "sparse live sets cover diamond loop and unreachable CFG regions" {
  let cfg : DenseCfgEdges = {
    preds: [[], [0, 3], [0], [1, 2], []],
    succs: [[1, 2], [3], [3], [1], []],
  }
  let defs = [
    SparseVRegSet::new(),
    SparseVRegSet::new(),
    SparseVRegSet::new(),
    SparseVRegSet::new(),
    SparseVRegSet::new(),
  ]
  let live_in = [
    SparseVRegSet::new(),
    SparseVRegSet::new(),
    SparseVRegSet::new(),
    SparseVRegSet::new(),
    SparseVRegSet::new(),
  ]
  defs[0].set(7, true)
  live_in[3].set(7, true)
  live_in[4].set(1_000_000, true)
  let sets = propagate_live_sets(5, cfg, defs, live_in)
  debug_inspect(sets.live_in, content="[[], [7], [7], [7], [1000000]]")
  debug_inspect(sets.live_out, content="[[7], [7], [7], [7], []]")
}

///|
test "compute sparse live sets over reusable CFG model" {
  let cfg : DenseCfgEdges = { preds: [[], [0], [1]], succs: [[1], [2], []], }
  let defs = [SparseVRegSet::new(), SparseVRegSet::new(), SparseVRegSet::new()]
  let live_in = [
    SparseVRegSet::new(),
    SparseVRegSet::new(),
    SparseVRegSet::new(),
  ]
  defs[0].set(0, true)
  live_in[1].set(1, true)
  live_in[2].set(0, true)
  let live_sets = propagate_live_sets(3, cfg, defs, live_in)
  debug_inspect(live_sets.live_in, content="[[1], [0, 1], [0]]")
  debug_inspect(live_sets.live_out, content="[[0, 1], [0], []]")
}

///|
test "program point ordering is lexicographic across large blocks" {
  inspect(
    ProgramPoint(0, 1_500_000).compare_with_order(ProgramPoint(1, 0), [0, 1]),
    content="-1",
  )
}

///|
test "instruction edit resolution preserves position order and edge edits" {
  let plan = AllocationPlan::new(4)
  let r0 : PhysicalReg = { id: 0, class: Int, }
  let r1 : PhysicalReg = { id: 1, class: Int, }
  let r2 : PhysicalReg = { id: 2, class: Int, }
  let v0 : VirtualReg = { id: 0, class: Int, }
  let v1 : VirtualReg = { id: 1, class: Int, }
  let v2 : VirtualReg = { id: 2, class: Int, }
  plan.add_edit({ value: v0, from: Reg(r0), to: Reg(r1), position: Before(2), })
  plan.add_edit({ value: v1, from: Reg(r1), to: Reg(r2), position: After(0), })
  plan.add_edit({ value: v2, from: Reg(r2), to: Reg(r0), position: Before(1), })
  plan.add_edit({ value: v0, from: Reg(r0), to: Reg(r1), position: Before(2), })
  plan.add_edit({
    value: v1,
    from: Reg(r1),
    to: Reg(r0),
    position: Edge(source_block=3, successor_index=1),
  })
  resolve_instruction_edits(plan, MachineEnv::new([r0, r1, r2], [r2]))
  debug_inspect(
    plan.edits(),
    content=(
      #|[
      #|  {
      #|    value: { id: 0, class: Int },
      #|    from: Reg({ id: 0, class: Int }),
      #|    to: Reg({ id: 1, class: Int }),
      #|    position: Before(2),
      #|  },
      #|  {
      #|    value: { id: 1, class: Int },
      #|    from: Reg({ id: 1, class: Int }),
      #|    to: Reg({ id: 2, class: Int }),
      #|    position: After(0),
      #|  },
      #|  {
      #|    value: { id: 2, class: Int },
      #|    from: Reg({ id: 2, class: Int }),
      #|    to: Reg({ id: 0, class: Int }),
      #|    position: Before(1),
      #|  },
      #|  {
      #|    value: { id: 1, class: Int },
      #|    from: Reg({ id: 1, class: Int }),
      #|    to: Reg({ id: 0, class: Int }),
      #|    position: Edge(source_block=3, successor_index=1),
      #|  },
      #|]
    ),
  )
}

///|
test "reserve spill slots aligns vector slots" {
  let int_slot = reserve_spill_slot(0, Int)
  inspect(int_slot.slot, content="0")
  inspect(int_slot.next_slot, content="1")
  inspect(int_slot.slots_used, content="1")
  let vector_slot = reserve_spill_slot(1, Vector)
  inspect(vector_slot.slot, content="2")
  inspect(vector_slot.next_slot, content="4")
  inspect(vector_slot.slots_used, content="2")
}

///|
priv struct VerifierCfgView {
  value_count : Int
  blocks : Array[Array[Int]]
  operands : Array[Array[Operand]]
  successors : Array[Array[Int]]
  entry_values : Array[VirtualReg]
  parameters : Array[Array[VirtualReg]]
  edge_arguments : Array[Array[Array[VirtualReg]]]
  successor_queries : Ref[Int]
  block_visits : Ref[Int]
}

///|
impl FunctionView for VerifierCfgView with fn value_count(self) -> Int {
  self.value_count
}

///|
impl FunctionView for VerifierCfgView with fn value_class(_self, _value) -> RegClass {
  Int
}

///|
impl FunctionView for VerifierCfgView with fn value_spill_size(_self, _value) -> Int {
  8
}

///|
impl FunctionView for VerifierCfgView with fn value_spill_alignment(
  _self,
  _value,
) -> Int {
  8
}

///|
impl FunctionView for VerifierCfgView with fn values_share_spill_slot(
  _self,
  _lhs,
  _rhs,
) -> Bool {
  true
}

///|
impl FunctionView for VerifierCfgView with fn entry_values(self) -> Array[
  VirtualReg,
] {
  self.entry_values.copy()
}

///|
impl FunctionView for VerifierCfgView with fn block_count(self) -> Int {
  self.blocks.length()
}

///|
impl FunctionView for VerifierCfgView with fn block_id_at(_self, block) -> Int {
  block
}

///|
impl FunctionView for VerifierCfgView with fn block_parameters(self, block) -> Array[
  VirtualReg,
] {
  self.parameters[block].copy()
}

///|
impl FunctionView for VerifierCfgView with fn block_instructions(self, block) -> Array[
  Int,
] {
  self.block_visits.val = self.block_visits.val + 1
  self.blocks[block].copy()
}

///|
impl FunctionView for VerifierCfgView with fn block_successors(self, block) -> Array[
  Int,
] {
  self.successor_queries.val = self.successor_queries.val + 1
  self.successors[block].copy()
}

///|
impl FunctionView for VerifierCfgView with fn edge_arguments(
  self,
  block,
  successor,
) -> Array[VirtualReg] {
  self.edge_arguments[block][successor].copy()
}

///|
impl FunctionView for VerifierCfgView with fn instruction_operands(
  self,
  instruction,
) -> Array[Operand] {
  self.operands[instruction].copy()
}

///|
impl FunctionView for VerifierCfgView with fn instruction_clobbers(
  _self,
  _instruction,
) -> Array[PhysicalReg] {
  []
}

///|
test "operand assignment reuses a tied group's resident register" {
  let spilled : VirtualReg = { id: 0, class: Int, }
  let resident : VirtualReg = { id: 1, class: Int, }
  let r0 : PhysicalReg = { id: 0, class: Int, }
  let function : VerifierCfgView = {
    value_count: 2,
    blocks: [[0]],
    operands: [
      [
        Operand::use_reg(spilled).with_constraint(AnyLocation).with_tie(0),
        Operand::def(resident).with_tie(0),
      ],
    ],
    successors: [[]],
    entry_values: [spilled],
    parameters: [[]],
    edge_arguments: [[]],
    successor_queries: Ref(0),
    block_visits: Ref(0),
  }
  let plan = AllocationPlan::new(2)
  let slot = plan.create_spill_slot(8, 8)
  plan.assign_value(spilled, Spill(slot))
  plan.assign_value(resident, Reg(r0))
  let (segments, segments_by_value) = build_allocation_segments(
    build_function_live_ranges(function),
    allocatable=[r0],
  )
  for segment in segments_by_value[spilled.id] {
    segments[segment].location = Some(SegmentSpill)
  }
  for segment in segments_by_value[resident.id] {
    segments[segment].location = Some(SegmentReg(r0))
  }
  assign_segment_operands(
    plan,
    function,
    MachineEnv::new([r0], []),
    segments,
    segments_by_value,
  )
  verify_function_allocation(function, MachineEnv::new([r0], []), plan)
  debug_inspect(
    (plan.operand_location(0, 0), plan.operand_location(0, 1)),
    content="(Some(Reg({ id: 0, class: Int })), Some(Reg({ id: 0, class: Int })))",
  )
}

///|
fn verify_wrong_location(
  function : VerifierCfgView,
  def_instruction : Int?,
  use_instruction : Int,
) -> VerifyError? {
  let value : VirtualReg = { id: 0, class: Int, }
  let r0 : PhysicalReg = { id: 0, class: Int, }
  let r1 : PhysicalReg = { id: 1, class: Int, }
  let plan = AllocationPlan::new(1)
  plan.assign_value(value, Reg(r0))
  if def_instruction is Some(instruction) {
    plan.assign_operand(instruction, 0, Reg(r0))
  }
  plan.assign_operand(use_instruction, 0, Reg(r1))
  try {
    verify_function_allocation(function, MachineEnv::new([r0, r1], []), plan)
    None
  } catch {
    error => Some(error)
  }
}

///|
test "plan verifier rejects a spilled AnyReg operand" {
  let value : VirtualReg = { id: 0, class: Int, }
  let function : VerifierCfgView = {
    value_count: 1,
    blocks: [[0]],
    operands: [[Operand::use_reg(value)]],
    successors: [[]],
    entry_values: [value],
    parameters: [[]],
    edge_arguments: [[]],
    successor_queries: Ref(0),
    block_visits: Ref(0),
  }
  let plan = AllocationPlan::new(1)
  let slot = plan.create_spill_slot(8, 8)
  plan.assign_value(value, Spill(slot))
  plan.assign_operand(0, 0, Spill(slot))
  let error = try {
    verify_function_allocation(function, MachineEnv::new([], []), plan)
    None
  } catch {
    error => Some(error)
  }
  debug_inspect(
    error,
    content="Some(InvalidPlan(message=\"register-constrained operand allocated outside a register\"))",
  )
}

///|
test "plan verifier accepts a declared fixed-operand-only register" {
  let value : VirtualReg = { id: 0, class: Int, }
  let home : PhysicalReg = { id: 0, class: Int, }
  let edit_scratch : PhysicalReg = { id: 1, class: Int, }
  let fixed_only : PhysicalReg = { id: 2, class: Int, }
  let function : VerifierCfgView = {
    value_count: 1,
    blocks: [[0]],
    operands: [[Operand::use_reg(value).with_constraint(FixedReg(fixed_only))]],
    successors: [[]],
    entry_values: [value],
    parameters: [[]],
    edge_arguments: [[]],
    successor_queries: Ref(0),
    block_visits: Ref(0),
  }
  let plan = AllocationPlan::new(1)
  plan.assign_value(value, Reg(home))
  plan.assign_operand(0, 0, Reg(fixed_only))
  plan.add_edit({
    value,
    from: Reg(home),
    to: Reg(fixed_only),
    position: Before(0),
  })
  verify_function_allocation(
    function,
    MachineEnv::new([home], [edit_scratch])
    .with_operand_scratch_regs([])
    .with_fixed_operand_regs([fixed_only]),
    plan,
  )
}

///|
test "plan verifier rejects an unconstrained operand in a fixed-only register" {
  let value : VirtualReg = { id: 0, class: Int, }
  let home : PhysicalReg = { id: 0, class: Int, }
  let fixed_only : PhysicalReg = { id: 2, class: Int, }
  let function : VerifierCfgView = {
    value_count: 1,
    blocks: [[0]],
    operands: [[Operand::use_reg(value)]],
    successors: [[]],
    entry_values: [value],
    parameters: [[]],
    edge_arguments: [[]],
    successor_queries: Ref(0),
    block_visits: Ref(0),
  }
  let plan = AllocationPlan::new(1)
  plan.assign_value(value, Reg(home))
  plan.assign_operand(0, 0, Reg(fixed_only))
  plan.add_edit({
    value,
    from: Reg(home),
    to: Reg(fixed_only),
    position: Before(0),
  })
  let error = try {
    verify_function_allocation(
      function,
      MachineEnv::new([home], [])
      .with_operand_scratch_regs([])
      .with_fixed_operand_regs([fixed_only]),
      plan,
    )
    None
  } catch {
    error => Some(error)
  }
  debug_inspect(
    error,
    content="Some(InvalidPlan(message=\"illegal operand allocation location for v0\"))",
  )
}

///|
test "plan verifier always enters a self-looping entry block" {
  let value : VirtualReg = { id: 0, class: Int, }
  debug_inspect(
    verify_wrong_location(
      {
        value_count: 1,
        blocks: [[0]],
        operands: [[Operand::use_reg(value)]],
        successors: [[0]],
        entry_values: [value],
        parameters: [[]],
        edge_arguments: [[[]]],
        successor_queries: Ref(0),
        block_visits: Ref(0),
      },
      None,
      0,
    ),
    content=(
      #|Some(
      #|  IncorrectValue(
      #|    vreg={ id: 0, class: Int },
      #|    location=Reg({ id: 1, class: Int }),
      #|  ),
      #|)
    ),
  )
}

///|
test "plan verifier checks an unreachable cyclic component" {
  let value : VirtualReg = { id: 0, class: Int, }
  debug_inspect(
    verify_wrong_location(
      {
        value_count: 1,
        blocks: [[], [0, 1]],
        operands: [[Operand::def(value)], [Operand::use_reg(value)]],
        successors: [[], [1]],
        entry_values: [],
        parameters: [[], []],
        edge_arguments: [[], [[]]],
        successor_queries: Ref(0),
        block_visits: Ref(0),
      },
      Some(0),
      1,
    ),
    content=(
      #|Some(
      #|  IncorrectValue(
      #|    vreg={ id: 0, class: Int },
      #|    location=Reg({ id: 1, class: Int }),
      #|  ),
      #|)
    ),
  )
}

///|
test "plan verifier queries each block successor list once" {
  let successor_queries = Ref(0)
  let value : VirtualReg = { id: 0, class: Int, }
  let register : PhysicalReg = { id: 0, class: Int, }
  let function : VerifierCfgView = {
    value_count: 1,
    blocks: [[], [], [], []],
    operands: [],
    successors: [[1], [2], [3], []],
    entry_values: [value],
    parameters: [[], [], [], []],
    edge_arguments: [[[]], [[]], [[]], []],
    successor_queries,
    block_visits: Ref(0),
  }
  let plan = AllocationPlan::new(1)
  plan.assign_value(value, Reg(register))
  verify_function_allocation(function, MachineEnv::new([register], []), plan)
  inspect(successor_queries.val, content="4")
}

///|
test "production fragments cache local allocation metadata" {
  let r0 : PhysicalReg = { id: 0, class: Int, }
  let r1 : PhysicalReg = { id: 1, class: Int, }
  let range = LiveRange::LiveRange(0, { id: 0, class: Int, })
  range.add_range(ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 2)))
  range.add_range(ProgramRange(ProgramPoint(2, 0), ProgramPoint(2, 2)))
  range.add_use(
    UsePosition(ProgramPoint(0, 1), LiveUse, AnyReg).with_preference(Some(r1)),
  )
  range.add_use(
    UsePosition(ProgramPoint(2, 1), LiveUse, FixedReg(r0)).with_preference(
      Some(r0),
    ),
  )
  let ranges = LiveRangeSet::LiveRangeSet([0, 1, 2])
  ranges.add_range(range)
  let (segments, _) = build_allocation_segments(ranges, allocatable=[r0, r1])
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
      #|  (667, false, None, Some({ id: 1, class: Int })),
      #|  (1000, true, Some({ id: 0, class: Int }), Some({ id: 0, class: Int })),
      #|]
    ),
  )
}

///|
test "any-location definitions materialize in their stable home" {
  let value : VirtualReg = { id: 0, class: Int, }
  let register : PhysicalReg = { id: 0, class: Int, }
  let function : VerifierCfgView = {
    value_count: 1,
    blocks: [[0]],
    operands: [[Operand::def(value).with_constraint(AnyLocation)]],
    successors: [[]],
    entry_values: [],
    parameters: [[]],
    edge_arguments: [[]],
    successor_queries: Ref(0),
    block_visits: Ref(0),
  }
  let plan = AllocationPlan::new(1)
  let slot = plan.create_spill_slot(8, 8)
  plan.assign_value(value, Spill(slot))
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value,
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 2)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: Some(SegmentReg(register)),
    },
  ]
  assign_segment_operands(
    plan,
    function,
    MachineEnv::new([register], []),
    segments,
    [[0]],
  )
  |> ignore
  debug_inspect(
    (plan.operand_location(0, 0), plan.edits()),
    content="(Some(Spill(0)), [])",
  )
}

///|
test "production register allocation index orders updates by range end" {
  let segments : Array[AllocationSegment] = [
    {
      id: 0,
      value: { id: 0, class: Int, },
      range: ProgramRange(ProgramPoint(0, 0), ProgramPoint(0, 2)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
    {
      id: 1,
      value: { id: 1, class: Int, },
      range: ProgramRange(ProgramPoint(0, 4), ProgramPoint(0, 6)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
    {
      id: 2,
      value: { id: 2, class: Int, },
      range: ProgramRange(ProgramPoint(0, 8), ProgramPoint(0, 10)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
    {
      id: 3,
      value: { id: 3, class: Int, },
      range: ProgramRange(ProgramPoint(0, 5), ProgramPoint(0, 7)),
      weight: 1,
      has_fixed_constraint: false,
      fixed_hint: None,
      preference_hint: None,
      location: None,
    },
  ]
  let allocations = RegisterAllocationIndex::new(1, segments, [0])
  allocations.insert(0, 2)
  allocations.insert(0, 0)
  allocations.insert(0, 1)
  let stack : Array[Int] = []
  let ordered : Array[Int] = []
  allocations.seek(0, ProgramPoint(0, -1), stack)
  while allocations.next(stack) is Some(segment) {
    ordered.push(segment)
  }
  debug_inspect(ordered, content="[0, 1, 2]")
  allocations.remove(0, 1)
  ordered.clear()
  allocations.seek(0, ProgramPoint(0, -1), stack)
  while allocations.next(stack) is Some(segment) {
    ordered.push(segment)
  }
  debug_inspect(ordered, content="[0, 2]")
}

///|
/// ISS-370 regression: `index_plan_edits` buckets by position, and bucket
/// order must preserve the plan's edit order. The three moves below form a
/// dependency chain at one position — each requires the location produced by
/// the previous one — so any reordering inside the bucket fails verification
/// with `IncorrectValue`.
test "plan verifier applies same-position edits in plan order" {
  let value : VirtualReg = { id: 0, class: Int, }
  let r0 : PhysicalReg = { id: 0, class: Int, }
  let r1 : PhysicalReg = { id: 1, class: Int, }
  let r2 : PhysicalReg = { id: 2, class: Int, }
  let function : VerifierCfgView = {
    value_count: 1,
    blocks: [[0]],
    operands: [[Operand::use_reg(value)]],
    successors: [[]],
    entry_values: [value],
    parameters: [[]],
    edge_arguments: [[]],
    successor_queries: Ref(0),
    block_visits: Ref(0),
  }
  let plan = AllocationPlan::new(1)
  plan.assign_value(value, Reg(r0))
  plan.add_edit({ value, from: Reg(r0), to: Reg(r1), position: Before(0), })
  plan.add_edit({ value, from: Reg(r1), to: Reg(r2), position: Before(0), })
  plan.add_edit({ value, from: Reg(r2), to: Reg(r0), position: Before(0), })
  plan.assign_operand(0, 0, Reg(r0))
  verify_function_allocation(function, MachineEnv::new([r0, r1, r2], []), plan)
}

///|
/// ISS-370 regression: reverse postorder is a topological order on an
/// acyclic CFG, so every join merges all of its incoming states before its
/// block is processed and the whole function verifies in one pass — each
/// block exactly once. The chain of diamonds below refines the dataflow
/// state at every join (each arm publishes the value in a different extra
/// register, and the meet drops it), which is the shape that made the
/// previous LIFO worklist reprocess the downstream chain once per join and
/// grow verification cost with nesting depth.
test "plan verifier processes a deep diamond join chain once per block" {
  let diamonds = 8
  let block_count = 3 * diamonds + 1
  let value : VirtualReg = { id: 0, class: Int, }
  let r0 : PhysicalReg = { id: 0, class: Int, }
  let registers : Array[PhysicalReg] = Array::makei(diamonds + 1, id => {
    id,
    class: Int,
  })
  let blocks : Array[Array[Int]] = Array::makei(block_count, _ => [])
  let successors : Array[Array[Int]] = Array::makei(block_count, _ => [])
  let parameters : Array[Array[VirtualReg]] = Array::makei(block_count, _ => [])
  let edge_arguments : Array[Array[Array[VirtualReg]]] = Array::makei(
    block_count,
    _ => [],
  )
  let plan = AllocationPlan::new(1)
  plan.assign_value(value, Reg(r0))
  for i in 0..<diamonds {
    let top = 3 * i
    let left = 3 * i + 1
    let right = 3 * i + 2
    let join = 3 * i + 3
    successors[top] = [left, right]
    edge_arguments[top] = [[], []]
    successors[left] = [join]
    edge_arguments[left] = [[]]
    successors[right] = [join]
    edge_arguments[right] = [[]]
    // Only the right arm publishes the value in a per-diamond extra
    // register, so every join must drop it — and because the extra register
    // differs per level, a scheduler that enters a join with partial
    // predecessor state has to re-propagate the shrink one level at a time.
    plan.add_edit({
      value,
      from: Reg(r0),
      to: Reg(registers[i + 1]),
      position: Edge(source_block=right, successor_index=0),
    })
  }
  let function : VerifierCfgView = {
    value_count: 1,
    blocks,
    operands: [],
    successors,
    entry_values: [value],
    parameters,
    edge_arguments,
    successor_queries: Ref(0),
    block_visits: Ref(0),
  }
  verify_function_allocation(function, MachineEnv::new(registers, []), plan)
  inspect(function.block_visits.val, content="25")
  inspect(function.successor_queries.val, content="25")
}
