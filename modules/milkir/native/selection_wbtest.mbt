///|
priv struct LoweringTrace {
  operations : Array[@lowering.Operation]
  operation_blocks : Array[Int]
  terminators : Array[@lowering.TargetTerminator]
}

///|
fn trace_lowering(function : @milkir.Function) -> LoweringTrace raise {
  let operations : Array[@lowering.Operation] = []
  let operation_blocks : Array[Int] = []
  let terminators : Array[@lowering.TargetTerminator] = []
  let next_value = Ref(0)
  let next_block = Ref(1)
  let fresh_values = fn(count : Int) -> Array[Int] {
    Array::makei(count, _ => {
      let value = next_value.val
      next_value.val += 1
      value
    })
  }
  let sink = @lowering.TargetSink::new(
    fn() { fresh_values(function.params.length()) },
    fn() { 0 },
    fn(types) {
      let block = next_block.val
      next_block.val += 1
      (block, fresh_values(types.length()))
    },
    fn(_, _) { 0 },
    fn(_) { () },
    fn(block, operation, _, result_types, _, _, _) {
      operation_blocks.push(block)
      operations.push(operation)
      fresh_values(result_types.length())
    },
    fn(_, terminator, _) { terminators.push(terminator) },
    fn() { () },
  )
  lower_core_to_sink(function, sink, verify_input=false)
  { operations, operation_blocks, terminators, }
}

///|
test "native demand selection fuses multiply-add and shifted-add" {
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
  let trace = trace_lowering(builder.finalize())
  inspect(
    trace.operations.any(operation => operation is IntMultiplyAdd),
    content="true",
  )
  inspect(
    trace.operations.any(operation => operation is IntAddShiftedLeft(3)),
    content="true",
  )
  inspect(
    trace.operations.any(operation => {
      operation is (IntBinary(Mul) | IntBinary(ShiftLeft) | I32Const(_))
    }),
    content="false",
  )
}

///|
test "native demand selection leaves high multiply constants materialized" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("high_multiply")
  let input = builder.add_param(I64)
  builder.add_result(I64)
  let constant = builder.iconst_i64(17L)
  let result = builder.umulh(input, constant)
  builder.return_([result])
  let trace = trace_lowering(builder.finalize())
  inspect(
    trace.operations.any(operation => operation is I64Const(17UL)),
    content="true",
  )
  inspect(
    trace.operations.any(operation => operation is IntHighMultiply(Unsigned)),
    content="true",
  )
}

///|
test "native demand selection removes constants selected by every use" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("shared_immediate")
  let left = builder.add_param(I32)
  let right = builder.add_param(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  let constant = builder.iconst_i32(17)
  let first = builder.iadd(left, constant)
  let second = builder.iadd(right, constant)
  builder.return_([first, second])
  let trace = trace_lowering(builder.finalize())
  inspect(
    trace.operations
    .filter(operation => operation is IntBinaryImmediate(Add, 17UL))
    .length(),
    content="2",
  )
  inspect(
    trace.operations.any(operation => operation is I32Const(17U)),
    content="false",
  )
}

///|
test "native demand selection fuses compare into branch terminators" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("compare_branch")
  let input = builder.add_param(I32)
  let when_true = builder.create_block()
  let when_false = builder.create_block()
  let constant = builder.iconst_i32(17)
  let condition = builder.icmp_slt(input, constant)
  builder.brnz(condition, when_true, when_false)
  builder.switch_to_block(when_true)
  builder.return_([])
  builder.switch_to_block(when_false)
  builder.return_([])
  let trace = trace_lowering(builder.finalize())
  inspect(
    trace.terminators.any(terminator => {
      terminator
      is BranchIntCompareImmediate(SignedLessThan, _, 17UL, _, _, _, _)
    }),
    content="true",
  )
  inspect(
    trace.operations.any(operation => {
      operation is (I32Const(17U) | IntCompare(_))
    }),
    content="false",
  )
}

///|
test "native demand selection leaves reference comparisons semantic" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("reference_branch")
  let left = builder.add_param(Ref)
  let right = builder.add_param(Ref)
  let when_true = builder.create_block()
  let when_false = builder.create_block()
  let condition = builder.icmp_eq(left, right)
  builder.brnz(condition, when_true, when_false)
  builder.switch_to_block(when_true)
  builder.return_([])
  builder.switch_to_block(when_false)
  builder.return_([])
  let trace = trace_lowering(builder.finalize())
  inspect(
    trace.operations.any(operation => operation is ReferenceCompare(Equal)),
    content="true",
  )
  inspect(
    trace.terminators.any(terminator => terminator is Branch(_, _, _, _, _)),
    content="true",
  )
}

///|
test "native demand selection folds canonical addresses at the load" {
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
  let trace = trace_lowering(builder.finalize())
  inspect(
    trace.operations.any(operation => operation is LoadIndexed(_, 0)),
    content="true",
  )
  inspect(
    trace.operations.any(operation => {
      operation is (PointerOffset | IntBinary(Add) | I64Const(0UL))
    }),
    content="false",
  )
}

///|
test "native demand selection shares zero-cost pointer bitcasts" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("shared_base_bits")
  let base = builder.add_param(Ptr)
  let first_index = builder.add_param(I32)
  let second_index = builder.add_param(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  let base_bits = builder.bitcast(I64, base)
  let first_address = builder.iadd(base_bits, builder.uextend(I64, first_index))
  let second_address = builder.iadd(
    base_bits,
    builder.uextend(I64, second_index),
  )
  let zero = builder.iconst_i64(0L)
  let first = builder.load_ptr(I32, first_address, zero)
  let second = builder.load_ptr(I32, second_address, zero)
  builder.return_([first, second])
  let trace = trace_lowering(builder.finalize())
  inspect(
    trace.operations
    .filter(operation => operation is LoadIndexed(_, 0))
    .length(),
    content="2",
  )
  inspect(
    trace.operations.any(operation => {
      operation is (PointerOffset | Convert(Bitcast(Ptr64, I64)))
    }),
    content="false",
  )
}

///|
test "native demand selection preserves shared address definitions" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("shared_address")
  let base = builder.add_param(Ptr)
  let index = builder.add_param(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  let base_bits = builder.bitcast(I64, base)
  let extended = builder.uextend(I64, index)
  let address = builder.iadd(base_bits, extended)
  let zero = builder.iconst_i64(0L)
  let first = builder.load_ptr(I32, address, zero)
  let second = builder.load_ptr(I32, address, zero)
  builder.return_([first, second])
  let trace = trace_lowering(builder.finalize())
  inspect(
    trace.operations.filter(operation => operation is PointerOffset).length(),
    content="0",
  )
  inspect(
    trace.operations.any(operation => operation is IntBinary(Add)),
    content="true",
  )
}

///|
test "native demand selection keeps shared addresses in their dominator" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "shared_address_across_branches",
  )
  let base = builder.add_param(Ptr)
  let index = builder.add_param(I32)
  let condition = builder.add_param(I32)
  let when_true = builder.create_block()
  let when_false = builder.create_block()
  let base_bits = builder.bitcast(I64, base)
  let extended = builder.uextend(I64, index)
  let address = builder.iadd(base_bits, extended)
  let zero = builder.iconst_i64(0L)
  builder.brnz(condition, when_true, when_false)
  builder.switch_to_block(when_true)
  ignore(builder.load_ptr(I32, address, zero))
  builder.return_([])
  builder.switch_to_block(when_false)
  ignore(builder.load_ptr(I32, address, zero))
  builder.return_([])
  let trace = trace_lowering(builder.finalize())
  inspect(
    Array::makei(trace.operations.length(), index => index).any(index => {
      trace.operation_blocks[index] == 0 &&
      trace.operations[index] is IntBinary(Add)
    }),
    content="true",
  )
  inspect(
    Array::makei(trace.operations.length(), index => index).all(index => {
      if trace.operations[index] is (Load(_) | LoadIndexed(_, _)) {
        trace.operation_blocks[index] is (1 | 2)
      } else {
        true
      }
    }),
    content="true",
  )
  inspect(
    trace.operations
    .filter(operation => operation is (Load(_) | LoadIndexed(_, _)))
    .length(),
    content="2",
  )
}
