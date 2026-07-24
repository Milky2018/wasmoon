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
impl FunctionView for CfgTestFunction with fn entry_values(self) -> Array[
  VirtualReg,
] {
  self.entry_values.copy()
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
impl FunctionView for CfgTestFunction with fn block_parameters(self, block) -> Array[
  VirtualReg,
] {
  self.parameters[block].copy()
}

///|
impl FunctionView for CfgTestFunction with fn block_instructions(self, block) -> Array[
  Int,
] {
  self.blocks[block].copy()
}

///|
impl FunctionView for CfgTestFunction with fn block_successors(self, block) -> Array[
  Int,
] {
  self.successors[block].copy()
}

///|
impl FunctionView for CfgTestFunction with fn edge_arguments(
  self,
  block,
  successor,
) -> Array[VirtualReg] {
  self.edge_arguments[block][successor].copy()
}

///|
impl FunctionView for CfgTestFunction with fn instruction_operands(
  self,
  instruction,
) -> Array[Operand] {
  self.instructions[instruction].copy()
}

///|
impl FunctionView for CfgTestFunction with fn instruction_clobbers(
  self,
  instruction,
) -> Array[PhysicalReg] {
  self.clobbers[instruction].copy()
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
impl FunctionView for TestFunction with fn entry_values(self) -> Array[
  VirtualReg,
] {
  self.block_parameters.copy()
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
impl FunctionView for TestFunction with fn block_parameters(_self, _block) -> Array[
  VirtualReg,
] {
  []
}

///|
impl FunctionView for TestFunction with fn block_instructions(self, _block) -> Array[
  Int,
] {
  Array::makei(self.instructions.length(), index => index)
}

///|
impl FunctionView for TestFunction with fn block_successors(_self, _block) -> Array[
  Int,
] {
  []
}

///|
impl FunctionView for TestFunction with fn edge_arguments(
  _self,
  _block,
  _successor,
) -> Array[VirtualReg] {
  []
}

///|
impl FunctionView for TestFunction with fn instruction_operands(
  self,
  instruction,
) -> Array[Operand] {
  self.instructions[instruction].copy()
}

///|
impl FunctionView for TestFunction with fn instruction_clobbers(
  _self,
  _instruction,
) -> Array[PhysicalReg] {
  []
}

///|
fn value(id : Int) -> VirtualReg {
  { id, class: Int }
}

///|
fn int_reg(id : Int) -> PhysicalReg {
  { id, class: Int }
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
      #|  value_locations: [Some(Reg({ id: 0, class: Int })), Some(Reg({ id: 0, class: Int }))],
      #|  operand_locations: {
      #|    (0, 0): Reg({ id: 0, class: Int }),
      #|    (0, 1): Reg({ id: 0, class: Int }),
      #|    (1, 0): Reg({ id: 0, class: Int }),
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 0, operand: 1, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 0, location: Reg({ id: 0, class: Int }) },
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
      #|  value_locations: [
      #|    Some(Reg({ id: 0, class: Int })),
      #|    Some(Spill(0)),
      #|    Some(Reg({ id: 0, class: Int })),
      #|    Some(Spill(0)),
      #|  ],
      #|  operand_locations: {
      #|    (0, 0): Reg({ id: 0, class: Int }),
      #|    (0, 1): Reg({ id: 1, class: Int }),
      #|    (1, 0): Reg({ id: 0, class: Int }),
      #|    (1, 1): Reg({ id: 1, class: Int }),
      #|    (2, 0): Reg({ id: 0, class: Int }),
      #|    (2, 1): Reg({ id: 1, class: Int }),
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 0, operand: 1, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 1, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 1, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 2, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 2, operand: 1, location: Reg({ id: 1, class: Int }) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 1, class: Int },
      #|      from: Spill(0),
      #|      to: Reg({ id: 1, class: Int }),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 3, class: Int },
      #|      from: Reg({ id: 1, class: Int }),
      #|      to: Spill(0),
      #|      position: After(1),
      #|    },
      #|    {
      #|      value: { id: 3, class: Int },
      #|      from: Spill(0),
      #|      to: Reg({ id: 1, class: Int }),
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
      #|  value_locations: [
      #|    Some(Reg({ id: 0, class: Int })),
      #|    Some(Spill(0)),
      #|    Some(Reg({ id: 0, class: Int })),
      #|    Some(Spill(1)),
      #|  ],
      #|  operand_locations: {
      #|    (0, 0): Reg({ id: 0, class: Int }),
      #|    (0, 1): Reg({ id: 1, class: Int }),
      #|    (1, 0): Reg({ id: 0, class: Int }),
      #|    (1, 1): Reg({ id: 1, class: Int }),
      #|    (2, 0): Reg({ id: 0, class: Int }),
      #|    (2, 1): Reg({ id: 1, class: Int }),
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 0, operand: 1, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 1, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 1, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 2, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 2, operand: 1, location: Reg({ id: 1, class: Int }) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 1, class: Int },
      #|      from: Spill(0),
      #|      to: Reg({ id: 1, class: Int }),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 3, class: Int },
      #|      from: Reg({ id: 1, class: Int }),
      #|      to: Spill(1),
      #|      position: After(1),
      #|    },
      #|    {
      #|      value: { id: 3, class: Int },
      #|      from: Spill(1),
      #|      to: Reg({ id: 1, class: Int }),
      #|      position: Before(2),
      #|    },
      #|  ],
      #|  spill_slots: [{ size: 8, alignment: 8 }, { size: 8, alignment: 8 }],
      #|}
    ),
  )
}

///|
test "both strategies keep the dense live range resident" {
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
      #|  value_locations: [Some(Spill(0)), Some(Reg({ id: 0, class: Int }))],
      #|  operand_locations: {
      #|    (0, 0): Reg({ id: 0, class: Int }),
      #|    (1, 0): Reg({ id: 0, class: Int }),
      #|    (2, 0): Reg({ id: 0, class: Int }),
      #|    (3, 0): Reg({ id: 1, class: Int }),
      #|    (3, 1): Reg({ id: 0, class: Int }),
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 2, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 3, operand: 0, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 3, operand: 1, location: Reg({ id: 0, class: Int }) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(0),
      #|      to: Reg({ id: 1, class: Int }),
      #|      position: Before(3),
      #|    },
      #|  ],
      #|  spill_slots: [{ size: 8, alignment: 8 }],
      #|}
    ),
  )
  inspect(
    allocate_function(
      function,
      environment,
      config=RegallocConfig(strategy=SinglePass),
    ),
    content=(
      #|{
      #|  value_locations: [Some(Spill(0)), Some(Reg({ id: 0, class: Int }))],
      #|  operand_locations: {
      #|    (0, 0): Reg({ id: 0, class: Int }),
      #|    (1, 0): Reg({ id: 0, class: Int }),
      #|    (2, 0): Reg({ id: 0, class: Int }),
      #|    (3, 0): Reg({ id: 1, class: Int }),
      #|    (3, 1): Reg({ id: 0, class: Int }),
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 2, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 3, operand: 0, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 3, operand: 1, location: Reg({ id: 0, class: Int }) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(0),
      #|      to: Reg({ id: 1, class: Int }),
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
      #|  operand_locations: {
      #|    (0, 0): Reg({ id: 0, class: Int }),
      #|    (2, 0): Reg({ id: 0, class: Int }),
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 2, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(0),
      #|      to: Reg({ id: 0, class: Int }),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(0),
      #|      to: Reg({ id: 0, class: Int }),
      #|      position: Before(2),
      #|    },
      #|  ],
      #|  spill_slots: [{ size: 8, alignment: 8 }],
      #|}
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
      #|    Some(Reg({ id: 0, class: Int })),
      #|    Some(Reg({ id: 1, class: Int })),
      #|    Some(Reg({ id: 1, class: Int })),
      #|    Some(Reg({ id: 0, class: Int })),
      #|  ],
      #|  operand_locations: {
      #|    (19, 0): Reg({ id: 1, class: Int }),
      #|    (19, 1): Reg({ id: 0, class: Int }),
      #|    (21, 0): Reg({ id: 0, class: Int }),
      #|    (21, 1): Reg({ id: 0, class: Int }),
      #|    (21, 2): Reg({ id: 0, class: Int }),
      #|    (21, 3): Reg({ id: 0, class: Int }),
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 19, operand: 0, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 19, operand: 1, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 21, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 21, operand: 1, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 21, operand: 2, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 21, operand: 3, location: Reg({ id: 0, class: Int }) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(0),
      #|      to: Reg({ id: 0, class: Int }),
      #|      position: Before(21),
      #|    },
      #|    {
      #|      value: { id: 1, class: Int },
      #|      from: Reg({ id: 0, class: Int }),
      #|      to: Reg({ id: 1, class: Int }),
      #|      position: Edge(source_block=0, successor_index=0),
      #|    },
      #|    {
      #|      value: { id: 2, class: Int },
      #|      from: Reg({ id: 1, class: Int }),
      #|      to: Reg({ id: 0, class: Int }),
      #|      position: Edge(source_block=0, successor_index=0),
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
      #|  operand_locations: {
      #|    (0, 0): Reg({ id: 0, class: Int }),
      #|    (0, 1): Reg({ id: 1, class: Int }),
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 0, operand: 1, location: Reg({ id: 1, class: Int }) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(0),
      #|      to: Reg({ id: 0, class: Int }),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 1, class: Int },
      #|      from: Reg({ id: 1, class: Int }),
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
      #|    to: Reg({ id: 0, class: Int }),
      #|    position: Before(0),
      #|  },
      #|  {
      #|    value: { id: 0, class: Int },
      #|    from: Spill(0),
      #|    to: Reg({ id: 0, class: Int }),
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
      #|    Some(Reg({ id: 2, class: Int })),
      #|    Some(Reg({ id: 0, class: Int })),
      #|    Some(Reg({ id: 1, class: Int })),
      #|    Some(Reg({ id: 2, class: Int })),
      #|    Some(Reg({ id: 0, class: Int })),
      #|    Some(Reg({ id: 1, class: Int })),
      #|    Some(Reg({ id: 3, class: Int })),
      #|  ],
      #|  operand_locations: {
      #|    (1, 0): Reg({ id: 2, class: Int }),
      #|    (1, 1): Reg({ id: 0, class: Int }),
      #|    (1, 2): Reg({ id: 3, class: Int }),
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 1, operand: 0, location: Reg({ id: 2, class: Int }) },
      #|    { instruction: 1, operand: 1, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 2, location: Reg({ id: 3, class: Int }) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 4, class: Int },
      #|      from: Reg({ id: 0, class: Int }),
      #|      to: Reg({ id: 2, class: Int }),
      #|      position: Edge(source_block=1, successor_index=0),
      #|    },
      #|    {
      #|      value: { id: 6, class: Int },
      #|      from: Reg({ id: 3, class: Int }),
      #|      to: Reg({ id: 0, class: Int }),
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
      #|  value_locations: [
      #|    Some(Reg({ id: 1, class: Int })),
      #|    Some(Reg({ id: 0, class: Int })),
      #|    Some(Reg({ id: 1, class: Int })),
      #|  ],
      #|  operand_locations: {
      #|    (0, 0): Reg({ id: 1, class: Int }),
      #|    (1, 0): Reg({ id: 0, class: Int }),
      #|    (2, 0): Reg({ id: 1, class: Int }),
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 1, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 2, operand: 0, location: Reg({ id: 1, class: Int }) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 1, class: Int },
      #|      from: Reg({ id: 0, class: Int }),
      #|      to: Reg({ id: 1, class: Int }),
      #|      position: Edge(source_block=1, successor_index=0),
      #|    },
      #|  ],
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
      #|  value_locations: [Some(Reg({ id: 2, class: Int }))],
      #|  operand_locations: { (0, 0): Reg({ id: 2, class: Int }) },
      #|  operand_assignments: [{ instruction: 0, operand: 0, location: Reg({ id: 2, class: Int }) }],
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
          #|InvalidPreference(
          #|  vreg={ id: 0, class: Int },
          #|  preferred={ id: 9, class: Int },
          #|)
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
      #|  value_locations: [Some(Reg({ id: 1, class: Int }))],
      #|  operand_locations: { (0, 0): Reg({ id: 1, class: Int }) },
      #|  operand_assignments: [{ instruction: 0, operand: 0, location: Reg({ id: 1, class: Int }) }],
      #|  edits: [],
      #|  spill_slots: [],
      #|}
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
      #|  value_locations: [
      #|    Some(Reg({ id: 0, class: Int })),
      #|    Some(Spill(0)),
      #|    Some(Spill(1)),
      #|    Some(Spill(2)),
      #|  ],
      #|  operand_locations: {
      #|    (0, 0): Reg({ id: 1, class: Int }),
      #|    (0, 1): Reg({ id: 2, class: Int }),
      #|    (0, 2): Reg({ id: 0, class: Int }),
      #|    (1, 0): Reg({ id: 0, class: Int }),
      #|    (1, 1): Reg({ id: 0, class: Int }),
      #|    (1, 2): Reg({ id: 0, class: Int }),
      #|    (1, 3): Reg({ id: 0, class: Int }),
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 0, operand: 1, location: Reg({ id: 2, class: Int }) },
      #|    { instruction: 0, operand: 2, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 1, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 2, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 3, location: Reg({ id: 0, class: Int }) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Reg({ id: 0, class: Int }),
      #|      to: Spill(3),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 1, class: Int },
      #|      from: Spill(0),
      #|      to: Reg({ id: 1, class: Int }),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 2, class: Int },
      #|      from: Spill(1),
      #|      to: Reg({ id: 2, class: Int }),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 3, class: Int },
      #|      from: Spill(2),
      #|      to: Reg({ id: 0, class: Int }),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(3),
      #|      to: Reg({ id: 0, class: Int }),
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
      #|  value_locations: [
      #|    Some(Reg({ id: 0, class: Int })),
      #|    Some(Reg({ id: 1, class: Int })),
      #|    Some(Spill(0)),
      #|  ],
      #|  operand_locations: {
      #|    (0, 0): Reg({ id: 1, class: Int }),
      #|    (0, 1): Reg({ id: 0, class: Int }),
      #|    (1, 0): Reg({ id: 0, class: Int }),
      #|    (1, 1): Reg({ id: 0, class: Int }),
      #|    (1, 2): Reg({ id: 0, class: Int }),
      #|    (1, 3): Reg({ id: 0, class: Int }),
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 0, operand: 1, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 1, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 2, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 3, location: Reg({ id: 0, class: Int }) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Reg({ id: 0, class: Int }),
      #|      to: Spill(1),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 2, class: Int },
      #|      from: Spill(0),
      #|      to: Reg({ id: 0, class: Int }),
      #|      position: Before(0),
      #|    },
      #|    {
      #|      value: { id: 0, class: Int },
      #|      from: Spill(1),
      #|      to: Reg({ id: 0, class: Int }),
      #|      position: After(0),
      #|    },
      #|  ],
      #|  spill_slots: [{ size: 8, alignment: 8 }, { size: 8, alignment: 8 }],
      #|}
    ),
  )
}
