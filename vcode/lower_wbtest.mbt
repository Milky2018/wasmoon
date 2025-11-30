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
  let expected =
    #|vcode load_store(v0:int) -> int {
    #|block0:
    #|    v1 = load.i32 +0 v0
    #|    v2 = ldi 1
    #|    v3 = add v1, v2
    #|    store.i32 +4 v0, v3
    #|    ret v3
    #|}
    #|
  inspect(output, content=expected)
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
  let expected =
    #|vcode fconst_test() -> float {
    #|block0:
    #|    f0 = ldf 3.14
    #|    ret f0
    #|}
    #|
  inspect(output, content=expected)
}
