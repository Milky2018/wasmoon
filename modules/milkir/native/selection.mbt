///|
priv struct MemoryAddressSelection {
  base : @milkir.Value
  index : @milkir.Value?
  shift : Int
  offset : UInt64
}

///|
priv struct MemoryAddressMatch {
  selection : MemoryAddressSelection
  consumed : Array[@milkir.Value]
}

///|
priv enum ScalarSelection {
  IntImmediate(@milkir.Value, @lowering.IntBinaryOp, UInt64)
  ShiftImmediate(@milkir.Value, @lowering.IntBinaryOp, Int)
  MultiplyAdd(@milkir.Value, @milkir.Value, @milkir.Value)
  AddShiftedLeft(@milkir.Value, @milkir.Value, Int)
}

///|
priv enum BranchSelection {
  Compare(@milkir.Value, @milkir.Value, @lowering.IntComparison)
  CompareImmediate(@milkir.Value, UInt64, @lowering.IntComparison)
}

///|
priv struct SelectionFacts {
  uses : Array[Int]
  consumers : Array[Int]
  shared_consumers : Array[Array[Int]?]
  constants : Array[UInt64?]
  definitions : Array[@milkir.Inst?]
  instructions : Array[@milkir.Inst?]
  instruction_blocks : Array[Int]
  deferred : Array[Bool?]
  memory_consumers : Array[Int]
  memory_selection_computed : Array[Bool]
  memory_selections : Array[MemoryAddressMatch?]
}

///|
fn record_use(
  uses : Array[Int],
  consumers : Array[Int],
  shared_consumers : Array[Array[Int]?],
  value : @milkir.Value,
  consumer : Int,
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
fn natural_memory_shift(width : @native_types.AccessWidth) -> Int {
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
) -> (@milkir.Value, Int, Array[@milkir.Value]) {
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
) -> (@milkir.Value, Int, UInt64, Array[@milkir.Value])? {
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
fn select_memory_address(
  facts : SelectionFacts,
  base : @milkir.Value,
  offset : @milkir.Value,
  width : @native_types.AccessWidth,
) -> MemoryAddressMatch? {
  guard facts.constants[offset.id] is Some(static_offset) else { return None }
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
      facts.constants[value.id] is None && facts.uses[value.id] != 1
    }) {
    None
  } else {
    Some({ selection, consumed, })
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
fn selection_comparison(comparison : @milkir.IntCC) -> @lowering.IntComparison {
  match comparison {
    Eq => Equal
    Ne => NotEqual
    Slt => SignedLessThan
    Sle => SignedLessOrEqual
    Sgt => SignedGreaterThan
    Sge => SignedGreaterOrEqual
    Ult => UnsignedLessThan
    Ule => UnsignedLessOrEqual
    Ugt => UnsignedGreaterThan
    Uge => UnsignedGreaterOrEqual
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
  width : Int,
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
) -> (ScalarSelection, @milkir.Value)? {
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
        Some(selection) => Some((selection, right))
        None => None
      }
    None =>
      match constants[left.id] {
        Some(bits) if binary is (Add | Mul | And | Or | Xor) =>
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
fn build_selection_facts(function : @milkir.Function) -> SelectionFacts {
  let uses = Array::make(function.next_value_id, 0)
  let consumers = Array::make(function.next_value_id, -2)
  let shared_consumers : Array[Array[Int]?] = Array::make(
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
    for instruction in block.instructions {
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
      for argument in instruction.args {
        record_use(
          uses,
          consumers,
          shared_consumers,
          argument,
          instruction.id,
          constants[argument.id] is Some(_),
        )
      }
    }
    if block.terminator is Some(terminator) {
      for value in terminator_values(terminator) {
        record_use(
          uses,
          consumers,
          shared_consumers,
          value,
          -1,
          constants[value.id] is Some(_),
        )
      }
    }
  }
  {
    uses,
    consumers,
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
fn memory_consumer_id(value : @milkir.Value, facts : SelectionFacts) -> Int {
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
  selected.consumed.any(consumed_value => consumed_value == value)
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
  consumer_id : Int,
  facts : SelectionFacts,
) -> Bool {
  guard consumer_id >= 0 && facts.instructions[consumer_id] is Some(instruction) else {
    return false
  }
  if select_scalar_instruction(instruction, facts.constants)
    is Some((_, selected_constant)) &&
    selected_constant == constant {
    return true
  }
  if instruction.opcode is Scalar(IntCompare(_)) &&
    instruction.results is [condition] &&
    facts.consumers[condition.id] == -1 &&
    select_branch_lowering(condition, facts) is Some(CompareImmediate(_, _, _)) {
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
  guard result.ty is (I32 | I64) else { return false }
  if instruction.opcode is Scalar(IntConst(_)) {
    return constant_is_fully_selected(result, facts)
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
          is Some(MultiplyAdd(_, _, _))
        _ => false
      }
      composite || selected_by_memory_address(result, facts)
    }
    Scalar(IntBinary(ShiftLeft)) =>
      match facts.consumers[result.id] {
        consumer_id if consumer_id >= 0 =>
          select_scalar_lowering(
            facts.instructions[consumer_id].unwrap(),
            facts,
          )
          is Some(AddShiftedLeft(_, _, _))
        _ => false
      }
    Scalar(IntCompare(_)) =>
      facts.consumers[result.id] == -1 &&
      select_branch_lowering(result, facts) is Some(_)
    Scalar(Convert(UnsignedExtend)) =>
      instruction.args is [source] &&
      source.ty == I32 &&
      result.ty == I64 &&
      selected_by_memory_address(result, facts)
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
) -> ScalarSelection? {
  guard facts.uses[product.id] == 1 else { return None }
  guard facts.definitions[product.id] is Some(multiply) else { return None }
  guard multiply.opcode is Scalar(IntBinary(Mul)) else { return None }
  guard binary_operands(multiply) is Some((first, second)) else { return None }
  Some(MultiplyAdd(accumulator, first, second))
}

///|
fn select_shifted_add(
  accumulator : @milkir.Value,
  shifted : @milkir.Value,
  facts : SelectionFacts,
) -> ScalarSelection? {
  guard facts.uses[shifted.id] == 1 else { return None }
  guard facts.definitions[shifted.id] is Some(shift) else { return None }
  guard shift.opcode is Scalar(IntBinary(ShiftLeft)) else { return None }
  guard binary_operands(shift) is Some((input, amount)) else { return None }
  guard facts.constants[amount.id] is Some(bits) else { return None }
  let width = if shifted.ty == I32 { 32UL } else { 64UL }
  Some(AddShiftedLeft(accumulator, input, (bits % width).to_int()))
}

///|
fn select_scalar_lowering(
  instruction : @milkir.Inst,
  facts : SelectionFacts,
) -> ScalarSelection? {
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
  select_scalar_instruction(instruction, facts.constants).map(value => value.0)
}

///|
fn select_branch_lowering(
  condition : @milkir.Value,
  facts : SelectionFacts,
) -> BranchSelection? {
  guard facts.uses[condition.id] == 1 else { return None }
  guard facts.definitions[condition.id] is Some(instruction) else {
    return None
  }
  guard instruction.opcode is Scalar(IntCompare(comparison)) else {
    return None
  }
  guard binary_operands(instruction) is Some((left, right)) else { return None }
  guard left.ty == right.ty && left.ty is (I32 | I64) else { return None }
  let lowered = selection_comparison(comparison)
  match facts.constants[right.id] {
    Some(bits) => Some(CompareImmediate(left, bits, lowered))
    None =>
      match facts.constants[left.id] {
        Some(bits) =>
          Some(CompareImmediate(right, bits, swapped_comparison(lowered)))
        None => Some(Compare(left, right, lowered))
      }
  }
}
