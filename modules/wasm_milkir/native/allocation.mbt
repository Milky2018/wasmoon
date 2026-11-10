///|
fn struct_allocation_layout(
  validation : @wasm_milkir.WasmValidationContext,
  type_index : Int32,
) -> (Array[Int32], Array[Int32], UInt64, Int32)? {
  let widths : Array[Int32] = []
  let offsets : Array[Int32] = []
  let mut shape = 0UL
  let mut size = 0
  guard validation.struct_fields(type_index) is Some(fields) else {
    return None
  }
  for index, field in fields {
    guard field_width(field) is Some(width) &&
      index < 16 &&
      !(field.storage is Value(CallableRef | OpaqueRef)) else {
      return None
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
    let code = if field.storage is Value(Ref) { code | 8UL } else { code }
    shape = shape | (code << (index * 4))
  }
  let total = (size + 31) / 16 * 16
  Some((widths, offsets, shape, total))
}

///|
fn lower_struct_admission(
  context : @adapter.InstructionContext,
  environment : Environment,
  validation : @wasm_milkir.WasmValidationContext,
  type_ : Int32,
) -> Unit {
  let cell = context.emit(StackAddress(context.create_stack_object(4, 4)), [], [
      Ptr64,
    ])[0]
  refresh_struct_admission(context, environment, validation, type_, cell)
  context.forward_results([cell])
}

///|
fn refresh_struct_admission(
  context : @adapter.InstructionContext,
  environment : Environment,
  validation : @wasm_milkir.WasmValidationContext,
  type_ : Int32,
  cell : @lowering.Value,
) -> Unit {
  let (widths, _, shape, total) = struct_allocation_layout(validation, type_).unwrap()
  let slow = context.create_block([])
  let ready = context.create_block([I32])
  let (_, _, identity) = inline_struct_admission(
    context,
    environment,
    environment.inline_heap.unwrap(),
    type_,
    widths.length(),
    shape,
    total,
    slow,
  )
  context.jump(ready, [heap_add(context, identity, 1, I32)])
  context.switch_to_block(slow)
  context.jump(ready, [i32_immediate(context, 0)])
  context.switch_to_block(ready)
  heap_store(context, cell, 0, context.block_parameters(ready)[0], I32)
}

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
  admission~ : @lowering.Value? = None,
) -> Bool {
  let direct = environment.inline_heap is Some(_) &&
    (
      environment.direct_struct_allocations ||
      environment.direct_struct_sites.contains(context.instruction_id())
    )
  if (!environment.expand_structs && !direct) ||
    environment.gc_heap_field is None {
    return false
  }
  guard struct_allocation_layout(validation, type_index)
    is Some((widths, offsets, shape, total)) else {
    return false
  }
  let fields = context.operands()
  let field_types = context.operand_types()
  if admission is Some(_) {
    fields.pop() |> ignore
    field_types.pop() |> ignore
  }
  if !default_ && widths.length() != fields.length() {
    return false
  }
  let environment_value = context.environment()[0]
  let slow = context.create_block([])
  let join = context.create_block([GcRef64])
  let (object, reserved, word) = if direct &&
    environment.inline_heap is Some(layout) {
    inline_struct_reservation(
      context,
      environment,
      layout,
      type_index,
      widths.length(),
      shape,
      total,
      slow,
      admission~,
    )
  } else {
    let ticket = context.create_stack_object(16, 8)
    let address = context.emit(StackAddress(ticket), [], [Ptr64])[0]
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
    view_guard_immediate(context, NotEqual, word, 0UL, slow)
    (
      heap_load(context, address, 0, Ptr64),
      heap_load(context, address, 8, I64),
      word,
    )
  }
  // Header and explicit field stores initialize their complete byte ranges.
  // Zero only words containing padding or default fields. No observer can run
  // between reservation and the final initialized payload publication.
  let initialized = Array::make(total, false)
  for byte in 0..<16 {
    initialized[byte] = true
  }
  if !default_ {
    for index, offset in offsets {
      for byte in offset..<(offset + widths[index]) {
        initialized[byte] = true
      }
    }
  }
  if initialized.any(byte => !byte) {
    let zero = context.emit(I64Const(0UL), [], [I64])[0]
    for offset in 0..<(total / 8) {
      if !initialized[offset * 8:offset * 8 + 8].all(byte => byte) {
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
    }
  }
  let layout_flag = if environment.offset_refs is Some(_) {
    OFFSET_STRUCT_LAYOUT << 8
  } else {
    0UL
  }
  let header = context.emit(
      I64Const(
        1UL |
        layout_flag |
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
    for index, value in fields {
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
            field_types[index],
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
  if admission is Some(cell) {
    heap_store(context, cell, 0, i32_immediate(context, 0), I32)
  }
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
    emit_fixed_allocation(
      context,
      environment,
      GcAllocStructSlow,
      type_index,
      fields=Some((fields, field_types)),
    )
  }
  if admission is Some(cell) {
    refresh_struct_admission(context, environment, validation, type_index, cell)
  }
  let slow_reference = context.emit(GcRefFromBits, [slow_word], [GcRef64])[0]
  context.jump(join, [slow_reference])
  context.switch_to_block(join)
  context.forward_results(context.block_parameters(join))
  true
}

///|
/// Access views can admit reference carriers and a bounded prefix of a large
/// object. Allocation expansion still requires its original complete shape;
/// extending the access contract must not silently change allocator selection.
fn allocation_field_count(
  validation : @wasm_milkir.WasmValidationContext,
  type_ : Int32,
) -> Int32? {
  guard validation.struct_fields(type_) is Some(fields) else { return None }
  for index, field in fields {
    if index == 16 ||
      !(field.storage
      is (Packed8 | Packed16 | Value(I32 | F32 | I64 | F64 | V128 | Ref))) {
      return None
    }
  }
  Some(fields.length())
}

///|
/// Retain the same direct-code allowance when a large function contains hot
/// loops. Initializers keep shared helpers, and call-free loops receive the
/// budget before loops interrupted by opaque guest or host calls.
fn hot_struct_expansion_sites(
  function : @milkir.Function,
  validation : @wasm_milkir.WasmValidationContext,
) -> Map[Int32, Bool] {
  let selected : Map[Int32, Bool] = Map([])
  if function.blocks.length() > 256 {
    return selected
  }
  let cfg = @milkir.CFG::build(function)
  let loops = cfg.find_loops()
  if loops.is_empty() {
    return selected
  }
  let priorities = Array::make(cfg.size, 0)
  let blocks : Map[Int32, @milkir.Block] = Map([])
  for block in function.blocks {
    blocks[block.id] = block
  }
  for loop_ in loops {
    let interrupted = loop_.blocks.any(block => {
      function
      .block_instruction_ids(blocks[block])
      .any(id => {
        let inst = function.instruction_by_id(id).unwrap()
        if inst.opcode is Memory(_) {
          return false
        }
        if inst.opcode is Ext(extension, _) &&
          decode_projection(extension) is Some(_) {
          return false
        }
        !@effects.analyze(inst.opcode).preserves_checked_references()
      })
    })
    let priority = if interrupted { 1 } else { 2 }
    for block in loop_.blocks {
      priorities[block] = priorities[block].max(priority)
    }
  }
  let mut remaining = 512
  for priority in [2, 1] {
    for block in function.blocks {
      if priorities[block.id] != priority {
        continue
      }
      for id in function.block_instruction_ids(block) {
        let inst = function.instruction_by_id(id).unwrap()
        if @wasm_milkir.decode_opcode(inst.opcode)
          is Some(StructNew(type_) | StructNewDefault(type_)) &&
          allocation_field_count(validation, type_) is Some(fields) {
          let cost = 128 + fields * 4
          if cost <= remaining {
            selected[id] = true
            remaining -= cost
          }
        }
      }
    }
  }
  selected
}

///|
/// Stable-identity publication expands beyond a plain bump allocation. Inspect
/// the static allocation sites once for both policies: inline struct stores
/// have a bounded instruction budget; shared prepared arrays add two CFG blocks
/// per site. Large generated initializers keep the existing shared paths.
fn allocation_expansion_limits(
  function : @milkir.Function,
  validation : @wasm_milkir.WasmValidationContext,
) -> (Bool, Bool, Bool) {
  let mut struct_cost = 0
  let mut shared_cost = 0
  let mut arrays = 0
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      // Count only allocations: memory preparation also adds projections.
      let inst = function.instruction_by_id(id).unwrap()
      match @wasm_milkir.decode_opcode(inst.opcode) {
        Some(StructNew(type_) | StructNewDefault(type_)) if struct_cost <= 512 ||
          shared_cost <= 1200 =>
          if allocation_field_count(validation, type_) is Some(fields) {
            struct_cost += 128 + fields * 4
            // Shared reservation still expands guards, header/payload stores
            // and a slow/join diamond. Bound that work independently of the
            // larger direct-heap expansion; large functions keep the complete
            // collecting allocator instead of multiplying target CFG state.
            shared_cost += 32 + fields * 4
          }
        Some(ArrayNew(_) | ArrayNewDefault(_)) => arrays += 1
        _ => ()
      }
      if struct_cost > 512 && shared_cost > 1200 && arrays > 16 {
        return (false, false, false)
      }
    }
  }
  (struct_cost <= 512, arrays <= 16, shared_cost <= 1200)
}
