///|
priv struct TestFunction {
  value_count : Int
  instructions : Array[Array[Operand]]
  block_parameters : Array[VirtualReg]
}

///|
priv struct CfgTestFunction {
  value_count : Int
  blocks : Array[Array[Int]]
  instructions : Array[Array[Operand]]
  clobbers : Array[Array[PhysicalReg]]
  successors : Array[Array[Int]]
  entry_values : Array[VirtualReg]
  parameters : Array[Array[VirtualReg]]
  edge_arguments : Array[Array[Array[VirtualReg]]]
}

///|
impl FunctionView for CfgTestFunction with fn value_count(self) -> Int {
  self.value_count
}

///|
impl FunctionView for CfgTestFunction with fn value_class(_self, _value) -> RegClass {
  Int
}

///|
impl FunctionView for CfgTestFunction with fn value_spill_size(_self, _value) -> Int {
  8
}

///|
impl FunctionView for CfgTestFunction with fn value_spill_alignment(
  _self,
  _value,
) -> Int {
  8
}

///|
impl FunctionView for CfgTestFunction with fn values_share_spill_slot(
  _self,
  _lhs,
  _rhs,
) -> Bool {
  true
}

///|
impl FunctionView for CfgTestFunction with fn entry_values(self) -> ArrayView[
  VirtualReg,
] {
  self.entry_values[:]
}

///|
impl FunctionView for CfgTestFunction with fn block_count(self) -> Int {
  self.blocks.length()
}

///|
impl FunctionView for CfgTestFunction with fn block_id_at(_self, index) -> Int {
  index
}

///|
impl FunctionView for CfgTestFunction with fn block_parameters(self, block) -> ArrayView[
  VirtualReg,
] {
  self.parameters[block][:]
}

///|
impl FunctionView for CfgTestFunction with fn block_instructions(self, block) -> ArrayView[
  Int,
] {
  self.blocks[block][:]
}

///|
impl FunctionView for CfgTestFunction with fn block_successors(self, block) -> ArrayView[
  Int,
] {
  self.successors[block][:]
}

///|
impl FunctionView for CfgTestFunction with fn edge_arguments(
  self,
  block,
  successor,
) -> ArrayView[VirtualReg] {
  self.edge_arguments[block][successor][:]
}

///|
impl FunctionView for CfgTestFunction with fn instruction_operands(
  self,
  instruction,
) -> ArrayView[Operand] {
  self.instructions[instruction][:]
}

///|
impl FunctionView for CfgTestFunction with fn instruction_clobbers(
  self,
  instruction,
) -> ArrayView[PhysicalReg] {
  self.clobbers[instruction][:]
}

///|
impl FunctionView for TestFunction with fn value_count(self) -> Int {
  self.value_count
}

///|
impl FunctionView for TestFunction with fn value_class(_self, _value) -> RegClass {
  Int
}

///|
impl FunctionView for TestFunction with fn value_spill_size(_self, _value) -> Int {
  8
}

///|
impl FunctionView for TestFunction with fn value_spill_alignment(_self, _value) -> Int {
  8
}

///|
impl FunctionView for TestFunction with fn values_share_spill_slot(
  _self,
  _lhs,
  _rhs,
) -> Bool {
  true
}

///|
impl FunctionView for TestFunction with fn entry_values(self) -> ArrayView[
  VirtualReg,
] {
  self.block_parameters[:]
}

///|
impl FunctionView for TestFunction with fn block_count(_self) -> Int {
  1
}

///|
impl FunctionView for TestFunction with fn block_id_at(_self, index) -> Int {
  index
}

///|
impl FunctionView for TestFunction with fn block_parameters(_self, _block) -> ArrayView[
  VirtualReg,
] {
  let empty : Array[VirtualReg] = []
  empty[:]
}

///|
impl FunctionView for TestFunction with fn block_instructions(self, _block) -> ArrayView[
  Int,
] {
  let instructions = Array::makei(self.instructions.length(), index => index)
  instructions[:]
}

///|
impl FunctionView for TestFunction with fn block_successors(_self, _block) -> ArrayView[
  Int,
] {
  let empty : Array[Int] = []
  empty[:]
}

///|
impl FunctionView for TestFunction with fn edge_arguments(
  _self,
  _block,
  _successor,
) -> ArrayView[VirtualReg] {
  let empty : Array[VirtualReg] = []
  empty[:]
}

///|
impl FunctionView for TestFunction with fn instruction_operands(
  self,
  instruction,
) -> ArrayView[Operand] {
  self.instructions[instruction][:]
}

///|
impl FunctionView for TestFunction with fn instruction_clobbers(
  _self,
  _instruction,
) -> ArrayView[PhysicalReg] {
  let empty : Array[PhysicalReg] = []
  empty[:]
}

///|
fn value(id : Int) -> VirtualReg {
  { id, class: Int, }
}

///|
fn int_reg(id : Int) -> PhysicalReg {
  { id, class: Int, }
}

///|
test "backtracking reuses a register across early use and late def" {
  let function : TestFunction = {
    value_count: 2,
    block_parameters: [value(0)],
    instructions: [
      [
        Operand::use_reg(value(0)).with_timing(Early),
        Operand::def(value(1)).with_timing(Late),
      ],
      [Operand::use_reg(value(1))],
    ],
  }
  inspect(
    allocate_function(function, MachineEnv::new([int_reg(0)], [int_reg(1)])),
    content=(
      #|{
      #|  value_locations: [Some(Reg(p0:int)), Some(Reg(p0:int))],
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 0, operand: 1, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 0, location: Reg(p0:int) },
      #|  ],
      #|  edits: [],
      #|  spill_slots: [],
      #|}
    ),
  )
}

///|
test "backtracking reuses spill slots for disjoint values" {
  let function : TestFunction = {
    value_count: 4,
    block_parameters: [value(0), value(1)],
    instructions: [
      [Operand::use_reg(value(0)), Operand::use_reg(value(1))],
      [Operand::def(value(2)), Operand::def(value(3))],
      [Operand::use_reg(value(2)), Operand::use_reg(value(3))],
    ],
  }
  inspect(
    allocate_function(
      function,
      MachineEnv::new([int_reg(0)], [int_reg(1), int_reg(2)]),
    ),
    content=(
      #|{
      #|  value_locations: [Some(Reg(p0:int)), Some(Spill(0)), Some(Reg(p0:int)), Some(Spill(0))],
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 0, operand: 1, location: Reg(p1:int) },
      #|    { instruction: 1, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 1, location: Reg(p1:int) },
      #|    { instruction: 2, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 2, operand: 1, location: Reg(p1:int) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 1, class: Int },
      #|      from: Spill(0),
      #|      to: Reg(p1:int),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 3, class: Int },
      #|      from: Reg(p1:int),
      #|      to: Spill(0),
      #|      position: After(1),
      #|    },
      #|    {
      #|      value: { id: 3, class: Int },
      #|      from: Spill(0),
      #|      to: Reg(p1:int),
      #|      position: Before(2),
      #|    },
      #|  ],
      #|  spill_slots: [{ size: 8, alignment: 8 }],
      #|}
    ),
  )
}

///|
test "backtracking keeps spill homes distinct across CFG blocks" {
  let function : CfgTestFunction = {
    value_count: 4,
    blocks: [[0], [1, 2]],
    instructions: [
      [Operand::use_reg(value(0)), Operand::use_reg(value(1))],
      [Operand::def(value(2)), Operand::def(value(3))],
      [Operand::use_reg(value(2)), Operand::use_reg(value(3))],
    ],
    clobbers: [[], [], []],
    successors: [[1], []],
    entry_values: [value(0), value(1)],
    parameters: [[], []],
    edge_arguments: [[[]], []],
  }
  inspect(
    allocate_function(
      function,
      MachineEnv::new([int_reg(0)], [int_reg(1), int_reg(2)]),
    ),
    content=(
      #|{
      #|  value_locations: [Some(Reg(p0:int)), Some(Spill(0)), Some(Reg(p0:int)), Some(Spill(1))],
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 0, operand: 1, location: Reg(p1:int) },
      #|    { instruction: 1, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 1, location: Reg(p1:int) },
      #|    { instruction: 2, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 2, operand: 1, location: Reg(p1:int) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 1, class: Int },
      #|      from: Spill(0),
      #|      to: Reg(p1:int),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 3, class: Int },
      #|      from: Reg(p1:int),
      #|      to: Spill(1),
      #|      position: After(1),
      #|    },
      #|    {
      #|      value: { id: 3, class: Int },
      #|      from: Spill(1),
      #|      to: Reg(p1:int),
      #|      position: Before(2),
      #|    },
      #|  ],
      #|  spill_slots: [{ size: 8, alignment: 8 }, { size: 8, alignment: 8 }],
      #|}
    ),
  )
}

///|
test "backtracking keeps the dense live range resident" {
  let function : TestFunction = {
    value_count: 2,
    block_parameters: [value(0)],
    instructions: [
      [Operand::def(value(1))],
      [Operand::use_reg(value(1))],
      [Operand::use_reg(value(1))],
      [Operand::use_reg(value(0)), Operand::use_reg(value(1))],
    ],
  }
  let environment = MachineEnv::new([int_reg(0)], [int_reg(1), int_reg(2)])
  inspect(
    allocate_function(function, environment),
    content=(
      #|{
      #|  value_locations: [Some(Spill(0)), Some(Reg(p0:int))],
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 2, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 3, operand: 0, location: Reg(p1:int) },
      #|    { instruction: 3, operand: 1, location: Reg(p0:int) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(0),
      #|      to: Reg(p1:int),
      #|      position: Before(3),
      #|    },
      #|  ],
      #|  spill_slots: [{ size: 8, alignment: 8 }],
      #|}
    ),
  )
}

///|
test "backtracking splits a live range around a clobbered CFG fragment" {
  let function : CfgTestFunction = {
    value_count: 1,
    blocks: [[0], [1], [2]],
    instructions: [
      [Operand::use_reg(value(0))],
      [],
      [Operand::use_reg(value(0))],
    ],
    clobbers: [[], [int_reg(0)], []],
    successors: [[1], [2], []],
    entry_values: [value(0)],
    parameters: [[], [], []],
    edge_arguments: [[[]], [[]], []],
  }
  inspect(
    allocate_function(function, MachineEnv::new([int_reg(0)], [int_reg(1)])),
    content=(
      #|{
      #|  value_locations: [Some(Spill(0))],
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 2, operand: 0, location: Reg(p0:int) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(0),
      #|      to: Reg(p0:int),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(0),
      #|      to: Reg(p0:int),
      #|      position: Before(2),
      #|    },
      #|  ],
      #|  spill_slots: [{ size: 8, alignment: 8 }],
      #|}
    ),
  )
}

///|
test "backtracking spills a value defined before a same-block clobber" {
  let function : CfgTestFunction = {
    value_count: 1,
    blocks: [[0, 1, 2]],
    instructions: [[Operand::def(value(0))], [], [Operand::use_reg(value(0))]],
    clobbers: [[], [int_reg(0)], []],
    successors: [[]],
    entry_values: [],
    parameters: [[]],
    edge_arguments: [[]],
  }
  let plan = allocate_function(
    function,
    MachineEnv::new([int_reg(0)], [int_reg(1)]),
  )
  debug_inspect(
    (plan.value_location(0), plan.edits()),
    content=(
      #|(
      #|  Some(Spill(0)),
      #|  [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Reg(p0:int),
      #|      to: Spill(0),
      #|      position: After(0),
      #|    },
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(0),
      #|      to: Reg(p0:int),
      #|      position: Before(2),
      #|    },
      #|  ],
      #|)
    ),
  )
}

///|
test "backtracking parks cold live-through values outside hot loops" {
  let instructions : Array[Array[Operand]] = []
  for _ in 0..<19 {
    instructions.push([])
  }
  instructions.push([
    {
      vreg: value(3),
      role: UseDef,
      constraint: AnyReg,
      preference: None,
      tie_id: -1,
      timing: Early,
    },
    {
      vreg: value(4),
      role: UseDef,
      constraint: AnyReg,
      preference: None,
      tie_id: -1,
      timing: Early,
    },
  ])
  instructions.push([])
  instructions.push([
    Operand::use_reg(value(0)),
    Operand::use_reg(value(0)),
    Operand::use_reg(value(0)),
    Operand::use_reg(value(0)),
  ])
  let function : CfgTestFunction = {
    value_count: 5,
    blocks: [[], Array::makei(20, index => index), [21], [20]],
    instructions,
    clobbers: Array::makei(22, _ => []),
    successors: [[1], [3, 2], [], [1]],
    entry_values: [value(0), value(1), value(2)],
    parameters: [[], [value(3), value(4)], [], []],
    edge_arguments: [
      [[value(1), value(2)]],
      [[], []],
      [],
      [[value(3), value(4)]],
    ],
  }
  inspect(
    allocate_function(
      function,
      MachineEnv::new([int_reg(0), int_reg(1)], [int_reg(2)]),
    ),
    content=(
      #|{
      #|  value_locations: [
      #|    Some(Spill(0)),
      #|    Some(Reg(p1:int)),
      #|    Some(Reg(p0:int)),
      #|    Some(Reg(p1:int)),
      #|    Some(Reg(p0:int)),
      #|  ],
      #|  operand_assignments: [
      #|    { instruction: 19, operand: 0, location: Reg(p1:int) },
      #|    { instruction: 19, operand: 1, location: Reg(p0:int) },
      #|    { instruction: 21, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 21, operand: 1, location: Reg(p0:int) },
      #|    { instruction: 21, operand: 2, location: Reg(p0:int) },
      #|    { instruction: 21, operand: 3, location: Reg(p0:int) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(0),
      #|      to: Reg(p0:int),
      #|      position: Before(21),
      #|    },
      #|  ],
      #|  spill_slots: [{ size: 8, alignment: 8 }],
      #|}
    ),
  )
}

///|
test "backtracking shares a spill home across a loop-carried SSA bundle" {
  let function : CfgTestFunction = {
    value_count: 3,
    blocks: [[], [0], []],
    instructions: [
      [
        Operand::use_reg(value(0)).with_timing(Early),
        Operand::def(value(1)).with_timing(Late),
      ],
    ],
    clobbers: [[]],
    successors: [[1], [1, 2], []],
    entry_values: [value(2)],
    parameters: [[], [value(0)], []],
    edge_arguments: [[[value(2)]], [[value(1)], []], []],
  }
  inspect(
    allocate_function(function, MachineEnv::new([], [int_reg(0), int_reg(1)])),
    content=(
      #|{
      #|  value_locations: [Some(Spill(0)), Some(Spill(0)), Some(Spill(0))],
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 0, operand: 1, location: Reg(p1:int) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(0),
      #|      to: Reg(p0:int),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 1, class: Int },
      #|      from: Reg(p1:int),
      #|      to: Spill(0),
      #|      position: After(0),
      #|    },
      #|  ],
      #|  spill_slots: [{ size: 8, alignment: 8 }],
      #|}
    ),
  )
}

///|
test "backtracking reloads a resident segment only once" {
  let function : CfgTestFunction = {
    value_count: 1,
    blocks: [[0, 1], [2], [3, 4]],
    instructions: [
      [Operand::use_reg(value(0))],
      [Operand::use_reg(value(0))],
      [],
      [Operand::use_reg(value(0))],
      [Operand::use_reg(value(0))],
    ],
    clobbers: [[], [], [int_reg(0)], [], []],
    successors: [[1], [2], []],
    entry_values: [value(0)],
    parameters: [[], [], []],
    edge_arguments: [[[]], [[]], []],
  }
  let plan = allocate_function(
    function,
    MachineEnv::new([int_reg(0)], [int_reg(1)]),
  )
  debug_inspect(
    plan.edits(),
    content=(
      #|[
      #|  {
      #|    value: { id: 0, class: Int },
      #|    from: Spill(0),
      #|    to: Reg(p0:int),
      #|    position: Before(0),
      #|  },
      #|  {
      #|    value: { id: 0, class: Int },
      #|    from: Spill(0),
      #|    to: Reg(p0:int),
      #|    position: Before(3),
      #|  },
      #|]
    ),
  )
}

///|
test "backtracking coalesces conflict-free edges and preserves loop transfers" {
  let function : CfgTestFunction = {
    value_count: 7,
    blocks: [[0], [1, 2]],
    instructions: [
      [],
      [
        Operand::use_reg(value(3)).with_timing(Early),
        Operand::use_reg(value(4)).with_timing(Early),
        Operand::def(value(6)).with_timing(Late),
      ],
      [],
    ],
    clobbers: [[], [], []],
    successors: [[1], [1]],
    entry_values: [value(0), value(1), value(2)],
    parameters: [[], [value(3), value(4), value(5)]],
    edge_arguments: [
      [[value(0), value(1), value(2)]],
      [[value(4), value(6), value(5)]],
    ],
  }
  inspect(
    allocate_function(
      function,
      MachineEnv::new([int_reg(0), int_reg(1), int_reg(2), int_reg(3)], [
        int_reg(4),
      ]),
    ),
    content=(
      #|{
      #|  value_locations: [
      #|    Some(Reg(p2:int)),
      #|    Some(Reg(p0:int)),
      #|    Some(Reg(p1:int)),
      #|    Some(Reg(p2:int)),
      #|    Some(Reg(p0:int)),
      #|    Some(Reg(p1:int)),
      #|    Some(Reg(p2:int)),
      #|  ],
      #|  operand_assignments: [
      #|    { instruction: 1, operand: 0, location: Reg(p2:int) },
      #|    { instruction: 1, operand: 1, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 2, location: Reg(p2:int) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 4, class: Int },
      #|      from: Reg(p0:int),
      #|      to: Reg(p2:int),
      #|      position: Edge(source_block=1, successor_index=0),
      #|    },
      #|    {
      #|      value: { id: 6, class: Int },
      #|      from: Reg(p2:int),
      #|      to: Reg(p0:int),
      #|      position: Edge(source_block=1, successor_index=0),
      #|    },
      #|  ],
      #|  spill_slots: [],
      #|}
    ),
  )
}

///|
test "backtracking coalesces the conflict-free side of a critical-edge parameter" {
  let function : CfgTestFunction = {
    value_count: 3,
    blocks: [[0], [1], [2]],
    instructions: [
      [Operand::use_reg(value(0))],
      [Operand::def(value(1))],
      [Operand::use_reg(value(2))],
    ],
    clobbers: [[], [], []],
    successors: [[1, 2], [2], []],
    entry_values: [value(0)],
    parameters: [[], [], [value(2)]],
    edge_arguments: [[[], [value(0)]], [[value(1)]], []],
  }
  inspect(
    allocate_function(
      function,
      MachineEnv::new([int_reg(0), int_reg(1)], [int_reg(2)]),
    ),
    content=(
      #|{
      #|  value_locations: [Some(Reg(p0:int)), Some(Reg(p0:int)), Some(Reg(p0:int))],
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 2, operand: 0, location: Reg(p0:int) },
      #|  ],
      #|  edits: [],
      #|  spill_slots: [],
      #|}
    ),
  )
}

///|
test "soft register preference chooses a legal home without an edit" {
  let function : TestFunction = {
    value_count: 1,
    instructions: [
      [
        Operand::use_reg(value(0))
        .with_constraint(AnyLocation)
        .with_preference(int_reg(2)),
      ],
    ],
    block_parameters: [value(0)],
  }
  inspect(
    allocate_function(
      function,
      MachineEnv::new([int_reg(0), int_reg(1), int_reg(2)], [int_reg(3)]),
    ),
    content=(
      #|{
      #|  value_locations: [Some(Reg(p2:int))],
      #|  operand_assignments: [{ instruction: 0, operand: 0, location: Reg(p2:int) }],
      #|  edits: [],
      #|  spill_slots: [],
      #|}
    ),
  )
}

///|
test "non-allocatable register preference is rejected structurally" {
  let function : TestFunction = {
    value_count: 1,
    instructions: [
      [
        Operand::use_reg(value(0))
        .with_constraint(AnyLocation)
        .with_preference(int_reg(9)),
      ],
    ],
    block_parameters: [value(0)],
  }
  try
    allocate_function(function, MachineEnv::new([int_reg(0)], [int_reg(1)]))
  catch {
    error =>
      debug_inspect(
        error,
        content=(
          #|InvalidPreference(vreg={ id: 0, class: Int }, preferred=p9:int)
        ),
      )
  } noraise {
    _ => fail("expected an invalid preference error")
  }
}

///|
test "backtracking honors a fixed-register operand" {
  let function : TestFunction = {
    value_count: 1,
    block_parameters: [value(0)],
    instructions: [
      [Operand::use_reg(value(0)).with_constraint(FixedReg(int_reg(1)))],
    ],
  }
  inspect(
    allocate_function(
      function,
      MachineEnv::new([int_reg(0), int_reg(1)], [int_reg(2)]),
    ),
    content=(
      #|{
      #|  value_locations: [Some(Reg(p1:int))],
      #|  operand_assignments: [{ instruction: 0, operand: 0, location: Reg(p1:int) }],
      #|  edits: [],
      #|  spill_slots: [],
      #|}
    ),
  )
}

///|
test "backtracking preserves tied and fixed operands across a clobber" {
  let function : CfgTestFunction = {
    value_count: 2,
    blocks: [[0, 1]],
    instructions: [
      [
        Operand::use_reg(value(0)).with_tie(0),
        Operand::def(value(1)).with_tie(0),
      ],
      [Operand::use_reg(value(1)).with_constraint(FixedReg(int_reg(1)))],
    ],
    clobbers: [[], [int_reg(0)]],
    successors: [[]],
    entry_values: [value(0)],
    parameters: [[]],
    edge_arguments: [[]],
  }
  let plan = allocate_function(
    function,
    MachineEnv::new([int_reg(0), int_reg(1)], [int_reg(2)]),
  )
  debug_inspect(
    (
      plan.operand_location(0, 0),
      plan.operand_location(0, 1),
      plan.operand_location(1, 0),
    ),
    content=(
      #|(Some(Reg(p0:int)), Some(Reg(p0:int)), Some(Reg(p1:int)))
    ),
  )
}

///|
test "backtracking applies AnyReg to a sparse tied group" {
  let function : TestFunction = {
    value_count: 2,
    block_parameters: [value(0)],
    instructions: [
      [
        Operand::use_reg(value(0)).with_constraint(AnyLocation).with_tie(7),
        Operand::def(value(1)).with_constraint(AnyReg).with_tie(7),
      ],
    ],
  }
  let plan = allocate_function(function, MachineEnv::new([], [int_reg(0)]))
  debug_inspect(
    (plan.operand_location(0, 0), plan.operand_location(0, 1)),
    content=(
      #|(Some(Reg(p0:int)), Some(Reg(p0:int)))
    ),
  )
}

///|
test "backtracking borrows an allocatable register when spill temporaries are exhausted" {
  let function : TestFunction = {
    value_count: 4,
    block_parameters: [value(0), value(1), value(2), value(3)],
    instructions: [
      [
        Operand::use_reg(value(1)),
        Operand::use_reg(value(2)),
        Operand::use_reg(value(3)),
      ],
      [
        Operand::use_reg(value(0)),
        Operand::use_reg(value(0)),
        Operand::use_reg(value(0)),
        Operand::use_reg(value(0)),
      ],
    ],
  }
  inspect(
    allocate_function(
      function,
      MachineEnv::new([int_reg(0)], [int_reg(1), int_reg(2)]),
    ),
    content=(
      #|{
      #|  value_locations: [Some(Reg(p0:int)), Some(Spill(0)), Some(Spill(1)), Some(Spill(2))],
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg(p1:int) },
      #|    { instruction: 0, operand: 1, location: Reg(p2:int) },
      #|    { instruction: 0, operand: 2, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 1, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 2, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 3, location: Reg(p0:int) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Reg(p0:int),
      #|      to: Spill(3),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 1, class: Int },
      #|      from: Spill(0),
      #|      to: Reg(p1:int),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 2, class: Int },
      #|      from: Spill(1),
      #|      to: Reg(p2:int),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 3, class: Int },
      #|      from: Spill(2),
      #|      to: Reg(p0:int),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(3),
      #|      to: Reg(p0:int),
      #|      position: After(0),
      #|    },
      #|  ],
      #|  spill_slots: [
      #|    { size: 8, alignment: 8 },
      #|    { size: 8, alignment: 8 },
      #|    { size: 8, alignment: 8 },
      #|    { size: 8, alignment: 8 },
      #|  ],
      #|}
    ),
  )
}

///|
test "backtracking keeps edit-only scratch registers out of instruction operands" {
  let function : TestFunction = {
    value_count: 3,
    block_parameters: [value(0), value(1), value(2)],
    instructions: [
      [Operand::use_reg(value(1)), Operand::use_reg(value(2))],
      [
        Operand::use_reg(value(0)),
        Operand::use_reg(value(0)),
        Operand::use_reg(value(0)),
        Operand::use_reg(value(0)),
      ],
    ],
  }
  let environment = MachineEnv::new([int_reg(0), int_reg(1)], [int_reg(2)]).with_operand_scratch_regs([],
  )
  inspect(
    allocate_function(function, environment),
    content=(
      #|{
      #|  value_locations: [Some(Reg(p0:int)), Some(Reg(p1:int)), Some(Spill(0))],
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg(p1:int) },
      #|    { instruction: 0, operand: 1, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 0, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 1, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 2, location: Reg(p0:int) },
      #|    { instruction: 1, operand: 3, location: Reg(p0:int) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Reg(p0:int),
      #|      to: Spill(1),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 2, class: Int },
      #|      from: Spill(0),
      #|      to: Reg(p0:int),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(1),
      #|      to: Reg(p0:int),
      #|      position: After(0),
      #|    },
      #|  ],
      #|  spill_slots: [{ size: 8, alignment: 8 }, { size: 8, alignment: 8 }],
      #|}
    ),
  )
}

///|
/// The observer contract says every phase that opens is followed, eventually,
/// by exactly one `None`. A failing allocation is still an allocation that
/// ended, so it owes that event too — without it, whoever is measuring is
/// left holding a phase that never closed, and it is always the phase that
/// failed, which is the one worth seeing.
///
/// A `FixedReg` preference for a register outside the allocatable set gets
/// all the way through the pipeline before the plan verifier rejects it, so
/// this drives the real path rather than a contrived one.
test "a failed allocation still ends the observer's phase sequence" {
  let events : Array[String] = []
  let config = RegallocConfig::RegallocConfig(
    observer=Some(phase => {
      events.push(
        match phase {
          Some(named) => "\{named}"
          None => "END"
        },
      )
    }),
  )
  let function : TestFunction = {
    value_count: 1,
    instructions: [
      [Operand::use_reg(value(0)).with_constraint(FixedReg(int_reg(9)))],
    ],
    block_parameters: [value(0)],
  }
  let mut raised = false
  try
    allocate_function(function, MachineEnv::new([int_reg(0)], []), config~)
    |> ignore
  catch {
    _ => raised = true
  }
  inspect(raised, content="true")
  inspect(
    events.join(","),
    content="input_validation,live_ranges,segment_construction,bundle_formation,bundle_allocation,home_assignment,operand_assignment,edge_transfers,edit_resolution,verification,END",
  )
  // The terminator arrives once, at the end, not for every phase.
  inspect(events.filter(event => event == "END").length(), content="1")
}

///|
/// Input validation is an attributed phase too. A rejection there must expose
/// both the phase and its matching terminator rather than hiding adapter work
/// inside the preceding caller-owned phase.
test "an input-validation rejection closes its attributed phase" {
  let events : Array[String] = []
  let config = RegallocConfig::RegallocConfig(
    observer=Some(phase => {
      events.push(
        match phase {
          Some(named) => "\{named}"
          None => "END"
        },
      )
    }),
  )
  let function : TestFunction = {
    value_count: 1,
    instructions: [
      [
        Operand::use_reg(value(0))
        .with_constraint(AnyLocation)
        .with_preference(int_reg(9)),
      ],
    ],
    block_parameters: [value(0)],
  }
  let mut raised = false
  try
    allocate_function(
      function,
      MachineEnv::new([int_reg(0)], [int_reg(1)]),
      config~,
    )
    |> ignore
  catch {
    _ => raised = true
  }
  inspect(raised, content="true")
  inspect(events.join(","), content="input_validation,END")
}

///|
test "allocation session resets scratch between serial functions" {
  let environment = MachineEnv::new([int_reg(0), int_reg(1)], [int_reg(2)])
  let larger : TestFunction = {
    value_count: 3,
    instructions: [
      [Operand::def(value(0)), Operand::def(value(1))],
      [Operand::use_reg(value(0)), Operand::def(value(2))],
      [Operand::use_reg(value(1)), Operand::use_reg(value(2))],
    ],
    block_parameters: [],
  }
  let smaller : TestFunction = {
    value_count: 1,
    instructions: [[Operand::def(value(0))], [Operand::use_reg(value(0))]],
    block_parameters: [],
  }
  let expected_larger = allocate_function(larger, environment).to_string()
  let expected_smaller = allocate_function(smaller, environment).to_string()
  let session = AllocationSession::new()
  inspect(
    session.allocate_function(larger, environment).to_string() ==
    expected_larger,
    content="true",
  )
  inspect(
    session.allocate_function(smaller, environment).to_string() ==
    expected_smaller,
    content="true",
  )
  inspect(
    session.allocate_function(larger, environment).to_string() ==
    expected_larger,
    content="true",
  )
}
