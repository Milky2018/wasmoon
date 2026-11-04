///|
fn DirectBuilder::frame_emit(
  self : DirectBuilder,
  operation : Operation,
  operands : Array[Value],
  results : Array[@native.ValueType],
) -> Array[Value] {
  self.emit_raw(operation, operands, results, InstructionMetadata::empty())
}

///|
fn DirectBuilder::frame_load(
  self : DirectBuilder,
  base : Value,
  offset : Int32,
) -> Value {
  let (base, offset) = if offset < 0 {
    let bits = self.frame_emit(Convert(Bitcast(Ptr64, I64)), [base], [I64])[0]
    let bits = self.frame_emit(
        IntBinaryImmediate(Add, offset.to_int64().reinterpret_as_uint64()),
        [bits],
        [I64],
      )[0]
    (self.frame_emit(Convert(Bitcast(I64, Ptr64)), [bits], [Ptr64])[0], 0)
  } else {
    (base, offset)
  }
  self.frame_emit(
    Load(LoadSpec::new(W64, None, Ptr64, offset.to_uint64(), Little, None)),
    [base],
    [Ptr64],
  )[0]
}

///|
fn DirectBuilder::frame_store(
  self : DirectBuilder,
  base : Value,
  offset : Int32,
  value : Value,
  type_ : @native.ValueType,
) -> Unit {
  self.frame_emit(
    Store(StoreSpec::new(W64, type_, offset.to_uint64(), Little, None)),
    [base, value],
    [],
  )
  |> ignore
}

///|
fn DirectBuilder::frame_guard(
  self : DirectBuilder,
  pointer : Value,
  slow : Block,
) -> Unit {
  let next = self.create_block([])
  let bits = self.frame_emit(Convert(Bitcast(Ptr64, I64)), [pointer], [I64])[0]
  self.branch_int_compare_immediate(NotEqual, bits, 0UL, next, [], slow, [])
  self.switch_to_block(next)
}

///|
fn DirectBuilder::frame_execution(
  self : DirectBuilder,
  environment : Value,
  layout : InlineFunctionRootFrameLayout,
  slow : Block,
) -> Value {
  self.frame_guard(environment, slow)
  let execution = self.frame_load(environment, layout.execution_offset)
  self.frame_guard(execution, slow)
  let active = self.frame_load(execution, layout.active_offset)
  self.frame_guard(active, slow)
  execution
}

///|
/// Emit only the admitted non-calling path, then select the original helper
/// block. Root publication, precise masks and unwind markers use the same frame.
fn DirectBuilder::prepare_inline_frame_enter(
  self : DirectBuilder,
  environment : Value,
  header : Value,
  roots : Value,
  mask : Value,
  count : Int32,
  layout : InlineFunctionRootFrameLayout,
) -> Block {
  let slow = self.create_block([])
  let ready = self.create_block([])
  let execution = self.frame_execution(environment, layout, slow)
  let previous = self.frame_load(execution, layout.head_offset)
  self.frame_store(header, 0, previous, Ptr64)
  self.frame_store(header, 8, roots, Ptr64)
  self.frame_store(header, 16, mask, Ptr64)
  let count = self.frame_emit(I64Const(count.to_uint64()), [], [I64])[0]
  self.frame_store(header, 24, count, I64)
  self.frame_store(execution, layout.head_offset, header, Ptr64)
  self.jump(ready, [])
  self.switch_to_block(slow)
  ready
}

///|
/// A mismatched chain head always selects the original trapping helper.
fn DirectBuilder::prepare_inline_frame_leave(
  self : DirectBuilder,
  environment : Value,
  header : Value,
  layout : InlineFunctionRootFrameLayout,
) -> Block {
  let slow = self.create_block([])
  let ready = self.create_block([])
  let execution = self.frame_execution(environment, layout, slow)
  let current = self.frame_load(execution, layout.head_offset)
  let current = self.frame_emit(Convert(Bitcast(Ptr64, I64)), [current], [I64])[0]
  let expected = self.frame_emit(Convert(Bitcast(Ptr64, I64)), [header], [I64])[0]
  let matching = self.create_block([])
  self.branch_int_compare(Equal, current, expected, matching, [], slow, [])
  self.switch_to_block(matching)
  let previous = self.frame_load(header, 0)
  self.frame_store(execution, layout.head_offset, previous, Ptr64)
  self.jump(ready, [])
  self.switch_to_block(slow)
  ready
}
