///|
/// The optional embedding directory contains a live identity at each object
/// start. It never supplies an address. A packed reference supplies its own
/// 16-byte slot and keeps the stable identity in the low word.
pub(all) struct OffsetRefLayout {
  directory : Int32
  view_directory : Int32
  struct_bindings : Int32
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
  directory_bound~ : Bool = false,
) -> @lowering.Value {
  let word = offset_bits(context, context.operands()[0])
  let bits = context.emit(IntBinaryImmediate(Xor, OFFSET_REF_TAG), [word], [I64])[0]
  let tag = context.emit(IntBinaryImmediate(And, OFFSET_REF_MASK), [bits], [I64])[0]
  view_guard_immediate(context, Equal, tag, 0UL, slow)
  if !directory_bound {
    view_guard_nonzero(context, heap, slow)
  }
  let directory = heap_load(context, heap, layout.view_directory, Ptr64)
  if !directory_bound {
    view_guard_nonzero(context, directory, slow)
  }
  let slot = context.emit(IntExtractBits(32, 27), [word], [I64])[0]
  let low = context.emit(Convert(I32WrapI64), [word], [I32])[0]
  let id = context.emit(IntBinaryImmediate(Or, 1UL), [low], [I32])[0]
  let live = heap_load(
    context,
    heap_index_wide(context, directory, slot, 2),
    0,
    I32,
  )
  heap_cast_guard(context, Equal, live, id, slow)
  heap_index_wide(
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
  let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [header], [I64])[0]
  let bits = context.emit(IntBinaryImmediate(Add, size.to_uint64()), [bits], [
      I64,
    ])[0]
  context.emit(Convert(Bitcast(I64, Ptr64)), [bits], [Ptr64])[0]
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
  checked_type~ : Bool = false,
) -> Unit {
  let slow = context.create_block([])
  let ready = context.create_block([Ptr64])
  let bindings = if checked_type {
    None
  } else {
    let bindings = heap_load(
      context,
      context.environment()[0],
      offsets.struct_bindings,
      Ptr64,
    )
    view_guard_nonzero(context, bindings, slow)
    view_guard_immediate(
      context,
      SignedGreaterThan,
      heap_load(
        context,
        context.environment()[0],
        layout.type_count_offset,
        I32,
      ),
      type_index.to_uint64(),
      slow,
    )
    Some(bindings)
  }
  // Bindings or a previous complete check establish the logical layout.
  // Every projection still resolves the current heap and live directory.
  let heap = context.emit(
      EnvironmentField(environment.gc_heap_field.unwrap(), Mutable),
      context.environment(),
      [Ptr64],
    )[0]
  let header = checked_offset_header(
    context,
    heap,
    offsets,
    layout,
    slow,
    directory_bound=!checked_type,
  )
  view_guard_immediate(
    context,
    Equal,
    offset_header_byte(context, header, offsets.header_flags),
    OFFSET_STRUCT_LAYOUT,
    slow,
  )
  if bindings is Some(bindings) {
    let entry = type_index * 16
    let expected = heap_load(context, bindings, entry, I64)
    let reserved = heap_load(context, header, offsets.header_reserved, I64)
    heap_cast_guard(context, Equal, expected, reserved, slow)
    // The immutable binding pairs the exact typed header and field count with
    // its physical prefix. Every compiled field contributes a nonzero nibble.
    view_guard_immediate(
      context,
      Equal,
      heap_load(context, bindings, entry + 8, I64),
      shape,
      slow,
    )
  }
  // A previous complete check may retain the logical layout across collection.
  // The live directory and compact-layout flag above still validate this address.
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
