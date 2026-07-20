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
impl FunctionView for CfgTestFunction with fn block_parameters(_self, _block) -> Array[
  VirtualReg,
] {
  []
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
  _self,
  _block,
  _successor,
) -> Array[VirtualReg] {
  []
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
test "backtracking evicts a cheaper live range while single pass does not" {
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
      #|  value_locations: [Some(Reg({ id: 0, class: Int })), Some(Spill(0))],
      #|  operand_locations: {
      #|    (0, 0): Reg({ id: 1, class: Int }),
      #|    (1, 0): Reg({ id: 1, class: Int }),
      #|    (2, 0): Reg({ id: 1, class: Int }),
      #|    (3, 0): Reg({ id: 0, class: Int }),
      #|    (3, 1): Reg({ id: 1, class: Int }),
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 1, operand: 0, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 2, operand: 0, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 3, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 3, operand: 1, location: Reg({ id: 1, class: Int }) },
      #|  ],
      #|  edits: [
      #|    {
      #|      value: { id: 1, class: Int },
      #|      from: Reg({ id: 1, class: Int }),
      #|      to: Spill(0),
      #|      position: After(0),
      #|    },
      #|    {
      #|      value: { id: 1, class: Int },
      #|      from: Spill(0),
      #|      to: Reg({ id: 1, class: Int }),
      #|      position: Before(1),
      #|    },
      #|    {
      #|      value: { id: 1, class: Int },
      #|      from: Spill(0),
      #|      to: Reg({ id: 1, class: Int }),
      #|      position: Before(2),
      #|    },
      #|    {
      #|      value: { id: 1, class: Int },
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
      [Operand::use_reg(value(0))],
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
      #|  },
      #|  operand_assignments: [
      #|    { instruction: 0, operand: 0, location: Reg({ id: 1, class: Int }) },
      #|    { instruction: 0, operand: 1, location: Reg({ id: 2, class: Int }) },
      #|    { instruction: 0, operand: 2, location: Reg({ id: 0, class: Int }) },
      #|    { instruction: 1, operand: 0, location: Reg({ id: 0, class: Int }) },
      #|  ],
      #|  edits: [
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
      #|      value: { id: 0, class: Int },
      #|      from: Reg({ id: 0, class: Int }),
      #|      to: Spill(3),
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
