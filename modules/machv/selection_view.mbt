///|
/// Dense read-only semantic input exposed by a sealed `SelectionPlan`.
///
/// Every handle returned by this view belongs to the same verified function,
/// so target selection may use its dense index without repeating owner and
/// bounds checks. Collection access borrows canonical storage and remains
/// valid for the lifetime of the sealed plan.
pub struct SelectionView {
  priv construction : FunctionConstruction
  priv layout : Array[Int]
}

///|
/// Read-only view of one verified semantic block.
#valtype
pub struct SelectionBlockView {
  priv construction : FunctionConstruction
  priv index : Int
}

///|
/// Read-only view of one live verified semantic instruction.
#valtype
pub struct SelectionInstructionView {
  priv construction : FunctionConstruction
  priv index : Int
}

///|
/// Read-only view of one verified semantic terminator edge.
#valtype
pub struct SelectionEdgeView {
  priv edge : Edge
}

///|
/// Read-only aggregate terminator shape consumed by target selection.
pub(all) enum SelectionTerminatorView {
  SelectionJump(SelectionEdgeView)
  SelectionBranch(Value, SelectionEdgeView, SelectionEdgeView)
  SelectionSwitch(Value, ArrayView[SwitchCase], SelectionEdgeView)
  SelectionReturn(ArrayView[Value])
  SelectionTailCall(SemanticCall, ArrayView[Value])
  SelectionNoReturnCall(SemanticCall, ArrayView[Value])
  SelectionTrap(TrapReason)
}

///|
/// Read-only terminator record with borrowed root metadata.
#valtype
pub struct SelectionTerminatorRecordView {
  priv record : TerminatorRecord
}

///|
/// Dense stack-object layout known to belong to one sealed selection plan.
#valtype
pub struct SelectionStackObjectView {
  priv construction : FunctionConstruction
  priv index : Int
}

///|
/// Borrow the canonical target-selection view from a sealed plan.
pub fn SelectionPlan::view(self : SelectionPlan) -> SelectionView {
  { construction: self.construction, layout: self.layout, }
}

///|
pub fn SelectionView::name(self : SelectionView) -> String {
  self.construction.name
}

///|
pub fn SelectionView::protocol(self : SelectionView) -> CallProtocol {
  self.construction.protocol
}

///|
pub fn SelectionView::parameter_types(
  self : SelectionView,
) -> ArrayView[ValueType] {
  self.construction.signature.params[:]
}

///|
pub fn SelectionView::result_types(
  self : SelectionView,
) -> ArrayView[ValueType] {
  self.construction.signature.results[:]
}

///|
pub fn SelectionView::parameters(self : SelectionView) -> ArrayView[Value] {
  self.construction.parameters[:]
}

///|
pub fn SelectionView::value_count(self : SelectionView) -> Int {
  self.construction.values.length()
}

///|
/// Return the dense index of a value obtained from this view.
pub fn SelectionView::value_index(_self : SelectionView, value : Value) -> Int {
  value.id
}

///|
pub fn SelectionView::value_type(
  self : SelectionView,
  value : Value,
) -> ValueType {
  self.construction.values[value.id].ty
}

///|
pub fn SelectionView::value_type_at(
  self : SelectionView,
  index : Int,
) -> ValueType {
  self.construction.values[index].ty
}

///|
pub fn SelectionView::block_count(self : SelectionView) -> Int {
  self.construction.blocks.length()
}

///|
pub fn SelectionView::block(
  self : SelectionView,
  index : Int,
) -> SelectionBlockView {
  { construction: self.construction, index, }
}

///|
/// Return the dense index of a block obtained from this view.
pub fn SelectionView::block_index(_self : SelectionView, block : Block) -> Int {
  block.id
}

///|
pub fn SelectionView::layout(self : SelectionView) -> ArrayView[Int] {
  self.layout[:]
}

///|
pub fn SelectionView::instruction_slot_count(self : SelectionView) -> Int {
  self.construction.instructions.length()
}

///|
pub fn SelectionView::instruction_at(
  self : SelectionView,
  index : Int,
) -> SelectionInstructionView? {
  if self.construction.instructions[index].alive {
    Some({ construction: self.construction, index, })
  } else {
    None
  }
}

///|
pub fn SelectionView::instruction(
  self : SelectionView,
  instruction : Instruction,
) -> SelectionInstructionView {
  { construction: self.construction, index: instruction.id, }
}

///|
pub fn SelectionView::stack_object_count(self : SelectionView) -> Int {
  self.construction.stack_objects.length()
}

///|
pub fn SelectionView::stack_object(
  self : SelectionView,
  index : Int,
) -> SelectionStackObjectView {
  { construction: self.construction, index, }
}

///|
pub fn SelectionBlockView::index(self : SelectionBlockView) -> Int {
  self.index
}

///|
pub fn SelectionBlockView::parameters(
  self : SelectionBlockView,
) -> ArrayView[Value] {
  self.construction.blocks[self.index].parameters[:]
}

///|
pub fn SelectionBlockView::instructions(
  self : SelectionBlockView,
) -> ArrayView[Instruction] {
  self.construction.blocks[self.index].instructions[:]
}

///|
pub fn SelectionBlockView::terminator(
  self : SelectionBlockView,
) -> SelectionTerminatorRecordView {
  { record: self.construction.blocks[self.index].terminator.unwrap(), }
}

///|
pub fn SelectionInstructionView::index(self : SelectionInstructionView) -> Int {
  self.index
}

///|
/// Borrow the canonical operation. The returned operation is read-only by
/// contract; target selection must not mutate aggregate payload storage.
pub fn SelectionInstructionView::operation(
  self : SelectionInstructionView,
) -> Operation {
  self.construction.instructions[self.index].operation
}

///|
pub fn SelectionInstructionView::operands(
  self : SelectionInstructionView,
) -> ArrayView[Value] {
  self.construction.instructions[self.index].operands[:]
}

///|
pub fn SelectionInstructionView::results(
  self : SelectionInstructionView,
) -> ArrayView[Value] {
  self.construction.instructions[self.index].results[:]
}

///|
pub fn SelectionInstructionView::metadata(
  self : SelectionInstructionView,
) -> InstructionMetadataView {
  let metadata = self.construction.instructions[self.index].metadata
  {
    source: metadata.source,
    live_gc_roots: metadata.live_gc_roots,
    stack_map: metadata.stack_map,
  }
}

///|
pub fn SelectionEdgeView::target(self : SelectionEdgeView) -> Block {
  self.edge.target
}

///|
pub fn SelectionEdgeView::arguments(
  self : SelectionEdgeView,
) -> ArrayView[Value] {
  self.edge.arguments[:]
}

///|
pub fn SelectionTerminatorRecordView::kind(
  self : SelectionTerminatorRecordView,
) -> SelectionTerminatorView {
  match self.record.kind {
    Jump(edge) => SelectionJump({ edge, })
    Branch(condition, when_true, when_false) =>
      SelectionBranch(condition, { edge: when_true, }, { edge: when_false, })
    Switch(index, cases, default) =>
      SelectionSwitch(index, cases[:], { edge: default, })
    Return(values) => SelectionReturn(values[:])
    TailCall(call, values) => SelectionTailCall(call, values[:])
    NoReturnCall(call, values) => SelectionNoReturnCall(call, values[:])
    Trap(reason) => SelectionTrap(reason)
  }
}

///|
pub fn SelectionTerminatorRecordView::source(
  self : SelectionTerminatorRecordView,
) -> SourceLocation? {
  self.record.metadata.source
}

///|
pub fn SelectionTerminatorRecordView::live_gc_roots(
  self : SelectionTerminatorRecordView,
) -> ArrayView[Value] {
  self.record.metadata.live_gc_roots[:]
}

///|
pub fn SelectionStackObjectView::index(self : SelectionStackObjectView) -> Int {
  self.index
}

///|
pub fn SelectionStackObjectView::handle(
  self : SelectionStackObjectView,
) -> StackObject {
  StackObject::new(self.construction.owner, self.index)
}

///|
pub fn SelectionStackObjectView::size(self : SelectionStackObjectView) -> Int {
  self.construction.stack_objects[self.index].size
}

///|
pub fn SelectionStackObjectView::alignment(
  self : SelectionStackObjectView,
) -> Int {
  self.construction.stack_objects[self.index].alignment
}
