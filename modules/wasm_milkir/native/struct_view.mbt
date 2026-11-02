///|
/// Optional embedding-owned admission hints, independent of allocation layout.
/// Only complete checked helpers may publish exact canonical keys. Payload
/// movement, retirement, rollback, type changes and heap replacement must
/// invalidate affected hints; close clears them all. The control word excludes
/// full verification mode.
/// Entries are 32-byte non-root records; the existing borrow proof still limits
/// every resulting payload pointer to its physical address epoch.
pub(all) struct StructViewLayout {
  type_ids_offset : Int32
  type_count_offset : Int32
  allocation_control : Int32
  control_enabled : Int32
  struct_views : Int32
  view_reference : Int32
  view_identity : Int32
  view_fields : Int32
  view_shape : Int32
  view_payload : Int32
  view_bits : Int32
}

///|
fn view_guard_nonzero(
  context : @adapter.InstructionContext,
  pointer : @lowering.Value,
  slow : @lowering.Block,
) -> Unit {
  let next = context.create_block([])
  let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [pointer], [I64])[0]
  context.branch_int_compare_immediate(NotEqual, bits, 0UL, next, [], slow, [])
  context.switch_to_block(next)
}

///|
fn view_guard_immediate(
  context : @adapter.InstructionContext,
  comparison : @lowering.IntComparison,
  value : @lowering.Value,
  bits : UInt64,
  slow : @lowering.Block,
) -> Unit {
  let next = context.create_block([])
  context.branch_int_compare_immediate(
    comparison,
    value,
    bits,
    next,
    [],
    slow,
    [],
  )
  context.switch_to_block(next)
}

///|
/// Only the complete helper publishes admitted exact-layout keys. The generated
/// hit path repeats that key; every miss, verifier mode and unsupported layout
/// selects the same trapping accessor. Existing borrow epochs remain unchanged.
fn inline_cached_struct_projection(
  context : @adapter.InstructionContext,
  environment : Environment,
  layout : StructViewLayout,
  type_index : Int32,
  shape : UInt64,
  fields : Int32,
) -> Unit {
  let slow = context.create_block([])
  let ready = context.create_block([Ptr64])
  let heap = context.emit(
      EnvironmentField(environment.gc_heap_field.unwrap(), Mutable),
      context.environment(),
      [Ptr64],
    )[0]
  view_guard_nonzero(context, heap, slow)
  let control = heap_load(context, heap, layout.allocation_control, Ptr64)
  view_guard_nonzero(context, control, slow)
  view_guard_immediate(
    context,
    NotEqual,
    heap_load(context, control, layout.control_enabled, I32),
    0UL,
    slow,
  )
  let ref_pointer = context.emit(GcRefAddress, context.operands(), [Ptr64])[0]
  view_guard_nonzero(context, ref_pointer, slow)
  let word = context.emit(Convert(Bitcast(Ptr64, I64)), [ref_pointer], [I64])[0]
  let slot = context.emit(
      IntBinaryImmediate(And, ((1UL << layout.view_bits) - 1UL) << 1),
      [word],
      [I64],
    )[0]
  let offset = context.emit(
      IntBinary(ShiftLeft),
      [slot, context.emit(I64Const(4UL), [], [I64])[0]],
      [I64],
    )[0]
  let base = context.emit(
      PointerOffset,
      [
        heap,
        context.emit(I64Const(layout.struct_views.to_uint64()), [], [I64])[0],
      ],
      [Ptr64],
    )[0]
  let entry = context.emit(PointerOffset, [base, offset], [Ptr64])[0]
  let cached = heap_load(context, entry, layout.view_reference, I64)
  let matched = context.create_block([])
  context.branch_int_compare(Equal, cached, word, matched, [], slow, [])
  context.switch_to_block(matched)
  view_guard_immediate(
    context,
    Equal,
    heap_load(context, entry, layout.view_fields, I32),
    fields.to_uint64(),
    slow,
  )
  view_guard_immediate(
    context,
    Equal,
    heap_load(context, entry, layout.view_shape, I64),
    shape,
    slow,
  )
  let ids = heap_load(
    context,
    context.environment()[0],
    layout.type_ids_offset,
    Ptr64,
  )
  let count = heap_load(
    context,
    context.environment()[0],
    layout.type_count_offset,
    I32,
  )
  view_guard_nonzero(context, ids, slow)
  view_guard_immediate(
    context,
    SignedGreaterThan,
    count,
    type_index.to_uint64(),
    slow,
  )
  let identity = heap_load(context, ids, type_index * 4, I32)
  let actual = heap_load(context, entry, layout.view_identity, I32)
  let admitted = context.create_block([])
  context.branch_int_compare(Equal, identity, actual, admitted, [], slow, [])
  context.switch_to_block(admitted)
  context.jump(ready, [heap_load(context, entry, layout.view_payload, Ptr64)])
  context.switch_to_block(slow)
  let result = context.emit_call_without_roots(
      @native_types.NativeCall::new(
        External((environment.runtime_symbol)(GcStructData)),
        @native_types.Signature::new([Ptr64, GcRef64, I32, I64, I32], [Ptr64]),
        Platform,
        @native_types.CallBehavior::new(Read, true, false, false, false),
      ),
      [
        context.environment()[0],
        context.operands()[0],
        i32_immediate(context, type_index),
        context.emit(I64Const(shape), [], [I64])[0],
        i32_immediate(context, fields),
      ],
      [Ptr64],
    )[0]
  context.jump(ready, [result])
  context.switch_to_block(ready)
  context.forward_results(context.block_parameters(ready))
}
