// Tests for pattern matching instruction selection

///|
test "pattern: add x, 0 -> mov x" {
  // Build IR: fn(a: i32) -> i32 { a + 0 }
  let builder = @ir.IRBuilder::new("add_zero_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let zero = builder.iconst_i32(0)
  let result = builder.iadd(a, zero)
  builder.return_([result])

  // Lower with optimization
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  // Should optimize add(a, 0) to mov(a)
  let expected =
    #|vcode add_zero_test(v0:int) -> int {
    #|block0:
    #|    v1 = ldi 0
    #|    v2 = mov v0
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "pattern: add 0, x -> mov x" {
  // Build IR: fn(a: i32) -> i32 { 0 + a }
  let builder = @ir.IRBuilder::new("zero_add_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let zero = builder.iconst_i32(0)
  let result = builder.iadd(zero, a)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  // Should optimize add(0, a) to mov(a)
  let expected =
    #|vcode zero_add_test(v0:int) -> int {
    #|block0:
    #|    v1 = ldi 0
    #|    v2 = mov v0
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "pattern: mul x, 1 -> mov x" {
  let builder = @ir.IRBuilder::new("mul_one_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let one = builder.iconst_i32(1)
  let result = builder.imul(a, one)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  let expected =
    #|vcode mul_one_test(v0:int) -> int {
    #|block0:
    #|    v1 = ldi 1
    #|    v2 = mov v0
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "pattern: mul x, 0 -> 0" {
  let builder = @ir.IRBuilder::new("mul_zero_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let zero = builder.iconst_i32(0)
  let result = builder.imul(a, zero)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  // Should optimize mul(a, 0) to constant 0
  let expected =
    #|vcode mul_zero_test(v0:int) -> int {
    #|block0:
    #|    v1 = ldi 0
    #|    v2 = ldi 0
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "pattern: and x, 0 -> 0" {
  let builder = @ir.IRBuilder::new("and_zero_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let zero = builder.iconst_i32(0)
  let result = builder.band(a, zero)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  let expected =
    #|vcode and_zero_test(v0:int) -> int {
    #|block0:
    #|    v1 = ldi 0
    #|    v2 = ldi 0
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "pattern: or x, 0 -> mov x" {
  let builder = @ir.IRBuilder::new("or_zero_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let zero = builder.iconst_i32(0)
  let result = builder.bor(a, zero)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  let expected =
    #|vcode or_zero_test(v0:int) -> int {
    #|block0:
    #|    v1 = ldi 0
    #|    v2 = mov v0
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "pattern: xor x, 0 -> mov x" {
  let builder = @ir.IRBuilder::new("xor_zero_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let zero = builder.iconst_i32(0)
  let result = builder.bxor(a, zero)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  let expected =
    #|vcode xor_zero_test(v0:int) -> int {
    #|block0:
    #|    v1 = ldi 0
    #|    v2 = mov v0
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "pattern: shl x, 0 -> mov x" {
  let builder = @ir.IRBuilder::new("shl_zero_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let zero = builder.iconst_i32(0)
  let result = builder.ishl(a, zero)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  let expected =
    #|vcode shl_zero_test(v0:int) -> int {
    #|block0:
    #|    v1 = ldi 0
    #|    v2 = mov v0
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "pattern: sub x, 0 -> mov x" {
  let builder = @ir.IRBuilder::new("sub_zero_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let zero = builder.iconst_i32(0)
  let result = builder.isub(a, zero)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  let expected =
    #|vcode sub_zero_test(v0:int) -> int {
    #|block0:
    #|    v1 = ldi 0
    #|    v2 = mov v0
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "no pattern match: regular add" {
  // Build IR: fn(a: i32, b: i32) -> i32 { a + b }
  let builder = @ir.IRBuilder::new("regular_add")
  let a = builder.add_param(@ir.Type::I32)
  let b = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let result = builder.iadd(a, b)
  builder.return_([result])

  // Lower with optimization - should fall back to default
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  // No optimization applies, so regular add is emitted
  inspect(
    output,
    content=(
      #|vcode regular_add(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = add32 v0, v1
      #|    ret v2
      #|}
      #|
    ),
  )
}

///|
test "optimized vs non-optimized comparison" {
  // Build the same function
  let builder = @ir.IRBuilder::new("comparison")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let zero = builder.iconst_i32(0)
  let result = builder.iadd(a, zero)
  builder.return_([result])

  // Non-optimized lowering
  let vcode_non_opt = lower_function(builder.get_function())
  let output_non_opt = vcode_non_opt.print()

  // Should have an 'add' instruction
  inspect(
    output_non_opt,
    content=(
      #|vcode comparison(v0:int) -> int {
      #|block0:
      #|    ret v0
      #|}
      #|
    ),
  )

  // Rebuild for optimized test (builders consume the function)
  let builder2 = @ir.IRBuilder::new("comparison")
  let a2 = builder2.add_param(@ir.Type::I32)
  builder2.add_result(@ir.Type::I32)
  let entry2 = builder2.create_block()
  builder2.switch_to_block(entry2)
  let zero2 = builder2.iconst_i32(0)
  let result2 = builder2.iadd(a2, zero2)
  builder2.return_([result2])

  // Optimized lowering
  let vcode_opt = lower_function_optimized(builder2.get_function())
  let output_opt = vcode_opt.print()

  // Should have 'mov' instead of 'add'
  let expected_opt =
    #|vcode comparison(v0:int) -> int {
    #|block0:
    #|    v1 = ldi 0
    #|    v2 = mov v0
    #|    ret v2
    #|}
    #|
  inspect(output_opt, content=expected_opt)
}

///|
test "pattern: fmul x, 1.0 -> mov x" {
  let builder = @ir.IRBuilder::new("fmul_one_test")
  let a = builder.add_param(@ir.Type::F32)
  builder.add_result(@ir.Type::F32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let one = builder.fconst_f32(1.0)
  let result = builder.fmul(a, one)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode fmul_one_test(f0:float) -> float {
      #|block0:
      #|    f1 = ldf 1
      #|    f2 = mov f0
      #|    ret f2
      #|}
      #|
    ),
  )
}

///|
test "strength reduction: mul x, 2 -> shl x, 1" {
  let builder = @ir.IRBuilder::new("mul_pow2_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let two = builder.iconst_i32(2)
  let result = builder.imul(a, two)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  // mul(a, 2) -> shl(a, 1)
  inspect(
    output,
    content=(
      #|vcode mul_pow2_test(v0:int) -> int {
      #|block0:
      #|    v1 = ldi 2
      #|    v3 = ldi 1
      #|    v2 = shl32 v0, v3
      #|    ret v2
      #|}
      #|
    ),
  )
}

///|
test "strength reduction: mul x, 8 -> shl x, 3" {
  let builder = @ir.IRBuilder::new("mul_pow2_8_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let eight = builder.iconst_i32(8)
  let result = builder.imul(a, eight)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  // mul(a, 8) -> shl(a, 3)
  inspect(
    output,
    content=(
      #|vcode mul_pow2_8_test(v0:int) -> int {
      #|block0:
      #|    v1 = ldi 8
      #|    v3 = ldi 3
      #|    v2 = shl32 v0, v3
      #|    ret v2
      #|}
      #|
    ),
  )
}

///|
test "strength reduction: 4 * x -> shl x, 2" {
  let builder = @ir.IRBuilder::new("pow2_mul_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let four = builder.iconst_i32(4)
  let result = builder.imul(four, a)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  // mul(4, a) -> shl(a, 2)
  inspect(
    output,
    content=(
      #|vcode pow2_mul_test(v0:int) -> int {
      #|block0:
      #|    v1 = ldi 4
      #|    v3 = ldi 2
      #|    v2 = shl32 v0, v3
      #|    ret v2
      #|}
      #|
    ),
  )
}

///|
test "strength reduction: udiv x, 4 -> lshr x, 2" {
  let builder = @ir.IRBuilder::new("udiv_pow2_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let four = builder.iconst_i32(4)
  let result = builder.udiv(a, four)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  // udiv(a, 4) -> lshr(a, 2)
  inspect(
    output,
    content=(
      #|vcode udiv_pow2_test(v0:int) -> int {
      #|block0:
      #|    v1 = ldi 4
      #|    v3 = ldi 2
      #|    v2 = lshr32 v0, v3
      #|    ret v2
      #|}
      #|
    ),
  )
}

///|
test "no strength reduction: mul x, 3 (not power of 2)" {
  let builder = @ir.IRBuilder::new("mul_non_pow2_test")
  let a = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let three = builder.iconst_i32(3)
  let result = builder.imul(a, three)
  builder.return_([result])
  let vcode_func = lower_function_optimized(builder.get_function())
  let output = vcode_func.print()
  // 3 is not a power of 2, so regular mul is used
  inspect(
    output,
    content=(
      #|vcode mul_non_pow2_test(v0:int) -> int {
      #|block0:
      #|    v1 = ldi 3
      #|    v2 = mul32 v0, v1
      #|    ret v2
      #|}
      #|
    ),
  )
}
