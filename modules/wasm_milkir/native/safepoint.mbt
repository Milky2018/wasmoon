///|
/// Expand only after semantic optimization and leaf inlining. A poll is an
/// effectful boundary even when its countdown avoids the runtime call. The
/// slow call uses the ordinary precise-root and conservative reentry contract.
fn lower_safepoint_poll(
  context : @adapter.InstructionContext,
  environment : Environment,
  execution_offset : Int32,
  controls_offset : Int32,
  callback_offset : Int32,
  budget_offset : Int32,
) -> Unit {
  let slow = context.create_block([])
  let countdown = context.create_block([])
  let decrement = context.create_block([])
  let done = context.create_block([])
  let has_execution = context.create_block([])
  let has_controls = context.create_block([])
  let enabled = context.create_block([])
  let vmctx = context.environment()[0]
  let execution = heap_load(context, vmctx, execution_offset, Ptr64)
  context.branch(heap_nonzero(context, execution), has_execution, [], slow, [])
  context.switch_to_block(has_execution)
  let controls = heap_load(context, execution, controls_offset, Ptr64)
  context.branch(heap_nonzero(context, controls), has_controls, [], slow, [])
  context.switch_to_block(has_controls)
  let callback = heap_load(context, controls, callback_offset, I64)
  let budget = heap_load(context, controls, budget_offset, I32)
  let zero_word = context.emit(I64Const(0UL), [], [I64])[0]
  let callback_present = context.emit(
      IntCompare(NotEqual),
      [callback, zero_word],
      [I32],
    )[0]
  context.branch(callback_present, slow, [], countdown, [])
  context.switch_to_block(countdown)
  let zero = context.emit(I32Const(0U), [], [I32])[0]
  let one = context.emit(I32Const(1U), [], [I32])[0]
  let active = context.emit(IntCompare(SignedGreaterThan), [budget, zero], [I32])[0]
  context.branch(active, enabled, [], done, [])
  context.switch_to_block(enabled)
  let expired = context.emit(IntCompare(Equal), [budget, one], [I32])[0]
  context.branch(expired, slow, [], decrement, [])
  context.switch_to_block(decrement)
  let remaining = context.emit(IntBinary(Sub), [budget, one], [I32])[0]
  let (budget_base, budget_offset) = if budget_offset < 0 {
    let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [controls], [I64])[0]
    let address = context.emit(
        IntBinaryImmediate(
          Add,
          budget_offset.to_int64().reinterpret_as_uint64(),
        ),
        [bits],
        [I64],
      )[0]
    (context.emit(Convert(Bitcast(I64, Ptr64)), [address], [Ptr64])[0], 0)
  } else {
    (controls, budget_offset)
  }
  heap_store(context, budget_base, budget_offset, remaining, I32)
  context.jump(done, [])
  context.switch_to_block(slow)
  context.emit_call(
    @native_types.NativeCall::new(
      External((environment.runtime_symbol)(CancelPoll)),
      @native_types.Signature::new([Ptr64], []),
      Platform,
      @native_types.CallBehavior::conservative(),
    ),
    [vmctx],
    [],
  )
  |> ignore
  context.jump(done, [])
  context.switch_to_block(done)
  context.finish_void()
}
