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

// ============ CFG Tests ============

///|
test "cfg linear" {
  // Simple linear CFG: block0 -> block1 -> return
  let builder = IRBuilder::new("linear")
  builder.add_result(Type::I32)
  let b0 = builder.create_block()
  let b1 = builder.create_block()
  builder.switch_to_block(b0)
  let c = builder.iconst_i32(42)
  builder.jump(b1, [])
  builder.switch_to_block(b1)
  builder.return_([c])
  let func = builder.get_function()
  let cfg = CFG::build(func)
  // Check successors
  inspect(cfg.get_successors(0), content="[1]")
  inspect(cfg.get_successors(1), content="[]")
  // Check predecessors
  inspect(cfg.get_predecessors(0), content="[]")
  inspect(cfg.get_predecessors(1), content="[0]")
}

///|
test "cfg branching" {
  // Diamond CFG: block0 -> block1/block2 -> block3
  let builder = IRBuilder::new("diamond")
  let cond = builder.add_param(Type::I32)
  builder.add_result(Type::I32)
  let b0 = builder.create_block()
  let b1 = builder.create_block()
  let b2 = builder.create_block()
  let b3 = builder.create_block()
  builder.switch_to_block(b0)
  builder.brnz(cond, b1, b2)
  builder.switch_to_block(b1)
  let c1 = builder.iconst_i32(1)
  builder.jump(b3, [])
  builder.switch_to_block(b2)
  let c2 = builder.iconst_i32(2)
  builder.jump(b3, [])
  builder.switch_to_block(b3)
  let result = builder.iconst_i32(0)
  builder.return_([result])
  let func = builder.get_function()
  let cfg = CFG::build(func)
  // Check successors
  inspect(cfg.get_successors(0), content="[1, 2]")
  inspect(cfg.get_successors(1), content="[3]")
  inspect(cfg.get_successors(2), content="[3]")
  inspect(cfg.get_successors(3), content="[]")
  // Check predecessors
  inspect(cfg.get_predecessors(0), content="[]")
  inspect(cfg.get_predecessors(1), content="[0]")
  inspect(cfg.get_predecessors(2), content="[0]")
  inspect(cfg.get_predecessors(3), content="[1, 2]")
  // Suppress unused variable warnings
  ignore(c1)
  ignore(c2)
}

///|
test "cfg loop" {
  // Loop CFG: block0 -> block1 -> block1/block2
  let builder = IRBuilder::new("loop")
  let n = builder.add_param(Type::I32)
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  let loop_header = builder.create_block()
  let exit = builder.create_block()
  builder.switch_to_block(entry)
  let init = builder.iconst_i32(0)
  builder.jump(loop_header, [])
  let counter = builder.add_block_param(loop_header, Type::I32)
  builder.switch_to_block(loop_header)
  let cmp = builder.icmp_slt(counter, n)
  builder.brnz(cmp, loop_header, exit)
  builder.switch_to_block(exit)
  builder.return_([counter])
  let func = builder.get_function()
  let cfg = CFG::build(func)
  // Check back edge exists (loop_header -> loop_header)
  let back_edges = cfg.find_back_edges()
  inspect(back_edges, content="[(1, 1)]")
  // Check postorder traversal
  let po = cfg.postorder()
  inspect(po, content="[2, 1, 0]")
  // Suppress unused variable warnings
  ignore(init)
}

///|
test "cfg dominators" {
  // Diamond CFG for dominator testing
  let builder = IRBuilder::new("dom_test")
  let cond = builder.add_param(Type::I32)
  builder.add_result(Type::I32)
  let b0 = builder.create_block()
  let b1 = builder.create_block()
  let b2 = builder.create_block()
  let b3 = builder.create_block()
  builder.switch_to_block(b0)
  builder.brnz(cond, b1, b2)
  builder.switch_to_block(b1)
  builder.jump(b3, [])
  builder.switch_to_block(b2)
  builder.jump(b3, [])
  builder.switch_to_block(b3)
  let result = builder.iconst_i32(0)
  builder.return_([result])
  let func = builder.get_function()
  let cfg = CFG::build(func)
  // Compute dominators
  let idom = cfg.compute_dominators()
  // block0 is entry, dominates itself
  inspect(idom[0], content="0")
  // block1 is dominated by block0
  inspect(idom[1], content="0")
  // block2 is dominated by block0
  inspect(idom[2], content="0")
  // block3 is dominated by block0 (common dominator of b1 and b2)
  inspect(idom[3], content="0")
  // Check dominates function
  assert_true(cfg.dominates(0, 3))
  assert_false(cfg.dominates(1, 2))
}

///|
test "cfg dot output" {
  let builder = IRBuilder::new("dot_test")
  builder.add_result(Type::I32)
  let b0 = builder.create_block()
  let b1 = builder.create_block()
  builder.switch_to_block(b0)
  let c = builder.iconst_i32(1)
  builder.jump(b1, [])
  builder.switch_to_block(b1)
  builder.return_([c])
  let func = builder.get_function()
  let cfg = CFG::build(func)
  let dot = cfg.to_dot("dot_test")
  let expected =
    #|digraph dot_test {
    #|  node [shape=box];
    #|  block0 -> block1;
    #|}
    #|
  inspect(dot, content=expected)
}

// ============ Optimization Tests ============

///|
test "constant folding basic" {
  let builder = IRBuilder::new("const_fold")
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  // 10 + 20 should fold to 30
  let c10 = builder.iconst_i32(10)
  let c20 = builder.iconst_i32(20)
  let sum = builder.iadd(c10, c20)
  builder.return_([sum])
  let func = builder.get_function()
  let result = fold_constants(func)
  assert_true(result.changed)
  // After folding, the add should become a constant
  let output = func.print()
  inspect(
    output,
    content=(
      #|function const_fold() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 10
      #|    v1:i32 = iconst 20
      #|    v2:i32 = iconst 30
      #|    return v2
      #|}
      #|
    ),
  )
}

///|
test "dead code elimination" {
  let builder = IRBuilder::new("dce_test")
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  // c1 is used in return, c2 is unused (dead)
  let c1 = builder.iconst_i32(42)
  let c2 = builder.iconst_i32(100) // This should be eliminated
  builder.return_([c1])
  let func = builder.get_function()
  let result = eliminate_dead_code(func)
  assert_true(result.changed)
  // After DCE, c2 should be removed
  let output = func.print()
  inspect(
    output,
    content=(
      #|function dce_test() -> i32 {
      #|block0:
      #|    v0:i32 = iconst 42
      #|    return v0
      #|}
      #|
    ),
  )
  // Suppress warning
  ignore(c2)
}

///|
test "copy propagation" {
  let builder = IRBuilder::new("copy_prop")
  let p0 = builder.add_param(Type::I32)
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let copy = builder.copy(p0)
  let one = builder.iconst_i32(1)
  // Uses 'copy' instead of p0 directly
  let result = builder.iadd(copy, one)
  builder.return_([result])
  let func = builder.get_function()
  let cp_result = propagate_copies(func)
  assert_true(cp_result.changed)
  // After copy propagation, iadd should use p0 directly
  let block = func.blocks[0]
  let iadd_inst = block.instructions[2] // v3 = iadd copy, one
  assert_eq(iadd_inst.operands[0].id, p0.id)
}

///|
test "common subexpression elimination" {
  let builder = IRBuilder::new("cse_test")
  let p0 = builder.add_param(Type::I32)
  let p1 = builder.add_param(Type::I32)
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  // Same computation twice
  let sum1 = builder.iadd(p0, p1)
  let sum2 = builder.iadd(p0, p1) // Should become copy of sum1
  let result = builder.iadd(sum1, sum2)
  builder.return_([result])
  let func = builder.get_function()
  let cse_result = eliminate_common_subexpressions(func)
  assert_true(cse_result.changed)
  // After CSE, sum2 should become a copy
  let block = func.blocks[0]
  let sum2_inst = block.instructions[1]
  match sum2_inst.opcode {
    Copy => assert_true(true) // Expected
    _ => assert_true(false)
  }
}

///|
test "combined optimizations" {
  let builder = IRBuilder::new("optimize_test")
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  // Dead code: unused computation
  let unused = builder.iconst_i32(999)
  // Constant folding opportunity
  let c5 = builder.iconst_i32(5)
  let c7 = builder.iconst_i32(7)
  let sum = builder.iadd(c5, c7) // Should fold to 12
  builder.return_([sum])
  let func = builder.get_function()
  // Run combined optimizations
  let result = optimize(func)
  assert_true(result.changed)
  // After optimization, unused should be removed, sum should be constant,
  // and c5/c7 should also be removed since they're no longer used
  let output = func.print()
  let expected =
    #|function optimize_test() -> i32 {
    #|block0:
    #|    v3:i32 = iconst 12
    #|    return v3
    #|}
    #|
  inspect(output, content=expected)
  // Suppress warning
  ignore(unused)
}

// ============ Control Flow Optimization Tests ============

///|
test "branch simplification: constant brz" {
  // Test that brz with constant 0 condition simplifies to jump to then-target
  let builder = IRBuilder::new("branch_simp_brz")
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  let then_block = builder.create_block()
  let else_block = builder.create_block()
  builder.switch_to_block(entry)
  let zero = builder.iconst_i32(0) // condition is constant 0
  builder.brz(zero, then_block, else_block) // brz 0 -> jump to then_block
  builder.switch_to_block(then_block)
  let c1 = builder.iconst_i32(42)
  builder.return_([c1])
  builder.switch_to_block(else_block)
  let c2 = builder.iconst_i32(100)
  builder.return_([c2])
  let func = builder.get_function()
  let result = simplify_branches(func)
  assert_true(result.changed)
  // After simplification, brz should become jump
  match func.blocks[0].terminator {
    Some(Jump(target, _)) => assert_eq(target, 1) // should jump to then_block (id=1)
    _ => assert_true(false)
  }
}

///|
test "branch simplification: constant brnz" {
  // Test that brnz with constant 1 condition simplifies to jump to then-target
  let builder = IRBuilder::new("branch_simp_brnz")
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  let then_block = builder.create_block()
  let else_block = builder.create_block()
  builder.switch_to_block(entry)
  let one = builder.iconst_i32(1) // condition is constant 1
  builder.brnz(one, then_block, else_block) // brnz 1 -> jump to then_block
  builder.switch_to_block(then_block)
  let c1 = builder.iconst_i32(42)
  builder.return_([c1])
  builder.switch_to_block(else_block)
  let c2 = builder.iconst_i32(100)
  builder.return_([c2])
  let func = builder.get_function()
  let result = simplify_branches(func)
  assert_true(result.changed)
  // After simplification, brnz should become jump
  match func.blocks[0].terminator {
    Some(Jump(target, _)) => assert_eq(target, 1) // should jump to then_block (id=1)
    _ => assert_true(false)
  }
}

///|
test "unreachable code elimination" {
  // Create a function with an unreachable block
  let builder = IRBuilder::new("unreachable_test")
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  let reachable = builder.create_block()
  let dead_block = builder.create_block()
  builder.switch_to_block(entry)
  let c = builder.iconst_i32(42)
  builder.jump(reachable, [])
  builder.switch_to_block(reachable)
  builder.return_([c])
  builder.switch_to_block(dead_block)
  let dead = builder.iconst_i32(999)
  builder.return_([dead])
  let func = builder.get_function()
  assert_eq(func.blocks.length(), 3)
  let result = eliminate_unreachable_code(func)
  assert_true(result.changed)
  // After elimination, unreachable block should be removed
  assert_eq(func.blocks.length(), 2)
}

///|
test "basic block merging" {
  // Test merging blocks: b0 -> b1 -> b2 where b1 has single pred and succ
  let builder = IRBuilder::new("merge_test")
  builder.add_result(Type::I32)
  let b0 = builder.create_block()
  let b1 = builder.create_block()
  let b2 = builder.create_block()
  builder.switch_to_block(b0)
  let c1 = builder.iconst_i32(1)
  builder.jump(b1, [])
  builder.switch_to_block(b1)
  let c2 = builder.iconst_i32(2)
  builder.jump(b2, [])
  builder.switch_to_block(b2)
  let sum = builder.iadd(c1, c2)
  builder.return_([sum])
  let func = builder.get_function()
  assert_eq(func.blocks.length(), 3)
  let result = merge_blocks(func)
  assert_true(result.changed)
  // After merging, should have fewer blocks
  assert_true(func.blocks.length() < 3)
}

///|
test "jump threading" {
  // Test threading through jump-only blocks: b0 -> b1 -> b2 where b1 is just a jump
  let builder = IRBuilder::new("thread_test")
  builder.add_result(Type::I32)
  let b0 = builder.create_block()
  let b1 = builder.create_block()
  let b2 = builder.create_block()
  builder.switch_to_block(b0)
  let c = builder.iconst_i32(42)
  builder.jump(b1, [])
  builder.switch_to_block(b1)
  // b1 has no instructions, just a jump to b2
  builder.jump(b2, [])
  builder.switch_to_block(b2)
  builder.return_([c])
  let func = builder.get_function()
  let result = thread_jumps(func)
  assert_true(result.changed)
  // After threading, b0 should jump directly to b2
  match func.blocks[0].terminator {
    Some(Jump(target, _)) => assert_eq(target, 2) // should jump directly to b2
    _ => assert_true(false)
  }
}

///|
test "combined control flow optimizations" {
  // Test that all control flow optimizations work together
  let builder = IRBuilder::new("combined_cf_test")
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  let intermediate1 = builder.create_block()
  let intermediate2 = builder.create_block()
  let exit = builder.create_block()
  let dead_block = builder.create_block()
  builder.switch_to_block(entry)
  let zero = builder.iconst_i32(0)
  // brz 0 -> always takes then branch (intermediate1)
  builder.brz(zero, intermediate1, dead_block)
  builder.switch_to_block(intermediate1)
  // Just a jump to next block
  builder.jump(intermediate2, [])
  builder.switch_to_block(intermediate2)
  // Just a jump to exit
  builder.jump(exit, [])
  builder.switch_to_block(exit)
  let result = builder.iconst_i32(42)
  builder.return_([result])
  builder.switch_to_block(dead_block)
  let dead = builder.iconst_i32(999)
  builder.return_([dead])
  let func = builder.get_function()
  let initial_blocks = func.blocks.length()
  // Run full optimization
  let opt_result = optimize(func)
  assert_true(opt_result.changed)
  // After optimization:
  // - brz 0 should become jump
  // - unreachable block should be removed
  // - intermediate blocks should be threaded/merged
  assert_true(func.blocks.length() < initial_blocks)
}
