///|
priv struct VCodeFunctionView {
  value_types : Array[@semantic.ValueType]
  value_classes : Array[@regalloc.RegClass]
  value_sizes : Array[Int]
  entry_values : Array[@regalloc.VirtualReg]
  block_ids : Array[Int]
  parameter_offsets : Array[Int]
  parameters : Array[@regalloc.VirtualReg]
  instruction_offsets : Array[Int]
  instructions : Array[Int]
  successor_offsets : Array[Int]
  successors : Array[Int]
  edge_argument_offsets : Array[Int]
  edge_arguments : Array[@regalloc.VirtualReg]
  operand_offsets : Array[Int]
  operands : Array[@regalloc.Operand]
  clobber_offsets : Array[Int]
  clobbers : Array[@regalloc.PhysicalReg]
}

///|
fn[Inst] VCodeFunctionView::new(
  function : @vcode.Function[Inst],
) -> VCodeFunctionView {
  let block_to_layout = Array::make(function.block_count(), -1)
  for layout_index in 0..<function.block_count() {
    let block = function.layout_block_at(layout_index).unwrap()
    block_to_layout[function.block_index(block).unwrap()] = layout_index
  }
  let value_types : Array[@semantic.ValueType] = []
  let value_classes : Array[@regalloc.RegClass] = []
  let value_sizes : Array[Int] = []
  for value_index in 0..<function.value_count() {
    let ty = function
      .value_type(function.value_at(value_index).unwrap())
      .unwrap()
    value_types.push(ty)
    value_classes.push(@vcode.reg_class_for_value_type(ty))
    value_sizes.push(regalloc_value_size(ty))
  }
  let entry_values = Array::makei(function.parameter_count(), index => {
    to_regalloc_vreg(function, function.parameter_at(index).unwrap())
  })
  let block_ids : Array[Int] = []
  let parameter_offsets : Array[Int] = []
  let parameters : Array[@regalloc.VirtualReg] = []
  let instruction_offsets : Array[Int] = []
  let instructions : Array[Int] = []
  let successor_offsets : Array[Int] = []
  let successors : Array[Int] = []
  let edge_argument_offsets : Array[Int] = []
  let edge_arguments : Array[@regalloc.VirtualReg] = []
  for block_index in 0..<function.block_count() {
    let block = function.layout_block_at(block_index).unwrap()
    block_ids.push(function.block_index(block).unwrap())
    parameter_offsets.push(parameters.length())
    for parameter in 0..<function.block_parameter_count(block) {
      parameters.push(
        to_regalloc_vreg(
          function,
          function.block_parameter_at(block, parameter).unwrap(),
        ),
      )
    }
    instruction_offsets.push(instructions.length())
    for instruction in 0..<function.block_instruction_count(block) {
      instructions.push(
        function
        .instruction_index(
          function.block_instruction_at(block, instruction).unwrap(),
        )
        .unwrap(),
      )
    }
    successor_offsets.push(successors.length())
    let terminator = function.block_terminator(block).unwrap()
    for successor in 0..<function.instruction_successor_count(terminator) {
      let target = function
        .instruction_successor_target(terminator, successor)
        .unwrap()
      successors.push(block_to_layout[function.block_index(target).unwrap()])
      edge_argument_offsets.push(edge_arguments.length())
      for
        argument in 0..<function.instruction_successor_argument_count(
          terminator, successor,
        ) {
        edge_arguments.push(
          to_regalloc_vreg(
            function,
            function
            .instruction_successor_argument_at(terminator, successor, argument)
            .unwrap(),
          ),
        )
      }
    }
  }
  parameter_offsets.push(parameters.length())
  instruction_offsets.push(instructions.length())
  successor_offsets.push(successors.length())
  edge_argument_offsets.push(edge_arguments.length())
  let operand_offsets : Array[Int] = []
  let operands : Array[@regalloc.Operand] = []
  let clobber_offsets : Array[Int] = []
  let clobbers : Array[@regalloc.PhysicalReg] = []
  for instruction_index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(instruction_index).unwrap()
    operand_offsets.push(operands.length())
    for operand in 0..<function.instruction_operand_count(instruction) {
      operands.push(
        to_regalloc_operand(
          function,
          function.instruction_operand_at(instruction, operand).unwrap(),
        ),
      )
    }
    clobber_offsets.push(clobbers.length())
    for clobber in 0..<function.instruction_clobber_count(instruction) {
      clobbers.push(
        function.instruction_clobber_at(instruction, clobber).unwrap(),
      )
    }
  }
  operand_offsets.push(operands.length())
  clobber_offsets.push(clobbers.length())
  {
    value_types,
    value_classes,
    value_sizes,
    entry_values,
    block_ids,
    parameter_offsets,
    parameters,
    instruction_offsets,
    instructions,
    successor_offsets,
    successors,
    edge_argument_offsets,
    edge_arguments,
    operand_offsets,
    operands,
    clobber_offsets,
    clobbers,
  }
}

///|
fn regalloc_value_size(ty : @semantic.ValueType) -> Int {
  match ty {
    I32 | F32 => 4
    I64 | F64 | Ptr64 | GcRef64 => 8
    V128 => 16
  }
}

///|
fn to_regalloc_operand_constraint(
  constraint : @vcode.OperandConstraint,
) -> @regalloc.OperandConstraint {
  match constraint {
    Any => AnyReg
    AnyLocation => AnyLocation
    Fixed(reg) => FixedReg(reg)
    TiedTo(_) => AnyReg
  }
}

///|
fn[Inst] to_regalloc_operand(
  function : @vcode.Function[Inst],
  operand : @vcode.Operand,
) -> @regalloc.Operand {
  {
    vreg: to_regalloc_vreg(function, operand.value),
    role: operand.role,
    constraint: to_regalloc_operand_constraint(operand.constraint),
    preference: operand.preference,
    tie_id: operand.tie_id,
    timing: operand.timing,
  }
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn value_count(self) -> Int {
  self.value_types.length()
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn value_class(
  self,
  value,
) -> @regalloc.RegClass {
  self.value_classes[value]
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn value_spill_size(
  self,
  value,
) -> Int {
  self.value_sizes[value]
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn value_spill_alignment(
  self,
  value,
) -> Int {
  self.value_sizes[value]
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn values_share_spill_slot(
  self,
  lhs,
  rhs,
) -> Bool {
  self.value_types[lhs] == self.value_types[rhs]
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn entry_values(self) -> ArrayView[
  @regalloc.VirtualReg,
] {
  self.entry_values[:]
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn block_count(self) -> Int {
  self.block_ids.length()
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn block_id_at(
  self,
  index,
) -> Int {
  self.block_ids[index]
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn block_parameters(
  self,
  block,
) -> ArrayView[@regalloc.VirtualReg] {
  self.parameters[self.parameter_offsets[block]:self.parameter_offsets[block + 1]]
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn block_instructions(
  self,
  block,
) -> ArrayView[Int] {
  self.instructions[self.instruction_offsets[block]:self.instruction_offsets[block +
  1]]
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn block_successors(
  self,
  block,
) -> ArrayView[Int] {
  self.successors[self.successor_offsets[block]:self.successor_offsets[block + 1]]
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn edge_arguments(
  self,
  block,
  successor,
) -> ArrayView[@regalloc.VirtualReg] {
  let edge = self.successor_offsets[block] + successor
  self.edge_arguments[self.edge_argument_offsets[edge]:self.edge_argument_offsets[edge +
  1]]
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn instruction_operands(
  self,
  instruction,
) -> ArrayView[@regalloc.Operand] {
  self.operands[self.operand_offsets[instruction]:self.operand_offsets[instruction +
  1]]
}

///|
impl @regalloc.FunctionView for VCodeFunctionView with fn instruction_clobbers(
  self,
  instruction,
) -> ArrayView[@regalloc.PhysicalReg] {
  self.clobbers[self.clobber_offsets[instruction]:self.clobber_offsets[instruction +
  1]]
}
