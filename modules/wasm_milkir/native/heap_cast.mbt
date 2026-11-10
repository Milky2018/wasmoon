///|
fn emit_checked_ref_cast(
  context : @adapter.InstructionContext,
  environment : Environment,
  reference : @lowering.Value,
  type_index : Int32,
  nullable : Bool,
) -> @lowering.Value {
  context.emit_call_without_roots(
    @native_types.NativeCall::new(
      External((environment.runtime_symbol)(GcRefCast)),
      @native_types.Signature::new([Ptr64, GcRef64, I32, I32], [GcRef64]),
      Platform,
      @native_types.CallBehavior::new(Read, true, false, false, false),
    ),
    [
      context.environment()[0],
      reference,
      i32_immediate(context, type_index),
      bool_immediate(context, nullable),
    ],
    [GcRef64],
  )[0]
}

///|
fn heap_cast_guard(
  context : @adapter.InstructionContext,
  comparison : @lowering.IntComparison,
  left : @lowering.Value,
  right : @lowering.Value,
  slow : @lowering.Block,
) -> Unit {
  let next = context.create_block([])
  context.branch_int_compare(comparison, left, right, next, [], slow, [])
  context.switch_to_block(next)
}

///|
/// Read the authoritative canonical type from the current heap identity page.
/// No object payload or address survives this instruction. Noncanonical
/// references, invalid bounds, nonexact matches and legacy bindings retain
/// the original cast helper and its complete subtype and trap behavior.
fn inline_exact_heap_cast(
  context : @adapter.InstructionContext,
  environment : Environment,
  heap_field : @native_types.EnvironmentField,
  heap_layout : InlineHeapLayout,
  view_layout : StructViewLayout,
  pages_offset : Int32,
  reference : @lowering.Value,
  type_index : Int32,
  nullable : Bool,
) -> Unit {
  let slow = context.create_block([])
  let ready = context.create_block([GcRef64])
  let pointer = context.emit(GcRefAddress, [reference], [Ptr64])[0]
  let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [pointer], [I64])[0]
  let heap = context.emit(
      EnvironmentField(heap_field, Mutable),
      context.environment(),
      [Ptr64],
    )[0]
  let legacy = context.create_block([])
  let validated = context.create_block([])
  if environment.offset_refs is Some((offsets, _)) {
    let packed = context.create_block([])
    let tag = context.emit(IntBinaryImmediate(And, OFFSET_REF_MASK), [bits], [
        I64,
      ])[0]
    context.branch_int_compare_immediate(
      Equal,
      tag,
      OFFSET_REF_TAG,
      packed,
      [],
      legacy,
      [],
    )
    context.switch_to_block(packed)
    // Validate the entire packed reference before using its low identity word.
    // An interior or recycled slot must never become a valid legacy identity.
    checked_offset_header(context, heap, offsets, heap_layout, slow) |> ignore
    context.jump(validated, [])
  } else {
    context.jump(legacy, [])
  }
  context.switch_to_block(legacy)
  let disallowed = context.emit(
      IntBinaryImmediate(And, 0xFFFFFFFF00000001UL),
      [bits],
      [I64],
    )[0]
  view_guard_immediate(context, Equal, disallowed, 0UL, slow)
  context.jump(validated, [])
  context.switch_to_block(validated)
  let bits = context.emit(Convert(I32WrapI64), [bits], [I32])[0]
  let ref_ = context.emit(
      IntBinary(UnsignedShiftRight),
      [bits, i32_immediate(context, 1)],
      [I32],
    )[0]
  let ordinal = context.emit(IntBinaryImmediate(Sub, 1UL), [ref_], [I32])[0]
  view_guard_nonzero(context, heap, slow)
  let objects = heap_load(context, heap, heap_layout.object_count, I32)
  heap_cast_guard(context, UnsignedLessThan, ordinal, objects, slow)
  let pages = heap_load(context, heap, pages_offset, Ptr64)
  view_guard_nonzero(context, pages, slow)
  let page_index = context.emit(
      IntBinary(UnsignedShiftRight),
      [ordinal, i32_immediate(context, heap_layout.identity_page_bits)],
      [I32],
    )[0]
  let slot = context.emit(
      IntBinaryImmediate(And, (1UL << heap_layout.identity_page_bits) - 1UL),
      [ordinal],
      [I32],
    )[0]
  let page = heap_load(
    context,
    heap_index(context, pages, page_index, 3),
    0,
    Ptr64,
  )
  view_guard_nonzero(context, page, slow)
  let actual = heap_load(
    context,
    heap_index(context, page, slot, 2),
    heap_layout.page_types,
    I32,
  )
  let vmctx = context.environment()[0]
  let registry = heap_load(context, vmctx, view_layout.registry_offset, Ptr64)
  view_guard_nonzero(context, registry, slow)
  let type_count = heap_load(
    context,
    registry,
    view_layout.registry_type_count,
    I32,
  )
  heap_cast_guard(context, UnsignedLessThan, actual, type_count, slow)
  let local_count = heap_load(
    context,
    vmctx,
    view_layout.type_count_offset,
    I32,
  )
  view_guard_immediate(
    context,
    SignedGreaterThan,
    local_count,
    type_index.to_uint64(),
    slow,
  )
  let ids = heap_load(context, vmctx, view_layout.type_ids_offset, Ptr64)
  view_guard_nonzero(context, ids, slow)
  let expected = heap_load(context, ids, type_index * 4, I32)
  heap_cast_guard(context, Equal, actual, expected, slow)
  context.jump(ready, [reference])
  context.switch_to_block(slow)
  let result = emit_checked_ref_cast(
    context, environment, reference, type_index, nullable,
  )
  context.jump(ready, [result])
  context.switch_to_block(ready)
  context.forward_results(context.block_parameters(ready))
}
