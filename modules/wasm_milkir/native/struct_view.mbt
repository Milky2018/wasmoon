///|
/// Optional embedding-owned admission hints, independent of allocation layout.
/// Only complete checked helpers may publish actual canonical layout keys. Payload
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
  registry_offset : Int32
  registry_parents : Int32
  registry_type_count : Int32
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
/// The complete helper publishes a physical prefix under the actual identity.
/// Exact types and a current immediate-parent relation can use that prefix;
/// transitive relations retain the complete helper. No nominal result is cached.
/// Every miss and verifier mode keeps the trapping accessor and borrow epoch.
fn inline_cached_struct_projection(
  context : @adapter.InstructionContext,
  environment : Environment,
  layout : StructViewLayout,
  type_index : Int32,
  shape : UInt64,
  fields : Int32,
  exact_type~ : Bool,
) -> Unit {
  let slow = context.create_block([])
  let ready = context.create_block([Ptr64])
  let view = checked_cached_struct_view(
    context,
    environment,
    layout,
    type_index,
    shape,
    fields,
    slow,
    exact_type~,
  )
  context.jump(ready, [view])
  context.switch_to_block(slow)
  let result = emit_struct_data(context, environment, type_index, shape, fields)
  context.jump(ready, [result])
  context.switch_to_block(ready)
  context.forward_results(context.block_parameters(ready))
}

///|
fn checked_cached_struct_view(
  context : @adapter.InstructionContext,
  environment : Environment,
  layout : StructViewLayout,
  type_index : Int32,
  shape : UInt64,
  fields : Int32,
  slow : @lowering.Block,
  exact_type~ : Bool,
  cast_exact~ : Bool = false,
) -> @lowering.Value {
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
    if exact_type {
      Equal
    } else {
      UnsignedGreaterOrEqual
    },
    heap_load(context, entry, layout.view_fields, I32),
    fields.to_uint64(),
    slow,
  )
  let actual_shape = heap_load(context, entry, layout.view_shape, I64)
  let prefix_shape = if exact_type || fields == 16 {
    actual_shape
  } else {
    context.emit(
      IntBinaryImmediate(And, (1UL << (fields * 4)) - 1UL),
      [actual_shape],
      [I64],
    )[0]
  }
  view_guard_immediate(context, Equal, prefix_shape, shape, slow)
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
  if exact_type {
    if cast_exact {
      // ref.cast consults the current registry even when the identities
      // match. A cleared registry or a rebound out-of-range ID must miss.
      let registry = heap_load(
        context,
        context.environment()[0],
        layout.registry_offset,
        Ptr64,
      )
      view_guard_nonzero(context, registry, slow)
      let type_count = heap_load(
        context,
        registry,
        layout.registry_type_count,
        I32,
      )
      let live = context.create_block([])
      context.branch_int_compare(
        UnsignedLessThan,
        identity,
        type_count,
        live,
        [],
        slow,
        [],
      )
      context.switch_to_block(live)
    }
    context.branch_int_compare(Equal, identity, actual, admitted, [], slow, [])
  } else {
    let subtype = context.create_block([])
    context.branch_int_compare(Equal, identity, actual, admitted, [], subtype, [])
    context.switch_to_block(subtype)
    let registry = heap_load(
      context,
      context.environment()[0],
      layout.registry_offset,
      Ptr64,
    )
    view_guard_nonzero(context, registry, slow)
    let type_count = heap_load(
      context,
      registry,
      layout.registry_type_count,
      I32,
    )
    let in_bounds = context.create_block([])
    context.branch_int_compare(
      UnsignedLessThan,
      actual,
      type_count,
      in_bounds,
      [],
      slow,
      [],
    )
    context.switch_to_block(in_bounds)
    // The complete registry walk only matches a live identity. Parent
    // sentinels and out-of-range entries cannot admit a rebound local type.
    let valid_target = context.create_block([])
    context.branch_int_compare(
      UnsignedLessThan,
      identity,
      type_count,
      valid_target,
      [],
      slow,
      [],
    )
    context.switch_to_block(valid_target)
    let parents = heap_load(context, registry, layout.registry_parents, Ptr64)
    view_guard_nonzero(context, parents, slow)
    let parent = heap_load(
      context,
      heap_index(context, parents, actual, 2),
      0,
      I32,
    )
    context.branch_int_compare(Equal, identity, parent, admitted, [], slow, [])
  }
  context.switch_to_block(admitted)
  heap_load(context, entry, layout.view_payload, Ptr64)
}

///|
fn emit_struct_data(
  context : @adapter.InstructionContext,
  environment : Environment,
  type_index : Int32,
  shape : UInt64,
  fields : Int32,
) -> @lowering.Value {
  context.emit_call_without_roots(
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
}
