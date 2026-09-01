///|
priv struct MemoryAddressSelection {
  base : @milkir.Value
  index : @milkir.Value?
  shift : Int
  offset : UInt64
}

///|
priv struct LoweringAnalysis {
  memory_addresses : Array[MemoryAddressSelection?]
  skip_results : Array[Bool]
}

///|
fn count_use(uses : Array[Int], value : @milkir.Value) -> Unit {
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
  definitions : Array[@milkir.Inst?],
  value : @milkir.Value,
) -> @milkir.Value? {
  if value.ty == Ptr {
    return Some(value)
  }
  guard value.ty == I64 else { return None }
  guard scalar_definition(definitions, value) is Some(instruction) else {
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
  definitions : Array[@milkir.Inst?],
  value : @milkir.Value,
) -> @milkir.Value? {
  guard scalar_definition(definitions, value) is Some(instruction) else {
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
fn natural_memory_shift(width : @native.AccessWidth) -> Int {
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
  definitions : Array[@milkir.Inst?],
  constants : Array[UInt64?],
  value : @milkir.Value,
  width : @native.AccessWidth,
) -> (@milkir.Value, Int, Array[@milkir.Value]) {
  let shift = natural_memory_shift(width)
  if shift == 0 {
    return (value, 0, [])
  }
  guard scalar_definition(definitions, value) is Some(instruction) else {
    return (value, 0, [])
  }
  guard instruction.opcode is Scalar(IntBinary(Mul)) else {
    return (value, 0, [])
  }
  guard binary_operands(instruction) is Some((left, right)) else {
    return (value, 0, [])
  }
  let scale = 1UL << shift
  if constants[right.id] == Some(scale) {
    (left, shift, [value, right])
  } else if constants[left.id] == Some(scale) {
    (right, shift, [value, left])
  } else {
    (value, 0, [])
  }
}

///|
fn select_index_and_offset(
  definitions : Array[@milkir.Inst?],
  constants : Array[UInt64?],
  value : @milkir.Value,
  width : @native.AccessWidth,
) -> (@milkir.Value, Int, UInt64, Array[@milkir.Value])? {
  if extended_i32_source(definitions, value) is Some(index) {
    let (selected, shift, folded) = scaled_i32_source(
      definitions, constants, index, width,
    )
    let consumed = [value]
    consumed.append(folded)
    return Some((selected, shift, 0UL, consumed))
  }
  guard scalar_definition(definitions, value) is Some(instruction) else {
    return None
  }
  guard instruction.opcode is Scalar(IntBinary(Add)) else { return None }
  guard binary_operands(instruction) is Some((left, right)) else { return None }
  let selected = match constants[right.id] {
    Some(offset) => Some((left, right, offset))
    None =>
      match constants[left.id] {
        Some(offset) => Some((right, left, offset))
        None => None
      }
  }
  guard selected is Some((extended, constant, offset)) else { return None }
  guard extended_i32_source(definitions, extended) is Some(index) else {
    return None
  }
  let (selected_index, shift, scaled) = scaled_i32_source(
    definitions, constants, index, width,
  )
  let consumed = [value, extended, constant]
  consumed.append(scaled)
  Some((selected_index, shift, offset, consumed))
}

///|
fn select_memory_address(
  definitions : Array[@milkir.Inst?],
  constants : Array[UInt64?],
  base : @milkir.Value,
  offset : @milkir.Value,
  width : @native.AccessWidth,
) -> (MemoryAddressSelection, Array[@milkir.Value])? {
  guard constants[offset.id] is Some(static_offset) else { return None }
  if pointer_source(definitions, base) is Some(pointer) {
    let consumed = [offset]
    if pointer != base {
      consumed.push(base)
    }
    return Some(
      (
        { base: pointer, index: None, shift: 0, offset: static_offset, },
        consumed,
      ),
    )
  }
  guard scalar_definition(definitions, base) is Some(add) else { return None }
  guard add.opcode is Scalar(IntBinary(Add)) else { return None }
  guard binary_operands(add) is Some((left, right)) else { return None }
  let parts = match pointer_source(definitions, left) {
    Some(pointer) =>
      select_index_and_offset(definitions, constants, right, width).map(selected => {
        (pointer, left, selected)
      })
    None =>
      match pointer_source(definitions, right) {
        Some(pointer) =>
          select_index_and_offset(definitions, constants, left, width).map(selected => {
            (pointer, right, selected)
          })
        None => None
      }
  }
  guard parts is Some((pointer, pointer_bits, selected)) else { return None }
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

///|
fn memory_access(
  instruction : @milkir.Inst,
) -> (@milkir.Value, @milkir.Value, @native.AccessWidth)? {
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
fn analyze_lowering(function : @milkir.Function) -> LoweringAnalysis {
  let uses = Array::make(function.next_value_id, 0)
  let constants : Array[UInt64?] = Array::make(function.next_value_id, None)
  let definitions : Array[@milkir.Inst?] = Array::make(
    function.next_value_id,
    None,
  )
  for block in function.blocks {
    for instruction in block.instructions {
      for result in instruction.results {
        definitions[result.id] = Some(instruction)
      }
      match (instruction.opcode, instruction.results) {
        (Scalar(IntConst(bits)), [result]) =>
          constants[result.id] = Some(bits.reinterpret_as_uint64())
        _ => ()
      }
      for argument in instruction.args {
        count_use(uses, argument)
      }
    }
    if block.terminator is Some(terminator) {
      for value in terminator_values(terminator) {
        count_use(uses, value)
      }
    }
  }
  let folded_uses = Array::make(function.next_value_id, 0)
  let memory_addresses : Array[MemoryAddressSelection?] = Array::make(
    function.next_inst_id,
    None,
  )
  for block in function.blocks {
    for instruction in block.instructions {
      guard memory_access(instruction) is Some((base, offset, width)) else {
        continue
      }
      guard select_memory_address(definitions, constants, base, offset, width)
        is Some((selection, consumed)) else {
        continue
      }
      memory_addresses[instruction.id] = Some(selection)
      for value in consumed {
        folded_uses[value.id] += 1
      }
    }
  }
  let skip_results = Array::make(function.next_value_id, false)
  for value_id in 0..<function.next_value_id {
    if uses[value_id] > 0 && uses[value_id] == folded_uses[value_id] {
      skip_results[value_id] = true
    }
  }
  { memory_addresses, skip_results, }
}
