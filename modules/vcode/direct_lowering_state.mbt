///|
priv struct DirectStackObjectRequest {
  size : Int32
  alignment : Int32
}

///|
/// State owned by one streaming VCode construction, shared by native targets.
pub struct DirectLoweringState[Inst, Failure] {
  builder : CheckedBuilder[Inst]
  context : LoweringContext
  protocol : @native.CallProtocol
  signature : @native.Signature
  result_area : Value?
  on_event : (TargetCompileEvent) -> Unit
  priv values : Array[Value]
  priv value_types : Array[@native.ValueType]
  priv blocks : Array[Block]
  priv layout : Array[Block]
  priv stack_objects : Array[DirectStackObjectRequest]
  priv operands : Array[Value]
  priv operand_types : Array[@native.ValueType]
  priv roots : Array[Value]
  priv mut instruction_index : Int32
  priv mut first_error : Failure?
  priv mut constructed : Function[Inst]?
}

///|
pub fn[Inst, Failure] DirectLoweringState::new(
  builder : CheckedBuilder[Inst],
  context : LoweringContext,
  protocol : @native.CallProtocol,
  signature : @native.Signature,
  values : Array[Value],
  result_area : Value?,
  on_event : (TargetCompileEvent) -> Unit,
) -> DirectLoweringState[Inst, Failure] {
  let entry = builder.entry_block()
  {
    builder,
    context,
    protocol,
    signature,
    result_area,
    on_event,
    values,
    value_types: signature.params.copy(),
    blocks: [entry],
    layout: [entry],
    stack_objects: [],
    operands: [],
    operand_types: [],
    roots: [],
    instruction_index: 0,
    first_error: None,
    constructed: None,
  }
}

///|
pub fn[Inst, Failure] DirectLoweringState::record_error(
  self : DirectLoweringState[Inst, Failure],
  error : Failure,
) -> Unit {
  if self.first_error is None {
    self.first_error = Some(error)
  }
}

///|
pub fn[Inst, Failure] DirectLoweringState::target_value(
  self : DirectLoweringState[Inst, Failure],
  id : Int32,
) -> Value {
  self.values[id]
}

///|
fn[Inst, Failure] DirectLoweringState::target_values_into(
  self : DirectLoweringState[Inst, Failure],
  ids : Array[Int32],
  values : Array[Value],
) -> Array[Value] {
  values.clear()
  for id in ids {
    values.push(self.target_value(id))
  }
  values
}

///|
pub fn[Inst, Failure] DirectLoweringState::target_values(
  self : DirectLoweringState[Inst, Failure],
  ids : Array[Int32],
) -> Array[Value] {
  ids.map(id => self.target_value(id))
}

///|
pub fn[Inst, Failure] DirectLoweringState::create_block(
  self : DirectLoweringState[Inst, Failure],
  parameter_types : Array[@native.ValueType],
) -> (Int32, Array[Int32]) {
  let block = self.builder.create_block(parameter_types)
  let block_id = self.blocks.length()
  self.blocks.push(block)
  let parameters : Array[Int32] = []
  for index, ty in parameter_types {
    let value = self.builder.block_parameter(block, index) catch {
      _ => abort("direct lowering could not read a new block parameter")
    }
    parameters.push(self.values.length())
    self.values.push(value)
    self.value_types.push(ty)
  }
  (block_id, parameters)
}

///|
pub fn[Inst, Failure] DirectLoweringState::create_stack_object(
  self : DirectLoweringState[Inst, Failure],
  size : Int32,
  alignment : Int32,
) -> Int32 {
  let id = self.stack_objects.length()
  self.stack_objects.push({ size, alignment, })
  id
}

///|
pub fn[Inst, Failure] DirectLoweringState::switch_to_block(
  self : DirectLoweringState[Inst, Failure],
  block_id : Int32,
) -> Unit {
  let block = self.blocks[block_id]
  self.layout.push(block)
}

///|
pub fn[Inst, Failure] DirectLoweringState::block(
  self : DirectLoweringState[Inst, Failure],
  id : Int32,
) -> Block {
  self.blocks[id]
}

///|
pub fn[Inst, Failure] DirectLoweringState::value_type(
  self : DirectLoweringState[Inst, Failure],
  id : Int32,
) -> @native.ValueType {
  self.value_types[id]
}

///|
pub fn[Inst, Failure] DirectLoweringState::stack_object(
  self : DirectLoweringState[Inst, Failure],
  id : Int32,
) -> (Int32, Int32) {
  let request = self.stack_objects[id]
  (request.size, request.alignment)
}

///|
pub fn[Inst, Failure] DirectLoweringState::instruction_index(
  self : DirectLoweringState[Inst, Failure],
) -> Int32 {
  self.instruction_index
}

///|
pub fn[Inst, Failure] DirectLoweringState::first_error(
  self : DirectLoweringState[Inst, Failure],
) -> Failure? {
  self.first_error
}

///|
pub fn[Inst, Failure] DirectLoweringState::constructed_function(
  self : DirectLoweringState[Inst, Failure],
) -> Function[Inst]? {
  self.constructed
}

///|
/// Return a new semantic value ID backed by the same untraced machine word.
pub fn[Inst, Failure] DirectLoweringState::alias_word_bitcast(
  self : DirectLoweringState[Inst, Failure],
  operand_ids : Array[Int32],
  result_types : Array[@native.ValueType],
  from : @native.ValueType,
  to : @native.ValueType,
) -> Int32? {
  if operand_ids is [operand_id] &&
    result_types is [result_type] &&
    self.value_types[operand_id] == from &&
    result_type == to &&
    ((from == I64 && to == Ptr64) || (from == Ptr64 && to == I64)) {
    let id = self.values.length()
    self.values.push(self.target_value(operand_id))
    self.value_types.push(result_type)
    self.instruction_index += 1
    Some(id)
  } else {
    None
  }
}

///|
/// These buffers are consumed synchronously by selection.
pub fn[Inst, Failure] DirectLoweringState::instruction_operands(
  self : DirectLoweringState[Inst, Failure],
  operand_ids : Array[Int32],
  root_ids : Array[Int32],
) -> (Array[Value], Array[@native.ValueType], Array[Value]) {
  let operands = self.target_values_into(operand_ids, self.operands)
  self.operand_types.clear()
  for id in operand_ids {
    self.operand_types.push(self.value_types[id])
  }
  let roots = self.target_values_into(root_ids, self.roots)
  (operands, self.operand_types, roots)
}

///|
pub fn[Inst, Failure] DirectLoweringState::record_results(
  self : DirectLoweringState[Inst, Failure],
  results : Array[Value],
  result_types : Array[@native.ValueType],
) -> Array[Int32] {
  self.instruction_index += 1
  let ids : Array[Int32] = []
  for index, value in results {
    ids.push(self.values.length())
    self.values.push(value)
    self.value_types.push(result_types[index])
  }
  ids
}

///|
pub fn[Inst, Failure] DirectLoweringState::finish_construction(
  self : DirectLoweringState[Inst, Failure],
  build_failure : (VCodeBuildError) -> Failure,
) -> Unit {
  if self.constructed is Some(_) {
    return
  }
  let lowered = self.builder.finish() catch {
    error => {
      self.record_error(build_failure(error))
      return
    }
  }
  lowered.set_layout(self.layout) catch {
    error => {
      self.record_error(build_failure(error))
      return
    }
  }
  self.constructed = Some(lowered)
}

///|
/// Materialize typed definitions only when a raw word alias crosses a block edge.
pub fn[Inst, Failure] DirectLoweringState::edge(
  self : DirectLoweringState[Inst, Failure],
  block : Block,
  target : Int32,
  ids : Array[Int32],
  make_move : (@native.ValueType) -> Inst,
) -> Edge raise VCodeBuildError {
  let values : Array[Value] = []
  for id in ids {
    let value = self.target_value(id)
    let expected = self.value_type(id)
    let needs_move = match expected {
      Ptr64 => self.builder.value_type(value) == Some(I64)
      I64 => self.builder.value_type(value) == Some(Ptr64)
      _ => false
    }
    if needs_move {
      let (_, results) = self.builder.append_body(
        block,
        make_move(expected),
        [Input::any(value)],
        [Output::any(expected)],
        [],
        InstructionMetadata::empty(),
      )
      values.push(results[0])
    } else {
      values.push(value)
    }
  }
  Edge::new(self.block(target), values)
}

///|
pub fn[Inst, Failure] DirectLoweringState::switch_targets(
  self : DirectLoweringState[Inst, Failure],
  block : Block,
  cases : Array[@lowering.TargetSwitchCase],
  default_target : Int32,
  default_arguments : Array[Int32],
  make_move : (@native.ValueType) -> Inst,
) -> (Array[UInt64], Array[Edge]) raise VCodeBuildError {
  let keys : Array[UInt64] = []
  let edges : Array[Edge] = []
  for case in cases {
    keys.push(case.bits)
    edges.push(self.edge(block, case.target, case.arguments, make_move))
  }
  edges.push(self.edge(block, default_target, default_arguments, make_move))
  (keys, edges)
}

///|
/// Attach the recorded live roots when sealing a block.
pub fn[Inst, Failure] DirectLoweringState::terminator_metadata(
  self : DirectLoweringState[Inst, Failure],
  source : @native.SourceLocation?,
  live_gc_roots : Array[Int32],
) -> InstructionMetadata {
  InstructionMetadata::new(
    source?,
    live_gc_roots=self.target_values(live_gc_roots),
  )
}
