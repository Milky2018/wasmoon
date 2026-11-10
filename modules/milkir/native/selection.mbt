///|
priv struct MemoryAddressSelection {
  base : @milkir.Value
  index : @milkir.Value?
  shift : Int32
  offset : UInt64
}

///|
priv struct MemoryAddressMatch {
  selection : MemoryAddressSelection
  consumed : Array[@milkir.Value]
}

///|
priv enum ScalarSelection {
  CompareImmediate(@milkir.Value, @lowering.IntComparison, UInt64)
  IntImmediate(@milkir.Value, @lowering.IntBinaryOp, UInt64)
  ShiftImmediate(@milkir.Value, @lowering.IntBinaryOp, Int32)
  MultiplyAccumulate(@milkir.Value, @milkir.Value, @milkir.Value, Bool)
  AddShifted(@milkir.Value, @milkir.Value, Int32, Bool)
  LowBitsShiftedLeft(@milkir.Value, Int32, Int32)
}

///|
priv enum ComparisonSelection {
  Compare(@milkir.Value, @milkir.Value, @lowering.IntComparison)
  CompareImmediate(
    @milkir.Value,
    @milkir.Value,
    UInt64,
    @lowering.IntComparison
  )
}

///|
priv struct SelectionFacts {
  supports_int_binary_immediate : (
    @lowering.IntBinaryOp,
    @native_types.ValueType,
    UInt64,
  ) -> Bool
  supports_int_compare_immediate : (@native_types.ValueType, UInt64) -> Bool
  folds_unsigned_index_into_memory : Bool
  uses : Array[Int32]
  consumers : Array[Int32]
  branch_conditions : Array[Bool]
  shared_consumers : Array[Array[Int32]?]
  constants : Array[UInt64?]
  definitions : Array[@milkir.Inst?]
  instructions : Array[@milkir.Inst?]
  instruction_blocks : Array[Int32]
  deferred : Array[Bool?]
  memory_consumers : Array[Int32]
  memory_selection_computed : Array[Bool]
  memory_selections : Array[MemoryAddressMatch?]
}

///|
fn record_use(
  uses : Array[Int32],
  consumers : Array[Int32],
  shared_consumers : Array[Array[Int32]?],
  value : @milkir.Value,
  consumer : Int32,
  track_shared : Bool,
) -> Unit {
  if uses[value.id] == 0 {
    consumers[value.id] = consumer
  } else if uses[value.id] == 1 {
    if track_shared {
      let first = consumers[value.id]
      shared_consumers[value.id] = Some([first, consumer])
    }
    consumers[value.id] = -2
  } else if track_shared {
    guard shared_consumers[value.id] is Some(recorded) else {
      abort("shared consumers must exist after the second use")
    }
    recorded.push(consumer)
  }
  uses[value.id] += 1
}

///|
fn scalar_definition(
  definitions : Array[@milkir.Inst?],
  value : @milkir.Value,
) -> @milkir.Inst? {
  definitions[value.id]
}

///|
fn binary_operands(
  instruction : @milkir.Inst,
) -> (@milkir.Value, @milkir.Value)? {
  match instruction.args {
    [left, right] => Some((left, right))
    _ => None
  }
}

///|
fn unary_operand(instruction : @milkir.Inst) -> @milkir.Value? {
  match instruction.args {
    [operand] => Some(operand)
    _ => None
  }
}

///|
fn pointer_source(
  facts : SelectionFacts,
  value : @milkir.Value,
) -> @milkir.Value? {
  if value.ty == Ptr {
    return Some(value)
  }
  guard value.ty == I64 else { return None }
  guard scalar_definition(facts.definitions, value) is Some(instruction) else {
    return None
  }
  guard instruction.opcode is Scalar(Convert(Bitcast)) else { return None }
  guard unary_operand(instruction) is Some(pointer) && pointer.ty == Ptr else {
    return None
  }
  Some(pointer)
}

///|
fn extended_i32_source(
  facts : SelectionFacts,
  value : @milkir.Value,
) -> @milkir.Value? {
  guard scalar_definition(facts.definitions, value) is Some(instruction) else {
    return None
  }
  guard instruction.opcode is Scalar(Convert(UnsignedExtend)) else {
    return None
  }
  guard unary_operand(instruction) is Some(index) && index.ty == I32 else {
    return None
  }
  Some(index)
}

///|
fn natural_memory_shift(width : @native_types.AccessWidth) -> Int32 {
  match width {
    W8 => 0
    W16 => 1
    W32 => 2
    W64 => 3
    W128 => 4
  }
}

///|
fn scaled_i32_source(
  facts : SelectionFacts,
  value : @milkir.Value,
  width : @native_types.AccessWidth,
) -> (@milkir.Value, Int32, Array[@milkir.Value]) {
  let shift = natural_memory_shift(width)
  if shift == 0 {
    return (value, 0, [])
  }
  guard scalar_definition(facts.definitions, value) is Some(instruction) else {
    return (value, 0, [])
  }
  guard instruction.opcode is Scalar(IntBinary(Mul)) else {
    return (value, 0, [])
  }
  guard binary_operands(instruction) is Some((left, right)) else {
    return (value, 0, [])
  }
  let scale = 1UL << shift
  if facts.constants[right.id] == Some(scale) {
    (left, shift, [value, right])
  } else if facts.constants[left.id] == Some(scale) {
    (right, shift, [value, left])
  } else {
    (value, 0, [])
  }
}

///|
fn select_index_and_offset(
  facts : SelectionFacts,
  value : @milkir.Value,
  width : @native_types.AccessWidth,
) -> (@milkir.Value, Int32, UInt64, Array[@milkir.Value])? {
  if extended_i32_source(facts, value) is Some(index) {
    let (selected, shift, folded) = scaled_i32_source(facts, index, width)
    let consumed = [value]
    consumed.append(folded)
    return Some((selected, shift, 0UL, consumed))
  }
  guard scalar_definition(facts.definitions, value) is Some(instruction) else {
    return None
  }
  guard instruction.opcode is Scalar(IntBinary(Add)) else { return None }
  guard binary_operands(instruction) is Some((left, right)) else { return None }
  let selected = match facts.constants[right.id] {
    Some(offset) => Some((left, right, offset))
    None =>
      match facts.constants[left.id] {
        Some(offset) => Some((right, left, offset))
        None => None
      }
  }
  guard selected is Some((extended, constant, offset)) else { return None }
  guard extended_i32_source(facts, extended) is Some(index) else { return None }
  let (selected_index, shift, scaled) = scaled_i32_source(facts, index, width)
  let consumed = [value, extended, constant]
  consumed.append(scaled)
  Some((selected_index, shift, offset, consumed))
}

///|
fn select_pointer_index(
  facts : SelectionFacts,
  offset : @milkir.Value,
  width : @native_types.AccessWidth,
) -> (@milkir.Value, Int32, Array[@milkir.Value])? {
  if extended_i32_source(facts, offset) is Some(index) {
    return Some((index, 0, [offset]))
  }
  let shift = natural_memory_shift(width)
  guard shift > 0 &&
    scalar_definition(facts.definitions, offset) is Some(inst) &&
    binary_operands(inst) is Some((left, right)) else {
    return None
  }
  let scale = 1UL << shift
  let (extended, scale_value) = match inst.opcode {
    Scalar(IntBinary(ShiftLeft)) if facts.constants[right.id] ==
      Some(shift.to_uint64()) => (left, right)
    Scalar(IntBinary(Mul)) if facts.constants[right.id] == Some(scale) =>
      (left, right)
    Scalar(IntBinary(Mul)) if facts.constants[left.id] == Some(scale) =>
      (right, left)
    _ => return None
  }
  extended_i32_source(facts, extended).map(index => {
    (index, shift, [offset, extended, scale_value])
  })
}

///|
fn select_memory_address(
  facts : SelectionFacts,
  base : @milkir.Value,
  offset : @milkir.Value,
  width : @native_types.AccessWidth,
) -> MemoryAddressMatch? {
  guard facts.constants[offset.id] is Some(static_offset) else {
    guard pointer_source(facts, base) is Some(pointer) &&
      select_pointer_index(facts, offset, width)
      is Some((index, shift, consumed)) else {
      return None
    }
    if base != pointer {
      consumed.push(base)
    }
    guard consumed.all(value => {
      memory_address_value_is_free(value, facts) || facts.uses[value.id] == 1
    }) else {
      return None
    }
    return Some({
      selection: { base: pointer, index: Some(index), shift, offset: 0UL, },
      consumed,
    })
  }
  let selected = if pointer_source(facts, base) is Some(pointer) {
    let consumed = [offset]
    if pointer != base {
      consumed.push(base)
    }
    Some(
      (
        { base: pointer, index: None, shift: 0, offset: static_offset, },
        consumed,
      ),
    )
  } else {
    guard scalar_definition(facts.definitions, base) is Some(add) else {
      return direct_i64_memory_address(base, offset, static_offset)
    }
    guard add.opcode is Scalar(IntBinary(Add)) else {
      return direct_i64_memory_address(base, offset, static_offset)
    }
    guard binary_operands(add) is Some((left, right)) else {
      return direct_i64_memory_address(base, offset, static_offset)
    }
    let parts = match pointer_source(facts, left) {
      Some(pointer) =>
        select_index_and_offset(facts, right, width).map(selected => {
          (pointer, left, selected)
        })
      None =>
        match pointer_source(facts, right) {
          Some(pointer) =>
            select_index_and_offset(facts, left, width).map(selected => {
              (pointer, right, selected)
            })
          None => None
        }
    }
    guard parts is Some((pointer, pointer_bits, selected)) else {
      return direct_i64_memory_address(base, offset, static_offset)
    }
    let (index, shift, dynamic_offset, consumed_index) = selected
    let consumed = [base, offset]
    if pointer_bits != pointer {
      consumed.push(pointer_bits)
    }
    consumed.append(consumed_index)
    Some(
      (
        {
          base: pointer,
          index: Some(index),
          shift,
          offset: static_offset + dynamic_offset,
        },
        consumed,
      ),
    )
  }
  guard selected is Some((selection, consumed)) else { return None }
  if consumed.any(value => {
      !memory_address_value_is_free(value, facts) && facts.uses[value.id] != 1
    }) {
    None
  } else {
    Some({ selection, consumed, })
  }
}

///|
/// Values that add no instruction when folded into an address may be consumed
/// by more than one memory selection. A raw-word pointer bitcast is a typed IR
/// boundary, not a machine operation; requiring a single use here makes GVN of
/// that bitcast pessimize every later address.
fn memory_address_value_is_free(
  value : @milkir.Value,
  facts : SelectionFacts,
) -> Bool {
  if facts.constants[value.id] is Some(_) {
    return true
  }
  guard scalar_definition(facts.definitions, value) is Some(instruction) else {
    return false
  }
  match instruction.opcode {
    Scalar(Convert(Bitcast)) =>
      instruction.args is [source] && source.ty == Ptr && value.ty == I64
    Scalar(Convert(UnsignedExtend)) =>
      facts.folds_unsigned_index_into_memory &&
      instruction.args is [source] &&
      source.ty == I32 &&
      value.ty == I64
    _ => false
  }
}

///|
fn direct_i64_memory_address(
  base : @milkir.Value,
  offset : @milkir.Value,
  static_offset : UInt64,
) -> MemoryAddressMatch? {
  if base.ty == I64 {
    Some({
      selection: { base, index: None, shift: 0, offset: static_offset, },
      consumed: [offset],
    })
  } else {
    None
  }
}

///|
fn memory_access(
  instruction : @milkir.Inst,
) -> (@milkir.Value, @milkir.Value, @native_types.AccessWidth)? {
  match instruction.opcode {
    Memory(Load(result_type)) =>
      Some(
        (
          instruction.args[0],
          instruction.args[1],
          access_width_for_type(lower_type(result_type)),
        ),
      )
    Memory(Store(value_type)) =>
      Some(
        (
          instruction.args[0],
          instruction.args[2],
          access_width_for_type(lower_type(value_type)),
        ),
      )
    Memory(LoadNarrow(_, bits, _)) =>
      lower_width(bits).map(width => {
        (instruction.args[0], instruction.args[1], width)
      })
    Memory(StoreNarrow(bits)) =>
      lower_width(bits).map(width => {
        (instruction.args[0], instruction.args[2], width)
      })
    _ => None
  }
}

///|
fn selection_binary_operation(
  operation : @milkir.IntBinaryOp,
) -> @lowering.IntBinaryOp {
  match operation {
    Add => Add
    Sub => Sub
    Mul => Mul
    SignedDiv => SignedDiv
    UnsignedDiv => UnsignedDiv
    SignedRem => SignedRem
    UnsignedRem => UnsignedRem
    And => And
    Or => Or
    Xor => Xor
    ShiftLeft => ShiftLeft
    SignedShiftRight => SignedShiftRight
    UnsignedShiftRight => UnsignedShiftRight
    RotateLeft => RotateLeft
    RotateRight => RotateRight
    SignedMulHigh | UnsignedMulHigh =>
      abort("high multiply is not a selectable binary immediate")
  }
}

///|
fn swapped_comparison(
  comparison : @lowering.IntComparison,
) -> @lowering.IntComparison {
  match comparison {
    Equal => Equal
    NotEqual => NotEqual
    SignedLessThan => SignedGreaterThan
    SignedLessOrEqual => SignedGreaterOrEqual
    SignedGreaterThan => SignedLessThan
    SignedGreaterOrEqual => SignedLessOrEqual
    UnsignedLessThan => UnsignedGreaterThan
    UnsignedLessOrEqual => UnsignedGreaterOrEqual
    UnsignedGreaterThan => UnsignedLessThan
    UnsignedGreaterOrEqual => UnsignedLessOrEqual
  }
}

///|
fn select_right_immediate(
  binary : @milkir.IntBinaryOp,
  left : @milkir.Value,
  width : Int32,
  bits : UInt64,
) -> ScalarSelection? {
  match binary {
    ShiftLeft
    | SignedShiftRight
    | UnsignedShiftRight
    | RotateLeft
    | RotateRight =>
      Some(
        ShiftImmediate(
          left,
          selection_binary_operation(binary),
          (bits % width.to_uint64()).to_int(),
        ),
      )
    Add | Sub | Mul | And | Or | Xor =>
      Some(IntImmediate(left, selection_binary_operation(binary), bits))
    UnsignedRem if bits > 1UL && (bits & (bits - 1UL)) == 0UL =>
      Some(IntImmediate(left, UnsignedRem, bits))
    SignedDiv | UnsignedDiv | SignedRem | UnsignedRem => None
    SignedMulHigh | UnsignedMulHigh => None
  }
}

///|
fn select_scalar_instruction(
  instruction : @milkir.Inst,
  constants : Array[UInt64?],
  supports_int_binary_immediate : (
    @lowering.IntBinaryOp,
    @native_types.ValueType,
    UInt64,
  ) -> Bool,
  supports_int_compare_immediate : (@native_types.ValueType, UInt64) -> Bool,
) -> (ScalarSelection, @milkir.Value)? {
  if instruction.opcode is Scalar(IntCompare(_)) {
    return match
      select_comparison(instruction, constants, supports_int_compare_immediate) {
      Some(CompareImmediate(input, constant, bits, condition)) =>
        Some((CompareImmediate(input, condition, bits), constant))
      _ => None
    }
  }
  guard instruction.opcode is Scalar(IntBinary(binary)) else { return None }
  guard binary_operands(instruction) is Some((left, right)) else { return None }
  guard instruction.results is [result] &&
    (result.ty == I32 || result.ty == I64) else {
    return None
  }
  let width = if result.ty == I32 { 32 } else { 64 }
  match constants[right.id] {
    Some(bits) =>
      match select_right_immediate(binary, left, width, bits) {
        Some(IntImmediate(_, operation, selected_bits)) as selected =>
          if supports_int_binary_immediate(
              operation,
              lower_type(result.ty),
              selected_bits,
            ) {
            Some((selected.unwrap(), right))
          } else {
            None
          }
        Some(selection) => Some((selection, right))
        None => None
      }
    None =>
      match constants[left.id] {
        Some(bits) if binary is (Add | Mul | And | Or | Xor) &&
          supports_int_binary_immediate(
            selection_binary_operation(binary),
            lower_type(result.ty),
            bits,
          ) =>
          Some(
            (
              IntImmediate(right, selection_binary_operation(binary), bits),
              left,
            ),
          )
        _ => None
      }
  }
}

///|
fn selection_tracks_shared_consumers(
  value : @milkir.Value,
  constants : Array[UInt64?],
  definitions : Array[@milkir.Inst?],
  folds_unsigned_index_into_memory : Bool,
) -> Bool {
  if constants[value.id] is Some(_) {
    return true
  }
  match definitions[value.id] {
    Some(definition) =>
      match definition.opcode {
        Vector(Bitwise(Not)) => true
        Scalar(Convert(Bitcast)) =>
          definition.args is [source] && source.ty == Ptr && value.ty == I64
        Scalar(Convert(UnsignedExtend)) =>
          folds_unsigned_index_into_memory &&
          definition.args is [source] &&
          source.ty == I32 &&
          value.ty == I64
        _ => false
      }
    None => false
  }
}

///|
fn build_selection_facts(
  function : @milkir.Function,
  folds_unsigned_index_into_memory : Bool,
  supports_int_binary_immediate : (
    @lowering.IntBinaryOp,
    @native_types.ValueType,
    UInt64,
  ) -> Bool,
  supports_int_compare_immediate : (@native_types.ValueType, UInt64) -> Bool,
) -> SelectionFacts {
  let uses = Array::make(function.next_value_id, 0)
  let consumers = Array::make(function.next_value_id, -2)
  let branch_conditions = Array::make(function.next_value_id, false)
  let shared_consumers : Array[Array[Int32]?] = Array::make(
    function.next_value_id,
    None,
  )
  let constants : Array[UInt64?] = Array::make(function.next_value_id, None)
  let definitions : Array[@milkir.Inst?] = Array::make(
    function.next_value_id,
    None,
  )
  let instruction_blocks = Array::make(function.next_inst_id, -1)
  let instructions : Array[@milkir.Inst?] = Array::make(
    function.next_inst_id,
    None,
  )
  let deferred : Array[Bool?] = Array::make(function.next_inst_id, None)
  let memory_consumers = Array::make(function.next_value_id, -2)
  let memory_selection_computed = Array::make(function.next_inst_id, false)
  let memory_selections : Array[MemoryAddressMatch?] = Array::make(
    function.next_inst_id,
    None,
  )
  for block in function.blocks {
    for instruction_id in function.block_instruction_ids(block) {
      let instruction = function.instruction_by_id(instruction_id).unwrap()
      instructions[instruction.id] = Some(instruction)
      instruction_blocks[instruction.id] = block.id
      for result in instruction.results {
        definitions[result.id] = Some(instruction)
      }
      match (instruction.opcode, instruction.results) {
        (Scalar(IntConst(bits)), [result]) =>
          constants[result.id] = Some(
            if result.ty == I32 {
              bits.to_int().reinterpret_as_uint().to_uint64()
            } else {
              bits.reinterpret_as_uint64()
            },
          )
        _ => ()
      }
    }
  }
  // Definitions must be complete before classifying shared consumers: valid
  // SSA dominance does not require the function's block array to be in
  // dominator order.
  for block in function.blocks {
    for instruction_id in function.block_instruction_ids(block) {
      let instruction = function.instruction_by_id(instruction_id).unwrap()
      for argument in instruction.args {
        record_use(
          uses,
          consumers,
          shared_consumers,
          argument,
          instruction.id,
          selection_tracks_shared_consumers(
            argument, constants, definitions, folds_unsigned_index_into_memory,
          ),
        )
      }
    }
    if block.terminator is Some(terminator) {
      // Only these terminators absorb comparisons. Jump/return arguments and
      // br_table selectors still require an ordinary materialized value.
      match terminator {
        Branch(condition, _, _, _, _)
        | Brz(condition, _, _)
        | Brnz(condition, _, _) => branch_conditions[condition.id] = true
        _ => ()
      }
      for value in terminator_values(terminator) {
        record_use(
          uses,
          consumers,
          shared_consumers,
          value,
          -1,
          selection_tracks_shared_consumers(
            value, constants, definitions, folds_unsigned_index_into_memory,
          ),
        )
      }
    }
  }
  {
    supports_int_binary_immediate,
    supports_int_compare_immediate,
    folds_unsigned_index_into_memory,
    uses,
    consumers,
    branch_conditions,
    shared_consumers,
    constants,
    definitions,
    instructions,
    instruction_blocks,
    deferred,
    memory_consumers,
    memory_selection_computed,
    memory_selections,
  }
}

///|
fn memory_consumer_id(value : @milkir.Value, facts : SelectionFacts) -> Int32 {
  if facts.memory_consumers[value.id] != -2 {
    return facts.memory_consumers[value.id]
  }
  let direct_consumer = facts.consumers[value.id]
  let consumer_id = if facts.uses[value.id] == 1 && direct_consumer >= 0 {
    let instruction = facts.instructions[direct_consumer].unwrap()
    if memory_access(instruction) is Some(_) {
      instruction.id
    } else if instruction.results is [result] {
      memory_consumer_id(result, facts)
    } else {
      -1
    }
  } else {
    -1
  }
  facts.memory_consumers[value.id] = consumer_id
  consumer_id
}

///|
fn selected_by_memory_address(
  value : @milkir.Value,
  facts : SelectionFacts,
) -> Bool {
  let consumer_id = facts.consumers[value.id]
  guard consumer_id >= 0 && facts.instructions[consumer_id] is Some(consumer) else {
    return false
  }
  selected_by_memory_address_use(value, consumer, facts)
}

///|
fn MemoryAddressMatch::absorbs(
  self : MemoryAddressMatch,
  value : @milkir.Value,
) -> Bool {
  self.selection.base != value &&
  self.selection.index != Some(value) &&
  self.consumed.contains(value)
}

///|
fn selected_by_memory_address_use(
  value : @milkir.Value,
  consumer : @milkir.Inst,
  facts : SelectionFacts,
) -> Bool {
  let consumer_id = if memory_access(consumer) is Some(_) {
    consumer.id
  } else if consumer.results is [result] {
    memory_consumer_id(result, facts)
  } else {
    -1
  }
  guard consumer_id >= 0 &&
    facts.instructions[consumer_id] is Some(instruction) &&
    memory_selection(instruction, facts) is Some(selected) else {
    return false
  }
  // A value can feed both the selected address and the stored payload.
  // Following a single-use chain to a store does not prove that the chain
  // contributes to its address.
  if consumer_id == consumer.id {
    if consumer.opcode is Memory(Store(_) | StoreNarrow(_)) &&
      consumer.args[1] == value {
      return false
    }
  } else {
    guard consumer.results is [result] && selected.absorbs(result) else {
      return false
    }
  }
  selected.absorbs(value)
}

///|
fn fully_selected_by_memory_addresses(
  value : @milkir.Value,
  facts : SelectionFacts,
) -> Bool {
  if facts.uses[value.id] == 1 && facts.consumers[value.id] >= 0 {
    return selected_by_memory_address(value, facts)
  }
  guard facts.uses[value.id] > 1 &&
    facts.shared_consumers[value.id] is Some(consumers) else {
    return false
  }
  consumers.all(consumer => {
    guard facts.instructions[consumer] is Some(instruction) else {
      return false
    }
    selected_by_memory_address_use(value, instruction, facts)
  })
}

///|
fn memory_selection(
  instruction : @milkir.Inst,
  facts : SelectionFacts,
) -> MemoryAddressMatch? {
  if !facts.memory_selection_computed[instruction.id] {
    facts.memory_selection_computed[instruction.id] = true
    if memory_access(instruction) is Some((base, offset, width)) {
      facts.memory_selections[instruction.id] = select_memory_address(
        facts, base, offset, width,
      )
    }
  }
  facts.memory_selections[instruction.id]
}

///|
fn consumer_selects_constant(
  constant : @milkir.Value,
  consumer_id : Int32,
  facts : SelectionFacts,
) -> Bool {
  guard consumer_id >= 0 && facts.instructions[consumer_id] is Some(instruction) else {
    return false
  }
  // A folded product disappears, but multiply-add still consumes both
  // factors as register values. Its constant must retain its SSA definition.
  if instruction.opcode is Scalar(IntBinary(Mul)) &&
    instruction.results is [product] &&
    facts.uses[product.id] == 1 &&
    facts.consumers[product.id] >= 0 &&
    facts.instructions[facts.consumers[product.id]] is Some(consumer) &&
    select_scalar_lowering(consumer, facts)
    is Some(MultiplyAccumulate(_, _, _, _)) {
    return false
  }
  // Test the actual selected recipe. A fused shifted add or multiply-add may
  // require a register even when the unfused operation accepts an immediate.
  let absorbed = match select_scalar_lowering(instruction, facts) {
    Some(
      CompareImmediate(input, _, _)
      | IntImmediate(input, _, _)
      | ShiftImmediate(input, _, _)
      | LowBitsShiftedLeft(input, _, _)
    ) => input != constant
    _ => false
  }
  if absorbed {
    return true
  }
  if instruction.opcode is Scalar(IntCompare(_)) &&
    instruction.results is [condition] &&
    facts.consumers[condition.id] == -1 &&
    select_branch_lowering(condition, facts)
    is Some(CompareImmediate(input, selected_constant, _, _)) &&
    selected_constant == constant &&
    input != constant {
    return true
  }
  selected_by_memory_address_use(constant, instruction, facts)
}

///|
fn constant_is_fully_selected(
  constant : @milkir.Value,
  facts : SelectionFacts,
) -> Bool {
  if facts.uses[constant.id] == 1 && facts.consumers[constant.id] != -2 {
    return consumer_selects_constant(
      constant,
      facts.consumers[constant.id],
      facts,
    )
  }
  guard facts.uses[constant.id] > 1 &&
    facts.shared_consumers[constant.id] is Some(consumers) else {
    return false
  }
  consumers.all(consumer => consumer_selects_constant(constant, consumer, facts))
}

///|
fn should_defer_instruction(
  instruction : @milkir.Inst,
  facts : SelectionFacts,
) -> Bool {
  if facts.deferred[instruction.id] is Some(deferred) {
    return deferred
  }
  let deferred = compute_should_defer_instruction(instruction, facts)
  facts.deferred[instruction.id] = Some(deferred)
  deferred
}

///|
fn compute_should_defer_instruction(
  instruction : @milkir.Inst,
  facts : SelectionFacts,
) -> Bool {
  guard instruction.results is [result] else { return false }
  if instruction.opcode is Vector(Bitwise(Not)) {
    return vector_not_is_fully_selected(result, facts)
  }
  guard result.ty is (I32 | I64) else { return false }
  if instruction.opcode is Scalar(IntConst(_)) {
    return constant_is_fully_selected(result, facts)
  }
  if instruction.opcode is Scalar(Convert(Bitcast)) &&
    instruction.args is [source] &&
    source.ty == Ptr &&
    result.ty == I64 {
    return fully_selected_by_memory_addresses(result, facts)
  }
  if instruction.opcode is Scalar(Convert(UnsignedExtend)) &&
    instruction.args is [source] &&
    source.ty == I32 &&
    result.ty == I64 {
    return fully_selected_by_memory_addresses(result, facts)
  }
  guard facts.uses[result.id] == 1 else { return false }
  match instruction.opcode {
    Scalar(IntBinary(Add)) => selected_by_memory_address(result, facts)
    Scalar(IntBinary(Mul)) => {
      let composite = match facts.consumers[result.id] {
        consumer_id if consumer_id >= 0 =>
          select_scalar_lowering(
            facts.instructions[consumer_id].unwrap(),
            facts,
          )
          is Some(MultiplyAccumulate(_, _, _, _))
        _ => false
      }
      composite || selected_by_memory_address(result, facts)
    }
    Scalar(IntBinary(ShiftLeft | UnsignedShiftRight)) => {
      let composite = match facts.consumers[result.id] {
        consumer_id if consumer_id >= 0 =>
          select_scalar_lowering(
            facts.instructions[consumer_id].unwrap(),
            facts,
          )
          is Some(AddShifted(_, _, _, _) | LowBitsShiftedLeft(_, _, _))
        _ => false
      }
      composite ||
      (
        instruction.opcode is Scalar(IntBinary(ShiftLeft)) &&
        selected_by_memory_address(result, facts)
      )
    }
    Scalar(IntCompare(_)) =>
      facts.consumers[result.id] == -1 &&
      select_branch_lowering(result, facts) is Some(_)
    Scalar(Convert(UnsignedExtend)) => false
    Scalar(Convert(Bitcast)) =>
      instruction.args is [source] &&
      source.ty == Ptr &&
      result.ty == I64 &&
      selected_by_memory_address(result, facts)
    Scalar(IntConst(_)) => abort("integer constants are handled above")
    _ => false
  }
}

///|
fn select_multiply_add(
  accumulator : @milkir.Value,
  product : @milkir.Value,
  facts : SelectionFacts,
  subtract~ : Bool = false,
) -> ScalarSelection? {
  guard facts.uses[product.id] == 1 else { return None }
  guard facts.definitions[product.id] is Some(multiply) else { return None }
  guard multiply.opcode is Scalar(IntBinary(Mul)) else { return None }
  guard binary_operands(multiply) is Some((first, second)) else { return None }
  Some(MultiplyAccumulate(accumulator, first, second, subtract))
}

///|
fn select_shifted_add(
  accumulator : @milkir.Value,
  shifted : @milkir.Value,
  facts : SelectionFacts,
) -> ScalarSelection? {
  guard facts.uses[shifted.id] == 1 else { return None }
  guard facts.definitions[shifted.id] is Some(shift) else { return None }
  guard shift.opcode is Scalar(IntBinary(ShiftLeft | UnsignedShiftRight)) else {
    return None
  }
  guard binary_operands(shift) is Some((input, amount)) else { return None }
  guard facts.constants[amount.id] is Some(bits) else { return None }
  let width = if shifted.ty == I32 { 32UL } else { 64UL }
  Some(
    AddShifted(
      accumulator,
      input,
      (bits % width).to_int(),
      shift.opcode is Scalar(IntBinary(UnsignedShiftRight)),
    ),
  )
}

///|
fn select_low_bits_shift(
  shifted : @milkir.Value,
  mask : UInt64,
  facts : SelectionFacts,
) -> ScalarSelection? {
  guard facts.uses[shifted.id] == 1 &&
    facts.definitions[shifted.id] is Some(shift) &&
    shift.opcode is Scalar(IntBinary(ShiftLeft)) &&
    binary_operands(shift) is Some((input, amount)) &&
    facts.constants[amount.id] is Some(bits) else {
    return None
  }
  let width = if shifted.ty == I32 { 32 } else { 64 }
  let amount = (bits % width.to_uint64()).to_int()
  guard amount > 0 else { return None }
  let mask = if width == 32 { mask & 0xFFFFFFFFUL } else { mask }
  guard (mask & ((1UL << amount) - 1UL)) == 0UL else { return None }
  let field = mask >> amount
  guard field != 0UL && (field & (field + 1UL)) == 0UL else { return None }
  Some(LowBitsShiftedLeft(input, 64 - field.clz(), amount))
}

///|
fn select_scalar_lowering(
  instruction : @milkir.Inst,
  facts : SelectionFacts,
) -> ScalarSelection? {
  if instruction.opcode is Scalar(IntBinary(And)) &&
    instruction.results is [_] &&
    binary_operands(instruction) is Some((left, right)) {
    if facts.constants[right.id] is Some(mask) &&
      select_low_bits_shift(left, mask, facts) is Some(selected) {
      return Some(selected)
    }
    if facts.constants[left.id] is Some(mask) &&
      select_low_bits_shift(right, mask, facts) is Some(selected) {
      return Some(selected)
    }
  }
  if instruction.opcode is Scalar(IntBinary(Sub)) &&
    instruction.results is [_] &&
    binary_operands(instruction) is Some((left, right)) &&
    select_multiply_add(left, right, facts, subtract=true) is Some(selected) {
    return Some(selected)
  }
  if instruction.opcode is Scalar(IntBinary(Add)) &&
    instruction.results is [_] &&
    binary_operands(instruction) is Some((left, right)) {
    match select_multiply_add(left, right, facts) {
      Some(selection) => return Some(selection)
      None =>
        match select_multiply_add(right, left, facts) {
          Some(selection) => return Some(selection)
          None => ()
        }
    }
    match select_shifted_add(left, right, facts) {
      Some(selection) => return Some(selection)
      None =>
        match select_shifted_add(right, left, facts) {
          Some(selection) => return Some(selection)
          None => ()
        }
    }
  }
  select_scalar_instruction(
    instruction,
    facts.constants,
    facts.supports_int_binary_immediate,
    facts.supports_int_compare_immediate,
  ).map(value => value.0)
}

///|
// Both value and branch consumers share operand matching and condition reversal.
// Branches retain their existing materialization fallback for any constant;
// value consumers only absorb constants accepted by the target.
fn select_comparison(
  instruction : @milkir.Inst,
  constants : Array[UInt64?],
  accepts_immediate : (@native_types.ValueType, UInt64) -> Bool,
) -> ComparisonSelection? {
  guard instruction.opcode is Scalar(IntCompare(comparison)) else {
    return None
  }
  guard binary_operands(instruction) is Some((left, right)) else { return None }
  guard left.ty == right.ty && left.ty is (I32 | I64) else { return None }
  let condition = lower_int_comparison(comparison)
  if constants[right.id] is Some(bits) &&
    accepts_immediate(lower_type(left.ty), bits) {
    return Some(CompareImmediate(left, right, bits, condition))
  }
  if constants[left.id] is Some(bits) &&
    accepts_immediate(lower_type(right.ty), bits) {
    return Some(
      CompareImmediate(right, left, bits, swapped_comparison(condition)),
    )
  }
  Some(Compare(left, right, condition))
}

///|
fn select_branch_lowering(
  condition : @milkir.Value,
  facts : SelectionFacts,
) -> ComparisonSelection? {
  guard facts.uses[condition.id] == 1 && facts.branch_conditions[condition.id] else {
    return None
  }
  guard facts.definitions[condition.id] is Some(instruction) else {
    return None
  }
  select_comparison(instruction, facts.constants, fn(_, _) { true })
}
