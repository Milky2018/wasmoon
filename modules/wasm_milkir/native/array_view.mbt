///|
/// Optional non-root, width-tagged array admission hints. The checked helper
/// alone publishes entries; retirement and every physical lifetime change
/// invalidate them. Array operations retain their null, bounds and width checks.
pub(all) struct ArrayViewLayout {
  allocation_control : Int32
  control_enabled : Int32
  array_views : Int32
  view_reference : Int32
  view_payload : Int32
  view_bits : Int32
  view_stride : Int32
}

///|
fn inline_cached_array_projection(
  context : @adapter.InstructionContext,
  environment : Environment,
  layout : ArrayViewLayout,
) -> Unit {
  let slow = context.create_block([])
  let ready = context.create_block([Ptr64])
  let heap = context.emit(
      EnvironmentField(environment.gc_heap_field.unwrap(), Mutable),
      context.environment(),
      [Ptr64],
    )[0]
  view_guard_nonzero(context, heap, slow)
  if !environment.ordinary_view_publication {
    let control = heap_load(context, heap, layout.allocation_control, Ptr64)
    view_guard_nonzero(context, control, slow)
    view_guard_immediate(
      context,
      NotEqual,
      heap_load(context, control, layout.control_enabled, I32),
      0UL,
      slow,
    )
  }
  let ref_pointer = context.emit(GcRefAddress, context.operands(), [Ptr64])[0]
  view_guard_nonzero(context, ref_pointer, slow)
  let word = context.emit(Convert(Bitcast(Ptr64, I64)), [ref_pointer], [I64])[0]
  let slot = context.emit(
      IntBinaryImmediate(And, ((1UL << layout.view_bits) - 1UL) << 1),
      [word],
      [I64],
    )[0]
  let offset = context.emit(
      IntBinary(Mul),
      [
        slot,
        context.emit(I64Const((layout.view_stride / 2).to_uint64()), [], [I64])[0],
      ],
      [I64],
    )[0]
  let base = context.emit(
      PointerOffset,
      [
        heap,
        context.emit(I64Const(layout.array_views.to_uint64()), [], [I64])[0],
      ],
      [Ptr64],
    )[0]
  let entry = context.emit(PointerOffset, [base, offset], [Ptr64])[0]
  let cached = heap_load(context, entry, layout.view_reference, I64)
  let matched = context.create_block([])
  context.branch_int_compare(Equal, cached, word, matched, [], slow, [])
  context.switch_to_block(matched)
  context.jump(ready, [heap_load(context, entry, layout.view_payload, Ptr64)])
  context.switch_to_block(slow)
  let result = emit_array_data(context, environment, heap)
  context.jump(ready, [result])
  context.switch_to_block(ready)
  context.forward_results(context.block_parameters(ready))
}

///|
fn emit_array_data(
  context : @adapter.InstructionContext,
  environment : Environment,
  heap : @lowering.Value,
) -> @lowering.Value {
  context.emit_call_without_roots(
    @native_types.NativeCall::new(
      External((environment.runtime_symbol)(GcArrayDataHeap)),
      @native_types.Signature::new([Ptr64, GcRef64, I32], [Ptr64]),
      Platform,
      @native_types.CallBehavior::new(Read, false, false, false, false),
    ),
    [heap, context.operands()[0], i32_immediate(context, 0)],
    [Ptr64],
  )[0]
}
