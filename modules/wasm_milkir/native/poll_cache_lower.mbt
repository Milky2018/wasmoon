///|
fn cached_poll_require_pointer(
  context : @adapter.InstructionContext,
  pointer : @lowering.Value,
  slow : @lowering.Block,
) -> Unit {
  let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [pointer], [I64])[0]
  let present = context.create_block([])
  context.branch_int_compare_immediate(NotEqual, bits, 0UL, present, [], slow, [])
  context.switch_to_block(present)
}

///|
fn cached_poll_controls(
  context : @adapter.InstructionContext,
  execution : @lowering.Value,
  layout : PollCacheLayout,
) -> @lowering.Value {
  heap_load(context, execution, layout.controls, Ptr64)
}

///|
fn publish_cached_budget(
  context : @adapter.InstructionContext,
  layout : PollCacheLayout,
  budget : @lowering.Value,
) -> Unit {
  // A positive cached value comes from a callback-free acquisition in this
  // activation. The loop verifier requires publication before every possible
  // change of execution, including faulting instructions and calls.
  let execution = heap_load(
    context,
    context.environment()[0],
    layout.execution,
    Ptr64,
  )
  let controls = cached_poll_controls(context, execution, layout)
  heap_store(context, controls, layout.budget, budget, I32)
}

///|
fn lower_cached_poll(
  context : @adapter.InstructionContext,
  poll : CachedPoll,
  environment : Environment,
) -> Unit {
  match poll {
    Publish(layout) => {
      let cached = context.operands()[0]
      let write = context.create_block([])
      let done = context.create_block([])
      context.branch_int_compare_immediate(
        NotEqual,
        cached,
        0UL,
        write,
        [],
        done,
        [],
      )
      context.switch_to_block(write)
      publish_cached_budget(context, layout, cached)
      context.jump(done, [])
      context.switch_to_block(done)
      context.finish_void()
    }
    Step(layout, fresh) => {
      let charge = context.create_block([I32])
      let slow = context.create_block([])
      let disabled = context.create_block([])
      let done = context.create_block([I32])
      if !fresh {
        let cached = context.operands()[0]
        let cold = context.create_block([])
        let publish = context.create_block([])
        let acquire = context.create_block([])
        context.branch_int_compare_immediate(
          SignedGreaterThan,
          cached,
          1UL,
          charge,
          [cached],
          cold,
          [],
        )
        context.switch_to_block(cold)
        context.branch_int_compare_immediate(
          Equal,
          cached,
          1UL,
          publish,
          [],
          acquire,
          [],
        )
        context.switch_to_block(publish)
        // Let the original runtime poll charge the last unit. It may yield or
        // cancel, so no value from this cache survives its call.
        publish_cached_budget(context, layout, cached)
        context.jump(slow, [])
        context.switch_to_block(acquire)
      }
      let vmctx = context.environment()[0]
      let execution = heap_load(context, vmctx, layout.execution, Ptr64)
      cached_poll_require_pointer(context, execution, slow)
      let controls = cached_poll_controls(context, execution, layout)
      cached_poll_require_pointer(context, controls, slow)
      let callback = heap_load(context, controls, layout.callback, I64)
      let ready = context.create_block([])
      context.branch_int_compare_immediate(
        Equal,
        callback,
        0UL,
        ready,
        [],
        slow,
        [],
      )
      context.switch_to_block(ready)
      let budget = heap_load(context, controls, layout.budget, I32)
      let boundary = context.create_block([])
      context.branch_int_compare_immediate(
        SignedGreaterThan,
        budget,
        1UL,
        charge,
        [budget],
        boundary,
        [],
      )
      context.switch_to_block(boundary)
      context.branch_int_compare_immediate(
        Equal,
        budget,
        1UL,
        slow,
        [],
        disabled,
        [],
      )
      context.switch_to_block(charge)
      let budget = context.block_parameters(charge)[0]
      let remaining = context.emit(IntBinaryImmediate(Sub, 1UL), [budget], [I32])[0]
      context.jump(done, [remaining])
      context.switch_to_block(slow)
      emit_slow_poll(context, environment, vmctx)
      context.jump(disabled, [])
      context.switch_to_block(disabled)
      context.jump(done, [i32_immediate(context, 0)])
      context.switch_to_block(done)
      context.forward_results(context.block_parameters(done))
    }
  }
}
