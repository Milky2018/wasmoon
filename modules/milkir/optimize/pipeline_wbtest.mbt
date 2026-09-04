///|
test "optimizer preserves external calls with unused results" {
  let func = @milkir.Function::new_empty("external_effect")
  let symbol = func.declare_external_symbol("effect")
  let ignored = func.new_value(I32)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(Call(Direct(symbol, Signature([], [I32]))), [], [ignored]),
  )
  entry.set_terminator(Return([]))
  optimize_with_level(func, O1) |> ignore
  inspect(instruction_count(func), content="1")
}

///|
test "optimizer folds integer constants" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("const_add")
  builder.add_result(I32)
  let lhs = builder.iconst_i32(10)
  let rhs = builder.iconst_i32(20)
  let sum = builder.iadd(lhs, rhs)
  builder.return_([sum])
  let func = builder.get_function()
  let result = optimize_with_level(func, O1)
  inspect(result.changed, content="true")
  inspect(instruction_count(func), content="1")
  inspect(
    func.print(),
    content=(
      #|function const_add() -> i32 {
      #|block0:
      #|    v2:i32 = iconst 30
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "optimizer leaves trap-prone division unfused" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("no_fold_div")
  builder.add_result(I32)
  let entry = builder.current_block()
  let lhs = builder.iconst_i32(10)
  let rhs = builder.iconst_i32(0)
  let result = builder.get_function().new_value(I32)
  entry.append_inst(
    builder
    .get_function()
    .new_inst(Scalar(IntBinary(SignedDiv)), [lhs, rhs], [result]),
  )
  builder.return_([result])
  let func = builder.get_function()
  let opt = optimize_with_level(func, O2)
  inspect(opt.changed, content="false")
  inspect(
    func.print(),
    content=(
      #|function no_fold_div() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 10
      #|    v1:i32 = iconst 0
      #|    v2:i32 = sdiv v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "optimizer O0 does not rewrite constants" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("o0")
  builder.add_result(I32)
  let lhs = builder.iconst_i32(1)
  let rhs = builder.iconst_i32(2)
  let sum = builder.iadd(lhs, rhs)
  builder.return_([sum])
  let func = builder.get_function()
  let result = optimize_with_level(func, O0)
  inspect(result.changed, content="false")
  inspect(
    func.print(),
    content=(
      #|function o0() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    v1:i32 = iconst 2
      #|    v2:i32 = iadd v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "optimizer O2 removes dead pure instructions after folding" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("o2_dce")
  builder.add_result(I32)
  let lhs = builder.iconst_i32(1)
  let rhs = builder.iconst_i32(2)
  let sum = builder.iadd(lhs, rhs)
  builder.return_([sum])
  let func = builder.get_function()
  let result = optimize_with_level(func, O2)
  inspect(result.changed, content="true")
  inspect(instruction_count(func), content="1")
  inspect(
    func.print(),
    content=(
      #|function o2_dce() -> i32 {
      #|block0:
      #|    v2:i32 = iconst 3
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "dead code pass keeps unused loads without alias metadata" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("keep_load")
  let ptr = builder.add_param(Ptr)
  builder.add_result(I32)
  let offset = builder.iconst_i64(0L)
  let _loaded = builder.load_ptr(I32, ptr, offset)
  let result = builder.iconst_i32(7)
  builder.return_([result])
  let func = builder.get_function()
  let opt = eliminate_dead_code(func)
  inspect(opt.changed, content="false")
  inspect(instruction_count(func), content="3")
}

///|
test "strength reduction derives shift amounts and remainder masks" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("strength_reduce_pow2")
  let value = builder.add_param(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  let eight = builder.iconst_i32(8)
  let product = builder.imul(value, eight)
  let quotient = builder.udiv(value, eight)
  let remainder = builder.urem(value, eight)
  builder.return_([product, quotient, remainder])
  let func = builder.get_function()
  let result = reduce_strength(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function strength_reduce_pow2(v0:i32) -> i32, i32, i32 {
      #|block0:
      #|    v1:i32 = iconst 8
      #|    v5:i32 = iconst 3
      #|    v2:i32 = ishl v0, v5
      #|    v6:i32 = iconst 3
      #|    v3:i32 = ushr v0, v6
      #|    v7:i32 = iconst 7
      #|    v4:i32 = band v0, v7
      #|    return v2, v3, v4
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "O3 derives power-of-two constants in a large function" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "o3_large_strength_reduce",
  )
  let value = builder.add_param(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  builder.add_result(I32)
  for _ in 0..<296 {
    builder.iconst_i32(0) |> ignore
  }
  let eight = builder.iconst_i32(8)
  let product = builder.imul(value, eight)
  let quotient = builder.udiv(value, eight)
  let remainder = builder.urem(value, eight)
  builder.return_([product, quotient, remainder])
  let func = builder.get_function()
  optimize_with_level(func, O3) |> ignore
  let instructions = test_block_instructions(func, func.blocks[0])
  inspect(instructions.length(), content="6")
  inspect(instructions[0].opcode, content="Scalar(IntConst(3))")
  inspect(instructions[1].opcode, content="Scalar(IntBinary(ShiftLeft))")
  inspect(instructions[2].opcode, content="Scalar(IntConst(3))")
  inspect(
    instructions[3].opcode,
    content="Scalar(IntBinary(UnsignedShiftRight))",
  )
  inspect(instructions[4].opcode, content="Scalar(IntConst(7))")
  inspect(instructions[5].opcode, content="Scalar(IntBinary(And))")
  inspect(func.verify(), content="()")
}

///|
test "O3 does not duplicate loop side effects without a safe unroll proof" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("o3_loop_side_effect")
  let condition = builder.add_param(I32)
  let header = builder.create_block()
  let body = builder.create_block()
  let exit = builder.create_block()
  builder.jump(header, [])
  builder.switch_to_block(header)
  builder.brnz(condition, body, exit)
  builder.switch_to_block(body)
  let func = builder.get_function()
  let symbol = func.declare_external_symbol("effect")
  builder
  .current_block()
  .append_inst(func.new_inst(Call(Direct(symbol, Signature([], []))), [], []))
  builder.jump(header, [])
  builder.switch_to_block(exit)
  builder.return_([])
  optimize_with_level(func, O3) |> ignore
  let mut external_calls = 0
  for block in func.blocks {
    for inst in test_block_instructions(func, block) {
      if inst.opcode is Call(_) {
        external_calls = external_calls + 1
      }
    }
  }
  inspect(external_calls, content="1")
  inspect(func.verify(), content="()")
}

///|
test "optimizer CSE replaces duplicate pure expression with copy" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("cse_local")
  let lhs = builder.add_param(I32)
  let rhs = builder.add_param(I32)
  builder.add_result(I32)
  let _sum0 = builder.iadd(lhs, rhs)
  let sum1 = builder.iadd(lhs, rhs)
  builder.return_([sum1])
  let func = builder.get_function()
  let result = optimize_with_level(func, O2)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function cse_local(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    v3:i32 = iadd v0, v1
      #|    return v3
      #|}
      #|
    ),
  )
}

///|
test "GVN reuses float constants with identical NaN bits" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("gvn_nan_bits")
  builder.add_result(F64)
  let nan = 0x7FF8000000000001UL.reinterpret_as_double()
  let _first = builder.fconst_f64(nan)
  let second = builder.fconst_f64(nan)
  builder.return_([second])
  let func = builder.get_function()
  let stats = run_acyclic_optimization_with_budget_and_analysis(
    func,
    instruction_count(func),
    FunctionAnalysis::build(func),
  )
  inspect(stats.result.changed, content="true")
  inspect(
    func.block_instruction_at(func.blocks[0], 1).unwrap().opcode is Scalar(Copy),
    content="true",
  )
  inspect(func.verify(), content="()")
}

///|
test "GVN does not conflate integer constants with different widths" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("gvn_integer_widths")
  builder.add_result(I64)
  let _narrow = builder.iconst_i32(1)
  let wide = builder.iconst_i64(1L)
  builder.return_([wide])
  let func = builder.get_function()
  let stats = run_acyclic_optimization_with_budget_and_analysis(
    func,
    instruction_count(func),
    FunctionAnalysis::build(func),
  )
  inspect(stats.result.changed, content="false")
  inspect(
    func.print(),
    content=(
      #|function gvn_integer_widths() -> i64 {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    v1:i64 = iconst 1
      #|    return v1
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer CSE reuses expressions from dominating blocks" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("cse_global")
  let lhs = builder.add_param(I32)
  let rhs = builder.add_param(I32)
  let cond = builder.add_param(I32)
  builder.add_result(I32)
  let then_block = builder.create_block()
  let else_block = builder.create_block()
  let sum0 = builder.iadd(lhs, rhs)
  builder.brnz(cond, then_block, else_block)
  builder.switch_to_block(then_block)
  let sum1 = builder.iadd(lhs, rhs)
  builder.return_([sum1])
  builder.switch_to_block(else_block)
  builder.return_([sum0])
  let func = builder.get_function()
  let result = optimize_with_level(func, O2)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function cse_global(v0:i32, v1:i32, v2:i32) -> i32 {
      #|block0:
      #|    v3:i32 = iadd v0, v1
      #|    brnz v2, block1, block2
      #|block1:
      #|    return v3
      #|block2:
      #|    return v3
      #|}
      #|
    ),
  )
}

///|
test "optimizer propagates local copies" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("copy_prop")
  let param = builder.add_param(I32)
  builder.add_result(I32)
  let copy = builder.copy(param)
  let one = builder.iconst_i32(1)
  let sum = builder.iadd(copy, one)
  builder.return_([sum])
  let func = builder.get_function()
  let result = canonicalize_aliases(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function copy_prop(v0:i32) -> i32 {
      #|block0:
      #|    v1:i32 = copy v0
      #|    v2:i32 = iconst 1
      #|    v3:i32 = iadd v0, v2
      #|    return v3
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer canonicalizes aliases through dominating blocks" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "alias_canon_copy_chain",
  )
  let param = builder.add_param(I32)
  builder.add_result(I32)
  let body = builder.create_block()
  let copy0 = builder.copy(param)
  builder.jump(body, [])
  builder.switch_to_block(body)
  let copy1 = builder.copy(copy0)
  let copy2 = builder.copy(copy1)
  let one = builder.iconst_i32(1)
  let sum = builder.iadd(copy2, one)
  builder.return_([sum])
  let func = builder.get_function()
  let result = canonicalize_aliases(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function alias_canon_copy_chain(v0:i32) -> i32 {
      #|block0:
      #|    v1:i32 = copy v0
      #|    jump block1
      #|block1:
      #|    v2:i32 = copy v0
      #|    v3:i32 = copy v0
      #|    v4:i32 = iconst 1
      #|    v5:i32 = iadd v0, v4
      #|    return v5
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer canonicalizes branch args without crossing sibling dominance" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "alias_canon_branch_args",
  )
  let value = builder.add_param(I32)
  let cond = builder.add_param(I32)
  builder.add_result(I32)
  let then_block = builder.create_block()
  let else_block = builder.create_block()
  let join = builder.create_block()
  let join_param = builder.add_block_param(join, I32)
  builder.brnz(cond, then_block, else_block)
  builder.switch_to_block(then_block)
  let copy = builder.copy(value)
  builder.jump(join, [copy])
  builder.switch_to_block(else_block)
  builder.jump(join, [value])
  builder.switch_to_block(join)
  let one = builder.iconst_i32(1)
  let sum = builder.iadd(join_param, one)
  builder.return_([sum])
  let func = builder.get_function()
  let result = canonicalize_aliases(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function alias_canon_branch_args(v0:i32, v1:i32) -> i32 {
      #|block0:
      #|    brnz v1, block1, block2
      #|block1:
      #|    v3:i32 = copy v0
      #|    jump block3(v0)
      #|block2:
      #|    jump block3(v0)
      #|block3(v2:i32):
      #|    v4:i32 = iconst 1
      #|    v5:i32 = iadd v2, v4
      #|    return v5
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer removes unused block params and jump args" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("dead_block_params")
  builder.add_result(I32)
  let target = builder.create_block()
  let used_arg = builder.iconst_i32(1)
  let dead_arg = builder.iconst_i32(2)
  builder.jump(target, [used_arg, dead_arg])
  let used_param = builder.add_block_param(target, I32)
  builder.add_block_param(target, I32) |> ignore
  builder.switch_to_block(target)
  builder.return_([used_param])
  let func = builder.get_function()
  let result = eliminate_dead_block_params(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function dead_block_params() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    v1:i32 = iconst 2
      #|    jump block1(v0)
      #|block1(v2:i32):
      #|    return v2
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer keeps block params forwarded through jump args" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "forwarded_block_params",
  )
  builder.add_result(I32)
  let middle = builder.create_block()
  let exit = builder.create_block()
  let arg = builder.iconst_i32(7)
  builder.jump(middle, [arg])
  let middle_param = builder.add_block_param(middle, I32)
  builder.switch_to_block(middle)
  builder.jump(exit, [middle_param])
  let exit_param = builder.add_block_param(exit, I32)
  builder.switch_to_block(exit)
  builder.return_([exit_param])
  let func = builder.get_function()
  let result = eliminate_dead_block_params(func)
  inspect(result.changed, content="false")
  inspect(func.verify(), content="()")
}

///|
test "optimizer removes dead branch arguments with their block parameters" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("dead_branch_params")
  let cond = builder.add_param(I32)
  builder.add_result(I32)
  let join = builder.create_block()
  let used = builder.iconst_i32(7)
  let dead = builder.iconst_i32(9)
  builder.branch(cond, join, [used, dead], join, [used, dead])
  let result = builder.add_block_param(join, I32)
  builder.add_block_param(join, I32) |> ignore
  builder.switch_to_block(join)
  builder.return_([result])
  let func = builder.get_function()
  inspect(eliminate_dead_block_params(func).changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function dead_branch_params(v0:i32) -> i32 {
      #|block0:
      #|    v1:i32 = iconst 7
      #|    v2:i32 = iconst 9
      #|    branch v0, block1(v1), block1(v1)
      #|block1(v3:i32):
      #|    return v3
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer removes constant block params and rewrites uses" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("const_block_params")
  builder.add_result(I32)
  let target = builder.create_block()
  let arg = builder.iconst_i32(7)
  builder.jump(target, [arg])
  let param = builder.add_block_param(target, I32)
  builder.switch_to_block(target)
  builder.return_([param])
  let func = builder.get_function()
  let result = eliminate_constant_block_params(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function const_block_params() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 7
      #|    jump block1
      #|block1:
      #|    return v0
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer removes constant branch block params" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "branch_const_block_params",
  )
  builder.add_result(I32)
  let join = builder.create_block()
  let cond = builder.iconst_i32(1)
  let arg = builder.iconst_i32(7)
  let block = builder.current_block()
  block.set_terminator(Branch(cond, join.id, [arg], join.id, [arg]))
  let param = builder.add_block_param(join, I32)
  builder.switch_to_block(join)
  builder.return_([param])
  let func = builder.get_function()
  let result = eliminate_constant_block_params(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function branch_const_block_params() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    v1:i32 = iconst 7
      #|    branch v0, block1(), block1()
      #|block1:
      #|    return v1
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer keeps varying branch block params" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "branch_varying_block_params",
  )
  builder.add_result(I32)
  let join = builder.create_block()
  let cond = builder.iconst_i32(1)
  let lhs = builder.iconst_i32(7)
  let rhs = builder.iconst_i32(9)
  let block = builder.current_block()
  block.set_terminator(Branch(cond, join.id, [lhs], join.id, [rhs]))
  let param = builder.add_block_param(join, I32)
  builder.switch_to_block(join)
  builder.return_([param])
  let func = builder.get_function()
  let result = eliminate_constant_block_params(func)
  inspect(result.changed, content="false")
  inspect(func.verify(), content="()")
}

///|
test "optimizer removes unreachable blocks" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("unreachable")
  builder.add_result(I32)
  let exit = builder.create_block()
  let dead = builder.create_block()
  builder.jump(exit, [])
  builder.switch_to_block(exit)
  let result_value = builder.iconst_i32(1)
  builder.return_([result_value])
  builder.switch_to_block(dead)
  let dead_value = builder.iconst_i32(99)
  builder.return_([dead_value])
  let func = builder.get_function()
  let result = eliminate_unreachable_code(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function unreachable() -> i32 {
      #|block0:
      #|    jump block1
      #|block1:
      #|    v0:i32 = iconst 1
      #|    return v0
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer simplifies constant brz" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("branch_simp_brz")
  builder.add_result(I32)
  let then_block = builder.create_block()
  let else_block = builder.create_block()
  let zero = builder.iconst_i32(0)
  builder.brz(zero, then_block, else_block)
  builder.switch_to_block(then_block)
  let then_value = builder.iconst_i32(42)
  builder.return_([then_value])
  builder.switch_to_block(else_block)
  let else_value = builder.iconst_i32(100)
  builder.return_([else_value])
  let func = builder.get_function()
  let result = simplify_branches(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function branch_simp_brz() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 0
      #|    jump block1
      #|block1:
      #|    v1:i32 = iconst 42
      #|    return v1
      #|block2:
      #|    v2:i32 = iconst 100
      #|    return v2
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer simplifies constant branch with block arguments" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("branch_simp_args")
  builder.add_result(I32)
  let target = builder.create_block()
  let condition = builder.iconst_i32(1)
  let on_true = builder.iconst_i32(42)
  let on_false = builder.iconst_i32(100)
  builder.branch(condition, target, [on_true], target, [on_false])
  let result = builder.add_block_param(target, I32)
  builder.switch_to_block(target)
  builder.return_([result])
  let func = builder.get_function()
  inspect(simplify_branches(func).changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function branch_simp_args() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    v1:i32 = iconst 42
      #|    v2:i32 = iconst 100
      #|    jump block1(v1)
      #|block1(v3:i32):
      #|    return v3
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer simplifies constant br_table" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("branch_simp_table")
  let target0 = builder.create_block()
  let target1 = builder.create_block()
  let default_target = builder.create_block()
  let index = builder.iconst_i32(1)
  builder.br_table(index, [target0, target1], default_target)
  builder.switch_to_block(target0)
  builder.trap("target0")
  builder.switch_to_block(target1)
  builder.trap("target1")
  builder.switch_to_block(default_target)
  builder.trap("default")
  let func = builder.get_function()
  let result = simplify_branches(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function branch_simp_table() {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    jump block2
      #|block1:
      #|    trap "target0"
      #|block2:
      #|    trap "target1"
      #|block3:
      #|    trap "default"
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer threads trivial jump blocks" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("thread_jump")
  let middle = builder.create_block()
  let exit = builder.create_block()
  builder.jump(middle, [])
  builder.switch_to_block(middle)
  builder.jump(exit, [])
  builder.switch_to_block(exit)
  builder.trap("exit")
  let func = builder.get_function()
  let result = thread_jumps(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function thread_jump() {
      #|block0:
      #|    jump block2
      #|block2:
      #|    trap "exit"
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer threads jump args through block params" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("thread_jump_args")
  builder.add_result(I32)
  let middle = builder.create_block()
  let exit = builder.create_block()
  let a = builder.iconst_i32(1)
  let b = builder.iconst_i32(2)
  builder.jump(middle, [a, b])
  let p0 = builder.add_block_param(middle, I32)
  let p1 = builder.add_block_param(middle, I32)
  builder.switch_to_block(middle)
  builder.jump(exit, [p1, p0])
  let q0 = builder.add_block_param(exit, I32)
  let q1 = builder.add_block_param(exit, I32)
  builder.switch_to_block(exit)
  let sum = builder.iadd(q0, q1)
  builder.return_([sum])
  let func = builder.get_function()
  let result = thread_jumps(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function thread_jump_args() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 1
      #|    v1:i32 = iconst 2
      #|    jump block2(v1, v0)
      #|block2(v4:i32, v5:i32):
      #|    v6:i32 = iadd v4, v5
      #|    return v6
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer threads branch args through block params" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("thread_branch_args")
  let condition = builder.add_param(I32)
  builder.add_result(I32)
  let middle = builder.create_block()
  let exit = builder.create_block()
  let a = builder.iconst_i32(1)
  let b = builder.iconst_i32(2)
  builder.branch(condition, middle, [a, b], middle, [b, a])
  let p0 = builder.add_block_param(middle, I32)
  let p1 = builder.add_block_param(middle, I32)
  builder.switch_to_block(middle)
  builder.jump(exit, [p1, p0])
  let q0 = builder.add_block_param(exit, I32)
  let q1 = builder.add_block_param(exit, I32)
  builder.switch_to_block(exit)
  let sum = builder.iadd(q0, q1)
  builder.return_([sum])
  let func = builder.get_function()
  inspect(thread_jumps(func).changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function thread_branch_args(v0:i32) -> i32 {
      #|block0:
      #|    v1:i32 = iconst 1
      #|    v2:i32 = iconst 2
      #|    branch v0, block2(v2, v1), block2(v1, v2)
      #|block2(v5:i32, v6:i32):
      #|    v7:i32 = iadd v5, v6
      #|    return v7
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer removes unreachable trampoline with dominating free value" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "thread_jump_free_value",
  )
  builder.add_result(I32)
  let defining = builder.create_block()
  let left = builder.create_block()
  let right = builder.create_block()
  let middle = builder.create_block()
  let exit = builder.create_block()
  builder.jump(defining, [])
  builder.switch_to_block(defining)
  let value = builder.iconst_i32(7)
  let condition = builder.iconst_i32(1)
  builder.brnz(condition, left, right)
  builder.switch_to_block(left)
  builder.jump(middle, [])
  builder.switch_to_block(right)
  builder.jump(middle, [])
  builder.switch_to_block(middle)
  builder.jump(exit, [value])
  let result = builder.add_block_param(exit, I32)
  builder.switch_to_block(exit)
  builder.return_([result])
  let func = builder.get_function()
  inspect(func.verify(), content="()")
  thread_jumps(func) |> ignore
  inspect(
    func.print(),
    content=(
      #|function thread_jump_free_value() -> i32 {
      #|block0:
      #|    jump block1
      #|block1:
      #|    v0:i32 = iconst 7
      #|    v1:i32 = iconst 1
      #|    brnz v1, block2, block3
      #|block2:
      #|    jump block5(v0)
      #|block3:
      #|    jump block5(v0)
      #|block5(v2:i32):
      #|    return v2
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "jump threading keeps trampoline parameters used by descendants" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder(
    "thread_jump_live_param",
  )
  builder.add_result(I32)
  let left = builder.create_block()
  let right = builder.create_block()
  let trampoline = builder.create_block()
  let exit = builder.create_block()
  let condition = builder.iconst_i32(1)
  let left_value = builder.iconst_i32(7)
  let right_value = builder.iconst_i32(9)
  builder.brnz(condition, left, right)
  builder.switch_to_block(left)
  builder.jump(trampoline, [left_value])
  builder.switch_to_block(right)
  builder.jump(trampoline, [right_value])
  let forwarded = builder.add_block_param(trampoline, I32)
  builder.switch_to_block(trampoline)
  builder.jump(exit, [])
  builder.switch_to_block(exit)
  builder.return_([forwarded])
  let func = builder.get_function()
  inspect(func.verify(), content="()")
  thread_jumps(func) |> ignore
  inspect(func.verify(), content="()")
}

///|
test "optimizer merges straight line blocks" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("merge_blocks")
  builder.add_result(I32)
  let exit = builder.create_block()
  builder.jump(exit, [])
  builder.switch_to_block(exit)
  let value = builder.iconst_i32(7)
  builder.return_([value])
  let func = builder.get_function()
  let result = merge_blocks(func)
  inspect(result.changed, content="true")
  inspect(
    func.print(),
    content=(
      #|function merge_blocks() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 7
      #|    return v0
      #|}
      #|
    ),
  )
  inspect(func.verify(), content="()")
}

///|
test "optimizer merges a complete straight-line chain in one pass" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("merge_block_chain")
  let first = builder.create_block()
  let second = builder.create_block()
  let exit = builder.create_block()
  builder.jump(first, [])
  builder.switch_to_block(first)
  builder.jump(second, [])
  builder.switch_to_block(second)
  builder.jump(exit, [])
  builder.switch_to_block(exit)
  builder.return_([])
  let func = builder.get_function()
  merge_blocks(func) |> ignore
  inspect(func.blocks.length(), content="1")
  inspect(func.verify(), content="()")
}

///|
test "optimizer does not merge block with params" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("merge_skip_params")
  builder.add_result(I32)
  let exit = builder.create_block()
  let arg = builder.iconst_i32(7)
  builder.jump(exit, [arg])
  let param = builder.add_block_param(exit, I32)
  builder.switch_to_block(exit)
  builder.return_([param])
  let func = builder.get_function()
  let result = merge_blocks(func)
  inspect(result.changed, content="false")
  inspect(func.verify(), content="()")
}

///|
test "CSE keeps duplicate loads without alias metadata" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("no_load_cse")
  let ptr = builder.add_param(Ptr)
  builder.add_result(I32)
  let offset = builder.iconst_i64(0L)
  let _loaded0 = builder.load_ptr(I32, ptr, offset)
  let loaded1 = builder.load_ptr(I32, ptr, offset)
  builder.return_([loaded1])
  let func = builder.get_function()
  let stats = run_acyclic_optimization_with_budget_and_analysis(
    func,
    instruction_count(func),
    FunctionAnalysis::build(func),
  )
  inspect(stats.result.changed, content="false")
  inspect(
    func.print(),
    content=(
      #|function no_load_cse(v0:ptr) -> i32 {
      #|block0:
      #|    v1:i64 = iconst 0
      #|    v2:i32 = load.i32 v0, v1
      #|    v3:i32 = load.i32 v0, v1
      #|    return v3
      #|}
      #|
    ),
  )
}
