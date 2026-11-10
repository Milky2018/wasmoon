///|
fn inline_struct_admission(
  context : @adapter.InstructionContext,
  environment : Environment,
  layout : InlineHeapLayout,
  type_index : Int32,
  count : Int32,
  shape : UInt64,
  total : Int32,
  slow : @lowering.Block,
) -> (@lowering.Value, @lowering.Value, @lowering.Value) {
  let heap = context.emit(
      EnvironmentField(environment.gc_heap_field.unwrap(), Mutable),
      context.environment(),
      [Ptr64],
    )[0]
  view_guard_nonzero(context, heap, slow)
  let control = heap_load(context, heap, layout.allocation_control, Ptr64)
  view_guard_nonzero(context, control, slow)
  let enabled = heap_load(context, control, layout.control_enabled, I32)
  let bytes = heap_load(context, heap, layout.byte_reservation, Ptr64)
  let objects = heap_load(context, heap, layout.object_reservation, Ptr64)
  let enabled = context.emit(IntBinaryImmediate(And, 1UL), [enabled], [I32])[0]
  view_guard_immediate(context, Equal, enabled, 1UL, slow)
  view_guard_immediate(
    context,
    Equal,
    context.emit(Convert(Bitcast(Ptr64, I64)), [bytes], [I64])[0],
    0UL,
    slow,
  )
  view_guard_immediate(
    context,
    Equal,
    context.emit(Convert(Bitcast(Ptr64, I64)), [objects], [I64])[0],
    0UL,
    slow,
  )
  let identity = if environment.offset_refs is Some((offsets, _)) {
    // The context publishes these immutable canonical bindings only for its
    // current heap. Shape and count equality prove the same physical layout
    // as the descriptor checks below, including alignment and total size.
    let bindings = heap_load(
      context,
      context.environment()[0],
      offsets.struct_bindings,
      Ptr64,
    )
    view_guard_nonzero(context, bindings, slow)
    let types = heap_load(
      context,
      context.environment()[0],
      layout.type_count_offset,
      I32,
    )
    view_guard_immediate(
      context,
      UnsignedGreaterThan,
      types,
      type_index.to_uint64(),
      slow,
    )
    let header = heap_load(context, bindings, type_index * 16, I64)
    let actual_shape = heap_load(context, bindings, type_index * 16 + 8, I64)
    let encoded_identity = context.emit(
        IntShiftImmediate(UnsignedShiftRight, 32),
        [header],
        [I64],
      )[0]
    let fields = context.emit(Convert(I32WrapI64), [header], [I32])[0]
    view_guard_immediate(context, NotEqual, encoded_identity, 0UL, slow)
    view_guard_immediate(context, Equal, fields, count.to_uint64(), slow)
    view_guard_immediate(context, Equal, actual_shape, shape, slow)
    let identity = context.emit(Convert(I32WrapI64), [encoded_identity], [I32])[0]
    heap_add(context, identity, -1, I32)
  } else {
    let ids = heap_load(
      context,
      context.environment()[0],
      layout.type_ids_offset,
      Ptr64,
    )
    let types = heap_load(
      context,
      context.environment()[0],
      layout.type_count_offset,
      I32,
    )
    view_guard_nonzero(context, ids, slow)
    view_guard_immediate(
      context,
      UnsignedGreaterThan,
      types,
      type_index.to_uint64(),
      slow,
    )
    let identity = heap_load(context, ids, type_index * 4, I32)
    let layouts = heap_load(context, heap, layout.layouts, Ptr64)
    let layout_count = heap_load(context, heap, layout.layout_capacity, I32)
    heap_cast_guard(context, UnsignedLessThan, identity, layout_count, slow)
    let descriptor = heap_load(
      context,
      heap_index(context, layouts, identity, 3),
      0,
      Ptr64,
    )
    view_guard_nonzero(context, descriptor, slow)
    let kind = heap_load(context, descriptor, layout.layout_kind, I32)
    let fields = heap_load(context, descriptor, layout.layout_count, I32)
    let size = heap_load(context, descriptor, layout.layout_size, I32)
    let actual_shape = heap_load(context, descriptor, layout.layout_shape, I64)
    view_guard_immediate(context, Equal, actual_shape, shape, slow)
    view_guard_immediate(context, Equal, fields, count.to_uint64(), slow)
    view_guard_immediate(context, Equal, kind, 1UL, slow)
    let aligned = context.emit(
        IntBinaryImmediate(And, 0xFFFFFFF0UL),
        [heap_add(context, size, 31, I32)],
        [I32],
      )[0]
    view_guard_immediate(context, Equal, aligned, total.to_uint64(), slow)
    identity
  }
  (heap, control, identity)
}

///|
/// Embedding-owned offsets for a 64-bit stable-identity heap. All capacity,
/// policy, canonical layout and identity-page checks precede publication.
/// Bound quota reservations always select the shared collecting allocator.
pub(all) struct InlineHeapLayout {
  type_ids_offset : Int32
  type_count_offset : Int32
  bump_offset : Int32
  data : Int32
  size : Int32
  capacity : Int32
  collection_limit : Int32
  layouts : Int32
  layout_capacity : Int32
  object_count : Int32
  live_objects : Int32
  live_count : Int32
  total_allocations : Int32
  quota_denied : Int32
  byte_reservation : Int32
  object_reservation : Int32
  allocation_control : Int32
  control_enabled : Int32
  control_attempts : Int32
  page_offsets : Int32
  page_types : Int32
  page_live_count : Int32
  layout_kind : Int32
  layout_count : Int32
  layout_size : Int32
  layout_shape : Int32
  identity_window_limit : Int32
  identity_window_page : Int32
  identity_page_bits : Int32
}

///|
fn heap_load(
  context : @adapter.InstructionContext,
  base : @lowering.Value,
  offset : Int32,
  type_ : @native_types.ValueType,
) -> @lowering.Value {
  let (base, offset) = if offset < 0 {
    let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [base], [I64])[0]
    let bits = context.emit(
        IntBinaryImmediate(Add, offset.to_int64().reinterpret_as_uint64()),
        [bits],
        [I64],
      )[0]
    (context.emit(Convert(Bitcast(I64, Ptr64)), [bits], [Ptr64])[0], 0)
  } else {
    (base, offset)
  }
  context.emit(
    Load(
      @lowering.LoadSpec::new(
        if type_ == I32 {
          W32
        } else {
          W64
        },
        None,
        type_,
        offset.to_uint64(),
        Little,
        None,
      ),
    ),
    [base],
    [type_],
  )[0]
}

///|
fn heap_store(
  context : @adapter.InstructionContext,
  base : @lowering.Value,
  offset : Int32,
  value : @lowering.Value,
  type_ : @native_types.ValueType,
) -> Unit {
  context.emit(
    Store(
      @lowering.StoreSpec::new(
        if type_ == I32 {
          W32
        } else {
          W64
        },
        type_,
        offset.to_uint64(),
        Little,
        None,
      ),
    ),
    [base, value],
    [],
  )
  |> ignore
}

///|
fn heap_add(
  context : @adapter.InstructionContext,
  value : @lowering.Value,
  amount : Int32,
  type_ : @native_types.ValueType,
) -> @lowering.Value {
  context.emit(IntBinaryImmediate(Add, amount.to_uint64()), [value], [type_])[0]
}

///|
fn heap_index(
  context : @adapter.InstructionContext,
  base : @lowering.Value,
  index : @lowering.Value,
  shift : Int32,
) -> @lowering.Value {
  let wide = context.emit(Convert(I64ExtendI32(Unsigned)), [index], [I64])[0]
  heap_index_wide(context, base, wide, shift)
}

///|
fn heap_index_wide(
  context : @adapter.InstructionContext,
  base : @lowering.Value,
  wide : @lowering.Value,
  shift : Int32,
) -> @lowering.Value {
  let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [base], [I64])[0]
  let address = context.emit(IntAddShiftedLeft(shift), [bits, wide], [I64])[0]
  context.emit(Convert(Bitcast(I64, Ptr64)), [address], [Ptr64])[0]
}

///|
/// Return admitted object bytes, the reserved header word and the encoded
/// identity. Every refusal branches to the unchanged collecting allocator.
/// Publication has no calls, safepoints, atomics or quota policy duplication.
fn inline_struct_reservation(
  context : @adapter.InstructionContext,
  environment : Environment,
  layout : InlineHeapLayout,
  type_index : Int32,
  count : Int32,
  shape : UInt64,
  total : Int32,
  slow : @lowering.Block,
  admission~ : @lowering.Value? = None,
) -> (@lowering.Value, @lowering.Value, @lowering.Value) {
  let (heap, control, identity) = if admission is Some(cell) {
    let token = heap_load(context, cell, 0, I32)
    view_guard_immediate(context, NotEqual, token, 0UL, slow)
    let heap = context.emit(
        EnvironmentField(environment.gc_heap_field.unwrap(), Mutable),
        context.environment(),
        [Ptr64],
      )[0]
    (
      heap,
      heap_load(context, heap, layout.allocation_control, Ptr64),
      heap_add(context, token, -1, I32),
    )
  } else {
    inline_struct_admission(
      context, environment, layout, type_index, count, shape, total, slow,
    )
  }
  let used = heap_load(context, heap, layout.size, I64)
  let end = heap_add(context, used, total, I64)
  let capacity = heap_load(context, heap, layout.capacity, I64)
  let limit = heap_load(context, heap, layout.collection_limit, I64)
  heap_cast_guard(context, UnsignedLessOrEqual, end, capacity, slow)
  heap_cast_guard(context, UnsignedLessThan, used, limit, slow)
  view_guard_immediate(context, UnsignedLessOrEqual, end, 2147483647UL, slow)
  let index = heap_load(context, heap, layout.object_count, I32)
  let identity_limit = heap_load(
    context,
    heap,
    layout.identity_window_limit,
    I32,
  )
  heap_cast_guard(context, UnsignedLessThan, index, identity_limit, slow)
  let page = heap_load(context, heap, layout.identity_window_page, Ptr64)
  let live_count = heap_load(context, heap, layout.live_count, I32)
  let slot = context.emit(
      IntBinaryImmediate(And, (1UL << layout.identity_page_bits) - 1UL),
      [index],
      [I32],
    )[0]
  let entry = heap_index(context, page, slot, 2)
  let live = heap_load(context, heap, layout.live_objects, Ptr64)
  let data = heap_load(context, heap, layout.data, Ptr64)
  let data_bits = context.emit(Convert(Bitcast(Ptr64, I64)), [data], [I64])[0]
  let object = context.emit(PointerOffset, [data, used], [Ptr64])[0]
  let reference = heap_add(context, index, 1, I32)
  // All refusal branches precede the first mutation. Match shared allocation
  // accounting and identity publication exactly, with no intermediate call.
  heap_store(context, heap, layout.quota_denied, i32_immediate(context, 0), I32)
  heap_store(
    context,
    control,
    layout.control_attempts,
    heap_add(
      context,
      heap_load(context, control, layout.control_attempts, I32),
      1,
      I32,
    ),
    I32,
  )
  heap_store(context, heap, layout.size, end, I64)
  heap_store(context, heap, layout.object_count, reference, I32)
  heap_store(
    context,
    entry,
    layout.page_offsets,
    context.emit(Convert(I32WrapI64), [used], [I32])[0],
    I32,
  )
  heap_store(context, entry, layout.page_types, identity, I32)
  heap_store(
    context,
    page,
    layout.page_live_count,
    heap_add(
      context,
      heap_load(context, page, layout.page_live_count, I32),
      1,
      I32,
    ),
    I32,
  )
  heap_store(
    context,
    heap_index(context, live, live_count, 2),
    0,
    reference,
    I32,
  )
  heap_store(
    context,
    heap,
    layout.live_count,
    heap_add(context, live_count, 1, I32),
    I32,
  )
  heap_store(
    context,
    heap,
    layout.total_allocations,
    heap_add(
      context,
      heap_load(context, heap, layout.total_allocations, I32),
      1,
      I32,
    ),
    I32,
  )
  let new_top = context.emit(IntBinary(Add), [data_bits, end], [I64])[0]
  heap_store(
    context,
    context.environment()[0],
    layout.bump_offset,
    new_top,
    I64,
  )
  // Capacity, collection limit and quota bindings do not change on this path;
  // the context's existing allocation limit remains valid.
  let runtime_type = context.emit(
      Convert(I64ExtendI32(Unsigned)),
      [heap_add(context, identity, 1, I32)],
      [I64],
    )[0]
  let runtime_type = context.emit(
      IntShiftImmediate(ShiftLeft, 32),
      [runtime_type],
      [I64],
    )[0]
  let reserved = context.emit(
      IntBinaryImmediate(Or, count.to_uint64()),
      [runtime_type],
      [I64],
    )[0]
  let word = context.emit(Convert(I64ExtendI32(Unsigned)), [reference], [I64])[0]
  let word = context.emit(IntShiftImmediate(ShiftLeft, 1), [word], [I64])[0]
  let word = if environment.offset_refs is Some((offsets, _)) {
    let directory = heap_load(context, heap, offsets.directory, Ptr64)
    let direct = context.create_block([])
    let ready = context.create_block([I64])
    let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [directory], [I64])[0]
    context.branch_int_compare_immediate(
      NotEqual,
      bits,
      0UL,
      direct,
      [],
      ready,
      [word],
    )
    context.switch_to_block(direct)
    let slot = context.emit(
        IntShiftImmediate(UnsignedShiftRight, 4),
        [context.emit(Convert(I32WrapI64), [used], [I32])[0]],
        [I32],
      )[0]
    let low = context.emit(Convert(I32WrapI64), [word], [I32])[0]
    let entry = context.emit(IntBinaryImmediate(Or, 1UL), [low], [I32])[0]
    heap_store(context, heap_index(context, directory, slot, 2), 0, entry, I32)
    let offset = context.emit(Convert(I64ExtendI32(Unsigned)), [slot], [I64])[0]
    let offset = context.emit(IntShiftImmediate(ShiftLeft, 32), [offset], [I64])[0]
    let tag = context.emit(IntBinaryImmediate(Or, OFFSET_REF_TAG), [offset], [
        I64,
      ])[0]
    let packed = context.emit(IntBinary(Or), [tag, word], [I64])[0]
    context.jump(ready, [packed])
    context.switch_to_block(ready)
    context.block_parameters(ready)[0]
  } else {
    word
  }
  (object, reserved, word)
}
