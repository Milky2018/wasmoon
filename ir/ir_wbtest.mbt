// Tests for the IR builder and printer

///|
test "simple add function" {
  // Build: function add(v0:i32, v1:i32) -> i32 { return v0 + v1 }
  let builder = IRBuilder::new("add")
  let p0 = builder.add_param(Type::I32)
  let p1 = builder.add_param(Type::I32)
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sum = builder.iadd(p0, p1)
  builder.return_([sum])
  let output = builder.print()
  let expected =
    #|function add(v0:i32, v1:i32) -> i32 {
    #|block0:
    #|    v2:i32 = iadd v0, v1
    #|    return v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "constants" {
  let builder = IRBuilder::new("constants")
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let c1 = builder.iconst_i32(42)
  let c2 = builder.iconst_i32(10)
  let sum = builder.iadd(c1, c2)
  builder.return_([sum])
  let output = builder.print()
  let expected =
    #|function constants() -> i32 {
    #|block0:
    #|    v0:i32 = iconst 42
    #|    v1:i32 = iconst 10
    #|    v2:i32 = iadd v0, v1
    #|    return v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "conditional branch" {
  let builder = IRBuilder::new("max")
  let p0 = builder.add_param(Type::I32)
  let p1 = builder.add_param(Type::I32)
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  let then_block = builder.create_block()
  let else_block = builder.create_block()
  builder.switch_to_block(entry)
  let cmp = builder.icmp_sgt(p0, p1)
  builder.brnz(cmp, then_block, else_block)
  builder.switch_to_block(then_block)
  builder.return_([p0])
  builder.switch_to_block(else_block)
  builder.return_([p1])
  let output = builder.print()
  let expected =
    #|function max(v0:i32, v1:i32) -> i32 {
    #|block0:
    #|    v2:i32 = icmp.sgt v0, v1
    #|    brnz v2, block1, block2
    #|block1:
    #|    return v0
    #|block2:
    #|    return v1
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "float operations" {
  let builder = IRBuilder::new("fadd")
  let p0 = builder.add_param(Type::F64)
  let p1 = builder.add_param(Type::F64)
  builder.add_result(Type::F64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sum = builder.fadd(p0, p1)
  let neg = builder.fneg(sum)
  builder.return_([neg])
  let output = builder.print()
  let expected =
    #|function fadd(v0:f64, v1:f64) -> f64 {
    #|block0:
    #|    v2:f64 = fadd v0, v1
    #|    v3:f64 = fneg v2
    #|    return v3
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "memory operations" {
  let builder = IRBuilder::new("load_store")
  let addr = builder.add_param(Type::I32)
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let loaded = builder.load(Type::I32, addr, 0)
  let c1 = builder.iconst_i32(1)
  let added = builder.iadd(loaded, c1)
  builder.store(Type::I32, addr, added, 4)
  builder.return_([added])
  let output = builder.print()
  let expected =
    #|function load_store(v0:i32) -> i32 {
    #|block0:
    #|    v1:i32 = load.i32 v0 +0
    #|    v2:i32 = iconst 1
    #|    v3:i32 = iadd v1, v2
    #|    store.i32 v0, v3 +4
    #|    return v3
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "block parameters" {
  let builder = IRBuilder::new("loop_sum")
  let n = builder.add_param(Type::I32)
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  let loop_header = builder.create_block()
  let loop_body = builder.create_block()
  let exit_block = builder.create_block()
  // Entry block
  builder.switch_to_block(entry)
  let init_sum = builder.iconst_i32(0)
  let init_counter = builder.iconst_i32(0)
  builder.jump(loop_header, [init_sum, init_counter])
  // Loop header with parameters
  let sum_param = builder.add_block_param(loop_header, Type::I32)
  let counter_param = builder.add_block_param(loop_header, Type::I32)
  builder.switch_to_block(loop_header)
  let cmp = builder.icmp_slt(counter_param, n)
  builder.brnz(cmp, loop_body, exit_block)
  // Loop body
  builder.switch_to_block(loop_body)
  let new_sum = builder.iadd(sum_param, counter_param)
  let one = builder.iconst_i32(1)
  let new_counter = builder.iadd(counter_param, one)
  builder.jump(loop_header, [new_sum, new_counter])
  // Exit
  builder.switch_to_block(exit_block)
  builder.return_([sum_param])
  let output = builder.print()
  let expected =
    #|function loop_sum(v0:i32) -> i32 {
    #|block0:
    #|    v1:i32 = iconst 0
    #|    v2:i32 = iconst 0
    #|    jump block1(v1, v2)
    #|block1(v3:i32, v4:i32):
    #|    v5:i32 = icmp.slt v4, v0
    #|    brnz v5, block2, block3
    #|block2:
    #|    v6:i32 = iadd v3, v4
    #|    v7:i32 = iconst 1
    #|    v8:i32 = iadd v4, v7
    #|    jump block1(v6, v8)
    #|block3:
    #|    return v3
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "translate simple add function" {
  // WASM: func add(i32, i32) -> i32 { local.get 0; local.get 1; i32.add }
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let instrs : Array[@types.Instruction] = [
    @types.Instruction::LocalGet(0),
    @types.Instruction::LocalGet(1),
    @types.Instruction::I32Add,
  ]
  let translator = Translator::new("add", func_type, [], [func_type], [0], 0)
  let func = translator.translate(instrs)
  let output = func.print()
  let expected =
    #|function add(v0:i32, v1:i32) -> i32 {
    #|block0:
    #|    v2:i32 = iadd v0, v1
    #|    return v2
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "translate multiply and add" {
  // WASM: func mul_add(i32, i32) -> i32 { local.get 0; local.get 1; i32.mul; i32.const 1; i32.add }
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let instrs : Array[@types.Instruction] = [
    @types.Instruction::LocalGet(0),
    @types.Instruction::LocalGet(1),
    @types.Instruction::I32Mul,
    @types.Instruction::I32Const(1),
    @types.Instruction::I32Add,
  ]
  let translator = Translator::new(
    "mul_add",
    func_type,
    [],
    [func_type],
    [0],
    0,
  )
  let func = translator.translate(instrs)
  let output = func.print()
  let expected =
    #|function mul_add(v0:i32, v1:i32) -> i32 {
    #|block0:
    #|    v2:i32 = imul v0, v1
    #|    v3:i32 = iconst 1
    #|    v4:i32 = iadd v2, v3
    #|    return v4
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "translate with local variable" {
  // WASM: func with_local(i32, i32) -> i32 {
  //   (local i32)
  //   local.get 0; local.get 1; i32.add; local.set 2;
  //   local.get 2; i32.const 2; i32.mul
  // }
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let instrs : Array[@types.Instruction] = [
    @types.Instruction::LocalGet(0),
    @types.Instruction::LocalGet(1),
    @types.Instruction::I32Add,
    @types.Instruction::LocalSet(2),
    @types.Instruction::LocalGet(2),
    @types.Instruction::I32Const(2),
    @types.Instruction::I32Mul,
  ]
  let translator = Translator::new(
    "with_local",
    func_type,
    [@types.ValueType::I32],
    [func_type],
    [0],
    0,
  )
  let func = translator.translate(instrs)
  let output = func.print()
  let expected =
    #|function with_local(v0:i32, v1:i32) -> i32 {
    #|block0:
    #|    v2:i32 = iconst 0
    #|    v3:i32 = iadd v0, v1
    #|    v4:i32 = iconst 2
    #|    v5:i32 = imul v3, v4
    #|    return v5
    #|}
    #|
  inspect(output, content=expected)
}

///|
test "translate comparison" {
  // WASM: func max(i32, i32) -> i32 {
  //   local.get 0; local.get 1; i32.gt_s; select
  // }
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let instrs : Array[@types.Instruction] = [
    @types.Instruction::LocalGet(0),
    @types.Instruction::LocalGet(1),
    @types.Instruction::LocalGet(0),
    @types.Instruction::LocalGet(1),
    @types.Instruction::I32GtS,
    @types.Instruction::Select,
  ]
  let translator = Translator::new("max", func_type, [], [func_type], [0], 0)
  let func = translator.translate(instrs)
  let output = func.print()
  let expected =
    #|function max(v0:i32, v1:i32) -> i32 {
    #|block0:
    #|    v2:i32 = icmp.sgt v0, v1
    #|    v3:i32 = select v2, v0, v1
    #|    return v3
    #|}
    #|
  inspect(output, content=expected)
}

// ============ Validator Tests ============

///|
test "validate valid function" {
  let builder = IRBuilder::new("add")
  let p0 = builder.add_param(Type::I32)
  let p1 = builder.add_param(Type::I32)
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sum = builder.iadd(p0, p1)
  builder.return_([sum])
  let func = builder.get_function()
  let result = validate_function(func)
  assert_true(result.valid)
  assert_eq(result.errors.length(), 0)
}

///|
test "validate function with no blocks" {
  let func : Function = {
    name: "empty",
    params: [],
    results: [],
    blocks: [],
    next_value_id: 0,
    next_block_id: 0,
  }
  let result = validate_function(func)
  assert_false(result.valid)
  assert_true(result.errors.length() > 0)
}

///|
test "validate translated function" {
  // Validate a function translated from WASM
  let func_type : @types.FuncType = {
    params: [@types.ValueType::I32, @types.ValueType::I32],
    results: [@types.ValueType::I32],
  }
  let instrs : Array[@types.Instruction] = [
    @types.Instruction::LocalGet(0),
    @types.Instruction::LocalGet(1),
    @types.Instruction::I32Add,
  ]
  let translator = Translator::new("add", func_type, [], [func_type], [0], 0)
  let func = translator.translate(instrs)
  let result = validate_function(func)
  assert_true(result.valid)
}
