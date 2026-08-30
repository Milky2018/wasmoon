///|
/// Thin non-owning adapter from selected VCode to generic register allocation.
priv struct VCodeFunctionView[Inst] {
  function : @vcode.Function[Inst]
}

///|
fn[Inst] VCodeFunctionView::new(
  function : @vcode.Function[Inst],
) -> VCodeFunctionView[Inst] {
  { function, }
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
  @vcode.reg_class_for_value_type(self.function.allocation_value_type_at(value))
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn value_spill_size(
  self,
  value,
) -> Int {
  regalloc_value_size(self.function.allocation_value_type_at(value))
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn value_spill_alignment(
  self,
  value,
) -> Int {
  regalloc_value_size(self.function.allocation_value_type_at(value))
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn values_share_spill_slot(
  self,
  lhs,
  rhs,
) -> Bool {
  self.function.allocation_value_type_at(lhs) ==
  self.function.allocation_value_type_at(rhs)
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn entry_value_count(
  self,
) -> Int {
  self.function.parameter_count()
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn entry_value_at(
  self,
  parameter,
) -> @regalloc.VirtualReg {
  self.function.allocation_entry_value_at(parameter)
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_count(
  self,
) -> Int {
  self.function.block_count()
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_id_at(
  self,
  block,
) -> Int {
  self.function.allocation_layout_block_id_at(block)
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_parameter_count(
  self,
  block,
) -> Int {
  self.function.allocation_block_parameter_count(block)
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_parameter_at(
  self,
  block,
  parameter,
) -> @regalloc.VirtualReg {
  self.function.allocation_block_parameter_at(block, parameter)
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_instruction_count(
  self,
  block,
) -> Int {
  self.function.allocation_block_instruction_count(block)
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_instruction_at(
  self,
  block,
  instruction,
) -> Int {
  self.function.allocation_block_instruction_at(block, instruction)
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_successor_count(
  self,
  block,
) -> Int {
  self.function.allocation_block_successor_count(block)
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn block_successor_at(
  self,
  block,
  successor,
) -> Int {
  self.function.allocation_block_successor_at(block, successor)
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn edge_argument_count(
  self,
  block,
  successor,
) -> Int {
  self.function.allocation_edge_argument_count(block, successor)
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn edge_argument_at(
  self,
  block,
  successor,
  argument,
) -> @regalloc.VirtualReg {
  self.function.allocation_edge_argument_at(block, successor, argument)
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn instruction_operands(
  self,
  instruction,
) -> ArrayView[@regalloc.Operand] {
  self.function.allocation_instruction_operands(instruction)
}

///|
impl[Inst] @regalloc.FunctionView for VCodeFunctionView[Inst] with fn instruction_clobbers(
  self,
  instruction,
) -> ArrayView[@regalloc.PhysicalReg] {
  self.function.allocation_instruction_clobbers(instruction)
}
