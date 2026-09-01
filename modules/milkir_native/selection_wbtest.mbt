///|
test "native selection fuses multiply-add and shifted-add without a second IR" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("composite_arithmetic")
  let accumulator = builder.add_param(I32)
  let left = builder.add_param(I32)
  let right = builder.add_param(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  let product = builder.imul(left, right)
  let multiply_add = builder.iadd(accumulator, product)
  let amount = builder.iconst_i32(3)
  let shifted = builder.ishl(left, amount)
  let shifted_add = builder.iadd(accumulator, shifted)
  builder.return_([multiply_add, shifted_add])
  let function = builder.finalize()
  let instructions = function.blocks[0].instructions
  let analysis = analyze_lowering(function)
  inspect(
    analysis.scalar_instructions[instructions[1].id]
    is Some(MultiplyAdd(selected_accumulator, selected_left, selected_right)) &&
    selected_accumulator == accumulator &&
    selected_left == left &&
    selected_right == right,
    content="true",
  )
  inspect(
    analysis.scalar_instructions[instructions[4].id]
    is Some(
      AddShiftedLeft(selected_accumulator, selected_input, selected_amount)
    ) &&
    selected_accumulator == accumulator &&
    selected_input == left &&
    selected_amount == 3,
    content="true",
  )
  inspect(analysis.skip_results[product.id], content="true")
  inspect(analysis.skip_results[shifted.id], content="true")
  inspect(analysis.skip_results[amount.id], content="true")
}

///|
test "native selection leaves high multiply constants materialized" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("high_multiply")
  let input = builder.add_param(I64)
  builder.add_result(I64)
  let constant = builder.iconst_i64(17L)
  let result = builder.umulh(input, constant)
  builder.return_([result])
  let function = builder.finalize()
  let multiply = function.blocks[0].instructions[1]
  let analysis = analyze_lowering(function)
  inspect(analysis.scalar_instructions[multiply.id] is None, content="true")
  inspect(analysis.skip_results[constant.id], content="false")
}

///|
test "native selection fuses compare into brz and brnz terminators" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("compare_branch")
  let input = builder.add_param(I32)
  let when_true = builder.create_block()
  let when_false = builder.create_block()
  let constant = builder.iconst_i32(17)
  let condition = builder.icmp_slt(input, constant)
  let entry = builder.current_block()
  builder.brnz(condition, when_true, when_false)
  builder.switch_to_block(when_true)
  builder.return_([])
  builder.switch_to_block(when_false)
  builder.return_([])
  let function = builder.finalize()
  let analysis = analyze_lowering(function)
  inspect(
    analysis.branches[entry.id]
    is Some(CompareImmediate(selected_input, selected_bits, SignedLessThan)) &&
    selected_input == input &&
    selected_bits == 17UL,
    content="true",
  )
  inspect(analysis.skip_results[constant.id], content="true")
  inspect(analysis.skip_results[condition.id], content="true")
}

///|
test "native selection folds canonical MilkIR addresses into indexed memory" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("indexed_memory")
  let base = builder.add_param(Ptr)
  let index = builder.add_param(I32)
  builder.add_result(I32)
  let base_bits = builder.bitcast(I64, base)
  let extended = builder.uextend(I64, index)
  let address = builder.iadd(base_bits, extended)
  let zero = builder.iconst_i64(0L)
  let loaded = builder.load_ptr(I32, address, zero)
  builder.return_([loaded])
  let function = builder.finalize()
  let load = function.blocks[0].instructions[4]
  let analysis = analyze_lowering(function)
  inspect(
    analysis.memory_addresses[load.id]
    is Some(
      {
        base: selected_base,
        index: Some(selected_index),
        shift: 0,
        offset: 0UL,
      }
    ) &&
    selected_base == base &&
    selected_index == index,
    content="true",
  )
  inspect(analysis.skip_results[base_bits.id], content="true")
  inspect(analysis.skip_results[extended.id], content="true")
  inspect(analysis.skip_results[address.id], content="true")
  inspect(analysis.skip_results[zero.id], content="true")
}
