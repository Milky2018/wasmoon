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
fn heap_guard(
  context : @adapter.InstructionContext,
  condition : @lowering.Value,
  slow : @lowering.Block,
) -> Unit {
  let next = context.create_block([])
  context.branch(condition, next, [], slow, [])
  context.switch_to_block(next)
}

///|
fn heap_nonzero(
  context : @adapter.InstructionContext,
  value : @lowering.Value,
) -> @lowering.Value {
  let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [value], [I64])[0]
  context.emit(IntCompareImmediate(NotEqual, 0UL), [bits], [I32])[0]
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
) -> (@lowering.Value, @lowering.Value, @lowering.Value) {
  let heap = context.emit(
      EnvironmentField(environment.gc_heap_field.unwrap(), Mutable),
      context.environment(),
      [Ptr64],
    )[0]
  heap_guard(context, heap_nonzero(context, heap), slow)
  let control = heap_load(context, heap, layout.allocation_control, Ptr64)
  heap_guard(context, heap_nonzero(context, control), slow)
  let enabled = heap_load(context, control, layout.control_enabled, I32)
  let bytes = heap_load(context, heap, layout.byte_reservation, Ptr64)
  let objects = heap_load(context, heap, layout.object_reservation, Ptr64)
  let unrestricted = context.emit(
      IntBinaryImmediate(Xor, 1UL),
      [heap_nonzero(context, bytes)],
      [I32],
    )[0]
  let unrestricted_objects = context.emit(
      IntBinaryImmediate(Xor, 1UL),
      [heap_nonzero(context, objects)],
      [I32],
    )[0]
  let allowed = context.emit(IntBinary(And), [enabled, unrestricted], [I32])[0]
  let allowed = context.emit(IntBinary(And), [allowed, unrestricted_objects], [
      I32,
    ])[0]
  heap_guard(context, allowed, slow)
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
  heap_guard(context, heap_nonzero(context, ids), slow)
  heap_guard(
    context,
    context.emit(
      IntCompareImmediate(UnsignedGreaterThan, type_index.to_uint64()),
      [types],
      [I32],
    )[0],
    slow,
  )
  let identity = heap_load(context, ids, type_index * 4, I32)
  let layouts = heap_load(context, heap, layout.layouts, Ptr64)
  let layout_count = heap_load(context, heap, layout.layout_capacity, I32)
  heap_guard(
    context,
    context.emit(IntCompare(UnsignedLessThan), [identity, layout_count], [I32])[0],
    slow,
  )
  let descriptor = heap_load(
    context,
    heap_index(context, layouts, identity, 3),
    0,
    Ptr64,
  )
  heap_guard(context, heap_nonzero(context, descriptor), slow)
  let kind = heap_load(context, descriptor, layout.layout_kind, I32)
  let fields = heap_load(context, descriptor, layout.layout_count, I32)
  let size = heap_load(context, descriptor, layout.layout_size, I32)
  let actual_shape = heap_load(context, descriptor, layout.layout_shape, I64)
  let shape_ok = context.emit(
      IntCompareImmediate(Equal, shape),
      [actual_shape],
      [I32],
    )[0]
  let fields_ok = context.emit(
      IntCompareImmediate(Equal, count.to_uint64()),
      [fields],
      [I32],
    )[0]
  let kind_ok = context.emit(IntCompareImmediate(Equal, 1UL), [kind], [I32])[0]
  let aligned = context.emit(
      IntBinaryImmediate(And, 0xFFFFFFF0UL),
      [heap_add(context, size, 31, I32)],
      [I32],
    )[0]
  let size_ok = context.emit(
      IntCompareImmediate(Equal, total.to_uint64()),
      [aligned],
      [I32],
    )[0]
  let valid = context.emit(IntBinary(And), [shape_ok, fields_ok], [I32])[0]
  let valid = context.emit(IntBinary(And), [valid, kind_ok], [I32])[0]
  heap_guard(
    context,
    context.emit(IntBinary(And), [valid, size_ok], [I32])[0],
    slow,
  )
  let used = heap_load(context, heap, layout.size, I64)
  let end = heap_add(context, used, total, I64)
  let capacity = heap_load(context, heap, layout.capacity, I64)
  let limit = heap_load(context, heap, layout.collection_limit, I64)
  let capacity_ok = context.emit(
      IntCompare(UnsignedLessOrEqual),
      [end, capacity],
      [I32],
    )[0]
  let budget_ok = context.emit(IntCompare(UnsignedLessThan), [used, limit], [
      I32,
    ])[0]
  let range_ok = context.emit(
      IntCompareImmediate(UnsignedLessOrEqual, 2147483647UL),
      [end],
      [I32],
    )[0]
  let room = context.emit(IntBinary(And), [capacity_ok, budget_ok], [I32])[0]
  heap_guard(
    context,
    context.emit(IntBinary(And), [room, range_ok], [I32])[0],
    slow,
  )
  let index = heap_load(context, heap, layout.object_count, I32)
  let identity_limit = heap_load(
    context,
    heap,
    layout.identity_window_limit,
    I32,
  )
  heap_guard(
    context,
    context.emit(IntCompare(UnsignedLessThan), [index, identity_limit], [I32])[0],
    slow,
  )
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
      IntBinary(ShiftLeft),
      [runtime_type, context.emit(I64Const(32UL), [], [I64])[0]],
      [I64],
    )[0]
  let reserved = context.emit(
      IntBinaryImmediate(Or, count.to_uint64()),
      [runtime_type],
      [I64],
    )[0]
  let word = context.emit(Convert(I64ExtendI32(Unsigned)), [reference], [I64])[0]
  let word = context.emit(
      IntBinary(ShiftLeft),
      [word, context.emit(I64Const(1UL), [], [I64])[0]],
      [I64],
    )[0]
  (object, reserved, word)
}
