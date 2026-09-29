///|
priv struct LoweringTrace {
  operations : Array[@lowering.Operation]
  operands : Array[Array[Int]]
  operation_blocks : Array[Int]
  terminators : Array[@lowering.TargetTerminator]
}

///|
fn trace_lowering(
  function : @milkir.Function,
  folds_unsigned_index_into_memory? : Bool = false,
  compare_immediates? : Bool = false,
) -> LoweringTrace raise {
  let operands : Array[Array[Int]] = []
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
    fn(block, operation, arguments, result_types, _, _, _) {
      operands.push(arguments)
      operation_blocks.push(block)
      operations.push(operation)
      fresh_values(result_types.length())
    },
    fn(_, terminator, _) { terminators.push(terminator) },
    fn() { () },
    folds_unsigned_index_into_memory~,
    supports_int_compare_immediate=fn(_, bits) {
      compare_immediates && bits == 42UL
    },
  )
  lower_core_to_sink(function, sink, verify_input=false)
  { operations, operands, operation_blocks, terminators, }
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
test "native demand selection shares zero-extended memory indices" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("shared_uxtw_index")
  let base = builder.add_param(Ptr)
  let index = builder.add_param(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  let base_bits = builder.bitcast(I64, base)
  let extended = builder.uextend(I64, index)
  let first_address = builder.iadd(base_bits, extended)
  let second_address = builder.iadd(base_bits, extended)
  let zero = builder.iconst_i64(0L)
  let first = builder.load_ptr(I32, first_address, zero)
  let second = builder.load_ptr(I32, second_address, zero)
  builder.return_([first, second])
  let trace = trace_lowering(
    builder.finalize(),
    folds_unsigned_index_into_memory=true,
  )
  inspect(
    trace.operations
    .filter(operation => operation is LoadIndexed(_, 0))
    .length(),
    content="2",
  )
  inspect(
    trace.operations.any(operation => {
      operation is (PointerOffset | Convert(I64ExtendI32(Unsigned)))
    }),
    content="false",
  )
}

///|
test "native demand selection preserves shared indices for other targets" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("shared_x64_index")
  let base = builder.add_param(Ptr)
  let index = builder.add_param(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  let base_bits = builder.bitcast(I64, base)
  let extended = builder.uextend(I64, index)
  let first_address = builder.iadd(base_bits, extended)
  let second_address = builder.iadd(base_bits, extended)
  let zero = builder.iconst_i64(0L)
  let first = builder.load_ptr(I32, first_address, zero)
  let second = builder.load_ptr(I32, second_address, zero)
  builder.return_([first, second])
  let trace = trace_lowering(builder.finalize())
  inspect(
    trace.operations
    .filter(operation => operation is Convert(I64ExtendI32(Unsigned)))
    .length(),
    content="1",
  )
  inspect(
    trace.operations.filter(operation => operation is IntBinary(Add)).length(),
    content="2",
  )
  inspect(
    trace.operations.any(operation => operation is LoadIndexed(_, _)),
    content="false",
  )
}

///|
test "native demand selection retains shared zero extension for arithmetic" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("mixed_uxtw_index")
  let base = builder.add_param(Ptr)
  let index = builder.add_param(I32)
  builder.add_result(I32)
  builder.add_result(I64)
  let base_bits = builder.bitcast(I64, base)
  let extended = builder.uextend(I64, index)
  let address = builder.iadd(base_bits, extended)
  let zero = builder.iconst_i64(0L)
  let one = builder.iconst_i64(1L)
  let loaded = builder.load_ptr(I32, address, zero)
  let arithmetic = builder.iadd(extended, one)
  builder.return_([loaded, arithmetic])
  let trace = trace_lowering(
    builder.finalize(),
    folds_unsigned_index_into_memory=true,
  )
  inspect(
    trace.operations
    .filter(operation => operation is LoadIndexed(_, 0))
    .length(),
    content="1",
  )
  inspect(
    trace.operations
    .filter(operation => operation is Convert(I64ExtendI32(Unsigned)))
    .length(),
    content="1",
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

///|
test "native vector and-not selection preserves operand order in both canonical forms" {
  for commuted in [false, true] {
    let builder = @milkir.FunctionBuilder::FunctionBuilder("andnot")
    let a = builder.add_param(V128)
    let b = builder.add_param(V128)
    builder.add_result(V128)
    let negated = builder.v128_not(b)
    let result = if commuted {
      builder.v128_and(negated, a)
    } else {
      builder.v128_and(a, negated)
    }
    builder.return_([result])
    let function = builder.finalize()
    function.verify()
    let trace = trace_lowering(function)
    debug_inspect(trace.operations, content="[Vector(Bitwise(AndNot))]")
    debug_inspect(trace.operands, content="[[0, 1]]")
  }
}

///|
test "native vector and-not selection absorbs shared negations only when fully consumed" {
  for returned in [false, true] {
    let builder = @milkir.FunctionBuilder::FunctionBuilder("shared_not")
    let a = builder.add_param(V128)
    let b = builder.add_param(V128)
    let c = builder.add_param(V128)
    builder.add_result(V128)
    builder.add_result(V128)
    let negated = builder.v128_not(b)
    let first = builder.v128_and(a, negated)
    let second = builder.v128_and(negated, c)
    let results = [first, second]
    if returned {
      builder.add_result(V128)
      results.push(negated)
    }
    builder.return_(results)
    let trace = trace_lowering(builder.finalize())
    inspect(
      trace.operations.filter(op => op is Vector(Bitwise(AndNot))).length(),
      content=if returned { "0" } else { "2" },
    )
    inspect(
      trace.operations.filter(op => op is Vector(Bitwise(Not))).length(),
      content=if returned { "1" } else { "0" },
    )
    let selected = []
    for i, op in trace.operations {
      if op is Vector(Bitwise(AndNot)) {
        selected.push(trace.operands[i])
      }
    }
    if returned {
      debug_inspect(
        trace.operations,
        content="[Vector(Bitwise(Not)), Vector(Bitwise(And)), Vector(Bitwise(And))]",
      )
      debug_inspect(trace.operands, content="[[1], [0, 3], [3, 2]]")
    } else {
      debug_inspect(selected, content="[[0, 1], [2, 1]]")
    }
  }
}

///|
test "native vector and-not selection retains the other negation and identical operands" {
  for identical in [false, true] {
    let builder = @milkir.FunctionBuilder::FunctionBuilder("two_nots")
    let a = builder.add_param(V128)
    let b = builder.add_param(V128)
    builder.add_result(V128)
    let left = builder.v128_not(a)
    let right = if identical { left } else { builder.v128_not(b) }
    builder.return_([builder.v128_and(left, right)])
    let trace = trace_lowering(builder.finalize())
    inspect(
      trace.operations.filter(op => op is Vector(Bitwise(Not))).length(),
      content="1",
    )
    if identical {
      debug_inspect(
        trace.operations,
        content="[Vector(Bitwise(Not)), Vector(Bitwise(And))]",
      )
      debug_inspect(trace.operands, content="[[0], [2, 2]]")
    } else {
      debug_inspect(
        trace.operations,
        content="[Vector(Bitwise(Not)), Vector(Bitwise(AndNot))]",
      )
      debug_inspect(trace.operands, content="[[0], [2, 1]]")
    }
  }
}

///|
test "native comparison selection respects target eligibility and shared constants" {
  for enabled in [false, true] {
    for returned in [false, true] {
      let builder = @milkir.FunctionBuilder::FunctionBuilder(
        "compare_constants",
      )
      let input = builder.add_param(I32)
      builder.add_result(I32)
      builder.add_result(I32)
      let constant = builder.iconst_i32(42)
      let left = builder.icmp_slt(input, constant)
      let right = builder.icmp_slt(constant, input)
      if returned {
        builder.add_result(I32)
        builder.return_([left, right, constant])
      } else {
        builder.return_([left, right])
      }
      let trace = trace_lowering(builder.finalize(), compare_immediates=enabled)
      inspect(
        trace.operations.any(op => {
          op is IntCompareImmediate(SignedLessThan, 42UL)
        }) ==
        enabled,
        content="true",
      )
      inspect(
        trace.operations.any(op => {
          op is IntCompareImmediate(SignedGreaterThan, 42UL)
        }) ==
        enabled,
        content="true",
      )
      inspect(
        trace.operations.any(op => op is I32Const(42U)) ==
        (!enabled || returned),
        content="true",
      )
    }
  }
  let builder = @milkir.FunctionBuilder::FunctionBuilder("ineligible_constant")
  let input = builder.add_param(I32)
  builder.add_result(I32)
  let constant = builder.iconst_i32(43)
  builder.return_([builder.icmp_slt(input, constant)])
  let trace = trace_lowering(builder.finalize(), compare_immediates=true)
  inspect(trace.operations.any(op => op is I32Const(43U)), content="true")
  inspect(trace.operations.any(op => op is IntCompare(_)), content="true")
}

///|
test "branch comparison sharing preserves constant-left fallback" {
  for enabled in [false, true] {
    let builder = @milkir.FunctionBuilder::FunctionBuilder(
      "branch_constant_left",
    )
    let input = builder.add_param(I64)
    builder.add_result(I64)
    let constant = builder.iconst_i64(4097L)
    let condition = builder.icmp_slt(constant, input)
    let yes = builder.create_block()
    let no = builder.create_block()
    builder.brnz(condition, yes, no)
    builder.switch_to_block(yes)
    builder.return_([constant])
    builder.switch_to_block(no)
    builder.return_([input])
    let trace = trace_lowering(builder.finalize(), compare_immediates=enabled)
    inspect(
      trace.terminators.any(t => {
        t is BranchIntCompareImmediate(SignedGreaterThan, _, 4097UL, _, _, _, _)
      }),
      content="true",
    )
    inspect(
      trace.operations.filter(op => op is I64Const(4097UL)).length(),
      content="1",
    )
    inspect(
      trace.operations.any(op => {
        op is (IntCompare(_) | IntCompareImmediate(_, _))
      }),
      content="false",
    )
  }
}
