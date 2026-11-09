///|
/// The optional embedding directory contains a live identity at each object
/// start. It never supplies an address. A packed reference supplies its own
/// 16-byte slot and keeps the stable identity in the low word.
pub(all) struct OffsetRefLayout {
  directory : Int32
  view_directory : Int32
  header_flags : Int32
  header_reserved : Int32
  header_size : Int32
}

///|
const OFFSET_REF_TAG : UInt64 = 0x0800000000000000UL

///|
const OFFSET_REF_MASK : UInt64 = 0xF800000000000001UL

///|
const OFFSET_STRUCT_LAYOUT : UInt64 = 0x80UL

///|
fn offset_bits(
  context : @adapter.InstructionContext,
  reference : @lowering.Value,
) -> @lowering.Value {
  let carrier = context.emit(GcRefAddress, [reference], [Ptr64])[0]
  context.emit(Convert(Bitcast(Ptr64, I64)), [carrier], [I64])[0]
}

///|
fn offset_upper_word(
  context : @adapter.InstructionContext,
  word : @lowering.Value,
) -> @lowering.Value {
  let high = context.emit(
      IntBinary(UnsignedShiftRight),
      [word, context.emit(I64Const(32UL), [], [I64])[0]],
      [I64],
    )[0]
  context.emit(Convert(I32WrapI64), [high], [I32])[0]
}

///|
/// A packed and an ID-only word can name the same object at a host boundary.
/// Other reference families retain their complete carrier bits.
fn canonical_reference_bits(
  context : @adapter.InstructionContext,
  reference : @lowering.Value,
) -> @lowering.Value {
  let word = offset_bits(context, reference)
  let tag = context.emit(IntBinaryImmediate(And, OFFSET_REF_MASK), [word], [I64])[0]
  let packed = context.emit(IntCompareImmediate(Equal, OFFSET_REF_TAG), [tag], [
      I32,
    ])[0]
  let low = context.emit(Convert(I32WrapI64), [word], [I32])[0]
  let identity = context.emit(Convert(I64ExtendI32(Unsigned)), [low], [I64])[0]
  context.emit(Select, [packed, identity, word], [I64])[0]
}

///|
fn checked_offset_header(
  context : @adapter.InstructionContext,
  heap : @lowering.Value,
  layout : OffsetRefLayout,
  heap_layout : InlineHeapLayout,
  slow : @lowering.Block,
) -> @lowering.Value {
  let word = offset_bits(context, context.operands()[0])
  let tag = context.emit(IntBinaryImmediate(And, OFFSET_REF_MASK), [word], [I64])[0]
  view_guard_immediate(context, Equal, tag, OFFSET_REF_TAG, slow)
  view_guard_nonzero(context, heap, slow)
  let directory = heap_load(context, heap, layout.view_directory, Ptr64)
  view_guard_nonzero(context, directory, slow)
  let slot = context.emit(
      IntBinaryImmediate(And, 0x07FFFFFFUL),
      [offset_upper_word(context, word)],
      [I32],
    )[0]
  let low = context.emit(Convert(I32WrapI64), [word], [I32])[0]
  let id = context.emit(IntBinaryImmediate(Or, 1UL), [low], [I32])[0]
  let live = heap_load(context, heap_index(context, directory, slot, 2), 0, I32)
  heap_cast_guard(context, Equal, live, id, slow)
  heap_index(
    context,
    heap_load(context, heap, heap_layout.data, Ptr64),
    slot,
    4,
  )
}

///|
fn offset_header_byte(
  context : @adapter.InstructionContext,
  header : @lowering.Value,
  offset : Int32,
) -> @lowering.Value {
  context.emit(
    Load(
      @lowering.LoadSpec::new(
        W8,
        Unsigned,
        I32,
        offset.to_uint64(),
        Little,
        None,
      ),
    ),
    [header],
    [I32],
  )[0]
}

///|
fn offset_payload(
  context : @adapter.InstructionContext,
  header : @lowering.Value,
  size : Int32,
) -> @lowering.Value {
  context.emit(
    PointerOffset,
    [header, context.emit(I64Const(size.to_uint64()), [], [I64])[0]],
    [Ptr64],
  )[0]
}

///|
fn inline_offset_struct_projection(
  context : @adapter.InstructionContext,
  environment : Environment,
  offsets : OffsetRefLayout,
  layout : InlineHeapLayout,
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
  let header = checked_offset_header(context, heap, offsets, layout, slow)
  view_guard_immediate(
    context,
    Equal,
    offset_header_byte(context, header, offsets.header_flags),
    OFFSET_STRUCT_LAYOUT,
    slow,
  )
  let reserved = heap_load(context, header, offsets.header_reserved, I64)
  let count = context.emit(Convert(I32WrapI64), [reserved], [I32])[0]
  view_guard_immediate(
    context,
    UnsignedGreaterOrEqual,
    count,
    fields.to_uint64(),
    slow,
  )
  let actual = offset_upper_word(context, reserved)
  view_guard_immediate(context, NotEqual, actual, 0UL, slow)
  let actual = heap_add(context, actual, -1, I32)
  let ids = heap_load(
    context,
    context.environment()[0],
    layout.type_ids_offset,
    Ptr64,
  )
  view_guard_nonzero(context, ids, slow)
  view_guard_immediate(
    context,
    SignedGreaterThan,
    heap_load(context, context.environment()[0], layout.type_count_offset, I32),
    type_index.to_uint64(),
    slow,
  )
  let expected = heap_load(context, ids, type_index * 4, I32)
  heap_cast_guard(context, Equal, expected, actual, slow)
  // Only constructors checked against a registered immutable struct
  // layout publish the header flag. The directory proves this is the
  // live header at an object start. That proof covers the layout table
  // entry and kind; the actual field count and requested shape are
  // still checked against this projection.
  let layouts = heap_load(context, heap, layout.layouts, Ptr64)
  let physical = heap_load(
    context,
    heap_index(context, layouts, actual, 3),
    0,
    Ptr64,
  )
  let physical_shape = heap_load(context, physical, layout.layout_shape, I64)
  let prefix = if fields == 16 {
    physical_shape
  } else {
    context.emit(
      IntBinaryImmediate(And, (1UL << (fields * 4)) - 1UL),
      [physical_shape],
      [I64],
    )[0]
  }
  view_guard_immediate(context, Equal, prefix, shape, slow)
  context.jump(ready, [offset_payload(context, header, offsets.header_size)])
  context.switch_to_block(slow)
  context.jump(ready, [
    emit_struct_data(context, environment, type_index, shape, fields),
  ])
  context.switch_to_block(ready)
  context.forward_results(context.block_parameters(ready))
}

///|
fn inline_offset_array_projection(
  context : @adapter.InstructionContext,
  environment : Environment,
  offsets : OffsetRefLayout,
  layout : InlineHeapLayout,
) -> Unit {
  let slow = context.create_block([])
  let ready = context.create_block([Ptr64])
  let heap = context.emit(
      EnvironmentField(environment.gc_heap_field.unwrap(), Mutable),
      context.environment(),
      [Ptr64],
    )[0]
  let header = checked_offset_header(context, heap, offsets, layout, slow)
  let code = offset_header_byte(context, header, offsets.header_flags)
  let width_index = heap_add(context, code, -1, I32)
  view_guard_immediate(context, UnsignedLessThan, width_index, 4UL, slow)
  let payload = offset_payload(context, header, offsets.header_size)
  let code = context.emit(Convert(I64ExtendI32(Unsigned)), [code], [I64])[0]
  let address = context.emit(Convert(Bitcast(Ptr64, I64)), [payload], [I64])[0]
  let bits = context.emit(IntBinary(Or), [address, code], [I64])[0]
  let view = context.emit(Convert(Bitcast(I64, Ptr64)), [bits], [Ptr64])[0]
  context.jump(ready, [view])
  context.switch_to_block(slow)
  let fallback = emit_array_data(context, environment, heap)
  context.jump(ready, [fallback])
  context.switch_to_block(ready)
  context.forward_results(context.block_parameters(ready))
}
