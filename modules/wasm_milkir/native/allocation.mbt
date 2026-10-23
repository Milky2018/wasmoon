///|
/// The shared no-GC reservation owns quotas and identity publication. Between
/// successful reservation and initialized header/payload this expansion emits
/// only stores: no helper, root update, poll or reentrant edge is admitted.
fn lower_fast_struct(
  context : @adapter.InstructionContext,
  environment : Environment,
  validation : @wasm_milkir.WasmValidationContext,
  type_index : Int32,
  default_ : Bool,
) -> Bool {
  if environment.gc_heap_field is None {
    return false
  }
  let widths : Array[Int32] = []
  let offsets : Array[Int32] = []
  let mut shape = 0UL
  let mut size = 0
  let mut index = 0
  while validation.struct_field(type_index, index) is Some(field) {
    guard field_width(field) is Some(width) &&
      !(field.storage is Value(Ref)) &&
      index < 16 else {
      return false
    }
    size = (size + width - 1) / width * width
    offsets.push(size + 16)
    size += width
    widths.push(width)
    let code = match width {
      1 => 1UL
      2 => 2UL
      4 => 3UL
      _ => 4UL
    }
    shape = shape | (code << (index * 4))
    index += 1
  }
  if !default_ && widths.length() != context.operands().length() {
    return false
  }
  let total = (size + 31) / 16 * 16
  let ticket = context.create_stack_object(16, 8)
  let address = context.emit(StackAddress(ticket), [], [Ptr64])[0]
  let environment_value = context.environment()[0]
  let word = context.emit_call_without_roots(
      @native_types.NativeCall::new(
        External((environment.runtime_symbol)(GcReserveStructFast)),
        @native_types.Signature::new([Ptr64, I32, I32, I64, I32, Ptr64], [I64]),
        Platform,
        @native_types.CallBehavior::new(ReadWrite, false, false, false, false),
      ),
      [
        environment_value,
        i32_immediate(context, type_index),
        i32_immediate(context, widths.length()),
        context.emit(I64Const(shape), [], [I64])[0],
        i32_immediate(context, total),
        address,
      ],
      [I64],
    )[0]
  let available = context.emit(IntCompareImmediate(NotEqual, 0UL), [word], [I32])[0]
  let fast = context.create_block([])
  let slow = context.create_block([])
  let join = context.create_block([GcRef64])
  context.branch(available, fast, [], slow, [])
  context.switch_to_block(fast)
  let object = context.emit(
      Load(@lowering.LoadSpec::new(W64, None, Ptr64, 0UL, Little, None)),
      [address],
      [Ptr64],
    )[0]
  let reserved = context.emit(
      Load(@lowering.LoadSpec::new(W64, None, I64, 8UL, Little, None)),
      [address],
      [I64],
    )[0]
  let zero = context.emit(I64Const(0UL), [], [I64])[0]
  for offset in 0..<(total / 8) {
    context.emit(
      Store(
        @lowering.StoreSpec::new(
          W64,
          I64,
          (offset * 8).to_uint64(),
          Little,
          None,
        ),
      ),
      [object, zero],
      [],
    )
    |> ignore
  }
  let header = context.emit(
      I64Const(
        1UL |
        ((type_index.to_uint64() & 65535UL) << 16) |
        (total.to_uint64() << 32),
      ),
      [],
      [I64],
    )[0]
  context.emit(
    Store(@lowering.StoreSpec::new(W64, I64, 0UL, Little, None)),
    [object, header],
    [],
  )
  |> ignore
  context.emit(
    Store(@lowering.StoreSpec::new(W64, I64, 8UL, Little, None)),
    [object, reserved],
    [],
  )
  |> ignore
  if !default_ {
    for index, value in context.operands() {
      let width : @native_types.AccessWidth = match widths[index] {
        1 => W8
        2 => W16
        4 => W32
        _ => W64
      }
      context.emit(
        Store(
          @lowering.StoreSpec::new(
            width,
            context.operand_types()[index],
            offsets[index].to_uint64(),
            Little,
            None,
          ),
        ),
        [object, value],
        [],
      )
      |> ignore
    }
  }
  let reference = context.emit(GcRefFromBits, [word], [GcRef64])[0]
  context.jump(join, [reference])
  context.switch_to_block(slow)
  let slow_word = if default_ {
    let null = context.emit(NullPtr, [], [Ptr64])[0]
    emit_gc_allocation(
      context,
      environment,
      GcAllocStructSlow,
      [
        environment_value,
        i32_immediate(context, type_index),
        null,
        i32_immediate(context, 0),
      ],
      [Ptr64, I32, Ptr64, I32],
    )
  } else {
    emit_fixed_allocation(context, environment, GcAllocStructSlow, type_index)
  }
  let slow_reference = context.emit(GcRefFromBits, [slow_word], [GcRef64])[0]
  context.jump(join, [slow_reference])
  context.switch_to_block(join)
  context.forward_results(context.block_parameters(join))
  true
}
