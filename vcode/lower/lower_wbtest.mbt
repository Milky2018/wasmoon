// Tests for IR to VCode lowering

///|
test "lower simple add function" {
  // Build IR function: fn add(a: i32, b: i32) -> i32 { a + b }
  let builder = @ir.IRBuilder::new("add")
  let a = builder.add_param(@ir.Type::I32)
  let b = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let result = builder.iadd(a, b)
  builder.return_([result])

  // Lower to VCode
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode add(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = add32 v0, v1
      #|    ret v2
      #|}
      #|
    ),
  )
}

///|
test "lower integer arithmetic" {
  let builder = @ir.IRBuilder::new("arith")
  let a = builder.add_param(@ir.Type::I64)
  let b = builder.add_param(@ir.Type::I64)
  builder.add_result(@ir.Type::I64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sum = builder.iadd(a, b)
  let diff = builder.isub(sum, a)
  let prod = builder.imul(diff, b)
  builder.return_([prod])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  // After e-graph optimization: sub(add(v0, v1), v0) = v1, so mul(v3, v1) = mul(v1, v1)
  let expected =
    #|vcode arith(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = add v0, v1
    #|    v3 = sub v2, v0
    #|    v4 = mul v1, v1
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "lower constants" {
  let builder = @ir.IRBuilder::new("const_test")
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let c1 = builder.iconst_i32(10)
  let c2 = builder.iconst_i32(20)
  let sum = builder.iadd(c1, c2)
  builder.return_([sum])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  // After e-graph optimization: add(10, 20) = 30 (constant folding)
  inspect(
    output,
    content=(
      #|vcode const_test() -> int {
      #|block0:
      #|    v2 = ldi 30
      #|    ret v2
      #|}
      #|
    ),
  )
}

///|
test "lower float operations" {
  let builder = @ir.IRBuilder::new("float_add")
  let a = builder.add_param(@ir.Type::F32)
  let b = builder.add_param(@ir.Type::F32)
  builder.add_result(@ir.Type::F32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sum = builder.fadd(a, b)
  let prod = builder.fmul(sum, a)
  builder.return_([prod])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode float_add(f0:float, f1:float) -> float {
      #|block0:
      #|    f2 = fadd.s f0, f1
      #|    f3 = fmul.s f2, f0
      #|    ret f3
      #|}
      #|
    ),
  )
}

///|
test "lower comparison" {
  let builder = @ir.IRBuilder::new("cmp_test")
  let a = builder.add_param(@ir.Type::I32)
  let b = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let cmp_result = builder.icmp_sgt(a, b)
  builder.return_([cmp_result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode cmp_test(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = cmp32.sgt v0, v1
      #|    ret v2
      #|}
      #|
    ),
  )
}

///|
test "lower conditional branch" {
  let builder = @ir.IRBuilder::new("max")
  let a = builder.add_param(@ir.Type::I32)
  let b = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  let then_block = builder.create_block()
  let else_block = builder.create_block()

  // Entry: compare and branch
  builder.switch_to_block(entry)
  let cmp_result = builder.icmp_sgt(a, b)
  builder.brnz(cmp_result, then_block, else_block)

  // Then: return a
  builder.switch_to_block(then_block)
  builder.return_([a])

  // Else: return b
  builder.switch_to_block(else_block)
  builder.return_([b])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode max(v0:int, v1:int) -> int {
      #|block0:
      #|    br_cmp.gt v0, v1, block1, block2
      #|block1:
      #|    ret v0
      #|block2:
      #|    ret v1
      #|}
      #|
    ),
  )
}

///|
test "lower memory operations" {
  // Note: Uses load_ptr/store_ptr directly (raw pointer ops without bounds checking)
  // Bounds checking is now done at IR translation time via FuncEnvironment
  let builder = @ir.IRBuilder::new("load_store")
  let addr = builder.add_param(@ir.Type::I64) // ptr is i64
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let offset0 = builder.iconst_i64(0)
  let loaded = builder.load_ptr(@ir.Type::I32, addr, offset0)
  let one = builder.iconst_i32(1)
  let sum = builder.iadd(loaded, one)
  let offset4 = builder.iconst_i64(4)
  builder.store_ptr(@ir.Type::I32, addr, sum, offset4)
  builder.return_([sum])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode load_store(v0:int) -> int {
      #|block0:
      #|    v2 = load_ptr.i32 +0 v0
      #|    v4 = add32 #1 v2
      #|    store_ptr.i32 +4 v0, v4
      #|    ret v4
      #|}
      #|
    ),
  )
}

///|
test "lower bitwise operations" {
  let builder = @ir.IRBuilder::new("bitwise")
  let a = builder.add_param(@ir.Type::I32)
  let b = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let and_res = builder.band(a, b)
  let or_res = builder.bor(a, b)
  let xor_res = builder.bxor(and_res, or_res)
  builder.return_([xor_res])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  let expected =
    #|vcode bitwise(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = and v0, v1
    #|    v3 = or v0, v1
    #|    v4 = xor v2, v3
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "lower shift operations" {
  let builder = @ir.IRBuilder::new("shifts")
  let a = builder.add_param(@ir.Type::I32)
  let b = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let shl_res = builder.ishl(a, b)
  let sshr_res = builder.sshr(shl_res, b)
  let ushr_res = builder.ushr(sshr_res, b)
  builder.return_([ushr_res])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode shifts(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = shl32 v0, v1
      #|    v3 = ashr32 v2, v1
      #|    v4 = lshr32 v3, v1
      #|    ret v4
      #|}
      #|
    ),
  )
}

///|
test "lower division operations" {
  let builder = @ir.IRBuilder::new("division")
  let a = builder.add_param(@ir.Type::I32)
  let b = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sdiv_res = builder.sdiv(a, b)
  let udiv_res = builder.udiv(a, b)
  let sum = builder.iadd(sdiv_res, udiv_res)
  builder.return_([sum])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode division(v0:int, v1:int) -> int {
      #|block0:
      #|    trap_if_zero32 #4 v1
      #|    trap_if_div_overflow32 #5 v0, v1
      #|    v2 = sdiv32 v0, v1
      #|    trap_if_zero32 #4 v1
      #|    v3 = udiv32 v0, v1
      #|    v4 = add32 v2, v3
      #|    ret v4
      #|}
      #|
    ),
  )
}

///|
test "lower float comparison" {
  let builder = @ir.IRBuilder::new("fcmp_test")
  let a = builder.add_param(@ir.Type::F32)
  let b = builder.add_param(@ir.Type::F32)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let cmp_result = builder.fcmp(@ir.FloatCC::Lt, a, b)
  builder.return_([cmp_result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  let expected =
    #|vcode fcmp_test(f0:float, f1:float) -> int {
    #|block0:
    #|    v2 = fcmp.lt f0, f1
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "lower f64 operations" {
  let builder = @ir.IRBuilder::new("f64_add")
  let a = builder.add_param(@ir.Type::F64)
  let b = builder.add_param(@ir.Type::F64)
  builder.add_result(@ir.Type::F64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sum = builder.fadd(a, b)
  let prod = builder.fmul(sum, a)
  builder.return_([prod])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode f64_add(f0:double, f1:double) -> double {
      #|block0:
      #|    f2 = fadd.d f0, f1
      #|    f3 = fmul.d f2, f0
      #|    ret f3
      #|}
      #|
    ),
  )
}

///|
test "lower f64 comparison" {
  let builder = @ir.IRBuilder::new("f64_cmp_test")
  let a = builder.add_param(@ir.Type::F64)
  let b = builder.add_param(@ir.Type::F64)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let cmp_result = builder.fcmp(@ir.FloatCC::Gt, a, b)
  builder.return_([cmp_result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  let expected =
    #|vcode f64_cmp_test(f0:double, f1:double) -> int {
    #|block0:
    #|    v2 = fcmp.gt f0, f1
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "lower f64 division and subtraction" {
  let builder = @ir.IRBuilder::new("f64_ops")
  let a = builder.add_param(@ir.Type::F64)
  let b = builder.add_param(@ir.Type::F64)
  builder.add_result(@ir.Type::F64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let div = builder.fdiv(a, b)
  let result = builder.fsub(div, b)
  builder.return_([result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode f64_ops(f0:double, f1:double) -> double {
      #|block0:
      #|    f2 = fdiv.d f0, f1
      #|    f3 = fsub.d f2, f1
      #|    ret f3
      #|}
      #|
    ),
  )
}

///|
test "lower mixed int and f64" {
  // fn mixed(a: i64, b: f64) -> f64
  // Converts int to float and adds
  let builder = @ir.IRBuilder::new("mixed_int_f64")
  let a = builder.add_param(@ir.Type::I64)
  let b = builder.add_param(@ir.Type::F64)
  builder.add_result(@ir.Type::F64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  // Just return b doubled (can't convert int to float in current IR)
  let result = builder.fadd(b, b)
  builder.return_([result])
  ignore(a)
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode mixed_int_f64(v0:int, f1:double) -> double {
      #|block0:
      #|    f2 = fadd.d f1, f1
      #|    ret f2
      #|}
      #|
    ),
  )
}

///|
test "lower unconditional jump" {
  let builder = @ir.IRBuilder::new("jump_test")
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  let target = builder.create_block()
  builder.switch_to_block(entry)
  let c = builder.iconst_i32(42)
  builder.jump(target, [])
  builder.switch_to_block(target)
  builder.return_([c])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode jump_test() -> int {
      #|block0:
      #|    v0 = ldi 42
      #|    jump block1
      #|block1:
      #|    ret v0
      #|}
      #|
    ),
  )
}

///|
test "lower trap" {
  let builder = @ir.IRBuilder::new("trap_test")
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  builder.trap("unreachable")
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  let expected =
    #|vcode trap_test() -> int {
    #|block0:
    #|    trap "unreachable"
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "lower double constant" {
  let builder = @ir.IRBuilder::new("fconst_test")
  builder.add_result(@ir.Type::F64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let c = builder.fconst_f64(3.14)
  builder.return_([c])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode fconst_test() -> double {
      #|block0:
      #|    f0 = ldf 3.14
      #|    ret f0
      #|}
      #|
    ),
  )
}

// ============ AArch64-Specific Instruction Selection Tests ============
// Note: Current implementation emits both the constituent instruction (mul/shl)
// and the fused instruction (madd/add_shifted). A future optimization pass
// could eliminate the dead constituent instructions via dead code elimination.

///|
test "lower add(x, mul(y, z)) to madd" {
  // Pattern: add(x, mul(y, z)) -> MADD: x + y * z
  let builder = @ir.IRBuilder::new("madd_test")
  let x = builder.add_param(@ir.Type::I64)
  let y = builder.add_param(@ir.Type::I64)
  let z = builder.add_param(@ir.Type::I64)
  builder.add_result(@ir.Type::I64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let mul_yz = builder.imul(y, z)
  let result = builder.iadd(x, mul_yz)
  builder.return_([result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  // Emits both mul and madd (madd consumes mul pattern, mul becomes dead code)
  inspect(
    output,
    content=(
      #|vcode madd_test(v0:int, v1:int, v2:int) -> int {
      #|block0:
      #|    v3 = mul v1, v2
      #|    v4 = madd v0, v1, v2
      #|    ret v4
      #|}
      #|
    ),
  )
}

///|
test "lower sub(x, mul(y, z)) to msub" {
  // Pattern: sub(x, mul(y, z)) -> MSUB: x - y * z
  let builder = @ir.IRBuilder::new("msub_test")
  let x = builder.add_param(@ir.Type::I64)
  let y = builder.add_param(@ir.Type::I64)
  let z = builder.add_param(@ir.Type::I64)
  builder.add_result(@ir.Type::I64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let mul_yz = builder.imul(y, z)
  let result = builder.isub(x, mul_yz)
  builder.return_([result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  // Emits both mul and msub (msub consumes mul pattern)
  inspect(
    output,
    content=(
      #|vcode msub_test(v0:int, v1:int, v2:int) -> int {
      #|block0:
      #|    v3 = mul v1, v2
      #|    v4 = msub v0, v1, v2
      #|    ret v4
      #|}
      #|
    ),
  )
}

///|
test "lower sub(0, mul(x, y)) to mneg" {
  // Pattern: sub(0, mul(x, y)) -> MNEG: -(x * y)
  let builder = @ir.IRBuilder::new("mneg_test")
  let x = builder.add_param(@ir.Type::I64)
  let y = builder.add_param(@ir.Type::I64)
  builder.add_result(@ir.Type::I64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let zero = builder.iconst_i64(0L)
  let mul_xy = builder.imul(x, y)
  let result = builder.isub(zero, mul_xy)
  builder.return_([result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  // Emits both mul and mneg
  inspect(
    output,
    content=(
      #|vcode mneg_test(v0:int, v1:int) -> int {
      #|block0:
      #|    v3 = mul v0, v1
      #|    v4 = mneg v0, v1
      #|    ret v4
      #|}
      #|
    ),
  )
}

///|
test "lower add(x, shl(y, n)) to add_shifted" {
  // Pattern: add(x, shl(y, n)) -> AddShifted: x + (y << n)
  let builder = @ir.IRBuilder::new("add_shifted_test")
  let x = builder.add_param(@ir.Type::I64)
  let y = builder.add_param(@ir.Type::I64)
  builder.add_result(@ir.Type::I64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let shift_amt = builder.iconst_i64(3L)
  let shl_y = builder.ishl(y, shift_amt)
  let result = builder.iadd(x, shl_y)
  builder.return_([result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  // Emits shl and add_shifted (shl becomes dead code)
  inspect(
    output,
    content=(
      #|vcode add_shifted_test(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = ldi 3
      #|    v3 = shl v1, v2
      #|    v4 = add.lsl #3 v0, v1
      #|    ret v4
      #|}
      #|
    ),
  )
}

///|
test "lower sub(x, shl(y, n)) to sub_shifted" {
  // Pattern: sub(x, shl(y, n)) -> SubShifted: x - (y << n)
  let builder = @ir.IRBuilder::new("sub_shifted_test")
  let x = builder.add_param(@ir.Type::I64)
  let y = builder.add_param(@ir.Type::I64)
  builder.add_result(@ir.Type::I64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let shift_amt = builder.iconst_i64(2L)
  let shl_y = builder.ishl(y, shift_amt)
  let result = builder.isub(x, shl_y)
  builder.return_([result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  // Emits shl and sub_shifted
  inspect(
    output,
    content=(
      #|vcode sub_shifted_test(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = ldi 2
      #|    v3 = shl v1, v2
      #|    v4 = sub.lsl #2 v0, v1
      #|    ret v4
      #|}
      #|
    ),
  )
}

///|
test "lower and(x, shl(y, n)) to and_shifted" {
  // Pattern: and(x, shl(y, n)) -> AndShifted: x & (y << n)
  let builder = @ir.IRBuilder::new("and_shifted_test")
  let x = builder.add_param(@ir.Type::I64)
  let y = builder.add_param(@ir.Type::I64)
  builder.add_result(@ir.Type::I64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let shift_amt = builder.iconst_i64(4L)
  let shl_y = builder.ishl(y, shift_amt)
  let result = builder.band(x, shl_y)
  builder.return_([result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  // Emits shl and and_shifted
  inspect(
    output,
    content=(
      #|vcode and_shifted_test(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = ldi 4
      #|    v3 = shl v1, v2
      #|    v4 = and.lsl #4 v0, v1
      #|    ret v4
      #|}
      #|
    ),
  )
}

///|
test "lower or(x, shl(y, n)) to or_shifted" {
  // Pattern: or(x, shl(y, n)) -> OrShifted: x | (y << n)
  let builder = @ir.IRBuilder::new("or_shifted_test")
  let x = builder.add_param(@ir.Type::I64)
  let y = builder.add_param(@ir.Type::I64)
  builder.add_result(@ir.Type::I64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let shift_amt = builder.iconst_i64(5L)
  let shl_y = builder.ishl(y, shift_amt)
  let result = builder.bor(x, shl_y)
  builder.return_([result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  // Emits shl and or_shifted
  inspect(
    output,
    content=(
      #|vcode or_shifted_test(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = ldi 5
      #|    v3 = shl v1, v2
      #|    v4 = or.lsl #5 v0, v1
      #|    ret v4
      #|}
      #|
    ),
  )
}

///|
test "lower xor(x, shl(y, n)) to xor_shifted" {
  // Pattern: xor(x, shl(y, n)) -> XorShifted: x ^ (y << n)
  let builder = @ir.IRBuilder::new("xor_shifted_test")
  let x = builder.add_param(@ir.Type::I64)
  let y = builder.add_param(@ir.Type::I64)
  builder.add_result(@ir.Type::I64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let shift_amt = builder.iconst_i64(1L)
  let shl_y = builder.ishl(y, shift_amt)
  let result = builder.bxor(x, shl_y)
  builder.return_([result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  // Emits shl and xor_shifted
  inspect(
    output,
    content=(
      #|vcode xor_shifted_test(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = ldi 1
      #|    v3 = shl v1, v2
      #|    v4 = xor.lsl #1 v0, v1
      #|    ret v4
      #|}
      #|
    ),
  )
}

///|
test "madd commutative: add(mul(x, y), z) to madd" {
  // Pattern: add(mul(x, y), z) -> MADD: z + x * y (commutative)
  let builder = @ir.IRBuilder::new("madd_commutative")
  let x = builder.add_param(@ir.Type::I64)
  let y = builder.add_param(@ir.Type::I64)
  let z = builder.add_param(@ir.Type::I64)
  builder.add_result(@ir.Type::I64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let mul_xy = builder.imul(x, y)
  let result = builder.iadd(mul_xy, z)
  builder.return_([result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  // Emits both mul and madd (with z as accumulator)
  inspect(
    output,
    content=(
      #|vcode madd_commutative(v0:int, v1:int, v2:int) -> int {
      #|block0:
      #|    v3 = mul v0, v1
      #|    v4 = madd v2, v0, v1
      #|    ret v4
      #|}
      #|
    ),
  )
}

///|
test "add_shifted commutative: add(shl(x, n), y) to add_shifted" {
  // Pattern: add(shl(x, n), y) -> AddShifted: y + (x << n)
  let builder = @ir.IRBuilder::new("add_shifted_commutative")
  let x = builder.add_param(@ir.Type::I64)
  let y = builder.add_param(@ir.Type::I64)
  builder.add_result(@ir.Type::I64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let shift_amt = builder.iconst_i64(3L)
  let shl_x = builder.ishl(x, shift_amt)
  let result = builder.iadd(shl_x, y)
  builder.return_([result])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  // Emits shl and add_shifted with y as base (commutative)
  inspect(
    output,
    content=(
      #|vcode add_shifted_commutative(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = ldi 3
      #|    v3 = shl v0, v2
      #|    v4 = add.lsl #3 v1, v0
      #|    ret v4
      #|}
      #|
    ),
  )
}

// ============ br_table Pattern Test (f32_br_2locals reproduction) ============
// This test reproduces the pattern from spec/f32_br_2locals.wast
//
// The WASM function:
//   (func (export "test") (param i32) (result f32)
//     (local f32 f32)   ; local1, local2
//     (local.set 1 (f32.const 10.0))
//     (block $3
//       (block $2
//         (block $1
//           (block $0
//             (br_table $0 $1 $2 $3 (local.get 0))
//           )
//           ;; case 0: store local1, load to local2, br $3
//           (f32.store (i32.const 0) (local.get 1))
//           (local.set 2 (f32.load (i32.const 0)))
//           (br $3)
//         )
//         ;; case 1: same as case 0
//       )
//       ;; case 2: same as case 0
//     )
//     ;; case 3/default: local2 is never set, returns default 0.0
//     (local.get 2)
//   )
//
// The key challenges for register allocation:
// 1. br_table is lowered to a comparison chain
// 2. Multiple paths define the same vreg (block parameter for local2)
// 3. All paths merge at the exit block via block parameters
// 4. Float register allocation must handle this correctly

///|
test "lower br_table with f32 locals (f32_br_2locals pattern)" {
  // Build IR that mimics the f32_br_2locals.wast function:
  //   fn test(selector: i32) -> f32
  //
  // Structure:
  //   entry:
  //     local1 = f32.const 10.0
  //     local2_init = f32.const 0.0
  //     addr = i32.const 0
  //     br_table selector, [case0, case1, case2], exit
  //
  //   case0, case1, case2:
  //     store.f32 addr, local1
  //     local2_i = load.f32 addr
  //     jump exit(local2_i)
  //
  //   exit(local2_phi: f32):
  //     return local2_phi

  let builder = @ir.IRBuilder::new("test")
  let selector = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::F32)

  // Create all blocks first
  let entry = builder.create_block()
  let case0 = builder.create_block()
  let case1 = builder.create_block()
  let case2 = builder.create_block()
  let exit = builder.create_block()

  // Add block parameter for exit (the merged local2 value)
  let local2_phi = builder.add_block_param(exit, @ir.Type::F32)

  // Entry block
  builder.switch_to_block(entry)
  let local1 = builder.fconst_f32(10.0)
  let local2_init = builder.fconst_f32(0.0)
  let addr = builder.iconst_i64(0) // ptr is i64
  let offset0 = builder.iconst_i64(0)
  // br_table with 3 cases + default
  // targets = [case0, case1, case2], default = exit
  builder.br_table(selector, [case0, case1, case2], exit)

  // case0: store local1, load to local2, jump exit with local2
  builder.switch_to_block(case0)
  builder.store_ptr(@ir.Type::F32, addr, local1, offset0)
  let local2_0 = builder.load_ptr(@ir.Type::F32, addr, offset0)
  builder.jump(exit, [local2_0])

  // case1: same pattern
  builder.switch_to_block(case1)
  builder.store_ptr(@ir.Type::F32, addr, local1, offset0)
  let local2_1 = builder.load_ptr(@ir.Type::F32, addr, offset0)
  builder.jump(exit, [local2_1])

  // case2: same pattern
  builder.switch_to_block(case2)
  builder.store_ptr(@ir.Type::F32, addr, local1, offset0)
  let local2_2 = builder.load_ptr(@ir.Type::F32, addr, offset0)
  builder.jump(exit, [local2_2])

  // exit: return local2_phi
  builder.switch_to_block(exit)
  builder.return_([local2_phi])

  // Ignore warnings about unused values (they're used in block param passing)
  ignore(local2_init)

  // ============ Phase 1: Lower to VCode ============
  let vcode_func = lower_function(builder.get_function())

  // Inspect the lowered VCode structure
  // This shows how br_table is lowered to comparison chain
  inspect(
    vcode_func.print(),
    content=(
      #|vcode test(v0:int) -> float {
      #|block0:
      #|    f2 = ldf 10
      #|    v4 = ldi 0
      #|    br_cmp_imm.eq v0, #0, block1, block5
      #|block1:
      #|    store_ptr.f32 +0 v4, f2
      #|    f12 = load_ptr.f32 +0 v4
      #|    jump block4 (f12)
      #|block2:
      #|    store_ptr.f32 +0 v4, f2
      #|    f13 = load_ptr.f32 +0 v4
      #|    jump block4 (f13)
      #|block3:
      #|    store_ptr.f32 +0 v4, f2
      #|    f14 = load_ptr.f32 +0 v4
      #|    jump block4 (f14)
      #|block4(f1:float):
      #|    ret f1
      #|block5:
      #|    br_cmp_imm.eq v0, #1, block2, block6
      #|block6:
      #|    br_cmp_imm.eq v0, #2, block3, block4
      #|}
      #|
    ),
  )

  // ============ Phase 2: Register Allocation ============
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode_func)

  // Inspect the allocated VCode
  // Key observations:
  // 1. All case blocks (1, 2, 3) should write the block parameter to the SAME register (d2)
  // 2. The exit block (4) should return that same register (d2)
  // 3. Float values should be in float registers (d0, d1, d2, ...)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int) -> float {
      #|block0:
      #|    d0 = ldf 10
      #|    x1 = ldi 0
      #|    br_cmp_imm.eq x0, #0, block1, block5
      #|block1:
      #|    store_ptr.f32 +0 x1, d0
      #|    d0 = load_ptr.f32 +0 x1
      #|    jump block4
      #|block2:
      #|    store_ptr.f32 +0 x1, d0
      #|    d0 = load_ptr.f32 +0 x1
      #|    jump block4
      #|block3:
      #|    store_ptr.f32 +0 x1, d0
      #|    d0 = load_ptr.f32 +0 x1
      #|    jump block4
      #|block4(f1:float):
      #|    ret d0
      #|block5:
      #|    br_cmp_imm.eq x0, #1, block2, block6
      #|block6:
      #|    br_cmp_imm.eq x0, #2, block3, block4
      #|}
      #|
    ),
  )

  // ============ Phase 3: Verify Key Properties ============

  // Count the number of blocks (entry + 3 cases + exit + 2 comparison chain blocks = 7)
  inspect(allocated_func.blocks.length(), content="7")

  // Verify the function returns a float
  inspect(allocated_func.results.length(), content="1")

  // ============ Phase 4: Verify SSA Deconstruction ============
  // The critical property: all paths that define the block parameter (f1)
  // should write to the SAME physical register (d2)
  //
  // block1: d2 = mov d0
  // block2: d2 = mov d1
  // block3: d2 = mov d1
  // block4: ret d2
  //
  // This ensures the value correctly flows through all paths

  // Check block1's last instruction defines d2
  let block1_last = allocated_func.blocks[1].insts.last().unwrap()
  inspect(block1_last.opcode, content="load_ptr.f32 +0")
  match block1_last.defs[0].reg {
    Physical(preg) => inspect(preg.to_string(), content="d0")
    Virtual(_) => fail("block1_last is virtual")
  }

  // Check block2's last instruction defines d2
  let block2_last = allocated_func.blocks[2].insts.last().unwrap()
  match block2_last.defs[0].reg {
    Physical(preg) => inspect(preg.to_string(), content="d0")
    Virtual(_) => fail("block2_last is virtual")
  }

  // Check block3's last instruction defines d2
  let block3_last = allocated_func.blocks[3].insts.last().unwrap()
  match block3_last.defs[0].reg {
    Physical(preg) => inspect(preg.to_string(), content="d0")
    Virtual(_) => fail("block3_last is virtual")
  }
}

// ============ Minimal Test: Dead Float Constants ============
// This test reproduces the pattern from WASM local initialization.
// The issue: dead value and live value get allocated to the same register.

///|
test "minimal: dead float constant should not affect live values" {
  let builder = @ir.IRBuilder::new("dead_fconst_test")
  builder.add_result(@ir.Type::F32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)

  // Use DIFFERENT values to make bug obvious:
  // If f0 and f1 share register, return value will be WRONG
  let v1 = builder.fconst_f32(1.0) // DEAD - should not affect result
  let v2 = builder.fconst_f32(2.0) // LIVE - returned, must be 2.0
  let v3 = builder.fconst_f32(10.0) // LIVE - stored to memory
  let addr = builder.iconst_i64(0) // ptr is i64
  let offset0 = builder.iconst_i64(0)
  builder.store_ptr(@ir.Type::F32, addr, v3, offset0)
  builder.return_([v2])
  ignore(v1)

  // Lower to VCode
  let vcode_func = lower_function(builder.get_function())
  inspect(
    vcode_func.print(),
    content=(
      #|vcode dead_fconst_test() -> float {
      #|block0:
      #|    f1 = ldf 2
      #|    f2 = ldf 10
      #|    v3 = ldi 0
      #|    store_ptr.f32 +0 v3, f2
      #|    ret f1
      #|}
      #|
    ),
  )

  // Register allocation with DCE:
  // Dead code (f0 = ldf 1) is eliminated before register allocation
  // Only live values get registers: f1 -> d0, f2 -> d1
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode_func)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode dead_fconst_test() -> float {
      #|block0:
      #|    d1 = ldf 2
      #|    d0 = ldf 10
      #|    x0 = ldi 0
      #|    store_ptr.f32 +0 x0, d0
      #|    ret d1
      #|}
      #|
    ),
  )
}

// ============ br_table with Block Arguments Test ============
// Simple test: br_table with 1 target + default, uses local variable

///|
test "br_table with block arguments from WAT" {
  // test(0) = 100 (case 0), test(1) = 0 (default)
  let wat_source =
    #|(module
    #|  (func (export "test") (param i32) (result i32)
    #|    (local i32)
    #|    (block $done
    #|      (block $case0
    #|        (br_table $case0 $done (local.get 0))
    #|      )
    #|      (local.set 1 (i32.const 100))
    #|    )
    #|    (local.get 1)
    #|  )
    #|)
  let wasm_module = @wat.parse(wat_source) catch {
    e => {
      inspect(e)
      return
    }
  }
  let func_code = wasm_module.codes[0]
  let func_type = wasm_module.get_func_type(wasm_module.funcs[0])
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    @types.extract_func_types(wasm_module.types),
    wasm_module.funcs.mapi(fn(i, _) { wasm_module.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  let vcode_func = lower_function(ir_func)
  inspect(
    vcode_func.print(),
    content=(
      #|vcode test(v0:int, v1:int) -> int {
      #|block0:
      #|    v6 = ldi 0
      #|    br_cmp_imm.eq v1, #0, block3, block4
      #|block1(v2:int, v3:int):
      #|    ret v3
      #|block2(v4:int, v5:int):
      #|    v9 = ldi 100
      #|    jump block1 (v4, v9)
      #|block3:
      #|    jump block2 (v1, v6)
      #|block4:
      #|    jump block1 (v1, v6)
      #|}
      #|
    ),
  )
}
