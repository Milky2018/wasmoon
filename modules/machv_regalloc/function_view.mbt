///|
priv struct VCodeFunctionView[Inst] {
  function : @vcode.Function[Inst]
  layout : Array[@vcode.Block]
  block_to_layout : Array[Int]
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
  { function, layout, block_to_layout }
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
  to_regalloc_class(
    @vcode.reg_class_for_value_type(
      self.function.value_type(self.function.value_at(value).unwrap()).unwrap(),
    ),
  )
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn value_spill_size(
  self,
  value,
) -> Int {
  regalloc_value_size(
    self.function.value_type(self.function.value_at(value).unwrap()).unwrap(),
  )
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn value_spill_alignment(
  self,
  value,
) -> Int {
  regalloc_value_size(
    self.function.value_type(self.function.value_at(value).unwrap()).unwrap(),
  )
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
  Array::makei(self.function.parameter_count(), index => {
    to_regalloc_vreg(self.function, self.function.parameter_at(index).unwrap())
  })
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
  let handle = self.layout[block]
  self.function
  .block_parameters(handle)
  .map(value => to_regalloc_vreg(self.function, value))
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_instructions(
  self,
  block,
) -> Array[Int] {
  let handle = self.layout[block]
  let instructions = self.function.block_body(handle)
  instructions.push(self.function.block_terminator(handle).unwrap())
  instructions.map(instruction => {
    self.function.instruction_index(instruction).unwrap()
  })
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_successors(
  self,
  block,
) -> Array[Int] {
  let terminator = self.function.block_terminator(self.layout[block]).unwrap()
  self.function
  .instruction_successors(terminator)
  .map(edge => {
    self.block_to_layout[self.function.block_index(edge.target).unwrap()]
  })
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn edge_arguments(
  self,
  block,
  successor,
) -> Array[@regalloc.VirtualReg] {
  let terminator = self.function.block_terminator(self.layout[block]).unwrap()
  self.function.instruction_successor_at(terminator, successor).unwrap().arguments.map(value => {
      to_regalloc_vreg(self.function, value)
    },
  )
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn instruction_operands(
  self,
  instruction,
) -> Array[@regalloc.Operand] {
  let handle = self.function.instruction_at(instruction).unwrap()
  self.function
  .instruction_operands(handle)
  .map(operand => to_regalloc_operand(self.function, operand))
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn instruction_clobbers(
  self,
  instruction,
) -> Array[@regalloc.PhysicalReg] {
  let handle = self.function.instruction_at(instruction).unwrap()
  self.function.instruction_clobbers(handle).map(reg => to_regalloc_preg(reg))
}
