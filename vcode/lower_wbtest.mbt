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
  let expected =
    #|vcode add(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = add v0, v1
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
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
  let expected =
    #|vcode arith(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = add v0, v1
    #|    v3 = sub v2, v0
    #|    v4 = mul v3, v1
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
  let expected =
    #|vcode const_test() -> int {
    #|block0:
    #|    v0 = ldi 10
    #|    v1 = ldi 20
    #|    v2 = add v0, v1
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "lower float operations" {
  let builder = @ir.IRBuilder::new("float_add")
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
      #|vcode float_add(f0:float, f1:float) -> float {
      #|block0:
      #|    f2 = fadd f0, f1
      #|    f3 = fmul f2, f0
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
  let expected =
    #|vcode cmp_test(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = cmp.sgt v0, v1
    #|    ret v2
    #|}
    #|
  inspect(output, content=expected)
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
  let expected =
    #|vcode max(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = cmp.sgt v0, v1
    #|    branch v2, block1, block2
    #|block1:
    #|    ret v0
    #|block2:
    #|    ret v1
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "lower memory operations" {
  let builder = @ir.IRBuilder::new("load_store")
  let addr = builder.add_param(@ir.Type::I64)
  builder.add_result(@ir.Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let loaded = builder.load(@ir.Type::I32, addr, 0)
  let one = builder.iconst_i32(1)
  let sum = builder.iadd(loaded, one)
  builder.store(@ir.Type::I32, addr, sum, 4)
  builder.return_([sum])
  let vcode_func = lower_function(builder.get_function())
  let output = vcode_func.print()
  inspect(
    output,
    content=(
      #|vcode load_store(v0:int) -> int {
      #|block0:
      #|    bounds_check +0, 4 v0
      #|    v2 = add x21, v0
      #|    v1 = load.i32 +0 v2
      #|    v3 = ldi 1
      #|    v4 = add v1, v3
      #|    bounds_check +4, 4 v0
      #|    v5 = add x21, v0
      #|    store.i32 +4 v5, v4
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
  let expected =
    #|vcode shifts(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = shl v0, v1
    #|    v3 = ashr v2, v1
    #|    v4 = lshr v3, v1
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
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
  let expected =
    #|vcode division(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = sdiv v0, v1
    #|    v3 = udiv v0, v1
    #|    v4 = add v2, v3
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "lower float comparison" {
  let builder = @ir.IRBuilder::new("fcmp_test")
  let a = builder.add_param(@ir.Type::F64)
  let b = builder.add_param(@ir.Type::F64)
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
  let expected =
    #|vcode jump_test() -> int {
    #|block0:
    #|    v0 = ldi 42
    #|    jump block1
    #|block1:
    #|    ret v0
    #|}
    #|
  inspect(output, content=expected)
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
test "lower float constant" {
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
      #|vcode fconst_test() -> float {
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
  let expected =
    #|vcode madd_test(v0:int, v1:int, v2:int) -> int {
    #|block0:
    #|    v3 = mul v1, v2
    #|    v4 = madd v0, v1, v2
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
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
  let expected =
    #|vcode msub_test(v0:int, v1:int, v2:int) -> int {
    #|block0:
    #|    v3 = mul v1, v2
    #|    v4 = msub v0, v1, v2
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
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
  let expected =
    #|vcode mneg_test(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = ldi 0
    #|    v3 = mul v0, v1
    #|    v4 = mneg v0, v1
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
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
  let expected =
    #|vcode add_shifted_test(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = ldi 3
    #|    v3 = shl v1, v2
    #|    v4 = add.lsl #3 v0, v1
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
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
  let expected =
    #|vcode sub_shifted_test(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = ldi 2
    #|    v3 = shl v1, v2
    #|    v4 = sub.lsl #2 v0, v1
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
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
  let expected =
    #|vcode and_shifted_test(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = ldi 4
    #|    v3 = shl v1, v2
    #|    v4 = and.lsl #4 v0, v1
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
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
  let expected =
    #|vcode or_shifted_test(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = ldi 5
    #|    v3 = shl v1, v2
    #|    v4 = or.lsl #5 v0, v1
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
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
  let expected =
    #|vcode xor_shifted_test(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = ldi 1
    #|    v3 = shl v1, v2
    #|    v4 = xor.lsl #1 v0, v1
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
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
  let expected =
    #|vcode madd_commutative(v0:int, v1:int, v2:int) -> int {
    #|block0:
    #|    v3 = mul v0, v1
    #|    v4 = madd v2, v0, v1
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
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
  let expected =
    #|vcode add_shifted_commutative(v0:int, v1:int) -> int {
    #|block0:
    #|    v2 = ldi 3
    #|    v3 = shl v0, v2
    #|    v4 = add.lsl #3 v1, v0
    #|    ret v4
    #|}
    #|
  inspect(output, content=expected)
}
