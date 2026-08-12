///|
priv struct VCodeFunctionView[Inst] {
  function : @vcode.Function[Inst]
  layout : Array[@vcode.Block]
  value_classes : Array[@regalloc.RegClass]
  value_sizes : Array[Int]
  entry : Array[@regalloc.VirtualReg]
  parameters : Array[Array[@regalloc.VirtualReg]]
  instructions : Array[Array[Int]]
  successors : Array[Array[Int]]
  edge_args : Array[Array[Array[@regalloc.VirtualReg]]]
  operands : Array[Array[@regalloc.Operand]]
  clobbers : Array[Array[@regalloc.PhysicalReg]]
}

///|
fn[Inst] VCodeFunctionView::new(
  function : @vcode.Function[Inst],
) -> VCodeFunctionView[Inst] {
  let layout = function.layout()
  let block_to_layout = Array::make(function.block_count(), -1)
  for layout_index, block in layout {
    block_to_layout[function.block_index(block).unwrap()] = layout_index
  }
  let value_classes : Array[@regalloc.RegClass] = []
  let value_sizes : Array[Int] = []
  for value_index in 0..<function.value_count() {
    let value = function.value_at(value_index).unwrap()
    let ty = function.value_type(value).unwrap()
    value_classes.push(to_regalloc_class(@vcode.reg_class_for_value_type(ty)))
    value_sizes.push(regalloc_value_size(ty))
  }
  let entry = Array::makei(function.parameter_count(), index => {
    to_regalloc_vreg(function, function.parameter_at(index).unwrap())
  })
  let parameters : Array[Array[@regalloc.VirtualReg]] = []
  let instructions : Array[Array[Int]] = []
  let successors : Array[Array[Int]] = []
  let edge_args : Array[Array[Array[@regalloc.VirtualReg]]] = []
  for block in layout {
    parameters.push(
      function
      .block_parameters(block)
      .map(value => to_regalloc_vreg(function, value)),
    )
    let block_instructions = function.block_body(block)
    let terminator = function.block_terminator(block).unwrap()
    block_instructions.push(terminator)
    instructions.push(
      block_instructions.map(instruction => {
        function.instruction_index(instruction).unwrap()
      }),
    )
    let block_successors : Array[Int] = []
    let block_edge_args : Array[Array[@regalloc.VirtualReg]] = []
    for edge in function.instruction_successors(terminator) {
      block_successors.push(
        block_to_layout[function.block_index(edge.target).unwrap()],
      )
      block_edge_args.push(
        edge.arguments.map(value => to_regalloc_vreg(function, value)),
      )
    }
    successors.push(block_successors)
    edge_args.push(block_edge_args)
  }
  let operands : Array[Array[@regalloc.Operand]] = []
  let clobbers : Array[Array[@regalloc.PhysicalReg]] = []
  for instruction_index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(instruction_index).unwrap()
    operands.push(
      function
      .instruction_operands(instruction)
      .map(operand => to_regalloc_operand(function, operand)),
    )
    clobbers.push(
      function
      .instruction_clobbers(instruction)
      .map(reg => to_regalloc_preg(reg)),
    )
  }
  {
    function,
    layout,
    value_classes,
    value_sizes,
    entry,
    parameters,
    instructions,
    successors,
    edge_args,
    operands,
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
fn to_regalloc_operand_role(role : @vcode.OperandRole) -> @regalloc.OperandRole {
  match role {
    Use => Use
    Def => Def
  }
}

///|
fn to_regalloc_operand_timing(
  timing : @vcode.OperandTiming,
) -> @regalloc.OperandTiming {
  match timing {
    Early => Early
    Late => Late
  }
}

///|
fn to_regalloc_operand_constraint(
  constraint : @vcode.OperandConstraint,
) -> @regalloc.OperandConstraint {
  match constraint {
    Any => AnyReg
    AnyLocation => AnyLocation
    Fixed(reg) => FixedReg(to_regalloc_preg(reg))
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
    role: to_regalloc_operand_role(operand.role),
    constraint: to_regalloc_operand_constraint(operand.constraint),
    preference: operand.preference.map(to_regalloc_preg),
    tie_id: operand.tie_id,
    timing: to_regalloc_operand_timing(operand.timing),
  }
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn value_count(
  self,
) -> Int {
  self.function.value_count()
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn value_class(
  self,
  value,
) -> @regalloc.RegClass {
  self.value_classes[value]
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn value_spill_size(
  self,
  value,
) -> Int {
  self.value_sizes[value]
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn value_spill_alignment(
  self,
  value,
) -> Int {
  self.value_sizes[value]
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn values_share_spill_slot(
  self,
  lhs,
  rhs,
) -> Bool {
  self.function.value_type(self.function.value_at(lhs).unwrap()) ==
  self.function.value_type(self.function.value_at(rhs).unwrap())
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn entry_values(
  self,
) -> Array[@regalloc.VirtualReg] {
  self.entry
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_count(
  self,
) -> Int {
  self.layout.length()
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_id_at(
  self,
  index,
) -> Int {
  self.function.block_index(self.layout[index]).unwrap()
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_parameters(
  self,
  block,
) -> Array[@regalloc.VirtualReg] {
  self.parameters[block]
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_instructions(
  self,
  block,
) -> Array[Int] {
  self.instructions[block]
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_successors(
  self,
  block,
) -> Array[Int] {
  self.successors[block]
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn edge_arguments(
  self,
  block,
  successor,
) -> Array[@regalloc.VirtualReg] {
  self.edge_args[block][successor]
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn instruction_operands(
  self,
  instruction,
) -> Array[@regalloc.Operand] {
  self.operands[instruction]
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn instruction_clobbers(
  self,
  instruction,
) -> Array[@regalloc.PhysicalReg] {
  self.clobbers[instruction]
}
