///|
priv struct PollRegion {
  execution : Int32
  controls : Int32
  callback : Int32
  budget : Int32
  limit : Int32
  key : Int32
} derive(Eq)

///|
fn poll_region_opcode(region : PollRegion, guard_ : Bool) -> @milkir.ExtOp {
  let values : FixedArray[Int32] = [
    region.execution,
    region.controls,
    region.callback,
    region.budget,
    region.limit,
    region.key,
  ]
  ExtOp(
    @wasm_milkir.WASM_DIALECT,
    if guard_ {
      "native_poll_budget_guard"
    } else {
      "native_poll_budget_charge"
    },
    values,
    effects=Some({
      read: Some(Control),
      write: if guard_ {
        None
      } else {
        Some(Control)
      },
      may_trap: !guard_,
      observable: !guard_,
      pointer_region: None,
      pointer_bytes: 0,
    }),
  )
}

///|
fn decode_poll_region(op : @milkir.ExtOp) -> (PollRegion, Bool)? {
  guard op.dialect == @wasm_milkir.WASM_DIALECT &&
    op.immediates is [execution, controls, callback, budget, limit, key] &&
    limit > 0 &&
    limit <= 256 &&
    key >= 0 else {
    return None
  }
  let guard_ = match op.opcode {
    "native_poll_budget_guard" => true
    "native_poll_budget_charge" => false
    _ => return None
  }
  let region = { execution, controls, callback, budget, limit, key, }
  if op != poll_region_opcode(region, guard_) {
    return None
  }
  Some((region, guard_))
}

///|
fn lower_poll_region(
  context : @adapter.InstructionContext,
  region : PollRegion,
  guard_ : Bool,
) -> Unit {
  let unavailable = context.create_block([])
  let has_execution = context.create_block([])
  let has_controls = context.create_block([])
  let ready = context.create_block([])
  let allowed = context.create_block([])
  let disabled = context.create_block([])
  let done = context.create_block(if guard_ { [I32] } else { [] })
  let execution = heap_load(
    context,
    context.environment()[0],
    region.execution,
    Ptr64,
  )
  context.branch(
    heap_nonzero(context, execution),
    has_execution,
    [],
    unavailable,
    [],
  )
  context.switch_to_block(has_execution)
  let controls = heap_load(context, execution, region.controls, Ptr64)
  context.branch(
    heap_nonzero(context, controls),
    has_controls,
    [],
    unavailable,
    [],
  )
  context.switch_to_block(has_controls)
  let callback = heap_load(context, controls, region.callback, I64)
  context.branch_int_compare_immediate(
    Equal,
    callback,
    0UL,
    ready,
    [],
    unavailable,
    [],
  )
  context.switch_to_block(ready)
  let budget = heap_load(context, controls, region.budget, I32)
  context.branch_int_compare_immediate(
    SignedGreaterThan,
    budget,
    if guard_ {
      region.limit.to_uint64()
    } else {
      1UL
    },
    allowed,
    [],
    disabled,
    [],
  )
  context.switch_to_block(disabled)
  context.branch_int_compare_immediate(
    SignedLessOrEqual,
    budget,
    0UL,
    if guard_ {
      allowed
    } else {
      done
    },
    [],
    unavailable,
    [],
  )
  context.switch_to_block(allowed)
  if guard_ {
    context.jump(done, [i32_immediate(context, 1)])
  } else {
    let remaining = context.emit(IntBinaryImmediate(Sub, 1UL), [budget], [I32])[0]
    let (base, offset) = if region.budget < 0 {
      let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [controls], [I64])[0]
      let address = context.emit(
          IntBinaryImmediate(
            Add,
            region.budget.to_int64().reinterpret_as_uint64(),
          ),
          [bits],
          [I64],
        )[0]
      (context.emit(Convert(Bitcast(I64, Ptr64)), [address], [Ptr64])[0], 0)
    } else {
      (controls, region.budget)
    }
    heap_store(context, base, offset, remaining, I32)
    context.jump(done, [])
  }
  context.switch_to_block(unavailable)
  if guard_ {
    context.jump(done, [i32_immediate(context, 0)])
  } else {
    context.set_trap_terminator(Unreachable)
  }
  context.switch_to_block(done)
  if guard_ {
    context.forward_results(context.block_parameters(done))
  } else {
    context.finish_void()
  }
}
